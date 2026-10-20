import SwiftUI
import AppKit

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
/// La "respiración" mientras Claude trabaja es una animación de Core Animation sobre una capa
/// (`CABasicAnimation` en el servidor de ventanas): la app no hace nada por cuadro. Con `repeatForever` de
/// SwiftUI el hilo principal recalculaba el layout de la ventana en cada cuadro (~5 % de CPU mientras
/// Claude trabajaba).
public struct ClaudeMarkView: View {
    public static let orange = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757

    public let size: CGFloat
    public let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat, isAnimating: Bool = false) {
        self.size = size
        self.isAnimating = isAnimating
    }

    public var body: some View {
        ClaudeMarkLayerView(size: size, breathing: isAnimating && !reduceMotion)
            .frame(width: size, height: size)
    }
}

/// La marca dibujada en una `CAShapeLayer`; respirar = escala 1 ⇄ 0.9 en bucle dentro de Core Animation
private struct ClaudeMarkLayerView: NSViewRepresentable {
    let size: CGFloat
    let breathing: Bool

    private static let breatheKey = "claude.breathe"

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        let shape = CAShapeLayer()
        shape.fillColor = NSColor(ClaudeMarkView.orange).cgColor
        view.layer?.addSublayer(shape)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let shape = view.layer?.sublayers?.first as? CAShapeLayer else { return }
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        if shape.bounds != bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shape.bounds = bounds
            shape.position = CGPoint(x: size / 2, y: size / 2)
            // El sistema de coordenadas de la capa crece hacia arriba: se voltea para que coincida con SwiftUI
            var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -size)
            shape.path = ClaudeSparkShape(phase: 0).path(in: bounds).cgPath.copy(using: &flip)
            CATransaction.commit()
        }
        let running = shape.animation(forKey: Self.breatheKey) != nil
        if breathing && !running {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.9
            pulse.toValue = 1.0
            pulse.duration = 1.25
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shape.add(pulse, forKey: Self.breatheKey)
        } else if !breathing && running {
            shape.removeAnimation(forKey: Self.breatheKey)
        }
    }
}
