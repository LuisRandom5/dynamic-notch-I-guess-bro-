import AppKit
import Combine

public final class ScreenService: ObservableObject {
    public static let shared = ScreenService()
    
    @Published public private(set) var currentGeometry: NotchGeometry = .fallback
    @Published public private(set) var targetScreen: NSScreen?
    /// Superficie actual (notch físico o isla); `currentGeometry` es el nombre histórico
    public var surface: SurfaceGeometry { currentGeometry }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        updateScreenGeometry()
        
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.updateScreenGeometry()
            }
            .store(in: &cancellables)
    }
    
    /// Seguir al cursor: se revisa en qué pantalla está cada medio segundo (sólo con esa preferencia)
    private var cursorTimer: Timer?
    private var lastCursorScreenIndex: Int?

    public func updateScreenGeometry() {
        // Preferencias leídas de UserDefaults (no de AppState: ambos singletons se crean al arrancar)
        let defaults = UserDefaults.standard
        let placement = SurfaceGeometry.ScreenPlacement(rawValue: defaults.string(forKey: "islandScreenPlacement") ?? "") ?? .automatic
        let style = SurfaceGeometry.IslandStyle(rawValue: defaults.string(forKey: "islandStyle") ?? "") ?? .floating
        let sizeMode = defaults.string(forKey: "islandSizeMode") ?? "menuBar"
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens.first
        let cursorIndex = Self.screenIndex(containing: NSEvent.mouseLocation, in: screens)
        lastCursorScreenIndex = cursorIndex
        // Diagnóstico (/debug/island): tratar todas las pantallas como si no tuvieran notch
        let ignoreNotch = defaults.bool(forKey: "debugIslandIgnoreNotch")
        let resolved = SurfaceGeometry.resolve(
            screens: screens.map { ($0.frame, ignoreNotch ? nil : $0.auxiliaryTopLeftArea, ignoreNotch ? nil : $0.auxiliaryTopRightArea) },
            placement: placement,
            mainIndex: main.flatMap { m in screens.firstIndex(where: { $0 == m }) },
            cursorIndex: cursorIndex,
            islandStyle: style,
            islandMetrics: { index in
                // "Barra de menús" (por defecto): la isla cabe en la barra y no tapa ventanas; "iPhone": 126 × 32
                guard sizeMode != "iphone", screens.indices.contains(index) else {
                    return (SurfaceGeometry.floatingIslandSize, SurfaceGeometry.floatingIslandTopInset)
                }
                let screen = screens[index]
                return SurfaceGeometry.menuBarIslandMetrics(menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
            }
        )
        let screen = resolved.screenIndex.map { screens[$0] } ?? main
        if screen != targetScreen { self.targetScreen = screen }
        if resolved.geometry != currentGeometry { self.currentGeometry = resolved.geometry }
        updateCursorFollowing(enabled: placement == .followCursor && screens.count > 1)
    }

    private static func screenIndex(containing point: NSPoint, in screens: [NSScreen]) -> Int? {
        screens.firstIndex { $0.frame.contains(point) }
    }

    private func updateCursorFollowing(enabled: Bool) {
        guard enabled != (cursorTimer != nil) else { return }
        if enabled {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let index = Self.screenIndex(containing: NSEvent.mouseLocation, in: NSScreen.screens)
                if let index, index != self.lastCursorScreenIndex {
                    self.updateScreenGeometry()
                }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            cursorTimer = timer
        } else {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }
    }
}
