import Foundation

/// Configuración de alerta de una actualización, como `AlertConfiguration` de ActivityKit: una actualización
/// esencial (terminó, necesita respuesta) expande la actividad un momento y regresa sola.
public struct ActivityAlertConfiguration: Equatable {
    /// Suena además de expandirse (por defecto en silencio: el propio proveedor ya suena si hace falta)
    public var sound: Bool
    /// Cuánto se queda expandida (nil = el ajuste "Duración de las alertas")
    public var duration: TimeInterval?

    public init(sound: Bool = false, duration: TimeInterval? = nil) {
        self.sound = sound
        self.duration = duration
    }
}

/// Reglas de ciclo de vida de las actividades, sin estado global (ver PLAN_ISLA_DINAMICA.md §1.1):
/// - Una actividad dura como máximo 8 h; después se termina sola.
/// - Pasada su `staleDate` está "obsoleta" (sin actualizar): se sigue viendo, pero atenuada.
/// - Alertas sólo para lo esencial: no si el usuario está usando el notch, no más de una cada
///   `minimumAlertInterval` por actividad (una urgente sí).
public enum ActivityLifecycle {
    /// Límite de la Isla Dinámica
    public static let maximumDuration: TimeInterval = 8 * 60 * 60
    /// Entre dos alertas de la misma actividad
    public static let minimumAlertInterval: TimeInterval = 30

    /// Superó las 8 h
    public static func isExpired(createdAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(createdAt) >= maximumDuration
    }

    /// Su contenido ya no está al día
    public static func isStale(staleDate: Date?, now: Date) -> Bool {
        guard let staleDate else { return false }
        return now >= staleDate
    }

    /// ¿Se muestra la alerta de esta actualización?
    /// - userIsBusy: el usuario tiene el notch abierto, el cursor encima u otra tarjeta expandida
    public static func shouldAlert(enabled: Bool, isUrgent: Bool, userIsBusy: Bool,
                                   lastAlertAt: Date?, now: Date) -> Bool {
        guard enabled, !userIsBusy else { return false }
        if isUrgent { return true }
        guard let last = lastAlertAt else { return true }
        return now.timeIntervalSince(last) >= minimumAlertInterval
    }
}
