import SwiftUI
import Combine

public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()
    
    @Published public private(set) var currentActivity: LiveActivity?
    @Published public private(set) var activeActivities: [LiveActivity] = []
    
    private var dismissTimers: [String: Timer] = [:]
    
    private init() {}
    
    /// Publica o actualiza una actividad según las reglas de prioridad y actualización en sitio
    public func publish(_ activity: LiveActivity) {
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
    
    /// Quita una actividad por su ID
    public func remove(id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        
        activeActivities.removeAll(where: { $0.id == id })
        evaluateHighestPriority()
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
            withAnimation(DesignTokens.activityEntrySpring) {
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
                    self?.remove(id: activity.id)
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
