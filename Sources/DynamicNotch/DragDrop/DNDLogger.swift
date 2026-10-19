import Foundation

public enum DNDLogger {
    private static let logURL = URL(fileURLWithPath: "/tmp/notch_dnd.log")
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    /// Al pasar de este tamaño el log se renombra a .1 y empieza de nuevo (antes crecía sin fin)
    private static let maxBytes: UInt64 = 5 * 1024 * 1024

    public static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        print("[DND] \(message)")
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            let size = handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
            if size > maxBytes { rotate() }
        } else {
            // Sólo lo lee este usuario: puede traer nombres de contactos
            FileManager.default.createFile(atPath: logURL.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }

    /// Texto privado (mensajes) en el log: sólo su largo
    public static func redact(_ text: String) -> String {
        "‹\(text.count) car.›"
    }

    private static func rotate() {
        let old = logURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: logURL, to: old)
    }
}
