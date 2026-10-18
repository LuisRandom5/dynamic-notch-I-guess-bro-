import Foundation

/// Detecta envíos y recepciones de AirDrop en tiempo real leyendo el registro unificado de `sharingd`
/// (`/usr/bin/log stream`, filtrado por el propio sistema; no requiere permisos especiales).
///
/// Señales (verificadas en el registro de esta Mac):
/// - Empieza un envío:     "Send StateMachine START"
/// - Empieza una recepción: "Receive StateMachine PreChecks START"
/// - Termina cualquiera:   MetricEvent 'com.apple.sharing.AirDrop.TransferResult' con
///                         "sender" : 1 (envío) / 0 (recepción) y "success" : true/false
public final class AirDropTransferMonitor {
    public static let shared = AirDropTransferMonitor()

    public enum Direction { case sending, receiving }

    private var process: Process?
    private var pending = Data()
    private var isStopped = true
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.AirDropLog", qos: .userInitiated)

    private static let predicate = """
    process == "sharingd" AND (eventMessage CONTAINS "Send StateMachine START" \
    OR eventMessage CONTAINS "Receive StateMachine PreChecks START" \
    OR eventMessage CONTAINS "AirDrop.TransferResult")
    """

    private init() {}

    public func start() {
        queue.async {
            guard self.isStopped else { return }
            self.isStopped = false
            self.launch()
        }
    }

    public func stop() {
        queue.async {
            self.isStopped = true
            self.process?.terminate()
            self.process = nil
        }
    }

    /// Si la app se cerró a la fuerza (p. ej. `killall -9`), su `log stream` pudo quedar huérfano
    private func killOrphanedStreams() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        // Patrón anclado: sólo procesos que SON nuestro `log stream` de sharingd (nunca otra cosa que
        // casualmente mencione el texto en su línea de comandos)
        pkill.arguments = ["-f", #"^/usr/bin/log stream --style ndjson --level default --predicate process == "sharingd""#]
        try? pkill.run()
        pkill.waitUntilExit()
    }
    
    private func launch() {
        if process == nil { killOrphanedStreams() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--level", "default", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Si `log stream` se cae, volver a escuchar (sin bucles agresivos)
            self?.queue.asyncAfter(deadline: .now() + 5) {
                guard let self = self, !self.isStopped else { return }
                self.launch()
            }
        }
        do {
            try process.run()
            self.process = process
            DNDLogger.log("AirDropTransferMonitor: escuchando sharingd")
        } catch {
            DNDLogger.log("AirDropTransferMonitor: no se pudo iniciar log stream: \(error)")
        }
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending.subdata(in: pending.startIndex..<newline)
            pending.removeSubrange(pending.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = json["eventMessage"] as? String else { continue }
            handle(message)
        }
    }

    private func handle(_ message: String) {
        if message.contains("Send StateMachine START") {
            DispatchQueue.main.async { AirDropActivityProvider.shared.beginTransfer(.sending) }
        } else if message.contains("Receive StateMachine PreChecks START") {
            DispatchQueue.main.async { AirDropActivityProvider.shared.beginTransfer(.receiving) }
        } else if message.contains("AirDrop.TransferResult") {
            let isSender = message.range(of: #""sender"\s*:\s*1"#, options: .regularExpression) != nil
            let success = message.range(of: #""success"\s*:\s*true"#, options: .regularExpression) != nil
            DispatchQueue.main.async {
                AirDropActivityProvider.shared.finishTransfer(isSender ? .sending : .receiving, success: success)
            }
        }
    }
}
