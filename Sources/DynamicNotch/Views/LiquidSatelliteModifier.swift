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
        let spread = 0.62 * Self.smoothstep((maxDistance - d) / (maxDistance * 0.30))
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
        let handleSize: CGFloat = 3.0
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
    /// La bolita es de Liquid Glass (notch desplegado en cristal): el propio contenedor de vidrio la funde con
    /// el notch, así que en vez de cubrirla de negro se disuelve al final de la absorción
    public var isGlass: Bool = false

    /// Fusión extra que inyecta la transición de aparecer/desaparecer (ver `.liquidSatellite`)
    @Environment(\.liquidSatelliteExtraMerge) private var extraMerge
    
    public var animatableData: CGFloat {
        get { merge }
        set { merge = newValue }
    }

    public func body(content: Content) -> some View {
        // `raw` puede bajar de 0 un instante: el resorte de desprendimiento sobrepasa el lugar de reposo y la
        // gota se aleja un poco antes de asentarse (rebote sutil). Todo lo demás usa el valor acotado.
        let raw = max(merge, extraMerge)
        let m = min(1, max(0, raw))
        let bubbleRadius = bubbleDiameter / 2
        // Absorbida: el centro de la bolita queda concéntrico con el extremo del notch
        let mergedX = notchEndX
        let travel = raw < 0 ? raw : Self.easeInOut(m)
        let x = restingX + (mergedX - restingX) * travel
        
        // Perfil de nacimiento calcado de la Isla Dinámica (cuadro por cuadro):
        //  m = 1    la gota nace DENTRO del extremo del notch, pequeña y muy apretada (un "(" del icono)
        //  m ≈ 0.6  asoma un bulto aplanado, más bajo que la cápsula, con el icono comprimido a lo ancho
        //  m ≈ 0.35 ya es un círculo completo unido por una cintura gruesa (forma de cacahuate)
        //  m ≈ 0.15 la cintura es un hilo · m = 0 separada en su lugar
        //  raw < 0  el resorte la pasa un poco: crece apenas por encima de su tamaño y se asienta
        let grow = Self.smoothstep((1 - m) / 0.65)
        // Fase B: la protuberancia nace estirada HACIA AFUERA (más ancha que alta) desde el borde del notch;
        // al formarse el cuello ya es un círculo
        let radiusScale: CGFloat = raw < 0 ? 1 + min(0.08, -raw * 0.6) : 0.55 + 0.45 * grow
        let widthFactor = 1 + 0.18 * Self.smoothstep((m - 0.35) / 0.40)
        // Tensión superficial: justo antes de que el hilo se corte (m 0.30 → 0.05) la gota se estira hacia
        // el notch; al soltarse (raw < 0) tiembla como gelatina: se ensancha y se aplana un instante
        let tension = (m > 0.05 && m < 0.30) ? sin(.pi * (0.30 - m) / 0.25) : 0
        let wobble: CGFloat = raw < 0 ? min(1, -raw / 0.06) : 0
        let scaleX = radiusScale * widthFactor * (1 + 0.09 * tension + 0.07 * wobble)
        let scaleY = radiusScale * (1 - 0.06 * tension - 0.06 * wobble)
        let rest = bubbleDiameter / 2
        let currentRadius = bubbleRadius * scaleY
        
        // Mismo umbral que el cuello: el cuello aguanta casi hasta la posición de reposo
        let gapTravel = abs(restingX - notchEndX - copysign(notchRadius + bubbleRadius, restingX - notchEndX))
        let maxDistance = notchRadius + bubbleRadius + gapTravel * 0.92
        let distance = abs(x - notchEndX)
        // Cuánto está unida la bolita al notch (0 separada · 1 cuello pleno)
        let attached = showsBridge ? Self.smoothstep((maxDistance - distance) / (maxDistance * 0.30)) : 0
        let notchCenterOffset = CGPoint(x: notchEndX - x, y: notchRadius - (offsetY + bubbleRadius))
        
        // Cristal: mientras la gota está en movimiento (desprendiéndose, fundiéndose o rebotando), la bolita y su
        // cuello se dibujan como UNA sola forma de vidrio (círculo ∪ cuello) que se estira, adelgaza y se corta.
        // En reposo vuelve la bolita normal; el relevo es invisible porque ahí ambas son el mismo círculo.
        let drawsGlassDroplet = isGlass && showsBridge && abs(raw) > 0.001
        let glassFade = isGlass ? 1 - Double(Self.smoothstep((m - 0.70) / 0.28)) : 1
        
        return content
            .environment(\.liquidBubbleGlassSuppressed, drawsGlassDroplet)
            // Sin costuras: mientras comparten superficie, el borde fino de la bolita se funde con el negro
            .overlay(
                Circle()
                    .strokeBorder(Color.black, lineWidth: 1.4)
                    .opacity(isGlass ? 0 : Double(attached))
                    .allowsHitTesting(false)
            )
            // Primero sólo se ve la protuberancia del propio notch; el anillo y el icono aparecen cuando la gota
            // ya es un círculo (fase de cuello), no antes
            .overlay(
                Circle()
                    .fill(Color.black)
                    .opacity(isGlass ? 0 : Double(Self.smoothstep((m - 0.40) / 0.18)))
                    .allowsHitTesting(false)
            )
            .opacity(glassFade)
            .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
            .background(
                ZStack {
                    if drawsGlassDroplet {
                        LiquidGlassDroplet(
                            shape: LiquidDropletShape(
                                notchCenterOffset: notchCenterOffset,
                                notchRadius: notchRadius,
                                bubbleRadius: bubbleRadius,
                                maxDistance: maxDistance,
                                scaleX: scaleX,
                                scaleY: scaleY
                            ),
                            reach: abs(notchCenterOffset.x) + notchRadius + 12
                        )
                        .opacity(glassFade)
                    } else if !isGlass && showsBridge && abs(raw) > 0.001 {
                        // Silueta líquida ÚNICA: el extremo del notch y la gota se dibujan juntos, se desenfocan y
                        // se cortan por umbral (metaball). El propio borde del notch se abomba, forma un cuello
                        // curvo que se adelgaza y se rompe solo; al regresar, el contacto se ensancha y se funde.
                        LiquidGooSilhouette(
                            notchCenterOffset: notchCenterOffset,
                            notchRadius: notchRadius,
                            bubbleRadius: bubbleRadius,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            notchIsLeading: notchEndX < restingX
                        )
                    }
                }
                .animation(nil, value: drawsGlassDroplet)
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

// MARK: - Silueta líquida (metaball por desenfoque + umbral)

/// El extremo del notch y la gota dibujados en un mismo lienzo, desenfocados y cortados por umbral de
/// opacidad: donde sus campos se suman aparece un único contorno continuo (protuberancia → cuello → corte).
/// Centro del lienzo = centro de la bolita.
struct LiquidGooSilhouette: View {
    let notchCenterOffset: CGPoint
    let notchRadius: CGFloat
    let bubbleRadius: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    /// El notch está a la izquierda de la gota (bolita del lado derecho)
    let notchIsLeading: Bool

    /// Radio del desenfoque: define hasta dónde se estira el cuello antes de romperse (~2× este valor)
    static let gooBlur: CGFloat = 7

    var body: some View {
        let reach = abs(notchCenterOffset.x) + notchRadius * 5 + bubbleRadius + 24
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = notchRadius
            let pillEnd = CGPoint(x: c.x + notchCenterOffset.x, y: c.y + notchCenterOffset.y)
            // El cuerpo del notch se extiende HACIA DENTRO (lado opuesto a la gota) para que el campo del extremo
            // sea el de una cápsula, no el de un círculo suelto
            let bodyLength = R * 4
            let pillRect = notchIsLeading
                ? CGRect(x: pillEnd.x - bodyLength, y: pillEnd.y - R, width: bodyLength + R, height: 2 * R)
                : CGRect(x: pillEnd.x - R, y: pillEnd.y - R, width: bodyLength + R, height: 2 * R)
            let w = 2 * bubbleRadius * scaleX
            let h = 2 * bubbleRadius * scaleY
            let drop = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)

            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: Self.gooBlur))
            context.drawLayer { layer in
                layer.fill(Path(roundedRect: pillRect, cornerRadius: R), with: .color(.black))
                layer.fill(Path(ellipseIn: drop), with: .color(.black))
            }
        }
        .frame(width: 2 * reach, height: 2 * reach)
        .allowsHitTesting(false)
    }
}

// MARK: - Gota de cristal (bolita ∪ cuello)

/// Gota (con su escala de nacimiento: comprimida al salir, plena al separarse) unida con el cuello metaball
/// hacia el notch, como una sola silueta. Coordenadas: el centro del rectángulo es el centro de la bolita.
struct LiquidDropletShape: Shape {
    var notchCenterOffset: CGPoint
    var notchRadius: CGFloat
    var bubbleRadius: CGFloat
    var maxDistance: CGFloat
    var scaleX: CGFloat
    var scaleY: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = bubbleRadius
        let w = 2 * r * scaleX
        let h = 2 * r * scaleY
        let drop = Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        let bubbleRect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        let neck = MetaballBridgeShape(
            notchCenter: CGPoint(x: r + notchCenterOffset.x, y: r + notchCenterOffset.y),
            notchRadius: notchRadius,
            bubbleRadius: r * scaleY,
            maxDistance: maxDistance
        ).path(in: CGRect(origin: .zero, size: bubbleRect.size))
            .offsetBy(dx: bubbleRect.minX, dy: bubbleRect.minY)
        return neck.isEmpty ? drop : drop.union(neck)
    }
}

/// La gota de vidrio con el mismo material y velo que las bolitas
private struct LiquidGlassDroplet: View {
    let shape: LiquidDropletShape
    /// Margen alrededor de la bolita para que el cuello quepa dentro del marco
    let reach: CGFloat

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var backdrop = BackdropBrightnessMonitor.shared

    var body: some View {
        let size = 2 * (shape.bubbleRadius + reach)
        ZStack {
            if #available(macOS 26.0, *) {
                Color.black.opacity(max(0.22, NotchGlassMetrics.veilOpacity(for: appState.effectiveAppearanceMode)))
                    .clipShape(shape)
                Color.clear
                    .glassEffect(backdrop.isBackdropBright ? Glass.regular : Glass.clear, in: shape)
                    .glassEffectTransition(.identity)
            } else {
                shape.fill(Color.black)
            }
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, .dark)
    }
}

private struct LiquidBubbleGlassSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// La gota de vidrio (bolita ∪ cuello) la dibuja LiquidSatelliteModifier: el fondo propio de la bolita se oculta
    var liquidBubbleGlassSuppressed: Bool {
        get { self[LiquidBubbleGlassSuppressedKey.self] }
        set { self[LiquidBubbleGlassSuppressedKey.self] = newValue }
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
    /// - Desprendimiento: resorte con poco amortiguamiento → la gota se separa, sobrepasa apenas su lugar y se
    ///   asienta (como mercurio que se suelta).
    /// - Absorción: curva que ACELERA (como atraída por un imán) hasta tocar el notch; ahí la cápsula se abulta
    ///   y rebota (ActivityCenter.pillImpulse).
    static var liquidSatellite: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: LiquidEmergeModifier(amount: 1), identity: LiquidEmergeModifier(amount: 0))
                // Al doble de un cambio normal: se alcanza a leer el nacimiento de la gota
                .animation(.spring(response: 1.32, dampingFraction: 0.70)),
            // Guardarse es lo mismo a la inversa: crece la cintura, la gota se encoge y se mete en el extremo
            removal: .modifier(active: LiquidEmergeModifier(amount: 1), identity: LiquidEmergeModifier(amount: 0))
                .animation(.spring(response: 1.12, dampingFraction: 0.94))
        )
    }
}
