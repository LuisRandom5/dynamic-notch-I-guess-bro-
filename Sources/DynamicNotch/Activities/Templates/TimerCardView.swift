import SwiftUI
import AppKit

// MARK: - TimerCardView (Panel Expandido del Temporizador - Minutka Style / iOS Dynamic Island)
public struct TimerCardView: View {
    @ObservedObject var provider = TimerActivityProvider.shared
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var isRevealed: Bool = false
    @State private var isPressedCancel: Bool = false
    @State private var isPressedToggle: Bool = false
    
    public init() {}
    
    private var isDismissing: Bool {
        center.dismissingActivityId == "live_timer"
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Fila Principal: Botón Cancelar (X) • Título y Cronómetro Gigante • Botón Pausar/Reanudar (||)
            HStack(alignment: .center, spacing: 14) {
                // MARK: - Control Izquierdo: Botón Circular Cancelar (X)
                Button(action: {
                    AppState.shared.hapticService.triggerSnap()
                    provider.cancelTimer()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isPressedCancel ? 0.22 : 0.12))
                            .frame(width: 36, height: 36)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: MotionTokens.physicalPixel)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.90))
                    }
                    .scaleEffect(isPressedCancel ? MotionTokens.pressScale : 1.0)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressedCancel = true }
                        .onEnded { _ in isPressedCancel = false }
                )
                .help("Cancelar temporizador")
                
                // MARK: - Centro: Título ("Minutka") y Tiempo Gigante (0:08)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(provider.isFinished ? "¡Tiempo Cumplido!" : provider.timerTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                        
                        if !provider.isFinished && !provider.isRunning {
                            Text("• En pausa")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignTokens.orange.opacity(0.85))
                        }
                        
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    
                    Text(provider.formattedDuration)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundColor(provider.isFinished ? DesignTokens.green : DesignTokens.orange)
                        .animation(MotionTokens.timerTickSpring, value: provider.formattedDuration)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    provider.collapseToPill()
                }
                .help("Haga clic para minimizar a píldora compacta")
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // MARK: - Control Derecho: Botón Circular Pausar / Reanudar (|| / ▶)
                if !provider.isFinished {
                    Button(action: {
                        AppState.shared.hapticService.triggerSnap()
                        provider.togglePauseResume()
                    }) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.orange.opacity(isPressedToggle ? 0.32 : 0.18))
                                .frame(width: 36, height: 36)
                            
                            Circle()
                                .stroke(DesignTokens.orange.opacity(0.45), lineWidth: MotionTokens.physicalPixel)
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: provider.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(DesignTokens.orange)
                                .offset(x: provider.isRunning ? 0 : MotionTokens.playIconOpticalOffsetX)
                        }
                        .scaleEffect(isPressedToggle ? MotionTokens.pressScale : 1.0)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isPressedToggle = true }
                            .onEnded { _ in isPressedToggle = false }
                    )
                    .help(provider.isRunning ? "Pausar" : "Reanudar")
                } else {
                    // Botón de aceptar al finalizar
                    Button(action: {
                        AppState.shared.hapticService.triggerSnap()
                        provider.cancelTimer()
                    }) {
                        Text("Aceptar")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DesignTokens.green))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // MARK: - Barra de Progreso Inferior Fina (Consumo de Tiempo)
            GeometryReader { barProxy in
                let w = barProxy.size.width
                let ratio = CGFloat(provider.progressRatio)
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3.5)
                    
                    Capsule()
                        .fill(provider.isFinished ? DesignTokens.green : DesignTokens.orange)
                        .frame(width: max(3.5, w * (1.0 - ratio)), height: 3.5)
                        .animation(.linear(duration: 0.15), value: ratio)
                }
            }
            .frame(height: 3.5)
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 36) // Despeja holgadamente la cámara física del notch
        .padding(.bottom, 12)
        .frame(width: 390, height: 112)
        .scaleEffect(isDismissing ? 0.94 : (isRevealed ? 1.0 : 0.95), anchor: .top)
        .opacity(isDismissing ? 0.0 : (isRevealed ? 1.0 : 0.0))
        .animation(MotionTokens.adaptiveSpring(response: 0.44, dampingFraction: 0.86), value: isDismissing)
        .animation(MotionTokens.adaptiveSpring(response: 0.44, dampingFraction: 0.86), value: isRevealed)
        .onAppear {
            withAnimation(MotionTokens.adaptiveSpring(response: 0.42, dampingFraction: 0.84)) {
                isRevealed = true
            }
        }
    }
}
