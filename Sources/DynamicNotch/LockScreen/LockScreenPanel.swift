import AppKit
import SwiftUI

/// Panel flotante para el Reproductor en Pantalla de Bloqueo de macOS.
/// Cumple estrictas reglas de seguridad:
/// - `canBecomeKey = false` y `canBecomeMain = false` para NUNCA robar el foco del teclado al introducir Touch ID o contraseña.
/// - `canBecomeVisibleWithoutLogin = true` para permitir rasterizado de WindowServer sobre la pantalla bloqueada.
/// - `level = CGShieldingWindowLevel() + 2` para flotar por encima del escudo de `loginwindow`.
/// - `sharingType = .readOnly` para seguridad de memoria y captura de pantalla.
public final class LockScreenPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
    
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
        self.canBecomeVisibleWithoutLogin = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        self.sharingType = .readWrite
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
    }
}

/// Subclase de NSHostingView para la Pantalla de Bloqueo que responde al primer clic
/// y permite que los clics en zonas transparentes pasen a la ventana inferior cuando la carátula está contraída.
public final class LockScreenHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        if AppState.shared.lockScreenStyle == .heroWidget && !AppState.shared.isLockScreenArtworkExpanded {
            let activeHeight = AppState.shared.lockScreenShowVolumeSlider
                ? LockScreenPlayerMetrics.heroCardHeightWithVolume
                : LockScreenPlayerMetrics.heroCardHeight
            // En coordenadas AppKit, Y=0 está en la base inferior:
            if point.y > (activeHeight + 14) {
                return nil
            }
        }
        return super.hitTest(point)
    }
}
