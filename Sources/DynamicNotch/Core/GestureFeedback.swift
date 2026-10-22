import Combine
import CoreGraphics

/// Lo que cambia con cada movimiento de los dedos durante un gesto (desenfoque mantenido y cierre interactivo).
/// Vive aparte de AppState a propósito: AppState lo observan ~20 vistas, y publicar ahí 120 veces por segundo
/// las recalculaba todas en cada evento del trackpad (el swipe gastaba 40–55 % de CPU y se sentía trabado).
/// Aquí sólo lo observan los dos modificadores que lo dibujan (MorphBlurModifier e InteractiveCollapseScale).
public final class GestureFeedback: ObservableObject {
    public static let shared = GestureFeedback()

    /// Desenfoque mantenido por un gesto del trackpad en curso (0…1)
    @Published public var blurHold: CGFloat = 0
    /// Cierre interactivo (0…1): el reproductor/repisa/tarjeta se encoge hacia el notch siguiendo los dedos
    @Published public var collapseProgress: CGFloat = 0

    private init() {}
}
