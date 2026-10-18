import SwiftUI

/// Destello radial al estilo de la marca de Claude: rayos redondeados de largo irregular alrededor de un centro.
/// `phase` hace "respirar" los rayos mientras Claude trabaja.
public struct ClaudeSparkShape: Shape {
    public var phase: Double

    // Largo relativo de cada rayo: la irregularidad es parte del carácter orgánico del destello
    private static let rayLengths: [CGFloat] = [1.00, 0.80, 0.94, 0.76, 0.99, 0.84, 0.91, 0.78, 0.97, 0.82, 0.89, 0.77]
    // Desfase angular sutil por rayo (radianes) para que no se vea mecánico
    private static let rayJitter: [CGFloat] = [0.00, 0.05, -0.03, 0.04, -0.02, 0.03, 0.00, -0.04, 0.02, -0.03, 0.04, -0.01]

    public init(phase: Double = 0) {
        self.phase = phase
    }

    public var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = Self.rayLengths.count
        let rayWidth = radius * 0.30

        for i in 0..<count {
            let breathing = 1.0 + 0.07 * CGFloat(sin(phase * 2 * .pi + Double(i) * 1.7))
            let length = radius * Self.rayLengths[i] * breathing
            let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi + Self.rayJitter[i] - .pi / 2

            // Rayo vertical (de -ancho/2 a +ancho/2, de 0 a largo) que luego se rota alrededor del centro
            let ray = CGRect(x: -rayWidth / 2, y: -rayWidth * 0.2, width: rayWidth, height: length + rayWidth * 0.2)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle - .pi / 2)
            path.addPath(Path(roundedRect: ray, cornerRadius: rayWidth / 2), transform: transform)
        }
        return path
    }
}

/// Marca de Claude lista para usarse en la bolita, las alas y la tarjeta del notch.
///
/// El giro lento y la "respiración" mientras Claude trabaja son animaciones de Core Animation
/// (repeatForever) sobre una forma fija: corren en el GPU a la frecuencia de la pantalla (60/120 Hz)
/// sin redibujar la forma ni tocar el hilo principal en cada cuadro.
public struct ClaudeMarkView: View {
    public static let orange = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
    
    public let size: CGFloat
    public let isAnimating: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false
    
    public init(size: CGFloat, isAnimating: Bool = false) {
        self.size = size
        self.isAnimating = isAnimating
    }
    
    private var active: Bool { isAnimating && !reduceMotion }
    
    public var body: some View {
        ClaudeSparkShape(phase: 0)
            .fill(Self.orange)
            .frame(width: size, height: size)
            .scaleEffect(active && !breathe ? 0.9 : 1.0)
            .animation(active ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true) : .easeOut(duration: 0.3), value: breathe)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(active ? .linear(duration: 18).repeatForever(autoreverses: false) : .easeOut(duration: 0.3), value: spin)
            .onAppear { update(active) }
            .onChange(of: active) { _, isActive in update(isActive) }
    }
    
    private func update(_ isActive: Bool) {
        spin = isActive
        breathe = isActive
    }
}
