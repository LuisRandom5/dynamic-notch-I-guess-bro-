import AppKit
import SwiftUI
import Combine

public final class NotchWindowManager: ObservableObject {
    public static let shared = NotchWindowManager()
    
    public private(set) var panel: NotchPanel?
    private var hitTestView: NotchHitTestView?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    
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
        
        if mode == .expanded || mode == .shelf {
            updateHitArea(width: max(PlayerMetrics.cardWidth + 24, 330), height: PlayerMetrics.cardHeight + 70)
            return
        }
        
        if let activity = ActivityCenter.shared.currentActivity {
            switch activity.style {
            case .pill:
                updateHitArea(width: geom.width + 190, height: max(50, geom.height + 14))
            case .sliderPill:
                updateHitArea(width: geom.width + 296, height: max(50, geom.height + 14))
            case .card:
                updateHitArea(width: 410, height: 130)
            }
            return
        }
        
        switch mode {
        case .idle:
            // Dar margen para la animación de squish & stretch (1.065x), latido y la sombra inferior
            updateHitArea(width: geom.width + 24, height: geom.height + 10)
        case .compact:
            updateHitArea(width: geom.width + 120, height: geom.height + 10)
        case .expanded, .shelf:
            updateHitArea(width: 430, height: 240)
        }
    }
    
    private func observeScreenChanges() {
        ScreenService.shared.$currentGeometry
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
            
        AppState.shared.$mode
            .sink { [weak self] newMode in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                    self?.handleModeForGlobalClickMonitor(newMode)
                }
            }
            .store(in: &cancellables)
            
        ActivityCenter.shared.$currentActivity
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
    }
    
    private var escKeyMonitor: Any?
    
    private func handleModeForGlobalClickMonitor(_ mode: NotchMode) {
        if mode == .expanded {
            if globalClickMonitor == nil {
                globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                    DispatchQueue.main.async {
                        AppState.shared.collapse()
                    }
                }
            }
            if escKeyMonitor == nil {
                escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { // Tecla Escape (Esc)
                        DispatchQueue.main.async {
                            AppState.shared.collapse()
                        }
                        return nil
                    }
                    return event
                }
            }
        } else {
            if let monitor = globalClickMonitor {
                NSEvent.removeMonitor(monitor)
                globalClickMonitor = nil
            }
            if let monitor = escKeyMonitor {
                NSEvent.removeMonitor(monitor)
                escKeyMonitor = nil
            }
        }
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
