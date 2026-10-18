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
        self.appearance = NSAppearance(named: .darkAqua) // siempre oscura: el vidrio clear en apariencia clara se ve esmerilado
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
    
    // MARK: - Captura Universal de Gestos del Notch (Drag Down y Tap para Expandir)
    private var notchDragStartY: CGFloat = 0
    private var notchDragStartX: CGFloat = 0
    private var notchMouseDownTime: Date = .distantPast
    private var isTrackingNotchDrag: Bool = false
    
    public override func sendEvent(_ event: NSEvent) {
        // Todos los swipes de 2 dedos pasan por una única máquina de estados (ver TrackpadGestureRecognizer)
        if event.type == .scrollWheel {
            if NotchWindowManager.shared.gestureRecognizer.handle(event) { return }
            super.sendEvent(event)
            return
        }
        
        let agentProvider = AgentActivityProvider.shared
        if agentProvider.isInteractionActive {
            switch event.type {
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
                        DNDLogger.log("NotchPanel.sendEvent -> agent drag down detectado! Expandiendo interacción")
                        agentProvider.expandInteraction()
                    } else if pullDown <= -10 {
                        isTrackingNotifDrag = false
                        agentProvider.dragPullOffset = 0
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
                        DNDLogger.log("NotchPanel.sendEvent -> drag down detectado (pullDown=\(pullDown))! Expandiendo QuickReply")
                        provider.expandQuickReply()
                    } else if pullDown <= -10 {
                        isTrackingNotifDrag = false
                        provider.dragPullOffset = 0
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
                    // Un clic sobre una bolita satélite es de la bolita (abre su panel), no un tap al notch
                    // Con margen de 8 pt: el notch crece al pasar el cursor y empuja un poco a la bolita
                    let isOnSatellite = hitView.dynamicHitPaths.contains { $0.boundingBox.insetBy(dx: -8, dy: -8).contains(point) }
                    // Con una tarjeta de actividad abierta (p. ej. la de Claude) el clic es para cerrarla: no debe
                    // contar también como tap al notch (antes abría el reproductor debajo de la tarjeta)
                    let hasOpenCard = ActivityCenter.shared.expandedActivity != nil
                        || ActivityCenter.shared.isFusing
                        || AgentActivityProvider.shared.isProgressHUDExpanded
                    if (detectionRect.contains(point) || isNearNotch) && !isOnSatellite && !hasOpenCard &&
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
                        // Se decide un instante después: si una bolita atendió este mismo clic (abrió su tarjeta), no
                        // es un tap al notch (antes se abría también el reproductor debajo de la tarjeta)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            guard Date().timeIntervalSince(ActivityCenter.shared.lastSatelliteTapAt) > 0.4,
                                  ActivityCenter.shared.expandedActivity == nil, !ActivityCenter.shared.isFusing else {
                                DNDLogger.log("NotchPanel.sendEvent -> clic atendido por una bolita; no se expande el notch")
                                return
                            }
                            DNDLogger.log("NotchPanel.sendEvent -> Tap directo detectado en Notch colapsado! Expandiendo...")
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
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

public final class NotchHitTestView: NSView {
    public var hitAreaRect: CGRect = .zero
    /// Zonas interactivas que las vistas SwiftUI reportan por sí mismas (bolitas satélite, +N…), en coordenadas de esta vista.
    public private(set) var dynamicHitPaths: [CGPath] = []
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
            if isNearDropZone || isInsideInteractiveArea(point) {
                return self
            }
        }
        
        // 2. Si el punto está dentro del área visible activa del notch o en las bolitas satélite disjuntas:
        // Delegar SIEMPRE a la jerarquía SwiftUI (NotchHostingView) para que funcionen los clics, botones y gestos
        if isInsideInteractiveArea(point) {
            return super.hitTest(point) ?? subviews.first ?? self
        }
        
        return nil
    }
    
    public func isInsideInteractiveArea(_ point: NSPoint) -> Bool {
        hitAreaRect.contains(point) || dynamicHitPaths.contains { $0.contains(point) }
    }
    
    public func updateHitArea(_ rect: CGRect) {
        self.hitAreaRect = rect
        updateTrackingAreas()
    }
    
    public func updateDynamicHitRegions(_ regions: [NotchHitRegion]) {
        dynamicHitPaths = regions.map { $0.path(inContainerOfHeight: bounds.height) }
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
        
        // Las bolitas satélite manejan su propio tap en SwiftUI (NotchBolitaView)
        // Clic en el cuerpo principal del Notch
        if hitAreaRect.contains(point) {
            // Si el Notch está colapsado (idle o compact) y no hay actividad modal activa, expandir al dar tap
            let hasOpenCard = ActivityCenter.shared.expandedActivity != nil
                || ActivityCenter.shared.isFusing
                || AgentActivityProvider.shared.isProgressHUDExpanded
            if AppState.shared.mode != .expanded && AppState.shared.mode != .shelf && ActivityCenter.shared.currentActivity == nil && !hasOpenCard {
                DNDLogger.log("NotchHitTestView.mouseDown: Tap directo en el notch detectado -> expandiendo")
                DispatchQueue.main.async {
                    AppState.shared.expand()
                }
                return
            }
        }
        super.mouseDown(with: event)
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
