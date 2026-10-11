import SwiftUI

// MARK: - ExitAnimationMetrics (Constantes para Animación de Cierre del Notch)
public struct ExitAnimationMetrics {
    // Escalonado de salida del contenido (de abajo hacia arriba)
    public static let controlsExitDelay: Double = 0.0          // t = 0 ms: controles
    public static let progressExitDelay: Double = 0.020        // t = 20 ms: barra de progreso
    public static let topRowExitDelay: Double = 0.040          // t = 40 ms: fila superior (textos)
    
    // Curva y valores visuales del contenido al desvanecerse
    public static let contentExitDuration: Double = 0.165      // ~165 ms (easeIn rápido)
    public static let contentExitBlur: CGFloat = 14.0          // blur 0 -> 14 pt
    public static let contentExitScale: CGFloat = 0.85         // scale 1 -> 0.85 con anchor .top
    
    // Forma y contracción (solapada en t = 40 ms)
    public static let shapeContractionDelay: Double = 0.040    // t = 40 ms (sin esperar a que termine el contenido)
    public static let shapeCloseResponse: Double = 0.38        // response ~0.38
    public static let shapeCloseDamping: Double = 0.86         // dampingFraction ~0.86 (más amortiguado)
    
    // Animación de apertura suave y orgánica estilo iPhone Dynamic Island (sin rebote ni golpe brusco)
    public static let shapeOpenResponse: Double = 0.52
    public static let shapeOpenDamping: Double = 0.90
    
    // Auto-cierre al salir el cursor
    public static let hoverExitDelay: Double = 0.60            // ~0.6 s
    
    // Fade-in del contenido compacto al llegar
    public static let compactFadeInDuration: Double = 0.12     // ~120 ms
}
