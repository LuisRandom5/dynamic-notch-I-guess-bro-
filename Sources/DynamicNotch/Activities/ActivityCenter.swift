import SwiftUI
import Combine

public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()
    
    @Published public private(set) var currentActivity: LiveActivity?
    @Published public private(set) var activeActivities: [LiveActivity] = []
    @Published public private(set) var dismissingActivityId: String? = nil
    @Published public private(set) var lastDismissedActivity: LiveActivity? = nil
    
    @Published public var customCardWidth: CGFloat? = nil
    @Published public var customCardHeight: CGFloat? = nil
    @Published public var customTopRadius: CGFloat? = nil
    @Published public var customBottomRadius: CGFloat? = nil
    
    private var dismissTimers: [String: Timer] = [:]
    
    private init() {}
    
    /// Publica o actualiza una actividad según las reglas de prioridad y actualización en sitio
    public func publish(_ activity: LiveActivity) {
        // Cancelar retención de notch puro si llega una nueva actividad
        AppState.shared.isHoldingBareNotch = false
        
        // Si se estaba cerrando este mismo ID, cancelar su cierre
        if dismissingActivityId == activity.id {
            dismissingActivityId = nil
        }
        
        // Regla 1: Si ya existe con el mismo ID, actualizar en sitio sin reiniciar entrada
        if let index = activeActivities.firstIndex(where: { $0.id == activity.id }) {
            activeActivities[index] = activity
            if currentActivity?.id == activity.id {
                currentActivity = activity
            }
            rescheduleTimer(for: activity)
            evaluateHighestPriority()
            return
        }
        
        // Agregar a la cola
        activeActivities.append(activity)
        rescheduleTimer(for: activity)
        evaluateHighestPriority()
    }
    
    /// Alias para compatibilidad
    public func show(_ activity: LiveActivity) {
        publish(activity)
    }
    
    /// Quita una actividad por su ID de forma inmediata
    public func remove(id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        if dismissingActivityId == id {
            dismissingActivityId = nil
        }
        
        activeActivities.removeAll(where: { $0.id == id })
        if currentActivity?.id == id {
            customCardWidth = nil
            customCardHeight = nil
            customTopRadius = nil
            customBottomRadius = nil
        }
        evaluateHighestPriority()
    }
    
    /// Pausa o cancela el temporizador de cierre automático (por ejemplo al abrir Quick Reply para escribir)
    public func pauseDismissTimer(for id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
    }
    
    /// Cierre sutil, orgánico y extremadamente fluido estilo Apple macOS:
    /// Inicia la contracción inmediata y sincronizada de la anchura y altura hacia el notch (~300 ms)
    /// mientras los elementos internos se desvanecen de manera progresiva y coordinada hacia el centro.
    public func dismissWithAnimation(id: String) {
        guard let current = currentActivity, current.id == id else {
            remove(id: id)
            return
        }
        
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        dismissingActivityId = id
        lastDismissedActivity = current
        
        let isCard = current.style == .card
        let duration = isCard ? ExitAnimationMetrics.cardDismissDuration : ExitAnimationMetrics.sliderDismissDuration
        
        // Si es una Card y estamos en modo compact con música activa, activamos isHoldingBareNotch
        // desde el inicio. Así el notch no sufre ningún espasmo ni apertura a los lados en negro.
        if isCard && AppState.shared.mode == .compact && MusicService.shared.hasActiveMusic {
            AppState.shared.isHoldingBareNotch = true
        }
        
        // El contenedor y el contenido inician su contracción simultánea hacia el notch.
        // Al completarse la duración precisa (280–300 ms), el contenedor ya está exactamente
        // integrado en la geometría del notch, garantizando continuidad visual perfecta.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.activeActivities.removeAll(where: { $0.id == id })
            self.customCardWidth = nil
            self.customCardHeight = nil
            self.customTopRadius = nil
            self.customBottomRadius = nil
            self.evaluateHighestPriority()
            self.dismissingActivityId = nil
            
            if isCard && AppState.shared.mode == .compact && MusicService.shared.hasActiveMusic {
                // Permanecer como notch puro durante 1.0 segundo exacto, luego expandir las alas del reproductor
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard self.currentActivity == nil else {
                        AppState.shared.isHoldingBareNotch = false
                        return
                    }
                    withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                        AppState.shared.isHoldingBareNotch = false
                    }
                }
            } else {
                AppState.shared.isHoldingBareNotch = false
                if self.currentActivity == nil {
                    if AppState.shared.shouldShowCompact && AppState.shared.mode == .idle {
                        withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                            AppState.shared.mode = .compact
                        }
                    }
                }
            }
        }
    }
    
    /// Evalúa la actividad de mayor prioridad y aplica crossfade si cambia
    private func evaluateHighestPriority() {
        // Ordenar por prioridad descendente; si hay empate, la más reciente primero
        let sorted = activeActivities.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.createdAt > $1.createdAt
        }
        
        let highest = sorted.first
        
        if currentActivity?.id != highest?.id {
            withAnimation(.spring(
                response: ExitAnimationMetrics.sliderDismissResponse,
                dampingFraction: ExitAnimationMetrics.sliderDismissDamping
            )) {
                self.currentActivity = highest
            }
        }
    }
    
    private func rescheduleTimer(for activity: LiveActivity) {
        dismissTimers[activity.id]?.invalidate()
        dismissTimers.removeValue(forKey: activity.id)
        
        if let duration = activity.duration, duration > 0 {
            let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.dismissWithAnimation(id: activity.id)
                }
            }
            dismissTimers[activity.id] = timer
        }
    }
    
    /// Maneja el click sobre la actividad: onTap si existe, o abre el widget completo
    public func handleTap() {
        guard let activity = currentActivity else { return }
        if let onTap = activity.onTap {
            onTap()
        } else {
            AppState.shared.expand()
        }
    }
}
