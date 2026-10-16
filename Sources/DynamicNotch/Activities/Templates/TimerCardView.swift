import SwiftUI
import AppKit

// MARK: - TimerCardView (Panel Expandido del Temporizador y Cronómetro - iOS Dynamic Island)
public struct TimerCardView: View {
    @ObservedObject var provider = TimerActivityProvider.shared
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var isRevealed: Bool = false
    @State private var isPressedCancel: Bool = false
    @State private var isPressedToggle: Bool = false
    @State private var isPressedLap: Bool = false
    
    public init() {}
    
    private var isDismissing: Bool {
        center.dismissingActivityId == "live_timer"
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Fila Principal: Botón Cancelar (X) • Título y Cronómetro Gigante • Vuelta / Pausar / Reanudar
            HStack(alignment: .center, spacing: 12) {
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
                .help("Cancelar \(provider.mode.title.lowercased())")
                
                // MARK: - Centro: Título y Tiempo Gigante
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: provider.mode.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DesignTokens.orange)
                        
                        Text(provider.isFinished ? "¡Tiempo Cumplido!" : provider.timerTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                        
                        if !provider.isFinished && !provider.isRunning {
                            Text("• En pausa")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignTokens.orange.opacity(0.85))
                        } else if provider.mode == .stopwatch, let lastLap = provider.stopwatchLaps.first {
                            Text("• V\(lastLap.index) \(lastLap.formattedSplit)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.50))
                        }
                        
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    
                    Text(provider.formattedDuration)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
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
                
                // MARK: - Botón de Vuelta (Lap) en modo Cronómetro
                if provider.mode == .stopwatch && provider.hasActiveSession {
                    Button(action: {
                        provider.recordLap()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(isPressedLap ? 0.24 : 0.12))
                                .frame(width: 34, height: 34)
                            
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: MotionTokens.physicalPixel)
                                .frame(width: 34, height: 34)
                            
                            Image(systemName: "flag.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.88))
                        }
                        .scaleEffect(isPressedLap ? MotionTokens.pressScale : 1.0)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isPressedLap = true }
                            .onEnded { _ in isPressedLap = false }
                    )
                    .help("Registrar vuelta")
                }
                
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
                let fillFraction = provider.mode == .countdown ? (1.0 - ratio) : ratio
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3.5)
                    
                    Capsule()
                        .fill(provider.isFinished ? DesignTokens.green : DesignTokens.orange)
                        .frame(width: max(3.5, w * fillFraction), height: 3.5)
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

// MARK: - TimerMiniAppOverlayView (Overlay Integrado en el Notch para Cronómetro y Temporizador)

public struct TimerMiniAppOverlayView: View {
    @ObservedObject var provider = TimerActivityProvider.shared
    @EnvironmentObject var appState: AppState
    public var onClose: () -> Void
    
    private let presets: [(label: String, seconds: TimeInterval, title: String)] = [
        ("1m", 60, "Temporizador 1m"),
        ("5m", 300, "Temporizador 5m"),
        ("10m", 600, "Temporizador 10m"),
        ("15m", 900, "Temporizador 15m"),
        ("25m 🍅", 1500, "Pomodoro 25m")
    ]
    
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Cabecera con selector de modo (Temporizador / Cronómetro) y botón cerrar
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(TimerMode.allCases) { item in
                        let isSelected = provider.mode == item
                        Button(action: {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                provider.mode = item
                            }
                            appState.hapticService.triggerSnap()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? DesignTokens.orange : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                if provider.hasActiveSession {
                    Button(action: {
                        appState.activeMiniAppOverlay = nil
                        appState.collapse()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("Isla")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(DesignTokens.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(DesignTokens.orange.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("Minimizar a Live Activity en el Dynamic Island")
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            
            // Cuerpo central: Display grande + Controles principales
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.hasActiveSession ? provider.formattedDuration : (provider.mode == .countdown ? "05:00" : "00:00.0"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(provider.isFinished ? DesignTokens.green : DesignTokens.orange)
                        .contentTransition(.numericText())
                    
                    Text(statusSubtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Botones de acción según modo
                HStack(spacing: 8) {
                    if provider.mode == .stopwatch {
                        if provider.hasActiveSession {
                            Button(action: {
                                provider.recordLap()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Vuelta")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                provider.resetStopwatch()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help("Reiniciar cronómetro")
                        }
                        
                        Button(action: {
                            if provider.hasActiveSession {
                                provider.togglePauseResume()
                            } else {
                                provider.startStopwatch(asCard: false)
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: provider.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(provider.isRunning ? "Pausar" : (provider.hasActiveSession ? "Reanudar" : "Iniciar"))
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DesignTokens.orange))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Modo Temporizador
                        if provider.hasActiveSession {
                            Button(action: {
                                provider.cancelTimer()
                            }) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help("Cancelar temporizador")
                        }
                        
                        Button(action: {
                            if provider.hasActiveSession {
                                provider.togglePauseResume()
                            } else {
                                provider.startTimer(duration: 300, title: "Temporizador 5m", asCard: false)
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: provider.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(provider.isRunning ? "Pausar" : (provider.hasActiveSession ? "Reanudar" : "Iniciar 5m"))
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DesignTokens.orange))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            
            // Fila inferior: Presets rápidos (Temporizador) o Lista de Vueltas (Cronómetro)
            if provider.mode == .countdown {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.label) { preset in
                        Button(action: {
                            provider.startTimer(duration: preset.seconds, title: preset.title, asCard: false)
                        }) {
                            Text(preset.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.90))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Historial compacto de vueltas
                if provider.stopwatchLaps.isEmpty {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.40))
                        Text("Pulsa «Vuelta» mientras corre para registrar parciales")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(provider.stopwatchLaps.prefix(6)) { lap in
                                HStack(spacing: 4) {
                                    Text("V\(lap.index)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(DesignTokens.orange)
                                    Text(lap.formattedSplit)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.90))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.09))
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var statusSubtitle: String {
        if provider.isFinished {
            return "¡Tiempo cumplido!"
        }
        if provider.isRunning {
            return provider.mode == .countdown ? "Cuenta atrás activa en Dynamic Island" : "Cronómetro en marcha"
        }
        if provider.hasActiveSession {
            return "En pausa"
        }
        return provider.mode == .countdown ? "Elige un preset rápido para empezar" : "Listo para medir tiempos y vueltas"
    }
}

// MARK: - AudioMonitorMiniAppOverlayView (Monitor FFT de 10 Bandas Integrado en el Notch)

public struct AudioMonitorMiniAppOverlayView: View {
    @ObservedObject var engine = AudioSpectrumEngine.shared
    @EnvironmentObject var appState: AppState
    public var onClose: () -> Void
    
    @State private var peakHolds: [Float] = Array(repeating: 0.05, count: 10)
    @State private var peakDecibel: Float = -60.0
    
    private let freqLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    private func expandToTenBands(_ sixBands: [Float]) -> [Float] {
        guard sixBands.count >= 6 else { return Array(repeating: 0.05, count: 10) }
        return [
            sixBands[0],
            (sixBands[0] + sixBands[1]) * 0.5,
            sixBands[1],
            (sixBands[1] + sixBands[2]) * 0.5,
            sixBands[2],
            (sixBands[2] + sixBands[3]) * 0.5,
            sixBands[3],
            (sixBands[3] + sixBands[4]) * 0.5,
            sixBands[4],
            sixBands[5]
        ]
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            // Cabecera
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isRunning ? (engine.isSilent ? Color.orange : Color.green) : Color.red)
                    .frame(width: 7, height: 7)
                
                Text("Monitor FFT en Tiempo Real")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(String(format: "%.1f dBFS", peakDecibel))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan.opacity(0.14)))
                
                Spacer()
                
                // Selector rápido de presets
                HStack(spacing: 3) {
                    ForEach(SpectrumResponsePreset.allCases) { preset in
                        Button(action: {
                            SpectrumMetrics.applyPreset(preset)
                            appState.hapticService.triggerSnap()
                        }) {
                            Text(preset.shortTitle)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            
            // Barras de Espectro 10 Bandas con Peak Hold
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let levels = expandToTenBands(engine.getMagnitudes())
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<10, id: \.self) { i in
                        let lv = CGFloat(levels.indices.contains(i) ? levels[i] : 0.05)
                        let pk = CGFloat(peakHolds.indices.contains(i) ? peakHolds[i] : 0.05)
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                let h = geo.size.height
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.white.opacity(0.07))
                                    
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.green, .cyan, .pink],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .frame(height: max(4, h * lv))
                                    
                                    Capsule()
                                        .fill(Color.white.opacity(0.90))
                                        .frame(height: 2)
                                        .offset(y: -min(h - 3, max(4, h * pk)))
                                }
                            }
                            
                            Text(freqLabels[i])
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }
                .frame(height: 88)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .onChange(of: timeline.date) { _, _ in
                    peakDecibel = engine.getPeakDecibels()
                    var updated = peakHolds
                    for i in 0..<min(10, levels.count) {
                        if levels[i] >= updated[i] {
                            updated[i] = levels[i]
                        } else {
                            updated[i] = max(0.05, updated[i] - 0.012)
                        }
                    }
                    peakHolds = updated
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

