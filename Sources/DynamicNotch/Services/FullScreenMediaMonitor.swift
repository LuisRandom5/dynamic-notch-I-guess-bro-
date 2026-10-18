import AppKit
import Combine

/// Esconde el notch mientras se ve algo a pantalla completa (un video, Apple Music en pantalla completa…)
/// y lo devuelve al salir.
///
/// Señal de pantalla completa: macOS quita la ventana "Menubar" de la pantalla cuando una app está en
/// pantalla completa (sin permisos especiales: CGWindowList da el dueño, nombre y tamaño de las ventanas).
/// Sólo se esconde si además algo se está reproduciendo, para no estorbar a quien trabaja a pantalla completa.
public final class FullScreenMediaMonitor {
    public static let shared = FullScreenMediaMonitor()

    @Published public private(set) var isHidingNotch = false
    private var timer: Timer?
    /// La lista de ventanas se consulta fuera del hilo principal (cuesta decenas de ms)
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.FullScreen", qos: .utility)

    private init() {}

    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.evaluate() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Al entrar o salir de pantalla completa cambia el espacio: reaccionar de inmediato
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.evaluate() }
        }
    }

    private func evaluate() {
        guard MusicService.shared.currentTrack.isPlaying || isHidingNotch,
              let screen = ScreenService.shared.targetScreen ?? NSScreen.main,
              let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let isPlaying = MusicService.shared.currentTrack.isPlaying && AppState.shared.hideNotchInFullScreen
        let screenFrame = screen.frame
        queue.async { [weak self] in
            let fullScreen = Self.isFullScreen(screenFrame: screenFrame, mainHeight: mainHeight)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let shouldHide = isPlaying && fullScreen
                guard shouldHide != self.isHidingNotch else { return }
                self.isHidingNotch = shouldHide
                DNDLogger.log("FullScreenMediaMonitor: \(shouldHide ? "pantalla completa con reproducción → notch oculto" : "fuera de pantalla completa → notch visible")")
                NotchWindowManager.shared.setHiddenForFullScreen(shouldHide)
            }
        }
    }

    private static func isFullScreen(screenFrame: CGRect, mainHeight: CGFloat) -> Bool {
        // Rectángulo de esa pantalla en coordenadas de CGWindowList (origen arriba a la izquierda)
        let screenRect = CGRect(
            x: screenFrame.minX,
            y: mainHeight - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuBarVisible = windows.contains { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (info[kCGWindowName as String] as? String) == "Menubar",
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.intersects(screenRect)
        }
        guard !menuBarVisible else { return false }
        // Y una ventana normal de otra app que ocupa (casi) toda la pantalla
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.width >= screenRect.width - 2 && bounds.height >= screenRect.height - 60
                && screenRect.insetBy(dx: -2, dy: -2).contains(bounds)
        }
    }
}
