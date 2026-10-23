import Foundation

/// Remitentes de los mensajes de demostración (botones de prueba): sus respuestas no se mandan a ningún lado.
/// Antes se reconocían por el nombre ("Carlos"), así que las respuestas a un contacto real llamado Carlos se
/// perdían sin avisar.
public enum DemoMessages {
    private static var senders: [String: Date] = [:]
    private static let lock = NSLock()

    /// Marca a un remitente como de demostración durante los siguientes 15 minutos
    public static func mark(_ sender: String) {
        lock.lock(); defer { lock.unlock() }
        senders[sender.lowercased()] = Date()
    }

    public static func isDemo(_ sender: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        senders = senders.filter { Date().timeIntervalSince($0.value) < 900 }
        return senders[sender.lowercased()] != nil
    }
}
