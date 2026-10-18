import AppKit
import SwiftUI

public final class NotchPanel: NSPanel, NSDraggingDestination {
    public var hitTestBoundsProvider: (() -> CGRect)?
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar
        self.appearance = (AppState.shared.effectiveAppearanceMode == .clearGlass)
            ? NSAppearance(named: .aqua)
            : NSAppearance(named: .darkAqua)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
        self.registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
    }
    
    public var allowsKeyInput: Bool = false
    
    public override var canBecomeKey: Bool {
        return allowsKeyInput
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
    
    /// Crítico para Liquid Glass en un NSPanel (.nonactivatingPanel):
    /// Evita que AppKit y WindowServer degraden `Glass.clear` y `Glass.regular`
    /// al material gris oscuro uniforme de ventana inactiva cuando el usuario está en otra app.
    @objc public func _hasActiveAppearance() -> Bool {
        return true
    }
    
    // MARK: - Captura Universal de Gestos de Notificación (Swipe Down & Drag Down)
    private var notifGestureStartY: CGFloat = 0
    private var isTrackingNotifDrag: Bool = false
    // Bloqueo por gesto: un swipe físico genera decenas de eventos (dedos + inercia + rebote final).
    // Solo se permite UNA acción por gesto; si no, la inercia/rebote colapsaba la respuesta al instante.
    private var notifScrollAccum: CGFloat = 0
    private var notifScrollConsumed: Bool = false
    private var notifLastActionTime: Date = .distantPast
    
    // MARK: - Captura Universal de Gestos del Notch (Drag Down y Tap para Expandir)
    private var notchDragStartY: CGFloat = 0
    private var notchDragStartX: CGFloat = 0
    private var notchMouseDownTime: Date = .distantPast
    private var isTrackingNotchDrag: Bool = false
    
    public override func sendEvent(_ event: NSEvent) {
        let agentProvider = AgentActivityProvider.shared
        if agentProvider.isActive {
            switch event.type {
            case .scrollWheel:
                handleAgentScroll(event)
                return
            case .leftMouseDown:
                if !agentProvider.isExpanded {
                    notifGestureStartY = event.locationInWindow.y
                    isTrackingNotifDrag = true
                } else {
                    isTrackingNotifDrag = false
                    if !self.isKeyWindow {
                        NotchWindowManager.shared.setAllowsKeyInput(true)
                    }
                }
            case .leftMouseDragged:
                if isTrackingNotifDrag && !agentProvider.isExpanded {
                    let currentY = event.locationInWindow.y
                    let pullDown = notifGestureStartY - currentY
                    if pullDown > 0 {
                        agentProvider.dragPullOffset = min(pullDown * 0.45, 24)
                    }
                    if pullDown >= 6 {
                        isTrackingNotifDrag = false
                        agentProvider.dragPullOffset = 0
                        markNotifActionDone()
                        DNDLogger.log("NotchPanel.sendEvent -> agent drag down detectado! Expandiendo interacción")
                        agentProvider.expandInteraction()
                    } else if pullDown <= -10 {
                        isTrackingNotifDrag = false
                        agentProvider.dragPullOffset = 0
                        markNotifActionDone()
                        DNDLogger.log("NotchPanel.sendEvent -> agent drag up detectado! Descartando interacción")
                        agentProvider.dismissActivity()
                    }
                }
            case .leftMouseUp:
                isTrackingNotifDrag = false
                if agentProvider.dragPullOffset != 0 {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        agentProvider.dragPullOffset = 0
                    }
                }
            case .keyDown:
                if event.keyCode == 53 && agentProvider.isExpanded { // Escape
                    agentProvider.collapseInteraction()
                    return
                }
            default:
                break
            }
        }
        
        let provider = NotificationActivityProvider.shared
        if provider.isNotificationActive {
            switch event.type {
            case .scrollWheel:
                handleNotificationScroll(event)
                // Tragar SIEMPRE el scroll mientras hay notificación: evita que el handler secundario
                // de NotchHitTestView.scrollWheel reinterprete la inercia como "swipe hacia arriba".
                return
                
            case .leftMouseDown:
                if !provider.isQuickReplyExpanded {
                    notifGestureStartY = event.locationInWindow.y
                    isTrackingNotifDrag = true
                } else {
                    isTrackingNotifDrag = false
                    if !self.isKeyWindow {
                        NotchWindowManager.shared.setAllowsKeyInput(true)
                    }
                }
                
            case .leftMouseDragged:
                if isTrackingNotifDrag && !provider.isQuickReplyExpanded {
                    // En coordenadas de ventana de macOS, y=0 está en el borde inferior.
                    // Si el usuario arrastra el cursor hacia abajo: currentY < startY (pullDown > 0)
                    let currentY = event.locationInWindow.y
                    let pullDown = notifGestureStartY - currentY
                    
                    if pullDown > 0 {
                        provider.dragPullOffset = min(pullDown * 0.45, 24)
                    }
                    
                    if pullDown >= 6 {
                        isTrackingNotifDrag = false
                        provider.dragPullOffset = 0
                        markNotifActionDone()
                        DNDLogger.log("NotchPanel.sendEvent -> drag down detectado (pullDown=\(pullDown))! Expandiendo QuickReply")
                        provider.expandQuickReply()
                    } else if pullDown <= -10 {
                        isTrackingNotifDrag = false
                        provider.dragPullOffset = 0
                        markNotifActionDone()
                        DNDLogger.log("NotchPanel.sendEvent -> drag up detectado (pullDown=\(pullDown))! Descartando Notificación")
                        provider.dismissNotification()
                    }
                }
                
            case .leftMouseUp:
                isTrackingNotifDrag = false
                if provider.dragPullOffset != 0 {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        provider.dragPullOffset = 0
                    }
                }
                
            case .keyDown:
                if event.keyCode == 53 && provider.isQuickReplyExpanded { // Tecla Escape (Esc)
                    provider.collapseQuickReply()
                    return
                }
                
            default:
                break
            }
        } else {
            // Gestos de arrastre directos en el Notch general cuando está colapsado (idle / compact)
            switch event.type {
            case .leftMouseDown:
                if let hitView = contentView as? NotchHitTestView {
                    let point = hitView.convert(event.locationInWindow, from: nil)
                    let centerX = hitView.bounds.width / 2.0
                    let isNearNotch = (point.y >= hitView.bounds.height - 100) && (abs(point.x - centerX) <= 260)
                    let detectionRect = hitView.hitAreaRect.insetBy(dx: -40, dy: -40)
                    if (detectionRect.contains(point) || isNearNotch) &&
                        AppState.shared.mode != .expanded && AppState.shared.mode != .shelf && ActivityCenter.shared.currentActivity == nil {
                        notchDragStartY = event.locationInWindow.y
                        notchDragStartX = event.locationInWindow.x
                        notchMouseDownTime = Date()
                        isTrackingNotchDrag = true
                    }
                }
                
            case .leftMouseDragged:
                if isTrackingNotchDrag && AppState.shared.mode != .expanded && AppState.shared.mode != .shelf {
                    let currentY = event.locationInWindow.y
                    let pullDown = notchDragStartY - currentY
                    if pullDown >= 8 {
                        isTrackingNotchDrag = false
                        DNDLogger.log("NotchPanel.sendEvent -> Arrastre hacia abajo detectado (\(pullDown)pt). ¡Expandiendo Notch!")
                        DispatchQueue.main.async {
                            AppState.shared.expand()
                            AppState.shared.hapticService.triggerExpand()
                        }
                        return
                    }
                }
                
            case .leftMouseUp:
                if isTrackingNotchDrag && AppState.shared.mode != .expanded && AppState.shared.mode != .shelf {
                    isTrackingNotchDrag = false
                    let currentX = event.locationInWindow.x
                    let currentY = event.locationInWindow.y
                    let dist = hypot(currentX - notchDragStartX, currentY - notchDragStartY)
                    let duration = Date().timeIntervalSince(notchMouseDownTime)
                    if dist <= 10.0 && duration < 0.65 {
                        DNDLogger.log("NotchPanel.sendEvent -> Tap directo detectado en Notch colapsado! Expandiendo...")
                        DispatchQueue.main.async {
                            AppState.shared.expand()
                            AppState.shared.hapticService.triggerExpand()
                        }
                        return
                    }
                }
                isTrackingNotchDrag = false
                
            default:
                break
            }
        }
        
        // Despacho directo de scroll de trackpad al NotchHitTestView cuando el cursor está en el área del notch
        if event.type == .scrollWheel, let hitView = contentView as? NotchHitTestView {
            let point = hitView.convert(event.locationInWindow, from: nil)
            let centerX = hitView.bounds.width / 2.0
            let isNearNotch = (point.y >= hitView.bounds.height - 320) && (abs(point.x - centerX) <= 340)
            let detectionRect = hitView.hitAreaRect.insetBy(dx: -80, dy: -120)
            if detectionRect.contains(point) || isNearNotch || hitView.isTrackingTrackpadGesture {
                hitView.scrollWheel(with: event)
                return
            }
        }
        
        super.sendEvent(event)
    }
    
    private func handleNotificationScroll(_ event: NSEvent) {
        let provider = NotificationActivityProvider.shared
        
        // Inicio de un nuevo gesto físico: reiniciar bloqueo
        if event.phase == .began || event.phase == .mayBegin {
            notifScrollAccum = 0
            notifScrollConsumed = false
        }
        
        // La inercia (momentum) nunca dispara acciones: es la causa del "abre y se cierra solo"
        if event.momentumPhase != [] { return }
        // Ya se ejecutó una acción en este gesto
        if notifScrollConsumed { return }
        // Cooldown tras la última acción (cubre ratones con rueda que no tienen fases)
        if Date().timeIntervalSince(notifLastActionTime) < 0.38 { return }
        
        let rawDy = event.scrollingDeltaY
        // Normalización física precisa:
        // fingerDy > 0: dedos se desplazan hacia ABAJO en el trackpad (hacia el usuario)
        // fingerDy < 0: dedos se desplazan hacia ARRIBA en el trackpad (hacia el notch)
        let fingerDy = event.isDirectionInvertedFromDevice ? rawDy : -rawDy
        // Rueda de ratón clásica (sin fases): cada "clic" de rueda cuenta como gesto
        let isDiscreteWheel = event.phase == [] && event.momentumPhase == []
        notifScrollAccum += fingerDy
        
        if !provider.isQuickReplyExpanded {
            let downThreshold: CGFloat = isDiscreteWheel ? 0.8 : 2.0
            let upThreshold: CGFloat = isDiscreteWheel ? -2.0 : -8.0
            
            if notifScrollAccum >= downThreshold || fingerDy >= downThreshold {
                DNDLogger.log("NotchPanel: swipe DOWN detectado -> expandQuickReply (accum=\(notifScrollAccum), fingerDy=\(fingerDy))")
                markNotifActionDone()
                provider.expandQuickReply()
            } else if notifScrollAccum <= upThreshold || fingerDy <= upThreshold {
                DNDLogger.log("NotchPanel: swipe UP detectado -> dismissNotification (accum=\(notifScrollAccum))")
                markNotifActionDone()
                provider.dismissNotification()
            }
        } else {
            // Cuando el cuadro de respuesta ya está abierto, exigir un swipe hacia arriba claro e intencional
            // para evitar que un roce accidental del trackpad al pasar las manos al teclado cierre la respuesta.
            let collapseUpThreshold: CGFloat = isDiscreteWheel ? -3.0 : -16.0
            if notifScrollAccum <= collapseUpThreshold {
                DNDLogger.log("NotchPanel: swipe UP intencional detectado -> collapseQuickReply (accum=\(notifScrollAccum))")
                markNotifActionDone()
                provider.collapseQuickReply()
            }
        }
        
        // Fin del gesto
        if event.phase == .ended || event.phase == .cancelled {
            notifScrollAccum = 0
            notifScrollConsumed = false
        }
    }
    
    private func handleAgentScroll(_ event: NSEvent) {
        let provider = AgentActivityProvider.shared
        
        if event.phase == .began || event.phase == .mayBegin {
            notifScrollAccum = 0
            notifScrollConsumed = false
        }
        
        if event.momentumPhase != [] { return }
        if notifScrollConsumed { return }
        if Date().timeIntervalSince(notifLastActionTime) < 0.38 { return }
        
        let rawDy = event.scrollingDeltaY
        let fingerDy = event.isDirectionInvertedFromDevice ? rawDy : -rawDy
        let isDiscreteWheel = event.phase == [] && event.momentumPhase == []
        notifScrollAccum += fingerDy
        
        if !provider.isExpanded {
            let downThreshold: CGFloat = isDiscreteWheel ? 0.8 : 2.0
            let upThreshold: CGFloat = isDiscreteWheel ? -2.0 : -8.0
            
            if notifScrollAccum >= downThreshold || fingerDy >= downThreshold {
                DNDLogger.log("NotchPanel: swipe DOWN detectado -> expandInteraction (accum=\(notifScrollAccum), fingerDy=\(fingerDy))")
                markNotifActionDone()
                provider.expandInteraction()
            } else if notifScrollAccum <= upThreshold || fingerDy <= upThreshold {
                DNDLogger.log("NotchPanel: swipe UP detectado -> dismissActivity (accum=\(notifScrollAccum))")
                markNotifActionDone()
                provider.dismissActivity()
            }
        } else {
            let collapseUpThreshold: CGFloat = isDiscreteWheel ? -3.0 : -16.0
            if notifScrollAccum <= collapseUpThreshold {
                DNDLogger.log("NotchPanel: swipe UP detectado -> collapseInteraction (accum=\(notifScrollAccum))")
                markNotifActionDone()
                provider.collapseInteraction()
            }
        }
        
        if event.phase == .ended || event.phase == .cancelled {
            notifScrollAccum = 0
            notifScrollConsumed = false
        }
    }
    
    private func markNotifActionDone() {
        notifScrollConsumed = true
        notifScrollAccum = 0
        notifLastActionTime = Date()
    }
    
    // MARK: - NSDraggingDestination en NotchPanel
    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DNDLogger.log("NotchPanel.draggingEntered")
        return (contentView as? NotchHitTestView)?.draggingEntered(sender) ?? .move
    }
    
    public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return (contentView as? NotchHitTestView)?.draggingUpdated(sender) ?? .move
    }
    
    public func draggingExited(_ sender: NSDraggingInfo?) {
        DNDLogger.log("NotchPanel.draggingExited")
        (contentView as? NotchHitTestView)?.draggingExited(sender)
    }
    
    public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return (contentView as? NotchHitTestView)?.prepareForDragOperation(sender) ?? true
    }
    
    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DNDLogger.log("NotchPanel.performDragOperation")
        return (contentView as? NotchHitTestView)?.performDragOperation(sender) ?? false
    }
}

// Subclase de NSHostingView que no traga eventos de arrastre y los delega a NotchHitTestView
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    @MainActor @preconcurrency required public init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return (superview as? NotchHitTestView)?.draggingEntered(sender) ?? .move
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return (superview as? NotchHitTestView)?.draggingUpdated(sender) ?? .move
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        (superview as? NotchHitTestView)?.draggingExited(sender)
    }
    
    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return (superview as? NotchHitTestView)?.performDragOperation(sender) ?? true
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

public final class NotchHitTestView: NSView {
    public var hitAreaRect: CGRect = .zero
    public var satelliteHitAreaRect: CGRect? = nil
    public var leftSatelliteHitAreaRect: CGRect? = nil
    public internal(set) var isTrackingTrackpadGesture: Bool = false
    private var trackingArea: NSTrackingArea?
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
    }
    
    private func isDraggingSessionActive() -> Bool {
        return DragDetectionProbe.shared.isDragging || AppState.shared.isDropInvitationActive || AppState.shared.isShelfDragTargeted
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let isDragging = isDraggingSessionActive()
        
        // 1. Si hay una sesión de arrastre activa (invitación de soltado o sonda detectó arrastre):
        // Si el cursor está en el área visible del notch o en la zona receptora amplia:
        // Devolver DIRECTAMENTE self (NotchHitTestView) para que AppKit entregue los eventos de arrastre a self
        if isDragging {
            let isNearDropZone = point.y >= (bounds.height - 320) && abs(point.x - (bounds.width / 2.0)) <= 320
            if isNearDropZone || hitAreaRect.contains(point) || (satelliteHitAreaRect?.contains(point) == true) || (leftSatelliteHitAreaRect?.contains(point) == true) {
                return self
            }
        }
        
        // 2. Si el punto está dentro del área visible activa del notch o en las bolitas satélite disjuntas:
        // Delegar SIEMPRE a la jerarquía SwiftUI (NotchHostingView) para que funcionen los clics, botones y gestos
        if hitAreaRect.contains(point) || (satelliteHitAreaRect?.contains(point) == true) || (leftSatelliteHitAreaRect?.contains(point) == true) {
            return super.hitTest(point) ?? subviews.first ?? self
        }
        
        return nil
    }
    
    public func updateHitArea(_ rect: CGRect, satelliteRect: CGRect? = nil, leftSatelliteRect: CGRect? = nil) {
        self.hitAreaRect = rect
        self.satelliteHitAreaRect = satelliteRect
        self.leftSatelliteHitAreaRect = leftSatelliteRect
        updateTrackingAreas()
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    public override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hitAreaRect.contains(point) {
            AppState.shared.handleMouseEnter()
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        AppState.shared.handleMouseLeave()
    }
    
    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let isInside = hitAreaRect.contains(point)
        if isInside && !AppState.shared.isHovered {
            AppState.shared.handleMouseEnter()
        } else if !isInside && AppState.shared.isHovered {
            AppState.shared.handleMouseLeave()
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 1. Clic en la burbuja satélite desprendida de la Dynamic Island (hit test explícito o geométrico)
        if let satRect = satelliteHitAreaRect, satRect.contains(point) {
            DNDLogger.log("NotchHitTestView.mouseDown: Tap en la burbuja satélite detectado -> alternando HUD de IA")
            DispatchQueue.main.async {
                AgentActivityProvider.shared.toggleProgressHUD()
            }
            return
        }
        
        // Comprobación geométrica robusta de las bolitas satélite secundarias (tolerancia de 12 pt)
        let center = ActivityCenter.shared
        if !center.secondaryActivities.isEmpty && center.expandedActivity == nil {
            let satSize = AppState.shared.bolitaDiameter
            let gap = AppState.shared.bolitaGap
            let geom = ScreenService.shared.currentGeometry
            let wingExtra: CGFloat = (!AppState.shared.shelfItems.isEmpty && AppState.shared.showShelfBadgeInNotch) ? 24 : 0
            let notchCardWidth: CGFloat = (AppState.shared.mode == .compact)
                ? (geom.width + 104 + (wingExtra * 2))
                : (!AppState.shared.shelfItems.isEmpty ? (geom.width + 96) : geom.width)
            
            let satY = bounds.height - geom.height - 4
            let rightCount = center.secondaryActivities.count + (center.overflowCount > 0 ? 1 : 0)
            let totalRightWidth = CGFloat(rightCount) * (satSize + 8) + gap
            let satX = (bounds.width / 2.0) + (notchCardWidth / 2.0) + gap
            let rightSatRect = CGRect(x: satX - 10, y: satY - 10, width: totalRightWidth + 20, height: satSize + 20)
            
            if rightSatRect.contains(point) {
                DNDLogger.log("NotchHitTestView.mouseDown: Tap directo en área de bolitas satélite -> alternando HUD de IA")
                DispatchQueue.main.async {
                    AgentActivityProvider.shared.toggleProgressHUD()
                }
                return
            }
        }
        
        // 2. Clic en el cuerpo principal del Notch
        if hitAreaRect.contains(point) {
            // Si el Notch está colapsado (idle o compact) y no hay actividad modal activa, expandir al dar tap
            if AppState.shared.mode != .expanded && AppState.shared.mode != .shelf && ActivityCenter.shared.currentActivity == nil {
                DNDLogger.log("NotchHitTestView.mouseDown: Tap directo en el notch detectado -> expandiendo")
                DispatchQueue.main.async {
                    AppState.shared.expand()
                }
                return
            }
        }
        super.mouseDown(with: event)
    }
    
    // MARK: - Gestos de Trackpad (Swipe con 2 dedos: deslizamiento horizontal con overscroll elástico + scroll vertical)
    private var accumulatedScrollDeltaX: CGFloat = 0.0
    private var accumulatedScrollDeltaY: CGFloat = 0.0
    private var lastScrollSwipeTime: Date = Date.distantPast
    private var lastCollapseDetailTime: Date = Date.distantPast
    private var playerDetailSwipeCount: Int = 0
    private var lastDetailSwipeTime: Date = Date.distantPast
    private var hasCollapsedDetailInCurrentGesture: Bool = false
    private var hasExpandedInCurrentGesture: Bool = false
    private var hasSwitchedPageInCurrentGesture: Bool = false
    private var hasTriggeredHapticInScroll: Bool = false
    private var isIgnoringMomentumForOverscroll: Bool = false
    private var trackpadResetTimer: Timer?
    
    private func resetTrackpadOverscroll() {
        isTrackingTrackpadGesture = false
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        hasTriggeredHapticInScroll = false
        hasExpandedInCurrentGesture = false
        hasSwitchedPageInCurrentGesture = false
        hasCollapsedDetailInCurrentGesture = false
        
        if AppState.shared.overscrollOffset != 0 || AppState.shared.contentOverscrollOffset != 0 {
            // Desfase orgánico horizontal
            withAnimation(AnimationSpeedManager.shared.spring(
                response: OverscrollMetrics.shapeSpringResponse,
                dampingFraction: OverscrollMetrics.shapeSpringDamping
            )) {
                AppState.shared.overscrollOffset = 0
            }
            withAnimation(AnimationSpeedManager.shared.spring(
                response: OverscrollMetrics.contentSpringResponse,
                dampingFraction: OverscrollMetrics.contentSpringDamping
            )) {
                AppState.shared.contentOverscrollOffset = 0
            }
        }
        
        if AppState.shared.verticalOverscrollOffset != 0 || AppState.shared.contentVerticalOverscrollOffset != 0 {
            // Desfase orgánico vertical: la forma regresa con spring rápido y el contenido con spring suave
            withAnimation(AnimationSpeedManager.shared.spring(
                response: OverscrollMetrics.shapeSpringResponse,
                dampingFraction: OverscrollMetrics.shapeSpringDamping
            )) {
                AppState.shared.verticalOverscrollOffset = 0
            }
            withAnimation(AnimationSpeedManager.shared.spring(
                response: OverscrollMetrics.contentSpringResponse,
                dampingFraction: OverscrollMetrics.contentSpringDamping
            )) {
                AppState.shared.contentVerticalOverscrollOffset = 0
            }
        }
        
        if AppState.shared.trackpadDragOffsetY != 0 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                AppState.shared.trackpadDragOffsetY = 0
            }
            AppState.shared.hapticService.triggerSnap()
        }
        
        // Watchdog de snap estricto: asegura que los valores residuales (< 0.5 pt) queden en 0.0 absoluto
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if abs(AppState.shared.overscrollOffset) < OverscrollMetrics.snapThreshold {
                AppState.shared.overscrollOffset = 0
            }
            if abs(AppState.shared.contentOverscrollOffset) < OverscrollMetrics.snapThreshold {
                AppState.shared.contentOverscrollOffset = 0
            }
            if abs(AppState.shared.verticalOverscrollOffset) < OverscrollMetrics.snapThreshold {
                AppState.shared.verticalOverscrollOffset = 0
            }
            if abs(AppState.shared.contentVerticalOverscrollOffset) < OverscrollMetrics.snapThreshold {
                AppState.shared.contentVerticalOverscrollOffset = 0
            }
        }
    }
    
    public override func scrollWheel(with event: NSEvent) {
        guard AppState.shared.enableTrackpadSwipe else {
            super.scrollWheel(with: event)
            return
        }
        
        if event.phase == .began {
            isTrackingTrackpadGesture = true
            hasCollapsedDetailInCurrentGesture = false
            hasExpandedInCurrentGesture = false
            hasSwitchedPageInCurrentGesture = false
            hasTriggeredHapticInScroll = false
            isIgnoringMomentumForOverscroll = false
            accumulatedScrollDeltaX = 0
            accumulatedScrollDeltaY = 0
            // Interrumpible: toma los valores actuales de overscroll y continúa suavemente
            if AppState.shared.overscrollOffset != 0 {
                accumulatedScrollDeltaX = AppState.shared.overscrollOffset
            }
            if AppState.shared.verticalOverscrollOffset != 0 {
                accumulatedScrollDeltaY = AppState.shared.verticalOverscrollOffset
            }
        }
        
        // Al cambiar de página o al terminar el overscroll, ignorar todo el momentumPhase
        if event.momentumPhase != [] {
            if isIgnoringMomentumForOverscroll || hasSwitchedPageInCurrentGesture || hasExpandedInCurrentGesture {
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                    isIgnoringMomentumForOverscroll = false
                    hasSwitchedPageInCurrentGesture = false
                    hasExpandedInCurrentGesture = false
                }
                return
            }
        }
        
        let isInverted = event.isDirectionInvertedFromDevice
        let rawDeltaX = event.scrollingDeltaX
        let rawDeltaY = event.scrollingDeltaY
        
        // Normalización física de dirección de los dedos:
        // fingerDeltaX > 0: dedos a la DERECHA
        // fingerDeltaX < 0: dedos a la IZQUIERDA
        // fingerDeltaY > 0: dedos hacia ABAJO (hacia el usuario)
        // fingerDeltaY < 0: dedos hacia ARRIBA (hacia el notch)
        let fingerDeltaX = isInverted ? rawDeltaX : -rawDeltaX
        let fingerDeltaY = isInverted ? rawDeltaY : -rawDeltaY
        
        let isExpandedOrShelf = AppState.shared.mode == .expanded || AppState.shared.mode == .shelf
        let isCompactOrIdle = AppState.shared.mode == .compact || AppState.shared.mode == .idle
        
        // Watchdog de seguridad (0.35 s): si los dedos se detienen durante overscroll, regresa automáticamente
        trackpadResetTimer?.invalidate()
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.resetTrackpadOverscroll()
        }
        RunLoop.main.add(timer, forMode: .common)
        trackpadResetTimer = timer
        
        // 1. SCROLL VERTICAL CON 2 DEDOS (Pastilla extendida, estiramiento elástico y guardado de píldora)
        if abs(fingerDeltaY) > abs(fingerDeltaX) && abs(fingerDeltaY) > 0.3 {
            accumulatedScrollDeltaY += fingerDeltaY
            accumulatedScrollDeltaX *= 0.4 // Decaer la acumulación horizontal para que el ruido lateral no bloquee el estiramiento vertical
            
            // PRIORIDAD 1: Si hay notificación activa en pantalla
            if NotificationActivityProvider.shared.isNotificationActive {
                DNDLogger.log("scrollWheel [Notif]: rawY=\(rawDeltaY), fingerY=\(fingerDeltaY), accumY=\(accumulatedScrollDeltaY)")
                if !NotificationActivityProvider.shared.isQuickReplyExpanded {
                    // Deslizar hacia abajo (dedos hacia el usuario / hacia la pantalla) -> Expandir respuesta rápida
                    if (fingerDeltaY > 0.3 || rawDeltaY > 0.3 || accumulatedScrollDeltaY > 0.6) {
                        guard !hasExpandedInCurrentGesture else { return }
                        lastScrollSwipeTime = Date()
                        hasExpandedInCurrentGesture = true
                        isIgnoringMomentumForOverscroll = true
                        accumulatedScrollDeltaY = 0
                        DNDLogger.log("scrollWheel -> expandQuickReply() disparado con éxito!")
                        NotificationActivityProvider.shared.expandQuickReply()
                        return
                    } else if (fingerDeltaY < -0.3 || rawDeltaY < -0.3 || accumulatedScrollDeltaY < -0.6) {
                        // Deslizar hacia arriba (dedos hacia el notch) -> Descartar notificación al notch
                        guard !hasExpandedInCurrentGesture else { return }
                        lastScrollSwipeTime = Date()
                        hasExpandedInCurrentGesture = true
                        isIgnoringMomentumForOverscroll = true
                        accumulatedScrollDeltaY = 0
                        DNDLogger.log("scrollWheel -> dismissNotification() disparado con éxito!")
                        NotificationActivityProvider.shared.dismissNotification()
                        return
                    }
                } else {
                    // Si ya está expandida y desliza hacia arriba -> Guardar/colapsar
                    if (fingerDeltaY < -0.4 || rawDeltaY < -0.4 || accumulatedScrollDeltaY < -0.8) {
                        accumulatedScrollDeltaY = 0
                        DNDLogger.log("scrollWheel -> collapseQuickReply() disparado!")
                        NotificationActivityProvider.shared.collapseQuickReply()
                        return
                    }
                }
                return
            }
            
            if fingerDeltaY > 0 {
                // Dedos hacia abajo:
                if AppState.shared.mode == .expanded {
                    if !AppState.shared.isPlayerDetailExpanded {
                        // Bloquear expansión al detalle secundario si en este mismo swipe ya se expandió (evita saltarse el reproductor normal en swipes rápidos)
                        guard !hasExpandedInCurrentGesture else { return }
                        
                        // Permitir estiramiento vertical natural sin que un micro-desplazamiento horizontal de 4pt lo cancele
                        guard abs(fingerDeltaY) >= abs(fingerDeltaX) * 1.02 && abs(accumulatedScrollDeltaX) < 20.0 else {
                            accumulatedScrollDeltaY *= 0.5
                            AppState.shared.verticalOverscrollOffset = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                            return
                        }
                        
                        // Estiramiento vertical elástico hacia abajo (anclado arriba al notch)
                        let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                        AppState.shared.verticalOverscrollOffset = stretch
                        AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                        
                        // Umbral deliberado hacia abajo (> 14 pt acumulados o impulso hacia abajo rápido)
                        let isDown = accumulatedScrollDeltaY > 14.0 || (fingerDeltaY > 2.2 && accumulatedScrollDeltaY > 8.0)
                        if isDown && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                AppState.shared.isPlayerDetailExpanded = true
                                AppState.shared.verticalOverscrollOffset = 0
                                AppState.shared.contentVerticalOverscrollOffset = 0
                            }
                            AppState.shared.hapticService.triggerExpand()
                            return
                        }
                    } else {
                        // Ya está expandida al máximo: estirar SOLO hacia abajo con rebote elástico (anclado arriba)
                        let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                        AppState.shared.verticalOverscrollOffset = stretch
                        AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                    }
                } else if CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall {
                    guard !hasExpandedInCurrentGesture else { return }
                    if CallActivityProvider.shared.isExpandedCard {
                        // Si está en llamada con tarjeta extendida y hace swipe hacia abajo:
                        // Mostrar reproductor NORMAL (sin volumen)
                        if accumulatedScrollDeltaY > 16 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.28 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            CallActivityProvider.shared.collapseToPill()
                            AppState.shared.isPlayerDetailExpanded = false
                            AppState.shared.expand()
                        }
                    } else {
                        // Llamada compacta en notch: expandir tarjeta de llamada de forma ágil y natural
                        if (accumulatedScrollDeltaY > 1.2 || fingerDeltaY > 0.4 || rawDeltaY > 0.4) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            DNDLogger.log("NotchHitTestView -> Swipe down en llamada! expandToCard()")
                            DispatchQueue.main.async {
                                CallActivityProvider.shared.expandToCard()
                            }
                        }
                    }
                    return
                } else if ActivityCenter.shared.currentActivity?.style == .card {
                    // Si hay una tarjeta modal activa (como llamada o alerta), no invadir con el reproductor
                    return
                } else if AppState.shared.mode == .shelf {
                    // Bandeja temporal (Drag and Drop): estiramiento elástico hacia abajo,
                    // vuelve a su forma original de forma natural (no hay menú extendido secundario)
                    let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                    AppState.shared.verticalOverscrollOffset = stretch
                    AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                } else if isCompactOrIdle {
                    guard ActivityCenter.shared.currentActivity?.style != .card else { return }
                    guard !NotificationActivityProvider.shared.isNotificationActive else { return }
                    guard !hasExpandedInCurrentGesture else { return }
                    if (accumulatedScrollDeltaY > 1.4 || fingerDeltaY > 0.4 || rawDeltaY > 0.4) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                        lastScrollSwipeTime = Date()
                        hasExpandedInCurrentGesture = true
                        isIgnoringMomentumForOverscroll = true
                        accumulatedScrollDeltaY = 0
                        DNDLogger.log("scrollWheel -> Expandiendo Notch por swipe hacia abajo!")
                        DispatchQueue.main.async {
                            AppState.shared.expand()
                            AppState.shared.hapticService.triggerExpand()
                        }
                        return
                    }
                }
            } else if fingerDeltaY < 0 {
                // Dedos hacia arriba (hacia el notch):
                
                // PRIORIDAD 0: Live Activity expandida o HUD de progreso de IA (Swipe up para guardar/colapsar)
                if ActivityCenter.shared.expandedActivity != nil || AgentActivityProvider.shared.isProgressHUDExpanded {
                    if (accumulatedScrollDeltaY <= -1.0 || fingerDeltaY < -0.35 || rawDeltaY < -0.35) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.10 {
                        lastScrollSwipeTime = Date()
                        accumulatedScrollDeltaY = 0
                        isIgnoringMomentumForOverscroll = true
                        DNDLogger.log("NotchPanel.scrollWheel -> Swipe UP en actividad expandida! Contrayendo hacia el notch...")
                        DispatchQueue.main.async {
                            ActivityCenter.shared.collapseExpandedActivity()
                            AgentActivityProvider.shared.collapseProgressHUD()
                            AppState.shared.hapticService.triggerSnap()
                        }
                        return
                    }
                }
                
                if NotificationActivityProvider.shared.isNotificationActive {
                    if (accumulatedScrollDeltaY < -3 || fingerDeltaY < -0.8 || rawDeltaY < -0.8) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                        lastScrollSwipeTime = Date()
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            if NotificationActivityProvider.shared.isQuickReplyExpanded {
                                NotificationActivityProvider.shared.collapseQuickReply()
                            } else {
                                NotificationActivityProvider.shared.dismissNotification()
                            }
                        }
                        return
                    }
                }
                
                if (CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall) && CallActivityProvider.shared.isExpandedCard {
                    if (accumulatedScrollDeltaY < -6 || fingerDeltaY < -1.0 || rawDeltaY < -1.0) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                        lastScrollSwipeTime = Date()
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            CallActivityProvider.shared.collapseToPill()
                        }
                        return
                    }
                }
                
                if AppState.shared.mode == .expanded && AppState.shared.isPlayerDetailExpanded {
                    let isUp = (accumulatedScrollDeltaY <= -2.0 || fingerDeltaY < -0.4 || rawDeltaY < -0.4)
                    if isUp && Date().timeIntervalSince(lastScrollSwipeTime) > 0.10 {
                        lastScrollSwipeTime = Date()
                        lastCollapseDetailTime = Date()
                        hasCollapsedDetailInCurrentGesture = true
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            self.playerDetailSwipeCount = 0
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                                AppState.shared.isPlayerDetailExpanded = false
                                AppState.shared.verticalOverscrollOffset = 0
                                AppState.shared.contentVerticalOverscrollOffset = 0
                            }
                            AppState.shared.hapticService.triggerSnap()
                        }
                        return
                    }
                } else if isExpandedOrShelf && !AppState.shared.isPlayerDetailExpanded {
                    // Si había vertical overscroll hacia abajo, regresar suavemente a 0
                    if AppState.shared.verticalOverscrollOffset > 0 {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            AppState.shared.verticalOverscrollOffset = 0
                            AppState.shared.contentVerticalOverscrollOffset = 0
                        }
                    }
                    
                    // Si está en pastilla normal y hace scroll hacia arriba: ¡GUARDAR LA PÍLDORA!
                    guard !hasCollapsedDetailInCurrentGesture else { return }
                    guard !hasSwitchedPageInCurrentGesture else { return }
                    guard abs(AppState.shared.overscrollOffset) < 4.0 else { return }
                    guard Date().timeIntervalSince(lastCollapseDetailTime) > 0.15 else { return }
                    guard abs(fingerDeltaY) >= abs(fingerDeltaX) else { return }
                    
                    // Gesto intencional hacia arriba (mínimo -2.0 pt acumulados o impulso rápido)
                    if (accumulatedScrollDeltaY <= -2.0 || fingerDeltaY < -0.4 || rawDeltaY < -0.4) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
                        lastScrollSwipeTime = Date()
                        lastCollapseDetailTime = Date()
                        hasCollapsedDetailInCurrentGesture = true
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            AppState.shared.collapse()
                            AppState.shared.hapticService.triggerSnap()
                        }
                    }
                }
            }
        } else if isExpandedOrShelf && abs(fingerDeltaX) > abs(fingerDeltaY) && abs(fingerDeltaX) > 0.3 {
            // 2. DESPLAZAMIENTO HORIZONTAL CON 2 DEDOS (Paginación limpia o overscroll elástico en los bordes)
            accumulatedScrollDeltaX += fingerDeltaX
            accumulatedScrollDeltaY = 0
            AppState.shared.verticalOverscrollOffset = 0
            AppState.shared.contentVerticalOverscrollOffset = 0
            let mode = AppState.shared.mode
            
            DispatchQueue.main.async {
                if mode == .expanded {
                    if self.accumulatedScrollDeltaX > 0 {
                        // En Menú 1 (Música): hacia la derecha NO hay menú más allá -> EFECTO DE OVERSCROLL ELÁSTICO
                        let stretch = OverscrollMetrics.calculateStretch(for: self.accumulatedScrollDeltaX)
                        AppState.shared.overscrollOffset = stretch
                        AppState.shared.contentOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                        if abs(stretch) > 2.0 && !self.hasTriggeredHapticInScroll {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            self.hasTriggeredHapticInScroll = true
                        }
                    } else {
                        // Dedos a la izquierda hacia la Bandeja:
                        // Si se estaba estirando a la derecha (resorte), jamás cambiar de menú al soltar
                        guard AppState.shared.overscrollOffset <= 0.5 else { return }
                        if !self.hasSwitchedPageInCurrentGesture {
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                            if self.accumulatedScrollDeltaX < -4.0 && Date().timeIntervalSince(self.lastScrollSwipeTime) > 0.12 {
                                self.lastScrollSwipeTime = Date()
                                self.accumulatedScrollDeltaX = 0
                                self.hasSwitchedPageInCurrentGesture = true
                                self.isIgnoringMomentumForOverscroll = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    AppState.shared.mode = .shelf
                                    AppState.shared.activeTab = .shelf
                                    AppState.shared.overscrollOffset = 0
                                    AppState.shared.contentOverscrollOffset = 0
                                }
                                AppState.shared.hapticService.triggerSnap()
                            }
                        } else {
                            // Ya se cambió de pestaña en este gesto: no acumular arrastre fantasma
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                        }
                    }
                } else if mode == .shelf {
                    if self.accumulatedScrollDeltaX < 0 {
                        // En Menú 2 (Bandeja): hacia la izquierda NO hay menú más allá -> EFECTO DE OVERSCROLL ELÁSTICO
                        let stretch = OverscrollMetrics.calculateStretch(for: self.accumulatedScrollDeltaX)
                        AppState.shared.overscrollOffset = stretch
                        AppState.shared.contentOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                        if abs(stretch) > 2.0 && !self.hasTriggeredHapticInScroll {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            self.hasTriggeredHapticInScroll = true
                        }
                    } else {
                        // Dedos a la derecha hacia Música:
                        // Si se estaba estirando a la izquierda (resorte), jamás cambiar de menú al soltar
                        guard AppState.shared.overscrollOffset >= -0.5 else { return }
                        if !self.hasSwitchedPageInCurrentGesture {
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                            if self.accumulatedScrollDeltaX > 4.0 && Date().timeIntervalSince(self.lastScrollSwipeTime) > 0.12 {
                                self.lastScrollSwipeTime = Date()
                                self.accumulatedScrollDeltaX = 0
                                self.hasSwitchedPageInCurrentGesture = true
                                self.isIgnoringMomentumForOverscroll = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    AppState.shared.mode = .expanded
                                    AppState.shared.activeTab = .music
                                    AppState.shared.overscrollOffset = 0
                                    AppState.shared.contentOverscrollOffset = 0
                                }
                                AppState.shared.hapticService.triggerSnap()
                            }
                        } else {
                            // Ya se cambió de pestaña en este gesto: no acumular arrastre fantasma
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                        }
                    }
                }
            }
        }
        
        // 3. FINALIZACIÓN DE FASE EN EL TRACKPAD (Dedos levantados)
        let isEnded = event.phase == .ended || event.phase == .cancelled
        if isEnded {
            isTrackingTrackpadGesture = false
            hasCollapsedDetailInCurrentGesture = false
            hasExpandedInCurrentGesture = false
            hasSwitchedPageInCurrentGesture = false
            hasTriggeredHapticInScroll = false
            isIgnoringMomentumForOverscroll = true
            trackpadResetTimer?.invalidate()
            DispatchQueue.main.async {
                self.resetTrackpadOverscroll()
            }
        }
        
        super.scrollWheel(with: event)
    }
    
    // MARK: - Drag & Drop Proximity (Notch Vivo - Se abre al acercar archivos)
    private var dragExitTimer: Timer?
    
    private func containsFiles(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let types = pb.types {
            for t in types {
                if t == .fileURL || t.rawValue == "NSFilenamesPboardType" || t.rawValue == "public.file-url" || t.rawValue == "com.apple.finder.node" {
                    return true
                }
            }
        }
        return false
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragExitTimer?.invalidate()
        dragExitTimer = nil
        
        let hasFiles = containsFiles(sender)
        let sourceMask = sender.draggingSourceOperationMask
        DNDLogger.log("NotchHitTestView.draggingEntered called. hasFiles: \(hasFiles), sourceMask: \(sourceMask.rawValue)")
        guard hasFiles else { return [] }
        guard ActivityCenter.shared.currentActivity == nil else { return [] }
        
        DispatchQueue.main.async {
            AppState.shared.isShelfDragTargeted = true
            if !AppState.shared.isDropInvitationActive && AppState.shared.mode != .shelf {
                withAnimation(.spring(response: ExitAnimationMetrics.cardOpenResponse, dampingFraction: ExitAnimationMetrics.cardOpenDamping)) {
                    AppState.shared.isDropInvitationActive = true
                }
                AppState.shared.hapticService.triggerSnap()
            }
        }
        
        if AppState.shared.moveFilesToShelf && sourceMask.contains(.move) {
            return .move
        } else if sourceMask.contains(.move) {
            return .move
        } else if sourceMask.contains(.copy) {
            return .copy
        }
        return .move
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragExitTimer?.invalidate()
        dragExitTimer = nil
        
        guard containsFiles(sender) else { return [] }
        guard ActivityCenter.shared.currentActivity == nil else { return [] }
        
        DispatchQueue.main.async {
            if !AppState.shared.isShelfDragTargeted {
                AppState.shared.isShelfDragTargeted = true
            }
            if !AppState.shared.isDropInvitationActive && AppState.shared.mode != .shelf {
                withAnimation(.spring(response: ExitAnimationMetrics.cardOpenResponse, dampingFraction: ExitAnimationMetrics.cardOpenDamping)) {
                    AppState.shared.isDropInvitationActive = true
                }
            }
        }
        
        let sourceMask = sender.draggingSourceOperationMask
        if AppState.shared.moveFilesToShelf && sourceMask.contains(.move) {
            return .move
        } else if sourceMask.contains(.move) {
            return .move
        } else if sourceMask.contains(.copy) {
            return .copy
        }
        return .move
    }
    
    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.animatesToDestination = true
        DNDLogger.log("NotchHitTestView.prepareForDragOperation")
        return true
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        DNDLogger.log("NotchHitTestView.draggingExited")
        DispatchQueue.main.async {
            AppState.shared.isShelfDragTargeted = false
        }
        
        dragExitTimer?.invalidate()
        dragExitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard self != nil else { return }
            DispatchQueue.main.async {
                if AppState.shared.shelfItems.isEmpty && (AppState.shared.mode == .shelf || AppState.shared.activeTab == .shelf) && !AppState.shared.isHovered {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                        if AppState.shared.shouldShowCompact {
                            AppState.shared.mode = .compact
                            AppState.shared.activeTab = .music
                        } else {
                            AppState.shared.mode = .idle
                            AppState.shared.activeTab = .music
                        }
                    }
                }
            }
        }
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragExitTimer?.invalidate()
        dragExitTimer = nil
        
        DNDLogger.log("NotchHitTestView.performDragOperation CALLED! pasteboard types: \(sender.draggingPasteboard.types ?? [])")
        var foundUrls: [URL] = []
        let pasteboards = [sender.draggingPasteboard, NSPasteboard(name: .drag)]
        
        for pb in pasteboards {
            // 1. URLs directas desde el pasteboard
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                foundUrls.append(contentsOf: urls)
            }
            
            // 2. URLs de archivo explícitas
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL] {
                foundUrls.append(contentsOf: urls)
            }
            
            // 3. Nombres de archivo heredados (Finder NSFilenamesPboardType)
            if let propertyList = pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
                for path in propertyList {
                    foundUrls.append(URL(fileURLWithPath: path))
                }
            }
            
            // 4. Pasteboard items (resolviendo filePathURL canónica)
            if let items = pb.pasteboardItems {
                for it in items {
                    for t in [NSPasteboard.PasteboardType.fileURL, .init("public.file-url"), .init("com.apple.finder.node"), .init("public.url")] {
                        if let str = it.string(forType: t), let u = URL(string: str) {
                            let fileUrl = (u as NSURL).filePathURL ?? u
                            foundUrls.append(fileUrl)
                        }
                    }
                }
            }
        }
        
        // 5. Enumerar elementos de arrastre nativos
        sender.enumerateDraggingItems(options: [], for: nil, classes: [NSURL.self], searchOptions: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) { (draggingItem, _, _) in
            if let url = draggingItem.item as? URL {
                foundUrls.append(url)
            }
        }
        
        // 6. Filtrar y validar URLs existentes reales evitando duplicados
        var seenPaths = Set<String>()
        let validUrls = foundUrls.compactMap { url -> URL? in
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            let path = canonical.path
            guard !path.isEmpty && FileManager.default.fileExists(atPath: path) && !seenPaths.contains(path) else { return nil }
            seenPaths.insert(path)
            return canonical
        }
        
        DNDLogger.log("performDragOperation resolved validUrls (\(validUrls.count)): \(validUrls.map { $0.path })")
        
        guard !validUrls.isEmpty else {
            DNDLogger.log("performDragOperation failed: validUrls is EMPTY")
            DispatchQueue.main.async {
                AppState.shared.isShelfDragTargeted = false
                AppState.shared.triggerDropError(message: "Formato no compatible")
            }
            return false
        }
        
        DispatchQueue.main.async {
            AppState.shared.isShelfDragTargeted = false
            DragDetectionProbe.shared.resetDragState()
            if AppState.shared.mode == .shelf {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    AppState.shared.addShelfFiles(urls: validUrls)
                }
            } else {
                AppState.shared.triggerDropSuccess(urls: validUrls)
            }
        }
        return true
    }
}
