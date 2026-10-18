import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // SwiftUI exige al menos una escena. La de Ajustes de SwiftUI se abría sola (al lanzar o reactivar la
        // app) y, como observa todo AppState, se redibujaba en cada cuadro de las animaciones del notch.
        // Los ajustes reales están en SettingsWindowController (menú de la barra): esta ventana se cierra sola.
        Settings {
            SettingsSceneCloser()
        }
    }
}

/// Cierra la ventana de la escena `Settings` de SwiftUI en cuanto aparece, sin dibujar nada.
private struct SettingsSceneCloser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CloserView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CloserView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = window else { return }
            window.alphaValue = 0
            DispatchQueue.main.async { window.close() }
        }
    }
}
