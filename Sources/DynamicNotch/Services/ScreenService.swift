import AppKit
import Combine

public final class ScreenService: ObservableObject {
    public static let shared = ScreenService()
    
    @Published public private(set) var currentGeometry: NotchGeometry = .fallback
    @Published public private(set) var targetScreen: NSScreen?
    
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
        // Find the screen that has a physical notch, or default to the primary display
        var selectedScreen = NSScreen.main ?? NSScreen.screens.first
        var foundPhysicalNotch = false
        var computedGeometry = NotchGeometry.fallback
        
        for screen in NSScreen.screens {
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea,
               leftArea.width > 0, rightArea.width > 0 {
                
                let baseWidth = rightArea.minX - leftArea.maxX
                let baseHeight = screen.frame.maxY - leftArea.minY
                
                // Subpixel buffer (+3.0pt width, +1.0pt height) to perfectly embrace the physical bezel
                let notchWidth = baseWidth + 3.0
                let notchHeight = baseHeight + 1.0
                let notchX = leftArea.maxX - 1.5
                let notchY = leftArea.minY - 1.0
                
                computedGeometry = NotchGeometry(
                    hasPhysicalNotch: true,
                    width: notchWidth,
                    height: notchHeight,
                    screenBounds: screen.frame,
                    notchBoundsInScreen: CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
                )
                selectedScreen = screen
                foundPhysicalNotch = true
                break
            }
        }
        
        if !foundPhysicalNotch, let screen = selectedScreen {
            let width: CGFloat = 180
            let height: CGFloat = 32
            let x = screen.frame.midX - (width / 2)
            let y = screen.frame.maxY - height
            
            computedGeometry = NotchGeometry(
                hasPhysicalNotch: false,
                width: width,
                height: height,
                screenBounds: screen.frame,
                notchBoundsInScreen: CGRect(x: x, y: y, width: width, height: height)
            )
        }
        
        self.targetScreen = selectedScreen
        self.currentGeometry = computedGeometry
    }
}
