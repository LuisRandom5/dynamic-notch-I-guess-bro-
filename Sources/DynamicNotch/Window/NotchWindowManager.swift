import AppKit
import SwiftUI
import Combine

public final class NotchWindowManager: ObservableObject {
    public static let shared = NotchWindowManager()
    
    public private(set) var panel: NotchPanel?
    private var hitTestView: NotchHitTestView?
    private var hostingView: NotchHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    
    private let maxWindowWidth: CGFloat = 680
    private let maxWindowHeight: CGFloat = 440
    
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
        
        hitView.wantsLayer = true
        hitView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let host = NotchHostingView(rootView: AnyView(rootView))
        host.frame = hitView.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        
        hitView.addSubview(host)
        newPanel.contentView = hitView
        newPanel.alphaValue = 1.0
        
        self.panel = newPanel
        self.hitTestView = hitView
        self.hostingView = host
        
        updateHitAreaForCurrentState()
        
        // Show window floating above everything
        panel?.orderFrontRegardless()
    }
    
    public func setAllowsKeyInput(_ allow: Bool) {
        panel?.allowsKeyInput = allow
        if allow {
            panel?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel?.resignKey()
        }
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
        
        if AppState.shared.isDropInvitationActive {
            updateHitArea(width: 480, height: 160)
            return
        }
        
        if mode == .expanded || mode == .shelf {
            let cardH = AppState.shared.isPlayerDetailExpanded ? PlayerMetrics.detailCardHeight : (mode == .shelf ? 204 : PlayerMetrics.cardHeight)
            updateHitArea(width: max(PlayerMetrics.cardWidth + 140, 330), height: cardH + 70)
            return
        }
        
        if let activity = ActivityCenter.shared.currentActivity {
            if ActivityCenter.shared.dismissingActivityId == activity.id {
                updateHitArea(width: geom.width + 24, height: geom.height + 10)
                return
            }
            switch activity.style {
            case .pill:
                updateHitArea(width: geom.width + 190, height: max(50, geom.height + 14))
            case .sliderPill:
                updateHitArea(width: geom.width + 296, height: max(50, geom.height + 14))
            case .airpodsPill:
                updateHitArea(width: 410, height: 215)
            case .card:
                updateHitArea(width: 430, height: 195)
            }
            return
        }
        
        switch mode {
        case .idle:
            // Dar margen para la animación de squish & stretch (1.065x), latido, alas simétricas y la sombra inferior
            let extraW: CGFloat = !AppState.shared.shelfItems.isEmpty ? 104 : 24
            updateHitArea(width: geom.width + extraW, height: geom.height + 10)
        case .compact:
            let extraW: CGFloat = !AppState.shared.shelfItems.isEmpty ? 156 : 120
            updateHitArea(width: geom.width + extraW, height: geom.height + 10)
        case .expanded, .shelf:
            updateHitArea(width: 430, height: 260)
        }
    }
    
    /// Retorna el rectángulo del Notch visible en coordenadas absolutas de pantalla de macOS (origen abajo a la izquierda)
    public var visibleNotchScreenFrame: CGRect {
        guard let panel = panel else { return .zero }
        let geom = ScreenService.shared.currentGeometry
        let mode = AppState.shared.mode
        
        let width: CGFloat
        let height: CGFloat
        
        if AppState.shared.isDropInvitationActive {
            width = 460
            height = 140
        } else if mode == .expanded || mode == .shelf {
            width = NotchTuning.expandedWidth
            let cardH = AppState.shared.isPlayerDetailExpanded ? PlayerMetrics.detailCardHeight : (mode == .shelf ? 204 : PlayerMetrics.cardHeight)
            height = cardH + 16
        } else if mode == .compact {
            width = geom.width + 104
            height = geom.height + 4
        } else {
            width = !AppState.shared.shelfItems.isEmpty ? geom.width + 96 : geom.width
            height = geom.height + 4
        }
        
        let notchX = panel.frame.origin.x + (panel.frame.width - width) / 2
        let notchY = panel.frame.maxY - height
        return CGRect(x: notchX, y: notchY, width: width, height: height)
    }
    
    private func observeScreenChanges() {
        ScreenService.shared.$currentGeometry
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
            
        AppState.shared.$isDropInvitationActive
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
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
            
        AppState.shared.$isPlayerDetailExpanded
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
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
            
        ActivityCenter.shared.$dismissingActivityId
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
    }
    
    private var escKeyMonitor: Any?
    
    private func handleModeForGlobalClickMonitor(_ mode: NotchMode) {
        if mode == .expanded || mode == .shelf {
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
