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
    
    // MARK: - Captura Universal de Gestos de Notificación (Swipe Down & Drag Down)
    private var notifGestureStartY: CGFloat = 0
    private var isTrackingNotifDrag: Bool = false
    
    public override func sendEvent(_ event: NSEvent) {
        if NotificationActivityProvider.shared.isNotificationActive {
            switch event.type {
            case .scrollWheel:
                let rawDy = event.scrollingDeltaY
                let isInverted = event.isDirectionInvertedFromDevice
                let fingerDy = isInverted ? rawDy : -rawDy
                
                // Si desliza hacia abajo (dedos hacia el usuario / hacia la pantalla)
                if (fingerDy > 1.2 || rawDy > 1.2) && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                    DNDLogger.log("NotchPanel.sendEvent -> swipe down detectado en scrollWheel! rawDy=\(rawDy), fingerDy=\(fingerDy)")
                    NotificationActivityProvider.shared.expandQuickReply()
                    return
                } else if (fingerDy < -1.5 || rawDy < -1.5) && NotificationActivityProvider.shared.isQuickReplyExpanded {
                    DNDLogger.log("NotchPanel.sendEvent -> swipe up detectado en scrollWheel! rawDy=\(rawDy), fingerDy=\(fingerDy)")
                    NotificationActivityProvider.shared.collapseQuickReply()
                    return
                }
                
            case .leftMouseDown:
                notifGestureStartY = event.locationInWindow.y
                isTrackingNotifDrag = true
                
            case .leftMouseDragged:
                if isTrackingNotifDrag {
                    // En coordenadas de ventana de macOS, y=0 está en el borde inferior.
                    // Si el usuario arrastra el cursor hacia abajo: currentY < startY (deltaY < 0)
                    let currentY = event.locationInWindow.y
                    let deltaY = currentY - notifGestureStartY
                    
                    if deltaY < -8 && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                        isTrackingNotifDrag = false
                        DNDLogger.log("NotchPanel.sendEvent -> drag down detectado (deltaY=\(deltaY))! Expandiendo QuickReply")
                        NotificationActivityProvider.shared.expandQuickReply()
                        return
                    } else if deltaY > 15 && NotificationActivityProvider.shared.isQuickReplyExpanded {
                        isTrackingNotifDrag = false
                        DNDLogger.log("NotchPanel.sendEvent -> drag up detectado (deltaY=\(deltaY))! Colapsando QuickReply")
                        NotificationActivityProvider.shared.collapseQuickReply()
                        return
                    }
                }
                
            case .leftMouseUp:
                isTrackingNotifDrag = false
                
            default:
                break
            }
        }
        
        super.sendEvent(event)
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
}

public final class NotchHitTestView: NSView {
    public var hitAreaRect: CGRect = .zero
    private var trackingArea: NSTrackingArea?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
        setupPanGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([
            .fileURL,
            .init("NSFilenamesPboardType"),
            .init("public.file-url"),
            .init("com.apple.finder.node")
        ])
        setupPanGesture()
    }
    
    private func setupPanGesture() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        pan.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(pan)
    }
    
    @objc private func handlePanGesture(_ gesture: NSPanGestureRecognizer) {
        guard NotificationActivityProvider.shared.isNotificationActive else { return }
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        // En coordenadas AppKit: Y=0 en la base. Hacia abajo es translation.y < 0
        let deltaDown = -translation.y
        let deltaUp = translation.y
        
        switch gesture.state {
        case .changed:
            if deltaDown >= 6 && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                DispatchQueue.main.async {
                    DNDLogger.log("NotchHitTestView: NSPanGestureRecognizer (.changed deltaDown=\(deltaDown)) -> expandQuickReply()")
                    NotificationActivityProvider.shared.expandQuickReply()
                }
            } else if deltaUp >= 10 && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                DispatchQueue.main.async {
                    DNDLogger.log("NotchHitTestView: NSPanGestureRecognizer (.changed deltaUp=\(deltaUp)) -> dismissNotification()")
                    NotificationActivityProvider.shared.dismissNotification()
                }
            }
        case .ended:
            if (deltaDown >= 4 || -velocity.y > 50) && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                DispatchQueue.main.async {
                    DNDLogger.log("NotchHitTestView: NSPanGestureRecognizer (.ended deltaDown=\(deltaDown)) -> expandQuickReply()")
                    NotificationActivityProvider.shared.expandQuickReply()
                }
            } else if (deltaUp >= 6 || velocity.y > 80) && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                DispatchQueue.main.async {
                    DNDLogger.log("NotchHitTestView: NSPanGestureRecognizer (.ended deltaUp=\(deltaUp)) -> dismissNotification()")
                    NotificationActivityProvider.shared.dismissNotification()
                }
            }
        default:
            break
        }
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
            if isNearDropZone || hitAreaRect.contains(point) {
                return self
            }
        }
        
        // 2. Si el punto está dentro del área visible activa del notch:
        // Delegar SIEMPRE a la jerarquía SwiftUI (NotchHostingView) para que funcionen los clics, botones, tap gesture y arrastre hacia afuera
        if hitAreaRect.contains(point) {
            return super.hitTest(point) ?? self
        }
        
        return nil
    }
    
    public func updateHitArea(_ rect: CGRect) {
        self.hitAreaRect = rect
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
    
    private var notificationMouseDownPoint: NSPoint? = nil
    
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NotificationActivityProvider.shared.isNotificationActive {
            notificationMouseDownPoint = point
        }
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
    
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NotificationActivityProvider.shared.isNotificationActive, let start = notificationMouseDownPoint {
            // En macOS AppKit: (0,0) abajo a la izquierda.
            // Arrastrar hacia abajo significa que point.y disminuye (start.y - point.y > 0).
            let deltaDown = start.y - point.y
            let deltaUp = point.y - start.y
            
            if deltaDown >= 10 && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                notificationMouseDownPoint = nil
                DispatchQueue.main.async {
                    NotificationActivityProvider.shared.expandQuickReply()
                }
                return
            } else if deltaUp >= 10 && !NotificationActivityProvider.shared.isQuickReplyExpanded {
                notificationMouseDownPoint = nil
                DispatchQueue.main.async {
                    NotificationActivityProvider.shared.dismissNotification()
                }
                return
            }
        }
        super.mouseDragged(with: event)
    }
    
    public override func mouseUp(with event: NSEvent) {
        notificationMouseDownPoint = nil
        super.mouseUp(with: event)
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
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        hasTriggeredHapticInScroll = false
        hasExpandedInCurrentGesture = false
        
        if AppState.shared.overscrollOffset != 0 || AppState.shared.contentOverscrollOffset != 0 {
            // Desfase orgánico horizontal
            withAnimation(.spring(
                response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                dampingFraction: OverscrollMetrics.shapeSpringDamping
            )) {
                AppState.shared.overscrollOffset = 0
            }
            withAnimation(.spring(
                response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                dampingFraction: OverscrollMetrics.contentSpringDamping
            )) {
                AppState.shared.contentOverscrollOffset = 0
            }
        }
        
        if AppState.shared.verticalOverscrollOffset != 0 || AppState.shared.contentVerticalOverscrollOffset != 0 {
            // Desfase orgánico vertical: la forma regresa con spring rápido y el contenido con spring suave
            withAnimation(.spring(
                response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                dampingFraction: OverscrollMetrics.shapeSpringDamping
            )) {
                AppState.shared.verticalOverscrollOffset = 0
            }
            withAnimation(.spring(
                response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
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
        
        // Watchdog de seguridad (0.13 s): si los dedos se detienen durante overscroll, regresa automáticamente
        trackpadResetTimer?.invalidate()
        trackpadResetTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resetTrackpadOverscroll()
            }
        }
        
        // 1. SCROLL VERTICAL CON 2 DEDOS (Pastilla extendida, estiramiento elástico y guardado de píldora)
        if abs(fingerDeltaY) > abs(fingerDeltaX) && abs(fingerDeltaY) > 0.3 {
            accumulatedScrollDeltaY += fingerDeltaY
            
            // PRIORIDAD 1: Si hay notificación activa en pantalla
            if NotificationActivityProvider.shared.isNotificationActive {
                DNDLogger.log("scrollWheel [Notif]: rawY=\(rawDeltaY), fingerY=\(fingerDeltaY), accumY=\(accumulatedScrollDeltaY)")
                if !NotificationActivityProvider.shared.isQuickReplyExpanded {
                    // Deslizar hacia abajo (dedos hacia el usuario / hacia la pantalla) -> Expandir respuesta rápida
                    if (fingerDeltaY > 0.3 || rawDeltaY > 0.3 || accumulatedScrollDeltaY > 0.8) {
                        guard !hasExpandedInCurrentGesture else { return }
                        lastScrollSwipeTime = Date()
                        hasExpandedInCurrentGesture = true
                        isIgnoringMomentumForOverscroll = true
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            DNDLogger.log("scrollWheel -> expandQuickReply() disparado con éxito!")
                            NotificationActivityProvider.shared.expandQuickReply()
                        }
                        return
                    }
                } else {
                    // Si ya está expandida y desliza hacia arriba -> Guardar/colapsar
                    if (fingerDeltaY < -0.6 || rawDeltaY < -0.6 || accumulatedScrollDeltaY < -1.5) {
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            DNDLogger.log("scrollWheel -> collapseQuickReply() disparado!")
                            NotificationActivityProvider.shared.collapseQuickReply()
                        }
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
                        
                        // Estiramiento vertical elástico hacia abajo (anclado arriba al notch)
                        let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                        DispatchQueue.main.async {
                            AppState.shared.verticalOverscrollOffset = stretch
                            AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                        }
                        if accumulatedScrollDeltaY > 20 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.28 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.48, dampingFraction: 0.80)) {
                                    AppState.shared.isPlayerDetailExpanded = true
                                    AppState.shared.verticalOverscrollOffset = 0
                                    AppState.shared.contentVerticalOverscrollOffset = 0
                                }
                                AppState.shared.hapticService.triggerExpand()
                            }
                        }
                    } else {
                        // Ya está expandida al máximo: estirar SOLO hacia abajo con rebote elástico (anclado arriba)
                        let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                        DispatchQueue.main.async {
                            AppState.shared.verticalOverscrollOffset = stretch
                            AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                        }
                    }
                } else if CallActivityProvider.shared.isCallActive {
                    guard !hasExpandedInCurrentGesture else { return }
                    if CallActivityProvider.shared.isExpandedCard {
                        // Si está en llamada con tarjeta extendida y hace swipe hacia abajo:
                        // Mostrar reproductor NORMAL (sin volumen)
                        if accumulatedScrollDeltaY > 16 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.28 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            DispatchQueue.main.async {
                                CallActivityProvider.shared.collapseToPill()
                                AppState.shared.isPlayerDetailExpanded = false
                                AppState.shared.expand()
                            }
                        }
                    } else {
                        // Llamada compacta en notch: expandir tarjeta de llamada
                        if accumulatedScrollDeltaY > 16 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.28 {
                            lastScrollSwipeTime = Date()
                            hasExpandedInCurrentGesture = true
                            isIgnoringMomentumForOverscroll = true
                            accumulatedScrollDeltaY = 0
                            DispatchQueue.main.async {
                                CallActivityProvider.shared.expandToCard()
                            }
                        }
                    }
                    return
                } else if ActivityCenter.shared.currentActivity != nil {
                    // Si hay cualquier LiveActivity activa, NUNCA invadir con el reproductor
                    return
                } else if AppState.shared.mode == .shelf {
                    // Bandeja temporal (Drag and Drop): estiramiento elástico hacia abajo,
                    // vuelve a su forma original de forma natural (no hay menú extendido secundario)
                    let stretch = OverscrollMetrics.calculateStretch(for: accumulatedScrollDeltaY)
                    DispatchQueue.main.async {
                        AppState.shared.verticalOverscrollOffset = stretch
                        AppState.shared.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                    }
                } else if isCompactOrIdle {
                    guard ActivityCenter.shared.currentActivity == nil else { return }
                    guard !hasExpandedInCurrentGesture else { return }
                    if accumulatedScrollDeltaY > 16 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.32 {
                        lastScrollSwipeTime = Date()
                        hasExpandedInCurrentGesture = true
                        isIgnoringMomentumForOverscroll = true
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            AppState.shared.expand()
                        }
                    }
                }
            } else if fingerDeltaY < 0 {
                // Dedos hacia arriba:
                if NotificationActivityProvider.shared.isNotificationActive {
                    if (accumulatedScrollDeltaY < -4 || fingerDeltaY < -1.2 || rawDeltaY < -1.2) && Date().timeIntervalSince(lastScrollSwipeTime) > 0.12 {
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
                
                if CallActivityProvider.shared.isCallActive && CallActivityProvider.shared.isExpandedCard {
                    if accumulatedScrollDeltaY < -14 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.25 {
                        lastScrollSwipeTime = Date()
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            CallActivityProvider.shared.collapseToPill()
                        }
                        return
                    }
                }
                
                if AppState.shared.mode == .expanded && AppState.shared.isPlayerDetailExpanded {
                    if accumulatedScrollDeltaY < -14 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.25 {
                        lastScrollSwipeTime = Date()
                        lastCollapseDetailTime = Date()
                        hasCollapsedDetailInCurrentGesture = true
                        accumulatedScrollDeltaY = 0
                        DispatchQueue.main.async {
                            self.playerDetailSwipeCount = 0
                            withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                                AppState.shared.isPlayerDetailExpanded = false
                                AppState.shared.verticalOverscrollOffset = 0
                                AppState.shared.contentVerticalOverscrollOffset = 0
                            }
                            AppState.shared.hapticService.triggerSnap()
                        }
                    }
                } else if isExpandedOrShelf && !AppState.shared.isPlayerDetailExpanded {
                    // Si está en pastilla normal y hace scroll hacia arriba: ¡GUARDAR LA PÍLDORA!
                    guard !hasCollapsedDetailInCurrentGesture else { return }
                    guard Date().timeIntervalSince(lastCollapseDetailTime) > 0.75 else { return }
                    
                    if accumulatedScrollDeltaY < -18 && Date().timeIntervalSince(lastScrollSwipeTime) > 0.30 {
                        lastScrollSwipeTime = Date()
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
            if hasSwitchedPageInCurrentGesture {
                // Bloquear sobre-desplazamiento para mantener la píldora centrada tras cambiar de página
                DispatchQueue.main.async {
                    AppState.shared.overscrollOffset = 0
                    AppState.shared.contentOverscrollOffset = 0
                }
            } else {
                accumulatedScrollDeltaX += fingerDeltaX
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
                            // Dedos a la izquierda hacia la Bandeja (MENÚ QUE SÍ EXISTE):
                            // NUNCA desplazar la tarjeta hacia los lados; solo cambiar de menú limpiamente
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                            if self.accumulatedScrollDeltaX < -16 && Date().timeIntervalSince(self.lastScrollSwipeTime) > 0.20 {
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
                            // Dedos a la derecha hacia Música (MENÚ QUE SÍ EXISTE):
                            // NUNCA desplazar la tarjeta hacia los lados; solo cambiar de menú limpiamente
                            AppState.shared.overscrollOffset = 0
                            AppState.shared.contentOverscrollOffset = 0
                            if self.accumulatedScrollDeltaX > 16 && Date().timeIntervalSince(self.lastScrollSwipeTime) > 0.20 {
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
                        }
                    }
                }
            }
        }
        
        // 3. FINALIZACIÓN DE FASE EN EL TRACKPAD (Dedos levantados)
        let isEnded = event.phase == .ended || event.phase == .cancelled
        if isEnded {
            hasCollapsedDetailInCurrentGesture = false
            hasExpandedInCurrentGesture = false
            hasTriggeredHapticInScroll = false
            if hasSwitchedPageInCurrentGesture {
                isIgnoringMomentumForOverscroll = true
            }
            if AppState.shared.overscrollOffset != 0 || AppState.shared.verticalOverscrollOffset != 0 {
                isIgnoringMomentumForOverscroll = true
            }
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
