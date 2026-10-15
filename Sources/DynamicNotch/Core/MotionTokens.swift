import SwiftUI
import AppKit

// MARK: - MotionTokens (Familia Unificada de Resortes y Tokens de Diseño - HIG / Dynamic Island)
public enum MotionTokens {
    // MARK: - Familia de Resortes (Spring Family)
    // 1. Apertura / Expansión: Movimiento orgánico y controlado, amortiguado críticamente
    public static let expandSpring = Animation.spring(response: 0.48, dampingFraction: 0.86)
    public static let expandResponse: Double = 0.48
    public static let expandDamping: Double = 0.86
    
    // 2. Cierre / Contracción: Rápido y fluido, el contenido se desvanece antes de la contracción física
    public static let collapseSpring = Animation.spring(response: 0.40, dampingFraction: 0.88)
    public static let collapseResponse: Double = 0.40
    public static let collapseDamping: Double = 0.88
    public static let contentExitFadeDuration: Double = 0.12
    
    // 3. Morphing Compacto: Transición continua entre notch en reposo y píldora compacta
    public static let compactMorphSpring = Animation.spring(response: 0.44, dampingFraction: 0.86)
    
    // 4. Pulsación de Botón (Pressed / Tap): Respuesta táctil inmediata con compresión 0.94
    public static let pressSpring = Animation.spring(response: 0.22, dampingFraction: 0.74)
    public static let pressScale: CGFloat = 0.94
    public static let pressBrightnessBoost: Double = 0.08
    
    // 5. Seguimiento del Cursor (Cursor Glow): Reacción instantánea sin inercia pesada
    public static let cursorGlowSpring = Animation.spring(response: 0.24, dampingFraction: 0.82)
    
    // 6. Tics de Temporizador y Contadores: Sin saltos de layout
    public static let timerTickSpring = Animation.spring(response: 0.26, dampingFraction: 0.80)
    
    // 7. Destello de Luz (Shimmer Sweep)
    public static let shimmerDuration: Double = 0.35
    
    // MARK: - Nitidez de Píxel Físico
    /// Retorna el grosor de 1 píxel físico real para la pantalla activa (0.5 pt en Retina, 1.0 pt en no-Retina)
    public static var physicalPixel: CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return max(0.5, 1.0 / scale)
    }
    
    // MARK: - Concentricidad de Radios (HIG)
    /// Calcula el radio interno concéntrico exacto: radioInterno = radioExterno - padding
    public static func concentricRadius(outerRadius: CGFloat, padding: CGFloat, minRadius: CGFloat = 6.0) -> CGFloat {
        return max(minRadius, outerRadius - padding)
    }
    
    // MARK: - Alineación Óptica
    /// Desplazamiento horizontal óptico para el glifo triangular de Play (centroid visual ≠ centro del bounding box)
    public static let playIconOpticalOffsetX: CGFloat = 1.4
    
    // MARK: - Accesibilidad
    public static var isReduceMotionActive: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    public static var isReduceTransparencyActive: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    
    /// Retorna el resorte adaptado: si "Reducir movimiento" está activo, utiliza una transición suave sin rebote
    public static func adaptiveSpring(response: Double, dampingFraction: Double) -> Animation {
        if isReduceMotionActive {
            return .easeInOut(duration: min(0.30, response * 0.7))
        }
        return .spring(response: response, dampingFraction: dampingFraction)
    }
}
