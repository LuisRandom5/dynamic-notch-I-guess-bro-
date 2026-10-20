import AppKit

/// ¿El usuario no puede ver la pantalla? (bloqueada, pantallas dormidas o sesión de otro usuario). Mientras
/// tanto los sondeos que sólo sirven para lo que se ve en pantalla (WhatsApp, avisos, llamadas por
/// accesibilidad, pantalla completa, brillo, fondo…) se saltan su vuelta: antes seguían corriendo toda la
/// noche con la Mac bloqueada. El reproductor de la pantalla bloqueada no depende de esto.
public enum SystemIdleState {
    private static let lock = NSLock()
    fileprivate static var screensAsleep = false
    fileprivate static var screenLocked = false
    fileprivate static var sessionInactive = false
    private static var observers: [NSObjectProtocol] = []

    /// Se puede leer desde cualquier hilo
    public static var isScreenUnavailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return screensAsleep || screenLocked || sessionInactive
    }

    public static func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let entries: [(Notification.Name, (Bool) -> Void, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, { screensAsleep = $0 }, true),
            (NSWorkspace.screensDidWakeNotification, { screensAsleep = $0 }, false),
            (NSWorkspace.sessionDidResignActiveNotification, { sessionInactive = $0 }, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, { sessionInactive = $0 }, false)
        ]
        for (name, set, value) in entries {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in update { set(value) } })
        }
        // Bloqueo y desbloqueo: entrega inmediata aunque la app esté en segundo plano
        distributed.addObserver(lockReceiver, selector: #selector(LockReceiver.locked), name: Notification.Name("com.apple.screenIsLocked"),
                                object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(lockReceiver, selector: #selector(LockReceiver.unlocked), name: Notification.Name("com.apple.screenIsUnlocked"),
                                object: nil, suspensionBehavior: .deliverImmediately)
    }

    private static let lockReceiver = LockReceiver()

    private final class LockReceiver: NSObject {
        @objc func locked() { DispatchQueue.main.async { SystemIdleState.update { SystemIdleState.screenLocked = true } } }
        @objc func unlocked() { DispatchQueue.main.async { SystemIdleState.update { SystemIdleState.screenLocked = false } } }
    }

    fileprivate static func update(_ change: () -> Void) {
        let wasUnavailable = isScreenUnavailable
        lock.lock()
        change()
        lock.unlock()
        let unavailable = isScreenUnavailable
        if unavailable != wasUnavailable {
            DNDLogger.log("SystemIdleState: \(unavailable ? "pantalla no visible → sondeos en pausa" : "pantalla visible → sondeos reanudados")")
        }
    }
}
