import CoreGraphics
import Foundation

/// Medidas de referencia de la Isla Dinámica (HIG "Live Activities" › Specifications, en pt; macOS usa las de
/// iOS). Son la guía de proporciones: la isla del Mac se adapta al alto real del notch con `scale`.
public enum IslandMetrics {
    // MARK: Referencia de Apple (iPhone 6.9", 430×932)

    /// Alto de la compacta y de la mínima
    public static let compactHeight: CGFloat = 36.67
    /// Ancho máximo de cada lado de la compacta (6.9"; 52.33 en 6.3")
    public static let compactSideMaxWidth: CGFloat = 62.33
    /// Ancho de la mínima separada: círculo, u óvalo si su contenido lo pide
    public static let minimalWidth: ClosedRange<CGFloat> = 36.67...45
    /// Ancho limitado (3 actividades a la vista): todo cabe en un círculo de este diámetro
    public static let limitedWidthDiameter: CGFloat = 28
    /// Expandida: ancho (6.3" … 6.9") y alto según el contenido
    public static let expandedWidth: ClosedRange<CGFloat> = 371...408
    public static let expandedHeight: ClosedRange<CGFloat> = 84...160
    /// Margen estándar de la pantalla bloqueada (y buen margen interior de la expandida)
    public static let standardMargin: CGFloat = 14
    /// Animaciones de actualización de contenido: 2 s como máximo (las de extender/contraer son aparte)
    public static let maximumUpdateAnimation: TimeInterval = 2

    // MARK: Adaptación al Mac

    /// Proporción entre el notch del Mac y la isla del iPhone (≈ 0.9 en una MacBook Air)
    public static func scale(notchHeight: CGFloat) -> CGFloat {
        guard notchHeight > 0 else { return 1 }
        return notchHeight / compactHeight
    }

    /// Alto de la expandida para un contenido: lo que mide, dentro del rango de Apple
    public static func expandedHeight(forContent contentHeight: CGFloat) -> CGFloat {
        min(expandedHeight.upperBound, max(expandedHeight.lowerBound, contentHeight.rounded(.up)))
    }

    /// Radio interior concéntrico: un elemento a `margin` del borde redondeado usa el radio exterior menos el
    /// margen, así su curva corre paralela a la de la isla (HIG: márgenes parejos y colocación concéntrica)
    public static func concentricRadius(outer: CGFloat, margin: CGFloat) -> CGFloat {
        max(0, outer - margin)
    }
}
