import SwiftUI
import Combine
import AppKit

// Ciclo de vida: alertas, límite de 8 h, obsoleto y cierre con resumen
extension ActivityCenter {
    // MARK: - Ciclo de vida: alertas, 8 h, obsoleto y cierre con resumen
    
    /// Alerta de una actualización (ActivityAlertConfiguration): se espera un instante para que la bolita o el
    /// notch se asienten y se aplica la política (no si el usuario está usando el notch, no más de una cada 30 s)
    func scheduleAlert(id: String, configuration: ActivityAlertConfiguration, isUrgent: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, let activity = self.activeActivities.first(where: { $0.id == id }) else { return }
            // Si su app ya está a la vista (p. ej. la ventana de Claude en el otro monitor), la alerta sobra
            if !isUrgent && ActivitySourceApp.isVisible(for: activity) {
                DNDLogger.log("ActivityCenter: alerta de '\(id)' omitida, su app está a la vista")
                return
            }
            let app = AppState.shared
            let userIsBusy = self.expandedActivity != nil || self.isFusing || app.isHovered
                || app.mode == .expanded || app.mode == .shelf
            guard ActivityLifecycle.shouldAlert(enabled: app.liveActivityAlertsEnabled, isUrgent: isUrgent,
                                                userIsBusy: userIsBusy, lastAlertAt: self.lastAlertAt[id], now: Date()) else { return }
            self.lastAlertAt[id] = Date()
            if configuration.sound && app.liveActivityAlertSound {
                NSSound(named: "Tink")?.play()
            }
            self.presentAlert(id: id, duration: configuration.duration)
        }
    }
    
    /// Termina una actividad como la Isla Dinámica: muestra su estado final (resumen) un momento y se va.
    /// - final: el último contenido (se publica como terminado); nil = el que ya tiene
    /// - dismissAfter: cuánto se queda el resumen (nil = ajuste "Resumen al terminar")
    /// - onRemove: limpieza del proveedor al irse; si no hay, se quita de la isla
    public func end(id: String, final: LiveActivity? = nil, dismissAfter: TimeInterval? = nil, onRemove: (() -> Void)? = nil) {
        if var final {
            final.state = .finished
            publish(final)
        }
        endTimers[id]?.invalidate()
        let delay = dismissAfter ?? AppState.shared.liveActivityEndSummaryDuration
        let finish: () -> Void = { [weak self] in
            guard let self = self else { return }
            // Si el usuario tiene su tarjeta abierta, espera a que la cierre
            if self.expandedActivity?.id == id && self.alertingActivityId != id {
                self.end(id: id, dismissAfter: 5, onRemove: onRemove)
                return
            }
            self.endTimers[id] = nil
            if let onRemove {
                onRemove()
            } else if self.currentActivity?.id == id {
                self.dismissWithAnimation(id: id)
            } else {
                self.remove(id: id)
            }
        }
        guard delay > 0 else { finish(); return }
        let timer = Timer(timeInterval: delay, repeats: false) { _ in finish() }
        RunLoop.main.add(timer, forMode: .common)
        endTimers[id] = timer
    }
    
    func startLifecycleTimerIfNeeded() {
        guard lifecycleTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.sweepLifecycle() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        lifecycleTimer = timer
    }
    
    /// Cada 30 s: termina lo que pasó de 8 h (la repisa no es una actividad con fin) y marca lo obsoleto
    func sweepLifecycle() {
        let now = Date()
        let expired = activeActivities.filter {
            $0.id != ShelfActivityProvider.activityId && ActivityLifecycle.isExpired(createdAt: $0.createdAt, now: now)
        }
        for activity in expired {
            DNDLogger.log("ActivityCenter: '\(activity.id)' llegó a 8 h; se termina")
            activity.onDismiss?()
            end(id: activity.id, dismissAfter: 0)
        }
        refreshStaleActivities()
        if activeActivities.isEmpty {
            lifecycleTimer?.invalidate()
            lifecycleTimer = nil
        }
    }
    
    /// Marca lo obsoleto y programa la revisión justo para la próxima `staleDate` (no espera al barrido)
    func refreshStaleActivities() {
        let now = Date()
        let stale = Set(activeActivities.filter { ActivityLifecycle.isStale(staleDate: $0.staleDate, now: now) }.map(\.id))
        if stale != staleActivityIds { staleActivityIds = stale }
        staleTimer?.invalidate()
        staleTimer = nil
        if let next = activeActivities.compactMap(\.staleDate).filter({ $0 > now }).min() {
            let timer = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
                self?.refreshStaleActivities()
            }
            RunLoop.main.add(timer, forMode: .common)
            staleTimer = timer
        }
    }
}
