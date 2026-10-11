import SwiftUI
import AppKit

public final class AnimationSpeedManager: ObservableObject {
    public static let shared = AnimationSpeedManager()
    
    @Published public var speedMultiplier: Double = 1.0 // 1.0 normal, 0.2 cámara lenta
    @Published public var isSlowMotion: Bool = false
    
    private var keyMonitor: Any?
    
    private init() {
        setupKeyboardShortcut()
    }
    
    public func toggleSlowMotion() {
        isSlowMotion.toggle()
        speedMultiplier = isSlowMotion ? 0.2 : 1.0
    }
    
    public func setSpeed(_ speed: Double) {
        speedMultiplier = max(0.1, min(2.0, speed))
        isSlowMotion = speedMultiplier < 0.9
    }
    
    // Convierte un resorte para que respete la velocidad actual
    public func spring(response: Double, dampingFraction: Double) -> Animation {
        let adjustedResponse = response / speedMultiplier
        return .spring(response: adjustedResponse, dampingFraction: dampingFraction)
    }
    
    // Convierte una curva temporal (easeIn, easeOut, etc.)
    public func easeIn(duration: Double) -> Animation {
        return .easeIn(duration: duration / speedMultiplier)
    }
    
    public func easeOut(duration: Double) -> Animation {
        return .easeOut(duration: duration / speedMultiplier)
    }
    
    public func adjustedDuration(_ seconds: Double) -> Double {
        return seconds / speedMultiplier
    }
    
    private func setupKeyboardShortcut() {
        // Atajo ⌘⇧S (Cmd + Shift + S) para alternar cámara lenta (1.0x <-> 0.2x)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers?.lowercased() == "s" {
                self?.toggleSlowMotion()
                return nil
            }
            return event
        }
    }
}
