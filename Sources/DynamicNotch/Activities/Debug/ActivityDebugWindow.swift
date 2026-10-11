import AppKit
import SwiftUI

public final class ActivityDebugWindow {
    public static let shared = ActivityDebugWindow()
    private var window: NSWindow?
    
    private init() {}
    
    public func show() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 440, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Panel de Pruebas: Live Activities"
        newWindow.contentView = NSHostingView(rootView: ActivityDebugView())
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
