import AppKit
import SwiftUI

public final class NotchPanel: NSPanel {
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
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
        self.registerForDraggedTypes([.fileURL])
    }
    
    public override var canBecomeKey: Bool {
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
}

public final class NotchHitTestView: NSView {
    public var hitAreaRect: CGRect = .zero
    private var trackingArea: NSTrackingArea?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        if hitAreaRect.contains(point) {
            return super.hitTest(point)
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
        if hitAreaRect.contains(point) {
            AppState.shared.handleMouseEnter()
        } else {
            AppState.shared.handleMouseLeave()
        }
    }
    
    // MARK: - Drag & Drop Proximity (Notch Vivo - Se abre al acercar archivos)
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let types = sender.draggingPasteboard.types, types.contains(.fileURL) else {
            return []
        }
        
        let point = convert(sender.draggingLocation, from: nil)
        // Proximidad: parte superior de la ventana cerca del notch
        let isNearNotch = point.y >= (bounds.height - 220) && abs(point.x - (bounds.width / 2.0)) <= 260
        
        if isNearNotch {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                    AppState.shared.mode = .shelf
                }
                AppState.shared.hapticService.triggerSnap()
            }
            return .copy
        }
        return []
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let types = sender.draggingPasteboard.types, types.contains(.fileURL) else {
            return []
        }
        
        let point = convert(sender.draggingLocation, from: nil)
        let isNearNotch = point.y >= (bounds.height - 220) && abs(point.x - (bounds.width / 2.0)) <= 260
        
        if isNearNotch {
            if AppState.shared.mode != .shelf {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                        AppState.shared.mode = .shelf
                    }
                    AppState.shared.hapticService.triggerSnap()
                }
            }
            return .copy
        } else {
            // Si el cursor se aleja del notch y no se ha soltado nada
            if AppState.shared.shelfItems.isEmpty && AppState.shared.mode == .shelf {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.86)) {
                        if AppState.shared.musicService.hasActiveMusic && AppState.shared.showCompactWhenPlaying {
                            AppState.shared.mode = .compact
                        } else {
                            AppState.shared.mode = .idle
                        }
                    }
                }
            }
            return []
        }
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async {
            if AppState.shared.shelfItems.isEmpty && AppState.shared.mode == .shelf {
                withAnimation(.spring(response: 0.50, dampingFraction: 0.86)) {
                    if AppState.shared.musicService.hasActiveMusic && AppState.shared.showCompactWhenPlaying {
                        AppState.shared.mode = .compact
                    } else {
                        AppState.shared.mode = .idle
                    }
                }
            }
        }
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }
        
        DispatchQueue.main.async {
            for url in urls {
                AppState.shared.addShelfFile(url: url)
            }
            AppState.shared.mode = .shelf
            AppState.shared.hapticService.triggerDrop()
        }
        return true
    }
}
