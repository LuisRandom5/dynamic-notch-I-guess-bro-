import SwiftUI

// MARK: - ActivitySliderPillView (Plantilla Unificada de SliderPill con Estados)
/// Renderiza la barra de control interactiva para Brillo, Volumen y Silenciado (Mute).
/// - Ancho: 320 pt, Alto: 36 pt, Forma: Cápsula estilizada.
/// - Barra con animación spring corta y reactiva al mantener teclas.
/// - Transiciones suaves de símbolo (`.symbolEffect(.replace)`) y crossfade de color (Verde ↔ Rojo en mute).
public struct ActivitySliderPillView: View {
    public let activity: LiveActivity
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    // MARK: - Propiedades Derivadas del Estado
    private var sliderState: SliderPillState? {
        activity.sliderState
    }
    
    private var level: Float {
        sliderState?.level ?? 0.5
    }
    
    private var isMuted: Bool {
        sliderState?.isMuted ?? false
    }
    
    // Icono correspondiente según el tipo y nivel
    @ViewBuilder
    private var leadingIconView: some View {
        if let state = sliderState {
            switch state {
            case .brightness(let lvl):
                // Icono de sol cuyo relleno/rayos crecen con el nivel usando variableValue
                Image(systemName: "sun.max.fill", variableValue: Double(max(0.12, lvl)))
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
                    
            case .volume(let lvl, let muted):
                if muted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(DesignTokens.red)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    let iconName: String = {
                        if lvl <= 0.005 {
                            return "speaker.fill"
                        } else if lvl < 0.33 {
                            return "speaker.wave.1.fill"
                        } else if lvl < 0.66 {
                            return "speaker.wave.2.fill"
                        } else {
                            return "speaker.wave.3.fill"
                        }
                    }()
                    Image(systemName: iconName)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        } else if let leading = activity.leading {
            leading
        } else {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    // Color de la barra de progreso con soporte de crossfade
    private var barFillColor: Color {
        if let state = sliderState {
            switch state {
            case .brightness:
                return .white
            case .volume(_, let muted):
                return muted ? DesignTokens.red : DesignTokens.green
            }
        }
        return activity.tint
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Icono Leading (22 x 22 pt centrado)
            leadingIconView
                .frame(width: 22, height: 22, alignment: .center)
            
            // Barra de Progreso en Cápsula (Alto 5.5 pt, Pista al 20%)
            GeometryReader { geo in
                let clampedLevel = min(1.0, max(0.0, level))
                let fillWidth = max(5.5, geo.size.width * CGFloat(clampedLevel))
                
                ZStack(alignment: .leading) {
                    // Pista de fondo
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 5.5)
                    
                    // Relleno animado
                    Capsule(style: .continuous)
                        .fill(barFillColor)
                        .frame(width: fillWidth, height: 5.5)
                        // Spring corto y reactivo para cambios fluidos al mantener presionada la tecla
                        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: level)
                        // Crossfade suave para el color entre verde y rojo al mutear
                        .animation(.easeInOut(duration: 0.24), value: isMuted)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)
            
            // Número 0-100 Trailing con tipografía monospaced SF Pro Rounded
            if sliderState != nil {
                Text("\(Int(round(level * 100)))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(isMuted ? DesignTokens.red.opacity(0.9) : .white)
                    .contentTransition(.numericText())
                    .frame(minWidth: 28, alignment: .trailing)
                    .animation(.easeInOut(duration: 0.20), value: isMuted)
            } else if let trailing = activity.trailing {
                trailing
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 36)
        .background(Color.black)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.40), radius: 14, x: 0, y: 6)
    }
}
