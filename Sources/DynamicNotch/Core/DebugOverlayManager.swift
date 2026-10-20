import SwiftUI
import AppKit

public final class DebugOverlayManager: ObservableObject {
    public static let shared = DebugOverlayManager()
    
    @Published public var isOverlayActive: Bool = false
    @Published public var opacity: Double = 0.50
    @Published public var overlayImage: NSImage? = nil
    @Published public var imagePath: String = ""
    
    private var keyMonitor: Any?
    
    private init() {
        // Superposición de una imagen de referencia (⌘⇧O): herramienta de desarrollo, no en la beta
        guard BuildFlavor.hasDeveloperTools else { return }
        lookForDefaultReferenceImage()
        setupKeyboardShortcut()
    }
    
    public func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isOverlayActive.toggle()
        }
    }
    
    public func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.prompt = "Cargar Imagen de Referencia"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let img = NSImage(contentsOf: url) {
                self.overlayImage = img
                self.imagePath = url.lastPathComponent
                self.isOverlayActive = true
            }
        }
    }
    
    private func lookForDefaultReferenceImage() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultPaths = [
            "\(home)/Documents/Dynamic Notch/reference.png",
            "\(home)/Documents/Dynamic Notch/reference.jpg",
            "\(home)/Desktop/reference.png",
            "\(home)/Downloads/reference.png"
        ]
        
        for path in defaultPaths {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                self.overlayImage = img
                self.imagePath = (path as NSString).lastPathComponent
                break
            }
        }
    }
    
    private func setupKeyboardShortcut() {
        // Atajo global local Cmd+Shift+O para activar / desactivar overlay de comparación
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers?.lowercased() == "o" {
                self?.toggleOverlay()
                return nil
            }
            return event
        }
    }
}
