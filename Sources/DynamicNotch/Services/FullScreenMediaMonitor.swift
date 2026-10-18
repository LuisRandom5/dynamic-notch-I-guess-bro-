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
        let shouldHide = MusicService.shared.currentTrack.isPlaying && isFullScreenOnNotchScreen()
        guard shouldHide != isHidingNotch else { return }
        isHidingNotch = shouldHide
        DNDLogger.log("FullScreenMediaMonitor: \(shouldHide ? "pantalla completa con reproducción → notch oculto" : "fuera de pantalla completa → notch visible")")
        NotchWindowManager.shared.setHiddenForFullScreen(shouldHide)
    }

    private func isFullScreenOnNotchScreen() -> Bool {
        guard let screen = ScreenService.shared.targetScreen ?? NSScreen.main,
              let mainHeight = NSScreen.screens.first?.frame.height else { return false }
        // Rectángulo de esa pantalla en coordenadas de CGWindowList (origen arriba a la izquierda)
        let screenRect = CGRect(
            x: screen.frame.minX,
            y: mainHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
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
