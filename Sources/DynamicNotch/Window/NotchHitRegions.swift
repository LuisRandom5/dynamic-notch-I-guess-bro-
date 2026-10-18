import AppKit
import SwiftUI

/// Región interactiva reportada por una vista SwiftUI al panel del notch.
/// Las vistas declaran su propia forma y `NotchHitTestView` la usa tal cual: no hay fórmulas de posición duplicadas.
public struct NotchHitRegion: Equatable {
    public enum Shape: Equatable {
        case circle
        case roundedRect(cornerRadius: CGFloat)
    }

    /// Marco en coordenadas globales de SwiftUI (origen arriba a la izquierda del NSHostingView).
    public var frame: CGRect
    public var shape: Shape
    /// Tolerancia extra alrededor de la forma (pt).
    public var padding: CGFloat

    /// Trazado en coordenadas AppKit de una vista no volteada de altura `containerHeight` (origen abajo a la izquierda).
    func path(inContainerOfHeight containerHeight: CGFloat) -> CGPath {
        let flipped = CGRect(
            x: frame.minX,
            y: containerHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        ).insetBy(dx: -padding, dy: -padding)
        switch shape {
        case .circle:
            return CGPath(ellipseIn: flipped, transform: nil)
        case .roundedRect(let cornerRadius):
            let r = min(cornerRadius + padding, flipped.width / 2, flipped.height / 2)
            return CGPath(roundedRect: flipped, cornerWidth: r, cornerHeight: r, transform: nil)
        }
    }
}

public struct NotchHitRegionsKey: PreferenceKey {
    public static var defaultValue: [String: NotchHitRegion] = [:]

    public static func reduce(value: inout [String: NotchHitRegion], nextValue: () -> [String: NotchHitRegion]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

public extension View {
    /// Registra esta vista como zona clicable del panel del notch.
    /// Aplicarlo DESPUÉS de `.offset` / `.scaleEffect` para que el marco reportado siga a la vista animada.
    func notchHitRegion(_ id: String, shape: NotchHitRegion.Shape = .circle, padding: CGFloat = 6) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: NotchHitRegionsKey.self,
                    value: [id: NotchHitRegion(frame: geo.frame(in: .global), shape: shape, padding: padding)]
                )
            }
        )
    }
}
