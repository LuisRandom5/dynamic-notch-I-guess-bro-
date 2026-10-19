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
    
    public func updateScreenGeometry() {
        // La primera pantalla con notch físico; si no hay, un notch virtual en la pantalla principal
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens.first
        let resolved = SurfaceGeometry.resolve(
            screens: screens.map { ($0.frame, $0.auxiliaryTopLeftArea, $0.auxiliaryTopRightArea) },
            preferredIndex: main.flatMap { m in screens.firstIndex(where: { $0 == m }) }
        )
        self.targetScreen = resolved.screenIndex.map { screens[$0] } ?? main
        self.currentGeometry = resolved.geometry
    }
}
