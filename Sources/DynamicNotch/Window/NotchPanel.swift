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
}
