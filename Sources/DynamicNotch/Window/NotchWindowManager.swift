import AppKit
import SwiftUI
import Combine

public final class NotchWindowManager: ObservableObject {
    public static let shared = NotchWindowManager()
    
    public private(set) var panel: NotchPanel?
    private var hitTestView: NotchHitTestView?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    
    private let maxWindowWidth: CGFloat = 680
    private let maxWindowHeight: CGFloat = 320
    
    private init() {
        observeScreenChanges()
    }
    
    public func setupWindow() {
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        
        let windowX = screenFrame.origin.x + (screenFrame.width - maxWindowWidth) / 2
        let windowY = screenFrame.origin.y + screenFrame.height - maxWindowHeight
        let windowRect = NSRect(x: windowX, y: windowY, width: maxWindowWidth, height: maxWindowHeight)
        
        let newPanel = NotchPanel(contentRect: windowRect)
        let hitView = NotchHitTestView(frame: NSRect(origin: .zero, size: windowRect.size))
        
        // Root SwiftUI View
        let rootView = NotchContainerView()
            .environmentObject(AppState.shared)
            .environmentObject(ScreenService.shared)
            .environmentObject(MusicService.shared)
            .environmentObject(BatteryService.shared)
        
        let host = NSHostingView(rootView: AnyView(rootView))
        host.frame = hitView.bounds
        host.autoresizingMask = [.width, .height]
        
        hitView.addSubview(host)
        newPanel.contentView = hitView
        
        self.panel = newPanel
        self.hitTestView = hitView
        self.hostingView = host
        
        updateHitAreaForCurrentState()
        
        // Show window floating above everything
        newPanel.orderFrontRegardless()
    }
    
    public func updateHitArea(width: CGFloat, height: CGFloat) {
        guard let hitView = hitTestView else { return }
        
        // In macOS coordinates, (0,0) is bottom-left
        let viewWidth = hitView.bounds.width
        let viewHeight = hitView.bounds.height
        
        let originX = (viewWidth - width) / 2
        let originY = viewHeight - height
        
        let activeRect = CGRect(x: originX, y: originY, width: width, height: height)
        hitView.updateHitArea(activeRect)
    }
    
    public func updateHitAreaForCurrentState() {
        let geom = ScreenService.shared.currentGeometry
        let mode = AppState.shared.mode
        
        switch mode {
        case .idle:
            updateHitArea(width: geom.width, height: geom.height)
        case .compact:
            updateHitArea(width: geom.width + 104, height: geom.height)
        case .expanded:
            updateHitArea(width: 520, height: 250)
        case .shelf:
            updateHitArea(width: 480, height: 215)
        }
    }
    
    private func observeScreenChanges() {
        ScreenService.shared.$currentGeometry
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
            
        AppState.shared.$mode
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
    }
    
    public func repositionWindow() {
        guard let panel = panel else { return }
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        
        let windowX = screenFrame.origin.x + (screenFrame.width - maxWindowWidth) / 2
        let windowY = screenFrame.origin.y + screenFrame.height - maxWindowHeight
        let windowRect = NSRect(x: windowX, y: windowY, width: maxWindowWidth, height: maxWindowHeight)
        
        panel.setFrame(windowRect, display: true, animate: false)
        updateHitAreaForCurrentState()
    }
}
