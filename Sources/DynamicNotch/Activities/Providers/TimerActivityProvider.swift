import SwiftUI
import Combine

/// Proveedor de Live Activity para Temporizador estilo Dynamic Island de iOS (Capturas 2 y 3).
/// - Estado Compacto: Anillo circular naranja con icono de temporizador a la izquierda y tiempo a la derecha.
/// - Estado Expandido ("Minutka"): Cronómetro gigante en naranja, controles de pausa/reanudar y botón de cancelar.
/// - Basado en marcas de tiempo reales (`Date()`) sin desincronizaciones por throttling.
public final class TimerActivityProvider: ObservableObject {
    public static let shared = TimerActivityProvider()
    
    @Published public private(set) var totalDuration: TimeInterval = 0
    @Published public private(set) var remainingTime: TimeInterval = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isFinished: Bool = false
    @Published public private(set) var isExpandedCard: Bool = false
    @Published public private(set) var timerTitle: String = "Minutka"
    
    private var internalTimer: Timer?
    private var targetEndDate: Date = Date()
    private var pausedRemainingTime: TimeInterval = 0
    private let activityId = "live_timer"
    
    private init() {}
    
    public var progressRatio: Double {
        guard totalDuration > 0 else { return 0.0 }
        return max(0.0, min(1.0, remainingTime / totalDuration))
    }
    
    public var formattedDuration: String {
        let totalSecs = Int(ceil(remainingTime))
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    /// Inicia un nuevo temporizador
    public func startTimer(duration: TimeInterval = 30.0, title: String = "Minutka", asCard: Bool = false) {
        internalTimer?.invalidate()
        internalTimer = nil
        
        self.totalDuration = max(duration, 1.0)
        self.remainingTime = max(duration, 1.0)
        self.pausedRemainingTime = self.remainingTime
        self.isRunning = true
        self.isFinished = false
        self.isExpandedCard = asCard
        self.timerTitle = title
        self.targetEndDate = Date().addingTimeInterval(remainingTime)
        
        publishCurrentState()
        
        // Timer de alta frecuencia (10 Hz) para actualizar la barra y los segundos sin parpadeos
        internalTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            let remaining = self.targetEndDate.timeIntervalSinceNow
            
            if remaining > 0.1 {
                self.remainingTime = remaining
                self.publishCurrentState()
            } else {
                self.remainingTime = 0
                self.isRunning = false
                self.isFinished = true
                self.internalTimer?.invalidate()
                self.internalTimer = nil
                self.publishTimerEnded()
            }
        }
        
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Alterna entre Pausar y Reanudar la cuenta atrás
    public func togglePauseResume() {
        if isRunning {
            // Pausar
            pausedRemainingTime = max(0, targetEndDate.timeIntervalSinceNow)
            remainingTime = pausedRemainingTime
            isRunning = false
            internalTimer?.invalidate()
            internalTimer = nil
            publishCurrentState()
            AppState.shared.hapticService.triggerSnap()
        } else if remainingTime > 0.1 {
            // Reanudar
            targetEndDate = Date().addingTimeInterval(remainingTime)
            isRunning = true
            isFinished = false
            publishCurrentState()
            
            internalTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                let remaining = self.targetEndDate.timeIntervalSinceNow
                
                if remaining > 0.1 {
                    self.remainingTime = remaining
                    self.publishCurrentState()
                } else {
                    self.remainingTime = 0
                    self.isRunning = false
                    self.isFinished = true
                    self.internalTimer?.invalidate()
                    self.internalTimer = nil
                    self.publishTimerEnded()
                }
            }
            AppState.shared.hapticService.triggerSnap()
        }
    }
    
    /// Expande la píldora a tarjeta completa interactiva ("Minutka")
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
    
    /// Cancela y cierra el temporizador por completo
    public func cancelTimer() {
        internalTimer?.invalidate()
        internalTimer = nil
        isRunning = false
        remainingTime = 0
        isFinished = false
        isExpandedCard = false
        ActivityCenter.shared.remove(id: activityId)
    }
    
    /// Publica el estado visual actualizado (píldora o tarjeta grande)
    private func publishCurrentState() {
        let durationStr = formattedDuration
        let ratio = progressRatio
        
        if isExpandedCard {
            // MARK: - Modo Expandido: Card interactiva completa
            let centerView = AnyView(
                TimerCardView()
            )
            
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
            // MARK: - Modo Compacto: Anillo circular naranja + contador monoespaciado
            let leading = AnyView(
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                            .frame(width: 17, height: 17)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(ratio))
                            .stroke(
                                DesignTokens.orange,
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 17, height: 17)
                        
                        Image(systemName: "timer")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(DesignTokens.orange)
                    }
                }
                .padding(.leading, 6)
            )
            
            let trailing = AnyView(
                Text(durationStr)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundColor(DesignTokens.orange)
                    .padding(.trailing, 6)
            )
            
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
