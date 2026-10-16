import SwiftUI

// MARK: - ActivitySliderPillView (Diseño Minimalista Integrado en las Alas del Notch - Imagen 1)
/// Extiende el notch físico horizontalmente hacia los lados:
/// - Ala izquierda: Icono de volumen/brillo + texto "Volume" / "Brightness".
/// - Centro: Espacio libre para la cámara física del notch.
/// - Ala derecha: Pequeña cápsula de progreso horizontal + nivel numérico (ej. "46").
public struct ActivitySliderPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var isContentRevealed: Bool = false
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var isContentVisible: Bool {
        isContentRevealed && center.dismissingActivityId != activity.id
    }
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    private var sliderState: SliderPillState? {
        activity.sliderState
    }
    
    private var level: Float {
        sliderState?.level ?? 0.5
    }
    
    private var isMuted: Bool {
        sliderState?.isMuted ?? false
    }
    
    private var titleText: String {
        if let state = sliderState {
            switch state {
            case .brightness:
                return "Brightness"
            case .volume(_, let muted):
                return muted ? "Mute" : "Volume"
            }
        }
        return "Volume"
    }
    
    // Icono correspondiente según el tipo y nivel
    @ViewBuilder
    private var leadingIconView: some View {
        if let state = sliderState {
            switch state {
            case .brightness(let lvl):
                Image(systemName: "sun.max.fill", variableValue: Double(max(0.12, lvl)))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
                    
            case .volume(let lvl, let muted):
                if muted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 13.5, weight: .semibold))
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
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        } else {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    // Color de la barra de progreso
    private var barFillColor: Color {
        if let state = sliderState {
            switch state {
            case .brightness:
                return .white
            case .volume(_, let muted):
                // Verde brillante idéntico a la referencia (#30D158) o Rojo en mute
                return muted ? DesignTokens.red : Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
            }
        }
        return Color(red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)
    }
    
    // Pista oscura sutil detrás de la barra
    private var barTrackColor: Color {
        if let state = sliderState {
            switch state {
            case .brightness:
                return Color.white.opacity(0.18)
            case .volume(_, let muted):
                return muted ? DesignTokens.red.opacity(0.25) : Color(red: 0x14 / 255.0, green: 0x5E / 255.0, blue: 0x28 / 255.0)
            }
        }
        return Color.white.opacity(0.18)
    }
    
    public var body: some View {
        let wingWidth: CGFloat = 146.0
        let clampedLevel = min(1.0, max(0.0, level))
        let barWidth: CGFloat = 46.0
        let fillWidth = max(4.0, barWidth * CGFloat(clampedLevel))
        
        HStack(spacing: 0) {
            // MARK: - ALA IZQUIERDA: Icono + "Volume" / "Brightness" con repliegue estético hacia el notch
            HStack(spacing: 8) {
                leadingIconView
                    .frame(width: 18, height: 18)
                
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .frame(width: wingWidth, height: geometry.height, alignment: .center)
            .opacity(isContentVisible ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.18), value: isContentVisible)
            
            // MARK: - CENTRO: Espacio bajo la cámara física del notch
            Spacer(minLength: 0)
                .frame(width: geometry.width)
            
            // MARK: - ALA DERECHA: Barra cápsula verde + Nivel numérico con repliegue estético hacia el notch
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                
                // Cápsula horizontal de progreso
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(barTrackColor)
                        .frame(width: barWidth, height: 4.5)
                    
                    Capsule(style: .continuous)
                        .fill(barFillColor)
                        .frame(width: fillWidth, height: 4.5)
                        .animation(.spring(response: 0.16, dampingFraction: 0.82), value: level)
                }
                .frame(height: 14)
                
                // Nivel numérico 0-100 con animación de cronómetro (odómetro vertical hacia arriba/abajo)
                RollingNumberView(
                    value: Int(round(level * 100)),
                    font: .system(size: 13, weight: .semibold, design: .rounded),
                    color: isMuted ? DesignTokens.red : .white,
                    alignment: .trailing
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 32, alignment: .trailing)
            }
            .padding(.trailing, 18)
            .frame(width: wingWidth, height: geometry.height, alignment: .center)
            .opacity(isContentVisible ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.18), value: isContentVisible)
        }
        .frame(width: geometry.width + (wingWidth * 2), height: geometry.height, alignment: .center)
        .onAppear {
            // Revelado suave sincronizado con el estiramiento del ancho del notch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    isContentRevealed = true
                }
            }
        }
    }
}
