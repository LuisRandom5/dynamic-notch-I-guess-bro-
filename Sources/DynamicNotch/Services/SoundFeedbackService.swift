import AppKit
import AudioToolbox

/// Servicio centralizado de retroalimentación acústica y háptica minimalista tipo Apple.
/// Proporciona confirmaciones suaves, no invasivas y con ganancia atenuada para evitar estridencias.
public final class SoundFeedbackService {
    public static let shared = SoundFeedbackService()
    
    public var isSoundEnabled: Bool = true
    public var isHapticEnabled: Bool = true
    
    private init() {}
    
    /// Reproduce confirmación elegante al autorizar permisos o aceptar una acción en el Notch
    public func playPermissionGranted() {
        triggerHaptic(performance: .alignment)
        
        guard isSoundEnabled else { return }
        DispatchQueue.main.async {
            // Sonido suave y minimalista tipo Apple Pop con volumen moderado
            if let sound = NSSound(named: "Pop") {
                sound.volume = 0.28
                sound.play()
            } else {
                AudioServicesPlaySystemSound(1057) // Native Apple UI tick
            }
        }
    }
    
    /// Reproduce feedback sutil al rechazar o descartar una notificación/permiso
    public func playActionDismissed() {
        triggerHaptic(performance: .levelChange)
        
        guard isSoundEnabled else { return }
        DispatchQueue.main.async {
            if let sound = NSSound(named: "Tink") {
                sound.volume = 0.16
                sound.play()
            }
        }
    }
    
    /// Micro-feedback acústico al interactuar con la burbuja satélite de la Dynamic Island
    public func playBubblePop() {
        triggerHaptic(performance: .generic)
        
        guard isSoundEnabled else { return }
        DispatchQueue.main.async {
            if let sound = NSSound(named: "Pop") {
                sound.volume = 0.20
                sound.play()
            }
        }
    }
    
    /// Ejecuta feedback táctil en el Trackpad mediante NSHapticFeedbackManager
    private func triggerHaptic(performance: NSHapticFeedbackManager.FeedbackPattern) {
        guard isHapticEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(performance, performanceTime: .now)
    }
}
