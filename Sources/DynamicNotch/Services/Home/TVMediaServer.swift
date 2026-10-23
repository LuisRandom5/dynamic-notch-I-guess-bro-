import Foundation
import Network

// MARK: - Servidor de imágenes para la tele
// PiPup sólo anima un GIF si lo descarga de una dirección (con Glide); no lo acepta subido. Este servidor mínimo
// le sirve a la tele los avisos animados que dibuja la Mac: escucha en el puerto 7980 de la red local, sólo
// responde GET /tv/<id>.gif con lo que se publicó en los últimos 2 minutos y nada más (ni listados ni archivos).
final class TVMediaServer: @unchecked Sendable {
    static let shared = TVMediaServer()
    static let preferredPort: UInt16 = 7980

    private let queue = DispatchQueue(label: "DynamicNotch.TVMediaServer")
    private var listener: NWListener?
    private var port: UInt16?
    private var files: [String: (data: Data, expires: Date)] = [:]

    private init() {}

    private final class Flag: @unchecked Sendable { var value = false }

    /// Publica un GIF y devuelve su ruta (/tv/<id>.gif); nil si el servidor no pudo arrancar
    func publish(gif: Data) async -> (path: String, port: UInt16)? {
        guard let port = await ensureListening() else { return nil }
        let id = UUID().uuidString.lowercased()
        queue.sync {
            let now = Date()
            files = files.filter { $0.value.expires > now }
            files[id] = (gif, now.addingTimeInterval(120))
        }
        return ("/tv/\(id).gif", port)
    }

    private func ensureListening() async -> UInt16? {
        if let port = queue.sync(execute: { self.port }) { return port }
        if let port = await start(on: NWEndpoint.Port(rawValue: Self.preferredPort)!) { return port }
        // El 7980 está ocupado: cualquiera libre
        return await start(on: .any)
    }

    private func start(on port: NWEndpoint.Port) async -> UInt16? {
        guard let listener = try? NWListener(using: .tcp, on: port) else { return nil }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        return await withCheckedContinuation { continuation in
            // Todo corre en `queue`: la bandera sólo evita reanudar dos veces
            let resumed = Flag()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !resumed.value else { return }
                switch state {
                case .ready:
                    resumed.value = true
                    self.listener = listener
                    self.port = listener.port?.rawValue
                    DNDLogger.log("Tele: sirviendo avisos animados en el puerto \(self.port ?? 0)")
                    continuation.resume(returning: self.port)
                case .failed, .cancelled:
                    resumed.value = true
                    listener.cancel()
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let parts = request.split(separator: "\r\n").first?.split(separator: " ") ?? []
            var body: Data?
            if parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/tv/"), parts[1].hasSuffix(".gif") {
                let id = String(parts[1].dropFirst("/tv/".count).dropLast(".gif".count))
                if let file = self.files[id], file.expires > Date() { body = file.data }
            }
            let head: String
            if let body {
                head = "HTTP/1.1 200 OK\r\nContent-Type: image/gif\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            } else {
                head = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            var response = Data(head.utf8)
            if let body { response.append(body) }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// La IP de esta Mac en la misma red que la tele (la que comparte los tres primeros números)
    static func localAddress(towards host: String) -> String? {
        var candidates: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                candidates.append(String(cString: buffer))
            }
        }
        let prefix = host.split(separator: ".").prefix(3).joined(separator: ".") + "."
        return candidates.first { $0.hasPrefix(prefix) } ?? candidates.first
    }
}
