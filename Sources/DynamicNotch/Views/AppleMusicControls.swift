import SwiftUI

// MARK: - Controles al estilo de Apple Music

/// Botón de transporte como en Apple Music: al PRESIONAR (no al soltar) el icono se comprime y aparece detrás
/// un círculo gris suave; al soltar, el icono regresa con un resorte y el círculo se desvanece.
public struct MusicTransportButtonStyle: ButtonStyle {
    public var haloSize: CGFloat
    public var pressedScale: CGFloat
    public var isHovering: Bool
    public var isActive: Bool

    public init(haloSize: CGFloat, pressedScale: CGFloat = 0.82, isHovering: Bool = false, isActive: Bool = false) {
        self.haloSize = haloSize
        self.pressedScale = pressedScale
        self.isHovering = isHovering
        self.isActive = isActive
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack {
            Circle()
                .fill(Color.white.opacity(pressed ? 0.18 : (isHovering ? 0.10 : (isActive ? 0.10 : 0))))
                .frame(width: haloSize, height: haloSize)
                // El círculo nace un poco más chico y se abre al presionar
                .scaleEffect(pressed ? 1.0 : (isHovering ? 0.96 : 0.78))
                .animation(pressed ? .spring(response: 0.16, dampingFraction: 0.82) : .easeOut(duration: 0.32), value: pressed)
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isHovering)
            configuration.label
                .scaleEffect(pressed ? pressedScale : 1.0)
                // Comprime rápido; regresa con un rebote leve
                .animation(pressed ? .spring(response: 0.14, dampingFraction: 0.86) : .spring(response: 0.34, dampingFraction: 0.58), value: pressed)
        }
        .frame(width: haloSize, height: haloSize)
        .contentShape(Circle())
    }
}

/// Triángulo que apunta a la derecha (la mitad de `forward.fill`)
private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        // Esquinas apenas redondeadas, como el símbolo del sistema
        let r = min(rect.width, rect.height) * 0.12
        var path = Path()
        let a = CGPoint(x: rect.minX, y: rect.minY)
        let b = CGPoint(x: rect.maxX, y: rect.midY)
        let c = CGPoint(x: rect.minX, y: rect.maxY)
        path.move(to: CGPoint(x: a.x, y: a.y + r))
        path.addArc(tangent1End: a, tangent2End: b, radius: r)
        path.addArc(tangent1End: b, tangent2End: c, radius: r)
        path.addArc(tangent1End: c, tangent2End: a, radius: r)
        path.closeSubpath()
        return path
    }
}

/// Siguiente / anterior de Apple Music: al tocar, el triángulo de adelante sale deslizándose y desvaneciéndose,
/// el de atrás avanza a su lugar y uno nuevo brota por detrás. El estado final es idéntico al inicial, así que
/// la animación se puede repetir sin saltos.
public struct SkipGlyph: View {
    public enum Direction { case forward, backward }

    let direction: Direction
    /// Cambia en cada toque (dispara la animación)
    let trigger: Int
    var triangleSize: CGSize
    var color: Color

    @State private var progress: CGFloat = 0

    public init(direction: Direction, trigger: Int, triangleSize: CGSize = CGSize(width: 10, height: 12), color: Color = .white) {
        self.direction = direction
        self.trigger = trigger
        self.triangleSize = triangleSize
        self.color = color
    }

    public var body: some View {
        SkipGlyphFrame(progress: progress, size: triangleSize, color: color)
            .scaleEffect(x: direction == .forward ? 1 : -1, y: 1)
            .onChange(of: trigger) { _, _ in
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { progress = 0 }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { progress = 1 }
            }
    }
}

/// Un cuadro de la animación de saltar (progress 0 → 1)
private struct SkipGlyphFrame: View, Animatable {
    var progress: CGFloat
    let size: CGSize
    let color: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(1.2, max(0, progress))
        let w = size.width
        let fadeOut = max(0, 1 - p * 1.6)
        ZStack(alignment: .leading) {
            // El nuevo, que brota en el lugar de atrás
            PlayTriangle().fill(color)
                .frame(width: w, height: size.height)
                .scaleEffect(min(1, p), anchor: .leading)
                .opacity(Double(min(1, p * 1.4)))
            // El de atrás, que avanza al lugar de adelante
            PlayTriangle().fill(color)
                .frame(width: w, height: size.height)
                .offset(x: w * min(1, p))
            // El de adelante, que sale
            PlayTriangle().fill(color)
                .frame(width: w, height: size.height)
                .scaleEffect(1 - 0.35 * min(1, p), anchor: .leading)
                .offset(x: w + w * 0.9 * p)
                .opacity(Double(fadeOut))
        }
        .frame(width: w * 2, height: size.height, alignment: .leading)
    }
}

// MARK: - Cambio de carátula

/// Giro de la carátula alrededor de su eje vertical (como pasar una página)
private struct ArtworkFlipModifier: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(opacity)
    }
}

public extension AnyTransition {
    /// Carátula que cambia de canción: la vieja gira hasta quedar de canto y, ya de canto, la nueva sigue el giro
    /// hasta quedar de frente, como pasar una página (hacia la derecha al ir a la siguiente; al revés al regresar)
    static func artworkSwap(direction: CGFloat = 1) -> AnyTransition {
        let turn = direction >= 0 ? 1.0 : -1.0
        let half = ArtworkSwapTiming.half
        return .asymmetric(
            insertion: .modifier(active: ArtworkFlipModifier(angle: -90 * turn, opacity: 0),
                                 identity: ArtworkFlipModifier(angle: 0, opacity: 1))
                .animation(.spring(response: half * 2.1, dampingFraction: 0.78).delay(half)),
            removal: .modifier(active: ArtworkFlipModifier(angle: 90 * turn, opacity: 0),
                               identity: ArtworkFlipModifier(angle: 0, opacity: 1))
                .animation(.easeIn(duration: half))
        )
    }
}

public enum ArtworkSwapTiming {
    /// Media vuelta (la vieja hasta quedar de canto)
    public static let half: Double = 0.16
}

public extension Animation {
    /// Transacción del cambio de carátula (cada mitad trae su propia curva, ver artworkSwap)
    static var artworkSwap: Animation { .easeInOut(duration: ArtworkSwapTiming.half * 2) }
}
