import SwiftUI

/// Cuello líquido ("metaball") entre el extremo del notch y una bolita satélite.
///
/// Ambos se modelan como círculos: el extremo redondeado del notch (radio = media altura) y la bolita.
/// Cuando están cerca se dibuja un puente con curvas Bézier tangentes a ambos; al alejarse, el puente se
/// adelgaza de forma continua hasta desaparecer, como dos gotas que se separan. Al acercarse ocurre lo
/// inverso y la bolita queda absorbida dentro del notch.
public struct MetaballBridgeShape: Shape {
    /// Centro y radio del extremo del notch, en coordenadas del rectángulo de la bolita
    public var notchCenter: CGPoint
    public var notchRadius: CGFloat
    public var bubbleRadius: CGFloat
    /// Distancia entre centros a partir de la cual ya no hay puente
    public var maxDistance: CGFloat

    public func path(in rect: CGRect) -> Path {
        let c1 = notchCenter
        let r1 = notchRadius
        let c2 = CGPoint(x: rect.midX, y: rect.midY)
        let r2 = bubbleRadius
        let d = hypot(c2.x - c1.x, c2.y - c1.y)
        var path = Path()
        guard r1 > 0, r2 > 0, d > abs(r1 - r2), d < maxDistance else { return path }

        // El "esparcimiento" del cuello se reduce a cero antes de maxDistance: se rompe sin saltos
        let spread = 0.5 * Self.smoothstep((maxDistance - d) / (maxDistance * 0.35))
        guard spread > 0.002 else { return path }

        var u1: CGFloat = 0
        var u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(max(-1, min(1, (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))))
            u2 = acos(max(-1, min(1, (r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))))
        }
        let between = atan2(c2.y - c1.y, c2.x - c1.x)
        let maxSpread = acos(max(-1, min(1, (r1 - r2) / d)))

        let a1 = between + u1 + (maxSpread - u1) * spread
        let a2 = between - u1 - (maxSpread - u1) * spread
        let a3 = between + .pi - u2 - (.pi - u2 - maxSpread) * spread
        let a4 = between - .pi + u2 + (.pi - u2 - maxSpread) * spread

        func point(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint {
            CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        let p1 = point(c1, r1, a1), p2 = point(c1, r1, a2)
        let p3 = point(c2, r2, a3), p4 = point(c2, r2, a4)

        // Largo de las asas: proporcional a la separación para que el cuello sea curvo y no recto
        let handleSize: CGFloat = 2.4
        let total = r1 + r2
        let baseHandle = min(spread * handleSize, hypot(p3.x - p1.x, p3.y - p1.y) / total)
        let handle = baseHandle * min(1, d * 2 / total)
        let h1 = point(p1, r1 * handle, a1 - .pi / 2)
        let h2 = point(p2, r1 * handle, a2 + .pi / 2)
        let h3 = point(p3, r2 * handle, a3 + .pi / 2)
        let h4 = point(p4, r2 * handle, a4 - .pi / 2)

        path.move(to: p1)
        path.addCurve(to: p3, control1: h1, control2: h3)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: h4, control2: h2)
        path.closeSubpath()
        return path
    }

    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

/// Coloca una bolita satélite y la funde con el notch según `merge` (0 = en reposo a su lado, 1 = absorbida).
/// Animable: sirve tanto para la fusión al tocarla como para las transiciones de aparecer y desaparecer.
public struct LiquidSatelliteModifier: ViewModifier, Animatable {
    public var merge: CGFloat
    /// Centro de la bolita en reposo, relativo al centro horizontal del contenedor
    public var restingX: CGFloat
    /// Centro del extremo redondeado del notch del mismo lado, relativo al centro horizontal
    public var notchEndX: CGFloat
    public var notchRadius: CGFloat
    public var bubbleDiameter: CGFloat
    /// Desplazamiento vertical de la bolita (su borde superior)
    public var offsetY: CGFloat
    /// El puente negro sólo tiene sentido cuando el notch es negro (no sobre la tarjeta de vidrio)
    public var showsBridge: Bool

    /// Fusión extra que inyecta la transición de aparecer/desaparecer (ver `.liquidSatellite`)
    @Environment(\.liquidSatelliteExtraMerge) private var extraMerge
    
    public var animatableData: CGFloat {
        get { merge }
        set { merge = newValue }
    }

    public func body(content: Content) -> some View {
        let m = min(1, max(0, max(merge, extraMerge)))
        let bubbleRadius = bubbleDiameter / 2
        // Absorbida: el centro de la bolita queda casi concéntrico con el extremo del notch
        let mergedX = notchEndX
        let x = restingX + (mergedX - restingX) * Self.easeInOut(m)
        // Deformación sutil en la dirección del movimiento, máxima a mitad del trayecto
        let stretch = 1 + 0.12 * sin(.pi * m)
        let squash = 1 - 0.07 * sin(.pi * m)
        let rest = bubbleDiameter / 2

        return content
            // Al entrar al notch, el contenido de la bolita (anillo, icono, borde) se cubre de negro:
            // el cuerpo se funde negro sobre negro en lugar de desvanecerse
            .overlay(
                Circle()
                    .fill(Color.black)
                    .opacity(Double(Self.smoothstep((m - 0.35) / 0.45)))
                    .allowsHitTesting(false)
            )
            .scaleEffect(x: stretch, y: squash, anchor: .center)
            .background(
                MetaballBridgeShape(
                    notchCenter: CGPoint(x: rest + (notchEndX - x), y: rest + (notchRadius - (offsetY + bubbleRadius))),
                    notchRadius: notchRadius,
                    bubbleRadius: bubbleRadius,
                    maxDistance: notchRadius + bubbleRadius + abs(restingX - notchEndX - copysign(notchRadius + bubbleRadius, restingX - notchEndX)) * 0.6 + 2
                )
                .fill(Color.black)
                .opacity(showsBridge ? 1 : 0)
                .allowsHitTesting(false)
            )
            .offset(x: x, y: offsetY)
    }

    private static func easeInOut(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Transición de aparecer / desaparecer

private struct LiquidSatelliteExtraMergeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var liquidSatelliteExtraMerge: CGFloat {
        get { self[LiquidSatelliteExtraMergeKey.self] }
        set { self[LiquidSatelliteExtraMergeKey.self] = newValue }
    }
}

/// Anima la fusión extra durante una transición: al aparecer la bolita sale del notch (1 → 0) y al
/// desaparecer regresa a él (0 → 1), con el mismo cuello líquido que al tocarla.
private struct LiquidEmergeModifier: ViewModifier, Animatable {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content.environment(\.liquidSatelliteExtraMerge, amount)
    }
}

public extension AnyTransition {
    /// La bolita brota del notch al aparecer y se reabsorbe en él al desaparecer.
    static var liquidSatellite: AnyTransition {
        .modifier(active: LiquidEmergeModifier(amount: 1), identity: LiquidEmergeModifier(amount: 0))
    }
}
