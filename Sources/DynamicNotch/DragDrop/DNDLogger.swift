import Foundation

public enum DNDLogger {
    private static let logURL = URL(fileURLWithPath: "/tmp/notch_dnd.log")
    private static let lock = NSLock()
    
    public static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        print("[DND] \(message)")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
