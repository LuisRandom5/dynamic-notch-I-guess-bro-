import SwiftUI

// MARK: - Overscroll Physics & Resistance Metrics
public struct OverscrollMetrics {
    // 1) Resistencia física tipo iOS
    // estiramiento(x) = maxStretch × (1 − 1 / (|x| × c / maxStretch + 1)) * sign(x)
    public static var maxStretch: CGFloat = 44.0            // Máximo estiramiento permitido en pt
    public static var resistanceC: CGFloat = 0.55          // Coeficiente de resistencia (c ≈ 0.55)
    
    // 2) Factores de transformación del contenido interno
    public static var contentFollow: CGFloat = 0.70         // El contenido se mueve al 70% del borde exterior
    public static var contentScaleMax: CGFloat = 1.03       // Escala máxima en X (3% extra para no deformar texto)
    public static var heightShortenPercent: CGFloat = 0.02  // La cápsula se acorta ~2% en alto mientras se estira
    public static var pageIndicatorStretch: CGFloat = 6.0   // Alargamiento de la cápsula del punto activo en pt
    
    // 3) Paralaje por capas (profundidad orgánica)
    public static var parallaxArtwork: CGFloat = 1.00       // Carátula sigue al 100% de contentFollow
    public static var parallaxText: CGFloat = 0.85          // Título y artista siguen al 85%
    public static var parallaxProgress: CGFloat = 0.70      // Barra de progreso y tiempos siguen al 70%
    public static var parallaxControls: CGFloat = 0.90      // Botones de control siguen al 90%
    
    // 4) Física de los resortes de rebote (Desfase Forma vs Contenido)
    public static var shapeSpringResponse: Double = 0.45    // Resorte de la cápsula exterior
    public static var shapeSpringDamping: Double = 0.55     // Amortiguación de la cápsula (rebote 10-15%)
    
    public static var contentSpringResponse: Double = 0.55  // Resorte del contenido (un poco más suave y lento)
    public static var contentSpringDamping: Double = 0.50   // Amortiguación del contenido
    
    // 5) Ajustes de depuración y tolerancia de snap a cero
    public static var speedMultiplier: Double = 1.0         // Multiplicador de velocidad (ej. 0.3 para cámara lenta)
    public static var snapThreshold: CGFloat = 0.5          // Si |offset| < 0.5 pt, se fuerza inmediatamente a 0.0
    
    /// Fuerza el valor a 0 exacto si cae por debajo del umbral mínimo de snap
    public static func snapToZeroIfMinimal(_ value: CGFloat) -> CGFloat {
        abs(value) < snapThreshold ? 0.0 : value
    }
    
    /// Calcula el estiramiento resistido aplicando la curva asintótica de iOS
    public static func calculateStretch(for rawX: CGFloat) -> CGFloat {
        let absX = abs(rawX)
        guard absX > 0.001 else { return 0 }
        let stretched = maxStretch * (1.0 - (1.0 / ((absX * resistanceC / maxStretch) + 1.0)))
        return rawX >= 0 ? stretched : -stretched
    }
}
