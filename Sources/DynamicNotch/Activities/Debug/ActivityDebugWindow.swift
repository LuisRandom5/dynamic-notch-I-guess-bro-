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
            contentRect: NSRect(x: 200, y: 200, width: 680, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Panel de Pruebas: Live Activities"
        newWindow.minSize = NSSize(width: 560, height: 520)
        newWindow.contentView = NSHostingView(rootView: ActivityDebugView())
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
