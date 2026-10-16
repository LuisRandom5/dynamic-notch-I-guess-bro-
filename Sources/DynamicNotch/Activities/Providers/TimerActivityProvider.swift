import SwiftUI
import Combine
import AppKit

public enum TimerMode: String, CaseIterable, Identifiable {
    case countdown = "countdown"
    case stopwatch = "stopwatch"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .countdown: return "Temporizador"
        case .stopwatch: return "Cronómetro"
        }
    }
    
    public var icon: String {
        switch self {
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch.fill"
        }
    }
}

public struct StopwatchLap: Identifiable, Equatable {
    public let id = UUID()
    public let index: Int
    public let splitTime: TimeInterval
    public let totalTime: TimeInterval
    
    public var formattedSplit: String {
        TimerActivityProvider.formatStopwatchTime(splitTime)
    }
    
    public var formattedTotal: String {
        TimerActivityProvider.formatStopwatchTime(totalTime)
    }
}

/// Proveedor de Live Activity para Temporizador y Cronómetro estilo Dynamic Island de iOS.
/// - Estado Compacto: Anillo circular naranja con icono a la izquierda y tiempo monoespaciado a la derecha.
/// - Estado Expandido: Cronómetro/Temporizador gigante en naranja, controles de pausa/reanudar, vueltas y cancelar.
/// - Basado en marcas de tiempo reales (`Date()`) sin desincronizaciones por throttling.
public final class TimerActivityProvider: ObservableObject {
    public static let shared = TimerActivityProvider()
    
    @Published public var mode: TimerMode = .countdown
    @Published public private(set) var totalDuration: TimeInterval = 300
    @Published public private(set) var remainingTime: TimeInterval = 0
    @Published public private(set) var stopwatchElapsed: TimeInterval = 0
    @Published public private(set) var stopwatchLaps: [StopwatchLap] = []
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isFinished: Bool = false
    @Published public private(set) var isExpandedCard: Bool = false
    @Published public private(set) var timerTitle: String = "Temporizador"
    
    private var internalTimer: Timer?
    private var targetEndDate: Date = Date()
    private var pausedRemainingTime: TimeInterval = 0
    
    private var stopwatchStartDate: Date = Date()
    private var accumulatedStopwatchTime: TimeInterval = 0
    
    private let activityId = "live_timer"
    
    private init() {}
    
    /// Indica si hay una sesión activa (corriendo o en pausa con progreso)
    public var hasActiveSession: Bool {
        switch mode {
        case .countdown:
            return isRunning || remainingTime > 0 || isFinished
        case .stopwatch:
            return isRunning || stopwatchElapsed > 0
        }
    }
    
    public var progressRatio: Double {
        switch mode {
        case .countdown:
            guard totalDuration > 0 else { return 0.0 }
            return max(0.0, min(1.0, remainingTime / totalDuration))
        case .stopwatch:
            let cycle = stopwatchElapsed.truncatingRemainder(dividingBy: 60.0)
            return max(0.0, min(1.0, cycle / 60.0))
        }
    }
    
    public var formattedDuration: String {
        switch mode {
        case .countdown:
            let totalSecs = Int(ceil(remainingTime))
            let hrs = totalSecs / 3600
            let mins = (totalSecs % 3600) / 60
            let secs = totalSecs % 60
            if hrs > 0 {
                return String(format: "%d:%02d:%02d", hrs, mins, secs)
            }
            return String(format: "%02d:%02d", mins, secs)
        case .stopwatch:
            return Self.formatStopwatchTime(stopwatchElapsed)
        }
    }
    
    public var compactFormattedDuration: String {
        switch mode {
        case .countdown:
            return formattedDuration
        case .stopwatch:
            let totalSecs = Int(stopwatchElapsed)
            let mins = totalSecs / 60
            let secs = totalSecs % 60
            return String(format: "%02d:%02d", mins, secs)
        }
    }
    
    public static func formatStopwatchTime(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let totalSecs = Int(clamped)
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        let tenths = Int((clamped - Double(totalSecs)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }
    
    // MARK: - Temporizador (Cuenta Regresiva)
    
    /// Inicia un nuevo temporizador de cuenta regresiva
    public func startTimer(duration: TimeInterval = 30.0, title: String = "Temporizador", asCard: Bool = false) {
        internalTimer?.invalidate()
        internalTimer = nil
        
        self.mode = .countdown
        self.totalDuration = max(duration, 1.0)
        self.remainingTime = max(duration, 1.0)
        self.pausedRemainingTime = self.remainingTime
        self.isRunning = true
        self.isFinished = false
        self.isExpandedCard = asCard
        self.timerTitle = title
        self.targetEndDate = Date().addingTimeInterval(remainingTime)
        
        publishCurrentState()
        startInternalLoop()
        
        AppState.shared.hapticService.triggerSnap()
    }
    
    // MARK: - Cronómetro (Stopwatch con Vueltas)
    
    /// Inicia o reanuda el cronómetro
    public func startStopwatch(asCard: Bool = false) {
        internalTimer?.invalidate()
        internalTimer = nil
        
        if mode != .stopwatch {
            mode = .stopwatch
            stopwatchElapsed = 0
            accumulatedStopwatchTime = 0
            stopwatchLaps.removeAll()
        }
        
        self.timerTitle = "Cronómetro"
        self.isFinished = false
        self.isRunning = true
        self.isExpandedCard = asCard
        self.stopwatchStartDate = Date()
        
        publishCurrentState()
        startInternalLoop()
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Registra una vuelta (Lap) en el cronómetro
    public func recordLap() {
        guard mode == .stopwatch, stopwatchElapsed > 0 else { return }
        let previousTotal = stopwatchLaps.first?.totalTime ?? 0
        let split = max(0, stopwatchElapsed - previousTotal)
        let lap = StopwatchLap(
            index: stopwatchLaps.count + 1,
            splitTime: split,
            totalTime: stopwatchElapsed
        )
        stopwatchLaps.insert(lap, at: 0)
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Reinicia el cronómetro a cero
    public func resetStopwatch() {
        internalTimer?.invalidate()
        internalTimer = nil
        isRunning = false
        stopwatchElapsed = 0
        accumulatedStopwatchTime = 0
        stopwatchLaps.removeAll()
        ActivityCenter.shared.remove(id: activityId)
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Alterna entre Pausar y Reanudar (tanto Temporizador como Cronómetro)
    public func togglePauseResume() {
        switch mode {
        case .countdown:
            if isRunning {
                pausedRemainingTime = max(0, targetEndDate.timeIntervalSinceNow)
                remainingTime = pausedRemainingTime
                isRunning = false
                internalTimer?.invalidate()
                internalTimer = nil
                AppState.shared.hapticService.triggerSnap()
            } else if remainingTime > 0.1 {
                targetEndDate = Date().addingTimeInterval(remainingTime)
                isRunning = true
                isFinished = false
                publishCurrentState()
                startInternalLoop()
                AppState.shared.hapticService.triggerSnap()
            }
        case .stopwatch:
            if isRunning {
                accumulatedStopwatchTime += Date().timeIntervalSince(stopwatchStartDate)
                stopwatchElapsed = accumulatedStopwatchTime
                isRunning = false
                internalTimer?.invalidate()
                internalTimer = nil
                AppState.shared.hapticService.triggerSnap()
            } else {
                stopwatchStartDate = Date()
                isRunning = true
                isFinished = false
                publishCurrentState()
                startInternalLoop()
                AppState.shared.hapticService.triggerSnap()
            }
        }
    }
    
    private func startInternalLoop() {
        internalTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            switch self.mode {
            case .countdown:
                let remaining = self.targetEndDate.timeIntervalSinceNow
                if remaining > 0.1 {
                    self.remainingTime = remaining
                } else {
                    self.remainingTime = 0
                    self.isRunning = false
                    self.isFinished = true
                    self.internalTimer?.invalidate()
                    self.internalTimer = nil
                    self.publishTimerEnded()
                }
            case .stopwatch:
                self.stopwatchElapsed = self.accumulatedStopwatchTime + Date().timeIntervalSince(self.stopwatchStartDate)
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        internalTimer = timer
    }
    
    /// Expande la píldora a tarjeta completa interactiva
    public func expandToCard() {
        withAnimation(MotionTokens.expandSpring) {
            isExpandedCard = true
            publishCurrentState()
        }
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Contrae la tarjeta a la píldora compacta
    public func collapseToPill() {
        withAnimation(MotionTokens.collapseSpring) {
            isExpandedCard = false
            publishCurrentState()
        }
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Cancela y cierra el temporizador/cronómetro por completo
    public func cancelTimer() {
        internalTimer?.invalidate()
        internalTimer = nil
        isRunning = false
        remainingTime = 0
        stopwatchElapsed = 0
        accumulatedStopwatchTime = 0
        stopwatchLaps.removeAll()
        isFinished = false
        isExpandedCard = false
        ActivityCenter.shared.remove(id: activityId)
    }
    
    /// Publica el estado visual actualizado (píldora o tarjeta grande)
    private func publishCurrentState() {
        if isExpandedCard {
            let centerView = AnyView(TimerCardView())
            let activity = LiveActivity(
                id: activityId,
                priority: 88,
                style: .card,
                leading: nil,
                center: centerView,
                trailing: nil,
                tint: .orange,
                duration: nil,
                onTap: nil
            )
            ActivityCenter.shared.publish(activity)
        } else {
            let leading = AnyView(TimerPillLeadingView())
            let trailing = AnyView(TimerPillTrailingView())
            let activity = LiveActivity(
                id: activityId,
                priority: 88,
                style: .pill,
                leading: leading,
                center: nil,
                trailing: trailing,
                tint: .orange,
                duration: nil,
                onTap: { [weak self] in
                    self?.expandToCard()
                }
            )
            ActivityCenter.shared.publish(activity)
        }
    }
    
    /// Notificación de finalización de temporizador
    private func publishTimerEnded() {
        AppState.shared.hapticService.triggerExpand()
        NSSound(named: "Glass")?.play()
        
        if isExpandedCard {
            publishCurrentState()
        } else {
            let leading = AnyView(
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignTokens.green)
                    .padding(.leading, 6)
            )
            let trailing = AnyView(
                Text("¡Tiempo!")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.trailing, 6)
            )
            
            let activity = LiveActivity(
                id: activityId,
                priority: 95,
                style: .pill,
                leading: leading,
                trailing: trailing,
                tint: .green,
                duration: 6.0,
                onTap: { [weak self] in
                    self?.cancelTimer()
                }
            )
            ActivityCenter.shared.publish(activity)
        }
    }
}

// MARK: - Subvistas Reactivas de Píldora Compacta (Cero recreación de AnyView en cada tick)

private struct TimerPillLeadingView: View {
    @ObservedObject var provider = TimerActivityProvider.shared
    
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                    .frame(width: 17, height: 17)
                
                Circle()
                    .trim(from: 0, to: CGFloat(provider.progressRatio))
                    .stroke(
                        DesignTokens.orange,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 17, height: 17)
                
                Image(systemName: provider.mode.icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(DesignTokens.orange)
            }
        }
        .padding(.leading, 6)
    }
}

private struct TimerPillTrailingView: View {
    @ObservedObject var provider = TimerActivityProvider.shared
    
    var body: some View {
        Text(provider.compactFormattedDuration)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundColor(DesignTokens.orange)
            .padding(.trailing, 6)
    }
}

