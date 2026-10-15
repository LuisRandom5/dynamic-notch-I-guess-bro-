import SwiftUI

// MARK: - ExitAnimationMetrics (Constantes para Animación de Cierre del Notch)
public struct ExitAnimationMetrics {
    // Escalonado de salida del contenido (de abajo hacia arriba)
    public static let controlsExitDelay: Double = 0.0          // t = 0 ms: controles
    public static let progressExitDelay: Double = 0.025        // t = 25 ms: barra de progreso
    public static let topRowExitDelay: Double = 0.050          // t = 50 ms: fila superior (textos + carátula + visualizador)
    
    // Curva y valores visuales del contenido al desvanecerse
    public static let contentExitDuration: Double = 0.14       // ~140 ms (salida ágil y fluida)
    public static let contentExitBlur: CGFloat = 0.0           // 0 pt (renderizado limpio y ligero a 120 FPS sin caídas de frame)
    public static let contentExitScale: CGFloat = 0.92         // scale 1 -> 0.92 con anchor .top (absorbido hacia la cámara)
    public static let contentExitOffsetY: CGFloat = -6.0       // elevación sutil hacia el notch
    
    // Forma y contracción (solapada en t = 55 ms, integrando contenido y cápsula como un solo fluido)
    public static let shapeContractionDelay: Double = 0.055    // t = 55 ms
    public static let shapeCloseResponse: Double = 0.44        // response 0.44 (curva fluida y líquida, sin sacudidas ni freno brusco)
    public static let shapeCloseDamping: Double = 0.84         // dampingFraction 0.84 (asentamiento elástico orgánico)
    
    // Animación de apertura suave y orgánica estilo iPhone Dynamic Island (sin rebote ni golpe brusco)
    public static let shapeOpenResponse: Double = 0.52
    public static let shapeOpenDamping: Double = 0.90
    
    // Morphing hacia la píldora compacta con música activa
    public static let compactMorphResponse: Double = 0.44      // response 0.44 (curva orgánica continua)
    public static let compactMorphDamping: Double = 0.86       // damping 0.86 (asentamiento sedoso estilo Apple)
    
    // Notificaciones Card (Carga MagSafe / Batería Baja / AirDrop / Pop-ups grandes)
    // Curva de aceleración y desaceleración suave estilo macOS (críticamente amortiguada, sin rebotes ni overshoot)
    public static let cardOpenResponse: Double = 0.46          // response 0.46 (expansión majestuosa tipo Dynamic Island)
    public static let cardOpenDamping: Double = 0.82           // damping 0.82 (asentamiento elástico orgánico)
    public static let cardDismissDuration: Double = 0.30       // 300 ms: rango óptimo (250–350 ms)
    public static let cardDismissResponse: Double = 0.30       // response 0.30 (curva física elegante y controlada)
    public static let cardDismissDamping: Double = 0.98        // damping 0.98 (críticamente amortiguada: cero rebote, desaceleración natural)
    
    // Tiempos y retrasos de desvanecimiento progresivo del contenido interno (de adentro hacia afuera)
    public static let cardDismissTextDuration: Double = 0.18   // 180 ms: texto central se disuelve primero hacia el notch
    public static let cardDismissTrailingDuration: Double = 0.22 // 220 ms: porcentaje y batería acompañan contracción derecha
    public static let cardDismissLeadingDuration: Double = 0.25  // 250 ms: icono hero acompaña contracción izquierda
    
    // Retracción de HUDs de volumen, brillo y píldoras (sliderPill / pill)
    public static let sliderDismissDuration: Double = 0.28     // 280 ms
    public static let sliderDismissResponse: Double = 0.28     // response 0.28
    public static let sliderDismissDamping: Double = 0.98      // damping 0.98 (sin rebote)
    
    // Auto-cierre al salir el cursor
    public static let hoverExitDelay: Double = 0.60            // ~0.6 s
    
    // Fade-in del contenido compacto al llegar
    public static let compactFadeInDuration: Double = 0.14     // ~140 ms
}
