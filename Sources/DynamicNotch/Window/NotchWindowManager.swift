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
    
    public func updateHitArea(width: CGFloat, height: CGFloat, satelliteRect: CGRect? = nil, leftSatelliteRect: CGRect? = nil) {
        guard let hitView = hitTestView else { return }
        
        // In macOS coordinates, (0,0) is bottom-left
        let viewWidth = hitView.bounds.width
        let viewHeight = hitView.bounds.height
        
        let originX = (viewWidth - width) / 2
        let originY = viewHeight - height
        
        let activeRect = CGRect(x: originX, y: originY, width: width, height: height)
        
        var effSatelliteRect = satelliteRect
        var effLeftSatelliteRect = leftSatelliteRect
        let center = ActivityCenter.shared
        let appState = AppState.shared
        
        // Calcular rectángulos de interacción para las bolitas satélite (si no hay tarjeta expandida)
        if center.expandedActivity == nil {
            let satSize = appState.bolitaDiameter
            let gap = appState.bolitaGap
            let satY = viewHeight - ScreenService.shared.currentGeometry.height - 4
            let rightCount = center.secondaryActivities.count + (center.overflowCount > 0 ? 1 : 0)
            
            // cardWidth real del notch en este modo (idéntico a NotchContainerView)
            let notchCardWidth: CGFloat
            switch appState.mode {
            case .idle:
                notchCardWidth = !appState.shelfItems.isEmpty ? (ScreenService.shared.currentGeometry.width + 96) : ScreenService.shared.currentGeometry.width
            case .compact:
                let wingExtra: CGFloat = (!appState.shelfItems.isEmpty && appState.showShelfBadgeInNotch) ? 24 : 0
                notchCardWidth = ScreenService.shared.currentGeometry.width + 104 + (wingExtra * 2)
            case .expanded, .shelf:
                notchCardWidth = NotchTuning.expandedWidth
            }
            
            if effSatelliteRect == nil && rightCount > 0 {
                let totalRightWidth = CGFloat(rightCount) * (satSize + 8) + gap
                let satX = (viewWidth / 2.0) + (notchCardWidth / 2.0) + gap
                effSatelliteRect = CGRect(x: satX - 8, y: satY - 8, width: totalRightWidth + 16, height: satSize + 16)
            }
            
            if effLeftSatelliteRect == nil && appState.satelliteLocation == .bothSides && center.secondaryActivities.count >= 2 {
                let satX = (viewWidth / 2.0) - (notchCardWidth / 2.0) - gap - satSize
                effLeftSatelliteRect = CGRect(x: satX - 8, y: satY - 8, width: satSize + 16, height: satSize + 16)
            }
        }
        
        hitView.updateHitArea(activeRect, satelliteRect: effSatelliteRect, leftSatelliteRect: effLeftSatelliteRect)
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
                updateHitArea(width: geom.width + 190, height: max(50, geom.height + 14))
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
    
    // MARK: - Monitores Globales de Swipe con Trackpad (Garantizan captura en todo macOS)
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var swipeAccumY: CGFloat = 0.0
    private var swipeAccumX: CGFloat = 0.0
    private var lastSwipeActionTime: Date = .distantPast
    
    public func setupScrollSwipeMonitors() {
        if globalScrollMonitor == nil {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScrollEvent(event)
            }
        }
        if localScrollMonitor == nil {
            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScrollEvent(event)
                return event
            }
        }
    }
    
    private func handleScrollEvent(_ event: NSEvent) {
        guard AppState.shared.enableTrackpadSwipe else { return }
        
        // La inercia nunca debe disparar acciones
        if event.momentumPhase != [] { return }
        
        let mouseLoc = NSEvent.mouseLocation
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let notchCenterX = screenFrame.origin.x + (screenFrame.width / 2.0)
        let notchTopY = screenFrame.origin.y + screenFrame.height
        
        let dxFromCenter = abs(mouseLoc.x - notchCenterX)
        let dyFromTop = notchTopY - mouseLoc.y
        
        let rawDy = event.scrollingDeltaY
        let rawDx = event.scrollingDeltaX
        let isInverted = event.isDirectionInvertedFromDevice
        // fingerDy > 0: dedos hacia abajo en el trackpad (hacia el usuario)
        // fingerDy < 0: dedos hacia arriba en el trackpad (hacia el notch)
        // fingerDx > 0: dedos a la DERECHA
        // fingerDx < 0: dedos a la IZQUIERDA
        let fingerDy = isInverted ? rawDy : -rawDy
        let fingerDx = isInverted ? rawDx : -rawDx
        
        if event.phase == .began || event.phase == .mayBegin {
            swipeAccumY = 0
            swipeAccumX = 0
        }
        
        swipeAccumY += fingerDy
        swipeAccumX += fingerDx
        
        // Cooldown entre acciones ejecutadas
        guard Date().timeIntervalSince(lastSwipeActionTime) > 0.30 else { return }
        
        let mode = AppState.shared.mode
        
        // 0. PRIORIDAD: Actividad expandida o HUD de progreso de IA (Swipe Up para guardar/colapsar)
        if ActivityCenter.shared.expandedActivity != nil || AgentActivityProvider.shared.isProgressHUDExpanded {
            if dxFromCenter <= 300 && dyFromTop >= 0 && dyFromTop <= 280 {
                if (fingerDy < -0.6 || swipeAccumY < -1.5) && abs(fingerDy) > abs(fingerDx) {
                    lastSwipeActionTime = Date()
                    swipeAccumY = 0
                    DNDLogger.log("NotchWindowManager Monitor -> Swipe UP en actividad expandida! Contrayendo...")
                    DispatchQueue.main.async {
                        ActivityCenter.shared.collapseExpandedActivity()
                        AgentActivityProvider.shared.collapseProgressHUD()
                        AppState.shared.hapticService.triggerSnap()
                    }
                    return
                }
            }
        }
        
        // 1. MÁXIMA PRIORIDAD: Notificación activa (WhatsApp, Mensajes, Alertas)
        if NotificationActivityProvider.shared.isNotificationActive {
            if dxFromCenter <= 280 && dyFromTop >= 0 && dyFromTop <= 240 {
                if !NotificationActivityProvider.shared.isQuickReplyExpanded {
                    // Deslizar hacia abajo: expandir Quick Reply para responder de inmediato
                    if (fingerDy > 0.5 || swipeAccumY > 1.2) && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DNDLogger.log("NotchWindowManager Monitor -> Swipe DOWN en notificación detectado! expandQuickReply()")
                        DispatchQueue.main.async {
                            NotificationActivityProvider.shared.expandQuickReply()
                        }
                        return
                    } else if (fingerDy < -0.6 || swipeAccumY < -1.5) && abs(fingerDy) > abs(fingerDx) {
                        // Deslizar hacia arriba: descartar notificación
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DNDLogger.log("NotchWindowManager Monitor -> Swipe UP en notificación detectado! dismissNotification()")
                        DispatchQueue.main.async {
                            NotificationActivityProvider.shared.dismissNotification()
                        }
                        return
                    }
                } else {
                    // Si ya está abierto el cuadro de respuesta: deslizar hacia arriba para guardar
                    if (fingerDy < -0.6 || swipeAccumY < -1.5) && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DNDLogger.log("NotchWindowManager Monitor -> Swipe UP en Quick Reply! collapseQuickReply()")
                        DispatchQueue.main.async {
                            NotificationActivityProvider.shared.collapseQuickReply()
                        }
                        return
                    }
                }
            }
            return
        }
        
        // 2. PRIORIDAD: Llamada activa o entrante (FaceTime / Teléfono)
        if CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall {
            if dxFromCenter <= 260 && dyFromTop >= 0 && dyFromTop <= 160 {
                if !CallActivityProvider.shared.isExpandedCard {
                    let isDown = (fingerDy > 0.4 || (isInverted ? rawDy > 0.4 : rawDy < -0.4)) || swipeAccumY > 1.2
                    if isDown && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DNDLogger.log("NotchWindowManager Monitor -> Swipe down en llamada! Expandiendo tarjeta...")
                        DispatchQueue.main.async {
                            CallActivityProvider.shared.expandToCard()
                        }
                        return
                    }
                } else {
                    let isUp = (fingerDy < -1.0 || (isInverted ? rawDy < -1.0 : rawDy > 1.0)) || swipeAccumY < -5.0
                    if isUp && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DNDLogger.log("NotchWindowManager Monitor -> Swipe up en llamada! Contrayendo...")
                        DispatchQueue.main.async {
                            CallActivityProvider.shared.collapseToPill()
                        }
                        return
                    }
                }
            }
            return
        }
        
        // 3. PRIORIDAD: Interacción modal del Agente de IA (preguntas / permisos de terminal)
        if AgentActivityProvider.shared.isActive && AgentActivityProvider.shared.currentPayload != nil {
            if dxFromCenter <= 260 && dyFromTop >= 0 && dyFromTop <= 240 {
                if !AgentActivityProvider.shared.isExpanded {
                    if (fingerDy > 0.8 || swipeAccumY > 2.0) && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DispatchQueue.main.async {
                            AgentActivityProvider.shared.expandInteraction()
                        }
                        return
                    } else if (fingerDy < -0.8 || swipeAccumY < -2.0) && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DispatchQueue.main.async {
                            AgentActivityProvider.shared.dismissActivity()
                        }
                        return
                    }
                } else {
                    if (fingerDy < -0.8 || swipeAccumY < -2.0) && abs(fingerDy) > abs(fingerDx) {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DispatchQueue.main.async {
                            AgentActivityProvider.shared.collapseInteraction()
                        }
                        return
                    }
                }
            }
            return
        }
        
        // 4. MODO COLAPSADO (idle o compact): Deslizar hacia abajo para abrir reproductor
        if mode == .idle || mode == .compact {
            // Zona del notch: 260 pt a cada lado del centro y hasta 120 pt debajo del borde superior
            if dxFromCenter <= 260 && dyFromTop >= 0 && dyFromTop <= 120 {
                // Swipe hacia abajo
                let isDown = (fingerDy > 0.5 || (isInverted ? rawDy > 0.5 : rawDy < -0.5)) || swipeAccumY > 1.6
                if isDown && abs(fingerDy) > abs(fingerDx) {
                    lastSwipeActionTime = Date()
                    swipeAccumY = 0
                    DNDLogger.log("NotchWindowManager Monitor -> Swipe down detectado! Expandiendo Notch...")
                    DispatchQueue.main.async {
                        AppState.shared.expand()
                        AppState.shared.hapticService.triggerExpand()
                    }
                    return
                }
            }
        } else if mode == .expanded || mode == .shelf {
            // 4. MODO EXPANDIDO / BANDEJA: Zona del notch y tarjeta
            let maxHeight = AppState.shared.isPlayerDetailExpanded ? (PlayerMetrics.detailCardHeight + 70) : 270
            if dxFromCenter <= 260 && dyFromTop >= 0 && dyFromTop <= maxHeight {
                if abs(fingerDy) >= abs(fingerDx) * 1.02 && abs(swipeAccumX) < 20.0 {
                    swipeAccumX *= 0.4 // Decaer ruido horizontal durante swipe vertical
                    let isUp = (fingerDy < -1.0 || (isInverted ? rawDy < -1.0 : rawDy > 1.0)) || swipeAccumY < -5.0
                    let isDown = swipeAccumY > 14.0 || (fingerDy > 2.2 && swipeAccumY > 8.0)
                    if isUp {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DispatchQueue.main.async {
                            if AppState.shared.mode == .expanded && AppState.shared.isPlayerDetailExpanded {
                                DNDLogger.log("NotchWindowManager Monitor -> Swipe up detectado! Colapsando detalle de volumen...")
                                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                                    AppState.shared.isPlayerDetailExpanded = false
                                    AppState.shared.verticalOverscrollOffset = 0
                                    AppState.shared.contentVerticalOverscrollOffset = 0
                                }
                                AppState.shared.hapticService.triggerSnap()
                            } else {
                                DNDLogger.log("NotchWindowManager Monitor -> Swipe up detectado! Colapsando Notch...")
                                AppState.shared.collapse()
                                AppState.shared.hapticService.triggerSnap()
                            }
                        }
                    } else if isDown && mode == .expanded && !AppState.shared.isPlayerDetailExpanded {
                        lastSwipeActionTime = Date()
                        swipeAccumY = 0
                        DispatchQueue.main.async {
                            DNDLogger.log("NotchWindowManager Monitor -> Swipe down detectado! Expandiendo detalle de volumen...")
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                AppState.shared.isPlayerDetailExpanded = true
                                AppState.shared.verticalOverscrollOffset = 0
                                AppState.shared.contentVerticalOverscrollOffset = 0
                            }
                            AppState.shared.hapticService.triggerExpand()
                        }
                    }
                } else {
                    swipeAccumY = 0
                    // Deslizar horizontalmente con 2 dedos para cambiar de pestaña (Música <-> Repisa)
                    // Regla estricta de navegación espacial:
                    // - En Reproductor (.expanded): swipe hacia la IZQUIERDA (fingerDx < 0) va a la Bandeja (.shelf).
                    //   El swipe a la derecha (fingerDx > 0) es OVERSCROLL ELÁSTICO (no cambia de menú).
                    // - En Bandeja (.shelf): swipe hacia la DERECHA (fingerDx > 0) regresa a Música (.expanded).
                    //   El swipe a la izquierda (fingerDx < 0) es OVERSCROLL ELÁSTICO (no cambia de menú).
                    if mode == .expanded {
                        let isSwipeLeft = fingerDx < -0.8 || swipeAccumX < -4.0
                        // Solo permitir transición a Bandeja si NO estamos rebotando de un resorte hacia la derecha
                        if isSwipeLeft && AppState.shared.overscrollOffset <= 0.5 {
                            lastSwipeActionTime = Date()
                            swipeAccumX = 0
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    AppState.shared.mode = .shelf
                                    AppState.shared.activeTab = .shelf
                                }
                                AppState.shared.hapticService.triggerExpand()
                            }
                        }
                    } else if mode == .shelf {
                        let isSwipeRight = fingerDx > 0.8 || swipeAccumX > 4.0
                        // Solo permitir transición a Música si NO estamos rebotando de un resorte hacia la izquierda
                        if isSwipeRight && AppState.shared.overscrollOffset >= -0.5 {
                            lastSwipeActionTime = Date()
                            swipeAccumX = 0
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    AppState.shared.mode = .expanded
                                    AppState.shared.activeTab = .music
                                }
                                AppState.shared.hapticService.triggerExpand()
                            }
                        }
                    }
                }
            }
        }
    }
}
