import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notch Physics & Animation Tuning
public struct NotchTuning {
    // 1) FASE PRESIONAR (Mouse Down) - Anticipación elástica física sutil
    public static let pressScaleX: CGFloat = 1.040              // Más sutil para no generar saltos bruscos
    public static let pressScaleY: CGFloat = 0.975              // Compresión vertical suave
    public static let pressShadowRadius: CGFloat = 18           // Sombra difusa debajo
    public static let pressShadowOpacity: Double = 0.42         // Opacidad suave
    public static let pressShadowY: CGFloat = 6                 // Desplazamiento vertical de la sombra
    public static let pressSpring = Animation.spring(response: 0.26, dampingFraction: 0.74)
    
    // 2) FASE SOLTAR (Mouse Up) - Expansión completa (MUCHO MÁS SMOOTH, sin golpe ni rebote brusco)
    public static let expandSpring = Animation.spring(response: 0.52, dampingFraction: 0.90)
    public static let expandedWidth: CGFloat = PlayerMetrics.cardWidth              // Ancho de la píldora expandida (420 pt)
    public static let expandedHeight: CGFloat = PlayerMetrics.cardHeight            // Alto de la píldora expandida (190 pt)
    public static let expandedTopRadius: CGFloat = PlayerMetrics.cornerRadius       // Curvatura superior (56 pt continuo)
    public static let expandedBottomRadius: CGFloat = PlayerMetrics.cornerRadius    // Curvatura inferior (56 pt continuo)
    public static let expandedShadowRadius: CGFloat = PlayerMetrics.shadowRadius    // Sombra de la isla abierta (30 pt)
    public static let expandedShadowOpacity: Double = PlayerMetrics.shadowOpacity   // Opacidad sombra abierta (0.50)
    public static let expandedShadowY: CGFloat = PlayerMetrics.shadowY              // Desplazamiento Y sombra abierta (12 pt)
    
    // Delays escalonados progresivos y suaves
    public static let stage1Delay: Double = 0.16               // Carátula, título, artista, ecualizador
    public static let stage2Delay: Double = 0.26               // Barra de progreso y tiempos
    public static let stage3Delay: Double = 0.36               // Controles de reproducción
    public static let stage4Delay: Double = 0.46               // Cápsulas inferiores flotantes
    public static let contentInSpring = Animation.spring(response: 0.52, dampingFraction: 0.88)
    
    // 3) FASE CERRAR / Contracción inversa
    public static let contentFadeOutDuration: Double = 0.12    // El contenido se desvanece primero
    public static let collapseSpring = Animation.spring(response: 0.62, dampingFraction: 0.86)
    
    // 4) FASE CANCELAR (arrastrar mouse fuera del notch)
    public static let dragCancelThresholdX: CGFloat = 45       // Umbral horizontal para cancelar
    public static let dragCancelThresholdY: CGFloat = 45       // Umbral vertical para cancelar
    public static let cancelSpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    
    // 5) ALAS COMPACTAS (música): ancho ajustado al contenido. La carátula (19 pt) y las barras (~21 pt) quedan
    //    con ~11 pt de margen a cada lado; el resto del ancho es la cámara, que no se puede reducir
    public static let compactWingWidth: CGFloat = 42
    public static let compactWingsExtraWidth: CGFloat = compactWingWidth * 2
    /// Mínima pegada (varias actividades): sólo el ala izquierda, más angosta; en ancho limitado (3 a la vista)
    /// todavía más, como el círculo de 28 pt de la Isla Dinámica
    public static let minimalWingWidth: CGFloat = 34
    public static let minimalWingLimitedWidth: CGFloat = 30
}

public enum NotchInteractionState: Equatable {
    case collapsed
    case pressed
    case expanded
}
