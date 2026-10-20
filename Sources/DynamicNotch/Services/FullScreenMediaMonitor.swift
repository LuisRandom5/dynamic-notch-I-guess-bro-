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
        // Cada 1.5 s; entrar o salir de pantalla completa cambia el Space y eso se atiende al instante (abajo)
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.evaluate() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Al entrar o salir de pantalla completa cambia el espacio: reaccionar de inmediato
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.evaluate() }
        }
    }

    /// Apps de video y navegadores: a pantalla completa casi siempre es un video, aunque MediaRemote no
    /// reporte que algo suena (pasa con muchos reproductores web)
    private static let mediaApps: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.operasoftware.Opera", "app.zen-browser.zen",
        "com.apple.Music", "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina",
        "org.videolan.vlc", "com.firecore.infuse", "com.spotify.client", "tv.plex.desktop"
    ]

    private func evaluate() {
        guard !SystemIdleState.isScreenUnavailable,
              AppState.shared.hideNotchInFullScreen || isHidingNotch,
              let screen = ScreenService.shared.targetScreen ?? NSScreen.main,
              let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let enabled = AppState.shared.hideNotchInFullScreen
        let isPlaying = MusicService.shared.currentTrack.isPlaying
        let screenFrame = screen.frame
        queue.async { [weak self] in
            let fullScreenPid = Self.fullScreenAppPid(screenFrame: screenFrame, mainHeight: mainHeight)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let isMediaApp = fullScreenPid
                    .flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
                    .map { Self.mediaApps.contains($0) } ?? false
                let shouldHide = enabled && fullScreenPid != nil && (isPlaying || isMediaApp)
                guard shouldHide != self.isHidingNotch else { return }
                self.isHidingNotch = shouldHide
                DNDLogger.log("FullScreenMediaMonitor: \(shouldHide ? "pantalla completa con video o música → notch oculto" : "fuera de pantalla completa → notch visible")")
                NotchWindowManager.shared.setHiddenForFullScreen(shouldHide)
            }
        }
    }

    /// La app al frente (la dueña de la primera ventana normal de la lista, que va de adelante hacia atrás) tiene
    /// su ventana enfocada en pantalla completa, sobre esta pantalla
    private static func frontmostFullScreenPid(windows: [[String: Any]], screenRect: CGRect) -> pid_t? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let front = windows.first(where: {
            ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? Int32) != ownPID
        }), let pid = front[kCGWindowOwnerPID as String] as? Int32,
              let dict = front[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              screenRect.insetBy(dx: -2, dy: -2).contains(bounds) else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, &value) == .success,
              (value as? Bool) == true else { return nil }
        return pid
    }

    /// Diagnóstico (GET /debug/fullscreen)
    public func debugSnapshot() -> [String: Any] {
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return [
            "isPlaying": MusicService.shared.currentTrack.isPlaying,
            "hideNotchInFullScreen": AppState.shared.hideNotchInFullScreen,
            "axTrusted": AXIsProcessTrusted(),
            "isHidingNotch": isHidingNotch,
            "fullScreenAppPid": screen.flatMap { Self.fullScreenAppPid(screenFrame: $0.frame, mainHeight: mainHeight) } ?? 0
        ]
    }

    /// La app que está a pantalla completa en esta pantalla (nil si ninguna)
    private static func fullScreenAppPid(screenFrame: CGRect, mainHeight: CGFloat) -> pid_t? {
        // Rectángulo de esa pantalla en coordenadas de CGWindowList (origen arriba a la izquierda)
        let screenRect = CGRect(
            x: screenFrame.minX,
            y: mainHeight - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // En una MacBook con notch, macOS deja visible la franja de la barra de menús junto al notch aun en
        // pantalla completa (la ventana "Menubar" nunca se va). Señal directa: la ventana enfocada de la app al
        // frente dice estar en pantalla completa (AXFullScreen) y está en esta pantalla
        if let pid = frontmostFullScreenPid(windows: windows, screenRect: screenRect) {
            return pid
        }
        let menuBarVisible = windows.contains { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (info[kCGWindowName as String] as? String) == "Menubar",
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.intersects(screenRect)
        }
        guard !menuBarVisible else { return nil }
        // Y una ventana normal de otra app que ocupa (casi) toda la pantalla
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let covering = windows.first { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.width >= screenRect.width - 2 && bounds.height >= screenRect.height - 60
                && screenRect.insetBy(dx: -2, dy: -2).contains(bounds)
        }
        return covering?[kCGWindowOwnerPID as String] as? Int32
    }
}
