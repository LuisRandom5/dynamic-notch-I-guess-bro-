import SwiftUI
import AppKit

/// Aviso de batería en la isla, como el iPhone: la isla se abre a los lados (igual que con los AirPods) y el
/// contenido sale de la cámara hacia afuera. "Cargando" / "Carga completa" / "Batería baja" a la izquierda; a la
/// derecha el porcentaje y la batería, que se llena con un resorte. Cargando: el rayo aparece con un rebote.
/// Batería baja: el relleno rojo parpadea unas veces, como la alerta del iPhone.
public struct BatteryNoticePillView: View {
    public enum Kind: Equatable { case charging, fullyCharged, low }

    let activityId: String
    let kind: Kind
    let label: String
    let labelColor: Color
    let percentage: Int
    let tint: Color
    let wingWidth: CGFloat

    @EnvironmentObject var screenService: ScreenService
    @ObservedObject private var center = ActivityCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var emerged = false
    @State private var fill: CGFloat = 0
    @State private var boltShown = false
    @State private var pulseTrigger = 0

    public init(activityId: String, kind: Kind, label: String, labelColor: Color, percentage: Int, tint: Color, wingWidth: CGFloat) {
        self.activityId = activityId
        self.kind = kind
        self.label = label
        self.labelColor = labelColor
        self.percentage = max(0, min(100, percentage))
        self.tint = tint
        self.wingWidth = wingWidth
    }

    /// Ancho de cada ala para que quepan el texto y la batería (el notch o la isla quedan al centro)
    public static func wingWidth(for label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: Metrics.labelSize, weight: .semibold)
        let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let batteryWidth: CGFloat = 40 + 6 + Metrics.glyphSize.width + 3
        return ceil(max(84, labelWidth, batteryWidth) + Metrics.edgePadding + 8)
    }

    private enum Metrics {
        static let labelSize: CGFloat = 13
        static let edgePadding: CGFloat = 16
        static let glyphSize = CGSize(width: 25, height: 12)
    }

    private var isDismissing: Bool { center.dismissingActivityId == activityId }
    private var shown: Bool { emerged && !isDismissing }

    public var body: some View {
        let geometry = screenService.currentGeometry
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: Metrics.labelSize, weight: .semibold))
                .foregroundColor(labelColor)
                .lineLimit(1)
                .fixedSize()
                .modifier(EmergeFromCamera(shown: shown, towardLeading: true))
                .padding(.leading, Metrics.edgePadding)
                .frame(width: wingWidth, height: geometry.height, alignment: .leading)

            Color.clear.frame(width: geometry.width, height: geometry.height)

            HStack(spacing: 6) {
                Text("\(percentage)%")
                    .font(.system(size: Metrics.labelSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                // Batería baja: sólo el relleno rojo parpadea (el contorno se queda), como el iPhone
                PhaseAnimator(kind == .low ? [1.0, 0.15, 1.0, 0.15, 1.0, 0.15, 1.0] : [1.0], trigger: pulseTrigger) { fillOpacity in
                    IPhoneBatteryGlyph(level: fill, tint: tint, showsBolt: boltShown, size: Metrics.glyphSize, fillOpacity: fillOpacity)
                } animation: { _ in .easeInOut(duration: 0.34) }
            }
            .fixedSize()
            .modifier(EmergeFromCamera(shown: shown, towardLeading: false))
            .padding(.trailing, Metrics.edgePadding)
            .frame(width: wingWidth, height: geometry.height, alignment: .trailing)
        }
        .frame(width: geometry.width + wingWidth * 2, height: geometry.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(percentage) por ciento")
        .onAppear(perform: animateIn)
    }

    private func animateIn() {
        let level = max(0.06, CGFloat(percentage) / 100)
        guard !reduceMotion else {
            emerged = true
            fill = level
            boltShown = kind == .charging
            return
        }
        // La isla se está abriendo: el contenido sale de la cámara un instante después
        withAnimation(.spring(response: 0.46, dampingFraction: 0.74).delay(0.08)) { emerged = true }
        withAnimation(.spring(response: 0.75, dampingFraction: 0.84).delay(0.22)) { fill = level }
        if kind == .charging {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.48).delay(0.62)) { boltShown = true }
        }
        if kind == .low {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { pulseTrigger += 1 }
        }
    }
}

/// El contenido del ala nace junto a la cámara (desenfocado y chico) y se desliza hacia su lado
private struct EmergeFromCamera: ViewModifier {
    let shown: Bool
    let towardLeading: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 5)
            .scaleEffect(shown ? 1 : 0.72, anchor: towardLeading ? .trailing : .leading)
            .offset(x: shown ? 0 : (towardLeading ? 22 : -22))
    }
}

/// Batería como la del iPhone: contorno gris translúcido, relleno de color redondeado y el borne a la derecha
public struct IPhoneBatteryGlyph: View {
    let level: CGFloat
    let tint: Color
    let showsBolt: Bool
    let size: CGSize
    let fillOpacity: Double

    public init(level: CGFloat, tint: Color, showsBolt: Bool = false, size: CGSize = CGSize(width: 25, height: 12),
                fillOpacity: Double = 1) {
        self.level = level
        self.tint = tint
        self.showsBolt = showsBolt
        self.size = size
        self.fillOpacity = fillOpacity
    }

    public var body: some View {
        let corner = size.height * 0.3
        let inset: CGFloat = 2
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
                RoundedRectangle(cornerRadius: corner - 1, style: .continuous)
                    .fill(tint)
                    .opacity(fillOpacity)
                    .frame(width: max(2.5, (size.width - inset * 2) * min(1, level)), height: size.height - inset * 2)
                    .padding(.leading, inset)
                Image(systemName: "bolt.fill")
                    .font(.system(size: size.height * 0.72, weight: .heavy))
                    .foregroundColor(.black.opacity(0.82))
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(showsBolt ? 1 : 0.2)
                    .opacity(showsBolt ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            Capsule()
                .fill(Color.white.opacity(0.38))
                .frame(width: 1.6, height: size.height * 0.36)
        }
    }
}
