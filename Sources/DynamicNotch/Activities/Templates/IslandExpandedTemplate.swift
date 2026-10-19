import SwiftUI

/// Presentación expandida con las regiones de la Isla Dinámica (`DynamicIslandExpandedRegion`):
/// - leading / trailing: a los lados de la cámara, pegados a ella (HIG: "envuelve la cámara")
/// - center: debajo de la cámara, entre ambos lados
/// - bottom: debajo de todo, a lo ancho
///
/// Márgenes parejos y concéntricos: el contenido queda a `IslandMetrics.standardMargin` del borde y los
/// elementos redondeados que usen `ContainerRelativeShape()` toman el radio interior que corre paralelo al de
/// la tarjeta. El alto se ajusta a lo que mide el contenido (84–160 pt, ver IslandMetrics.expandedHeight).
public struct IslandExpandedTemplate<Leading: View, Trailing: View, Center: View, Bottom: View>: View {
    let outerRadius: CGFloat
    let leading: Leading
    let trailing: Trailing
    let center: Center
    let bottom: Bottom

    public init(outerRadius: CGFloat = IslandExpandedTemplateMetrics.defaultOuterRadius,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder center: () -> Center,
                @ViewBuilder bottom: () -> Bottom) {
        self.outerRadius = outerRadius
        self.leading = leading()
        self.trailing = trailing()
        self.center = center()
        self.bottom = bottom()
    }

    public var body: some View {
        let geometry = ScreenService.shared.currentGeometry
        let margin = IslandMetrics.standardMargin
        VStack(spacing: 8) {
            // Fila de la cámara: los lados se pegan a ella, sin relleno entre el contenido y la cámara
            HStack(alignment: .center, spacing: 0) {
                leading
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: geometry.cameraCutoutWidth)
                trailing
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(minHeight: geometry.height)
            center
                .frame(maxWidth: .infinity)
            bottom
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        // Forma del contenedor para ContainerRelativeShape (esquinas de abajo; arriba cuelga del borde)
        .containerShape(
            UnevenRoundedRectangle(bottomLeadingRadius: outerRadius, bottomTrailingRadius: outerRadius, style: .continuous)
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: IslandExpandedContentHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(IslandExpandedContentHeightKey.self) { height in
            ActivityCenter.shared.reportExpandedContentHeight(height)
        }
    }
}

public enum IslandExpandedTemplateMetrics {
    /// Radio de las esquinas de abajo de una tarjeta expandida
    public static let defaultOuterRadius: CGFloat = 32
    /// Alto con el que abre antes de medir su contenido
    public static let initialHeight: CGFloat = 120
}

private struct IslandExpandedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Expandida por defecto

/// Presentación expandida para las actividades que no traen la suya: icono a la izquierda, dato vivo a la
/// derecha, título y detalle al centro y, abajo, el progreso y una sola acción ("Abrir"), como pide la HIG.
public struct DefaultActivityExpandedView: View {
    let activity: LiveActivity

    public init(activity: LiveActivity) {
        self.activity = activity
    }

    public var body: some View {
        IslandExpandedTemplate {
            Image(systemName: activity.bolitaVariant?.iconName ?? "circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(activity.tint)
        } trailing: {
            trailingValue
        } center: {
            VStack(spacing: 2) {
                Text(activity.title ?? activity.kind.rawValue.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = activity.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        // Cambios de texto como la Isla: reemplazo suave, no un salto
                        .contentTransition(.interpolate)
                }
            }
        } bottom: {
            VStack(spacing: 10) {
                if let progress = activity.progress {
                    ProgressCapsule(progress: progress, tint: activity.tint)
                }
                if let onTap = activity.onTap {
                    Button(action: onTap) {
                        Text("Abrir")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            // Concéntrico con la tarjeta (radio exterior menos el margen)
                            .background(ContainerRelativeShape().fill(activity.tint.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        if let progress = activity.progress {
            Text("\(Int((progress * 100).rounded())) %")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(activity.tint)
                .contentTransition(.numericText(value: progress))
                .animation(.smooth(duration: 0.4), value: progress)
        } else if let short = activity.bolitaVariant?.shortText {
            Text(short)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(activity.tint)
                .contentTransition(.numericText())
        }
    }
}

/// Barra de progreso de la expandida
private struct ProgressCapsule: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                    .animation(.smooth(duration: 0.6), value: progress)
            }
        }
        .frame(height: 6)
    }
}
