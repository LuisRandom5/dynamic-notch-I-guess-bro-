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
        setupScrollSwipeMonitors()
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
        
        setupScrollSwipeMonitors()
    }
    
    // App que tenía el foco antes de que el panel tomara el teclado (Quick Reply / interacción del agente).
    // Se reactiva al soltar el teclado para que el usuario siga escribiendo sin un clic extra.
    private var previousFrontmostApp: NSRunningApplication?

    /// App a la que se devolverá el foco al cerrar la entrada de teclado del notch (nil si no hay ninguna pendiente).
    public var appToRestoreFocus: NSRunningApplication? { previousFrontmostApp }

    public func setAllowsKeyInput(_ allow: Bool) {
        guard let panel = panel else { return }
        if allow {
            rememberFrontmostApp()
            panel.allowsKeyInput = true
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Si otra ventana propia (p. ej. Ajustes) tiene el foco, el usuario está ahí: no robarle el foco
            let panelOwnsFocus = NSApp.keyWindow == nil || NSApp.keyWindow === panel
            panel.allowsKeyInput = false
            panel.resignKey()
            restorePreviousApp(panelOwnsFocus: panelOwnsFocus)
        }
    }

    private func rememberFrontmostApp() {
        // Si ya somos la app activa, la referencia guardada sigue siendo la correcta (llamadas repetidas al enfocar).
        // Si no lo somos, la app frontal actual es a la que hay que volver (el usuario pudo cambiar de app entretanto).
        guard !NSApp.isActive || previousFrontmostApp == nil else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousFrontmostApp = front
    }

    private func restorePreviousApp(panelOwnsFocus: Bool) {
        guard let previous = previousFrontmostApp else { return }
        previousFrontmostApp = nil
        // Si el usuario ya se fue a otra app (o ésta se cerró), no arrebatarle el foco
        guard NSApp.isActive, panelOwnsFocus, !previous.isTerminated else { return }
        DNDLogger.log("NotchWindowManager: restaurando foco a \(previous.bundleIdentifier ?? "pid \(previous.processIdentifier)")")
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }
    
    public func updateHitArea(width: CGFloat, height: CGFloat) {
        guard let hitView = hitTestView else { return }
        
        // In macOS coordinates, (0,0) is bottom-left
        let originX = (hitView.bounds.width - width) / 2
        let originY = hitView.bounds.height - height
        hitView.updateHitArea(CGRect(x: originX, y: originY, width: width, height: height))
    }
    
    public func hitTestDebugInfo() -> [String: Any] {
        guard let hit = hitTestView else { return ["error": "sin hitTestView"] }
        func r(_ c: CGRect) -> [Double] { [Double(c.minX), Double(c.minY), Double(c.width), Double(c.height)] }
        return [
            "bounds": r(hit.bounds),
            "hitArea": r(hit.hitAreaRect),
            "dynamic": hit.dynamicHitPaths.map { r($0.boundingBox) },
            "lastRegionsRaw": lastRegionsRaw.map { "\($0.key): \(r($0.value.frame))" },
            "secondary": ActivityCenter.shared.secondaryActivities.map { $0.id },
            "mode": "\(AppState.shared.mode)"
        ]
    }
    private var lastRegionsRaw: [String: NotchHitRegion] = [:]
    
    /// Recibe las zonas que reportan las vistas SwiftUI (`.notchHitRegion`) y las aplica al hit-test del panel.
    public func updateDynamicHitRegions(_ regions: [String: NotchHitRegion]) {
        lastRegionsRaw = regions
        hitTestView?.updateDynamicHitRegions(Array(regions.values))
    }
    
    public func updateHitAreaForCurrentState() {
        let geom = ScreenService.shared.currentGeometry
        let mode = AppState.shared.mode
        let agentProvider = AgentActivityProvider.shared
        
        // 1. Si el HUD de 2 columnas de progreso de IA está expandido
        if agentProvider.isProgressHUDExpanded {
            updateHitArea(width: AgentLiveProgressView.hudWidth + 40, height: AgentLiveProgressView.hudHeight + 50)
            return
        }
        
        if mode == .expanded || mode == .shelf {
            let cardH = AppState.shared.isPlayerDetailExpanded ? PlayerMetrics.detailCardHeight : (mode == .shelf ? 204 : PlayerMetrics.cardHeight)
            updateHitArea(width: max(PlayerMetrics.cardWidth + 140, 330), height: cardH + 70)
            return
        }
        
        // Actividad fusionada con el notch (p. ej. la tarjeta de Claude): toda su tarjeta debe ser clicable
        if let expanded = ActivityCenter.shared.expandedActivity {
            let w = ActivityCenter.shared.customCardWidth ?? expanded.customExpandedWidth ?? 430
            let h = ActivityCenter.shared.customCardHeight ?? expanded.customExpandedHeight ?? 160
            updateHitArea(width: w + 40, height: h + 50)
            return
        }
        
        if AppState.shared.isDropInvitationActive {
            updateHitArea(width: 480, height: 160)
            return
        }
        
        // Modal Live Activities (como notificaciones, AirPods, llamadas) mandan sobre el notch en reposo
        if let activity = ActivityCenter.shared.currentActivity {
            if ActivityCenter.shared.dismissingActivityId == activity.id {
                updateHitArea(width: geom.width + 24, height: geom.height + 10)
                return
            }
            switch activity.style {
            case .pill:
                updateHitArea(width: (activity.customExpandedWidth ?? (geom.width + 170)) + 20, height: max(50, geom.height + 14))
            case .sliderPill:
                updateHitArea(width: geom.width + 296, height: max(50, geom.height + 14))
            case .airpodsPill:
                updateHitArea(width: geom.width + 116, height: max(44, geom.height + 10))
            case .card:
                let w = ActivityCenter.shared.customCardWidth ?? 430
                let h = ActivityCenter.shared.customCardHeight ?? 130
                // Margen inferior amplio para capturar gestos de arrastre y swipe hacia abajo sin cortes
                let extraH: CGFloat = (NotificationActivityProvider.shared.isNotificationActive || AgentActivityProvider.shared.isActive) ? 180 : 50
                updateHitArea(width: max(w + 60, 440), height: max(h + extraH, 280))
            }
            return
        }
        
        switch mode {
        case .idle:
            // Dar margen para la animación de squish & stretch (1.065x), latido, alas simétricas y la sombra inferior
            let extraW: CGFloat = !AppState.shared.shelfItems.isEmpty ? 104 : 24
            updateHitArea(width: geom.width + extraW, height: geom.height + 35)
        case .compact:
            let extraW: CGFloat = !AppState.shared.shelfItems.isEmpty ? 156 : 120
            updateHitArea(width: geom.width + extraW, height: geom.height + 35)
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
        } else if let activity = ActivityCenter.shared.currentActivity {
            switch activity.style {
            case .pill, .sliderPill:
                width = geom.width + 200
                height = geom.height + 8
            case .airpodsPill:
                width = geom.width + 132
                height = geom.height + 4
            case .card:
                width = ActivityCenter.shared.customCardWidth ?? 410
                height = (ActivityCenter.shared.customCardHeight ?? 112) + 8
            }
        } else if mode == .compact {
            width = geom.width + NotchTuning.compactWingsExtraWidth
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
            
        NotificationActivityProvider.shared.$isQuickReplyExpanded
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
            
        AgentActivityProvider.shared.$isExpanded
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
            
        AgentActivityProvider.shared.$isSatelliteActive
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateHitAreaForCurrentState()
                }
            }
            .store(in: &cancellables)
            
        AgentActivityProvider.shared.$isProgressHUDExpanded
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
    
    // MARK: - Gestos de Trackpad
    // Una sola máquina de estados recibe cada evento exactamente una vez:
    // - eventos dirigidos al panel del notch -> NotchPanel.sendEvent
    // - eventos dirigidos a otras apps        -> monitor global
    // (No hay monitor local: duplicaría los eventos que ya entrega NotchPanel.sendEvent.)
    public let gestureRecognizer = TrackpadGestureRecognizer()
    private let gestureDispatcher = NotchGestureDispatcher()
    private var globalScrollMonitor: Any?
    
    public func setupScrollSwipeMonitors() {
        gestureRecognizer.delegate = gestureDispatcher
        if globalScrollMonitor == nil {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.gestureRecognizer.handle(event)
            }
        }
    }
}
