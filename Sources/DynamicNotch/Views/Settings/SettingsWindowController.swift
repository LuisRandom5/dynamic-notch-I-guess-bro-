import AppKit
import SwiftUI

public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()
    /// Barra lateral + lista: lo que la vista pide como mínimo
    private static let contentSize = NSSize(width: 880, height: 640)
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Ventana estándar con barra lateral, como los Ajustes del Sistema (la barra de título transparente
        // desacomodaba la vista con barra lateral: se cortaba por arriba)
        window.title = L("Ajustes de Dynamic Notch")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(AppState.shared)
        )
        // La ventana manda en el tamaño (la vista se estira); si no, la vista la redimensionaba a su alto ideal
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(Self.contentSize)
        window.contentMinSize = Self.contentSize
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Diagnóstico: abre una pestaña y guarda una captura de la ventana (dibujada por la app)
    public func snapshot(tab: SettingsView.SettingsTab, to path: String) {
        SettingsNavigation.shared.selectedTab = tab
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let view = self?.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    
    /// Diagnóstico: la misma vista en una ventana sin barra de título, para separar el diseño del marco de la ventana
    private var bareWindow: NSWindow?
    public func snapshotBare(tab: SettingsView.SettingsTab, to path: String) {
        SettingsNavigation.shared.selectedTab = tab
        let bare = bareWindow ?? NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: [.borderless],
                                          backing: .buffered, defer: false)
        bareWindow = bare
        let host = NSHostingView(rootView: SettingsView().environmentObject(AppState.shared))
        host.frame = NSRect(origin: .zero, size: Self.contentSize)
        bare.contentView = host
        bare.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        bare.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            bare.orderOut(nil)
        }
    }

    public func show() {
        guard let window = self.window else { return }
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
