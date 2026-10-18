import AppKit
import Combine

/// ¿Lo que queda detrás del notch es claro? Sin permiso de grabación de pantalla no se pueden leer los
/// píxeles, así que se infiere:
/// - Si una ventana de app cubre la zona del notch desplegado → es clara cuando el sistema está en modo claro
///   (las apps siguen la apariencia del sistema).
/// - Si sólo está el fondo de pantalla → luminancia de la parte superior central del fondo.
///
/// Con fondo claro el notch usa `Glass.regular` en vez de `clear` (guía de Apple: clear sólo sobre contenido
/// visual; regular desenfoca y ajusta la luminosidad para que el texto se lea).
///
/// Sólo en "Cristal Oscuro" (como "Con tinte" de iOS 26). "Cristal Claro" es como "Transparente" de iOS:
/// el usuario eligió máxima transparencia y el vidrio nunca se adapta.
public final class BackdropBrightnessMonitor: ObservableObject {
    public static let shared = BackdropBrightnessMonitor()

    @Published public private(set) var isBackdropBright = false
    /// Modo oscuro del sistema (para la "keyline" de la Isla Dinámica)
    @Published public private(set) var isSystemDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"

    private var timer: Timer?
    /// La lista de ventanas del sistema cuesta ~decenas de ms: se consulta fuera del hilo principal para no
    /// robar cuadros a las animaciones del notch
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.Backdrop", qos: .utility)
    /// Zona que ocupa el notch desplegado (centrada arriba de la pantalla)
    private static let regionSize = CGSize(width: 520, height: 260)

    private init() {}

    public func start() {
        guard timer == nil else { return }
        scheduleEvaluate()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.scheduleEvaluate() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // El fondo de pantalla puede cambiar
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            GlassClearManager.shared.checkWallpaperLuminance()
        }
    }

    private func scheduleEvaluate() {
        // Datos de AppKit/estado en el hilo principal; la consulta pesada en segundo plano
        guard let screen = ScreenService.shared.targetScreen ?? NSScreen.main,
              let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let screenFrame = screen.frame
        let adapts = AppState.shared.effectiveAppearanceMode == .darkGlass
        let wallpaperBright = GlassClearManager.shared.detectedWallpaperLuminance > 0.62
        queue.async { [weak self] in
            self?.evaluate(screenFrame: screenFrame, mainHeight: mainHeight, adapts: adapts, wallpaperBright: wallpaperBright)
        }
    }
    
    private func evaluate(screenFrame: CGRect, mainHeight: CGFloat, adapts: Bool, wallpaperBright: Bool) {
        // Coordenadas de CGWindowList: origen arriba a la izquierda de la pantalla principal
        let region = CGRect(
            x: screenFrame.midX - Self.regionSize.width / 2,
            y: mainHeight - screenFrame.maxY,
            width: Self.regionSize.width,
            height: Self.regionSize.height
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let coveredByAppWindow = windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.intersects(region)
        }

        let backdropBright: Bool
        if coveredByAppWindow {
            let isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            backdropBright = !isDarkMode
        } else {
            backdropBright = wallpaperBright
        }
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        // Cristal Claro: siempre clear, sin adaptar
        let bright = adapts && backdropBright
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if dark != self.isSystemDarkMode { self.isSystemDarkMode = dark }
            if bright != self.isBackdropBright { self.isBackdropBright = bright }
        }
    }
}
