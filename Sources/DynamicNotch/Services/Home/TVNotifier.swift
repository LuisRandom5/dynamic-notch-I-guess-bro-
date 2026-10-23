import ImageIO
import Network
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Avisos en la tele
// Los avisos de Casa también salen en la pantalla de la tele, encima de lo que estés viendo. Usa PiPup
// (github.com/rogro82/PiPup), una app de Android TV que recibe avisos por HTTP en el puerto 7979 y los dibuja encima
// (necesita el permiso SYSTEM_ALERT_WINDOW, que sólo se da por ADB). La tele se busca en la red por Bonjour con el
// servicio del control remoto de Google TV (_androidtvremote2._tcp); se guarda su nombre y su IP, y si la IP cambia
// (el módem le asigna otra) se vuelve a buscar por el nombre.
@MainActor
public final class TVNotifier: ObservableObject {
    public static let shared = TVNotifier()

    public struct FoundTV: Identifiable, Equatable {
        public let name: String
        public let host: String
        public var id: String { name }
    }

    /// Esquina de la pantalla (los valores de PiPup)
    public enum Corner: Int, CaseIterable, Identifiable {
        case topRight = 0, topLeft = 1, bottomRight = 2, bottomLeft = 3, center = 4
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .topRight: return L("Arriba a la derecha")
            case .topLeft: return L("Arriba a la izquierda")
            case .bottomRight: return L("Abajo a la derecha")
            case .bottomLeft: return L("Abajo a la izquierda")
            case .center: return L("En medio")
            }
        }
    }

    @Published public var isEnabled: Bool = UserDefaults.standard.bool(forKey: "homeTVEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "homeTVEnabled") }
    }
    @Published public private(set) var tvName: String? = UserDefaults.standard.string(forKey: "homeTVName")
    @Published public private(set) var tvHost: String? = UserDefaults.standard.string(forKey: "homeTVHost")
    @Published public var corner: Corner = Corner(rawValue: UserDefaults.standard.integer(forKey: "homeTVCorner")) ?? .topRight {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "homeTVCorner") }
    }
    @Published public private(set) var isSearching = false
    @Published public private(set) var found: [FoundTV] = []
    /// Cómo le fue al último aviso (para Ajustes)
    @Published public private(set) var lastResult: String?

    static let port = 7979
    private var browser: NWBrowser?
    /// Lo que va encontrando la búsqueda en curso
    private var discovered: [FoundTV] = []

    private init() {}

    public var isReady: Bool { isEnabled && tvHost != nil }

    public func choose(_ tv: FoundTV) {
        tvName = tv.name
        tvHost = tv.host
        UserDefaults.standard.set(tv.name, forKey: "homeTVName")
        UserDefaults.standard.set(tv.host, forKey: "homeTVHost")
        isEnabled = true
    }

    // MARK: - Avisos

    /// Un aviso: se dibuja como la isla (SwiftUI) y viaja como PNG con transparencia
    public struct Notice {
        public var title: String
        public var message: String
        public var symbol: String
        public var tint: Color
        public var duration: Int = 15
    }

    /// Manda un aviso a la tele (si está activado). Si no contesta, busca la tele por su nombre y lo reintenta una vez.
    public func notify(_ notice: Notice) {
        guard isReady else { return }
        Task { await send(notice, retry: true) }
    }

    public func sendTest() {
        Task {
            await send(Notice(title: L("Así se ven los avisos"), message: L("Casa · Dynamic Notch"),
                              symbol: "house.fill", tint: DesignTokens.blue, duration: 8), retry: true)
        }
    }

    /// Píxeles de la tele (1920 de ancho) por punto de la tarjeta: 372 pt quedan en unos 710 px
    static let pixelsPerPoint: CGFloat = 1.9

    private func send(_ notice: Notice, retry: Bool) async {
        guard let host = tvHost, let url = URL(string: "http://\(host):\(Self.port)/notify") else { return }
        do {
            // Animado (GIF servido desde la Mac); si no se puede, la tarjeta fija
            let request = await animatedRequest(notice, url: url, host: host) ?? stillRequest(notice, url: url)
            guard let request else {
                DNDLogger.log("Tele: no se pudo dibujar el aviso")
                return
            }
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw URLError(.badServerResponse) }
            lastResult = L("Último aviso enviado") + " · " + Date().formatted(date: .omitted, time: .shortened)
            DNDLogger.log("Tele: aviso enviado (\(notice.title))")
        } catch {
            DNDLogger.log("Tele: no contestó \(host): \(error.localizedDescription)")
            // ¿Le cambió la IP? Se busca por su nombre y se reintenta una vez
            if retry, let name = tvName, let tv = await findTV(named: name), tv.host != host {
                DNDLogger.log("Tele: \(name) ahora está en \(tv.host)")
                choose(tv)
                await send(notice, retry: false)
                return
            }
            lastResult = L("La tele no contestó: ¿está prendida y con PiPup instalado?")
        }
    }

    /// El aviso animado: la Mac sirve el GIF y PiPup lo descarga (con JSON y una dirección; subido no se anima)
    private func animatedRequest(_ notice: Notice, url: URL, host: String) async -> URLRequest? {
        guard let mac = TVMediaServer.localAddress(towards: host),
              let (gif, pixelWidth) = TVNoticeRenderer.gif(for: notice, seconds: Double(notice.duration), scale: Self.pixelsPerPoint),
              let published = await TVMediaServer.shared.publish(gif: gif) else { return nil }
        DNDLogger.log("Tele: GIF de \(gif.count / 1024) KB en http://\(mac):\(published.port)\(published.path)")
        let body: [String: Any] = [
            // Un segundo de más: el GIF termina vacío y PiPup cuenta desde antes de descargarlo
            "duration": notice.duration + 1,
            "position": corner.rawValue,
            "backgroundColor": "#00000000",
            "media": ["image": ["uri": "http://\(mac):\(published.port)\(published.path)", "width": pixelWidth]],
        ]
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// La tarjeta fija como PNG subido (multipart/form-data: así respeta la transparencia de las esquinas)
    private func stillRequest(_ notice: Notice, url: URL) -> URLRequest? {
        guard let (png, pixelWidth) = TVNoticeRenderer.png(for: notice, scale: Self.pixelsPerPoint) else { return nil }
        let boundary = "DynamicNotch-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("duration", "\(notice.duration)")
        field("position", "\(corner.rawValue)")
        // Sin fondo propio: sólo la tarjeta (PiPup deja 20 px de margen transparente alrededor)
        field("backgroundColor", "#00000000")
        field("imageWidth", "\(pixelWidth)")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"aviso.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(png)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    // MARK: - Buscar la tele

    /// Busca durante unos segundos las teles con Google TV de la red
    public func search() {
        guard !isSearching else { return }
        isSearching = true
        found = []
        Task {
            let results = await discover(seconds: 4)
            found = results
            isSearching = false
            // Una sola tele y ninguna elegida: se elige sola
            if tvHost == nil, results.count == 1 { choose(results[0]) }
        }
    }

    private func findTV(named name: String) async -> FoundTV? {
        await discover(seconds: 3).first { $0.name == name }
    }

    private func discover(seconds: Double) async -> [FoundTV] {
        let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
        self.browser = browser
        discovered = []
        browser.browseResultsChangedHandler = { [weak self] browseResults, _ in
            Task { @MainActor in
                for result in browseResults {
                    guard let self, case .service(let name, _, _, _) = result.endpoint,
                          !self.discovered.contains(where: { $0.name == name }) else { continue }
                    if let host = await self.resolve(result.endpoint), !self.discovered.contains(where: { $0.name == name }) {
                        self.discovered.append(FoundTV(name: name, host: host))
                    }
                }
            }
        }
        browser.start(queue: .main)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        browser.cancel()
        self.browser = nil
        return discovered
    }

    /// IP de un servicio Bonjour: se abre una conexión y se lee a dónde quedó conectada
    private func resolve(_ endpoint: NWEndpoint) async -> String? {
        await withCheckedContinuation { continuation in
            let parameters = NWParameters.tcp
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: parameters)
            var finished = false
            let finish: (String?) -> Void = { host in
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: host)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        // Quita el sufijo de interfaz de IPv6 ("%en0") si llegara a salir
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        finish(text)
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}

// MARK: - La tarjeta

/// Lo de adentro de la tarjeta: ícono en un círculo de su color, título y detalle. Crece con el texto (un título
/// largo no se corta), entre 340 y 560 pt de ancho y 72 de alto.
struct TVNoticeContent: View {
    let notice: TVNotifier.Notice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(notice.tint.opacity(0.22))
                Image(systemName: notice.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(notice.tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(notice.message)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            // Firma discreta: de dónde viene el aviso
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.leading, 13)
        .padding(.trailing, 22)
        .frame(minWidth: 340, maxWidth: 560, minHeight: 72, maxHeight: 72)
        .fixedSize(horizontal: true, vertical: false)
        .environment(\.colorScheme, .dark)
    }
}

/// La tarjeta fija (PNG): cápsula negra con borde de su color y sombra suave
struct TVNoticeCard: View {
    let notice: TVNotifier.Notice

    var body: some View {
        TVNoticeContent(notice: notice)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .overlay(Capsule(style: .continuous).strokeBorder(notice.tint.opacity(0.35), lineWidth: 1))
            )
            // Sombra para que se lea sobre fondos claros (por eso el margen transparente)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .padding(14)
    }
}

/// Un cuadro de la animación: la cápsula de `expansion` (0 = nada, 1 = completa, un poco más en el rebote) y el
/// contenido con `content` de opacidad, recortado por la cápsula para que parezca que sale de ella, como la isla.
/// Sin sombra: el GIF sólo tiene transparencia total o nada.
struct TVNoticeFrame: View {
    let notice: TVNotifier.Notice
    let size: CGSize
    let expansion: CGFloat
    let content: Double
    /// A los lados cabe el rebote (la cápsula se estira ~10 % antes de asentarse)
    static let horizontalMargin: CGFloat = 26
    static let verticalMargin: CGFloat = 8

    var body: some View {
        let width = max(0, size.height * 0.55 + (size.width - size.height * 0.55) * expansion)
        let height = max(0, size.height * (0.55 + 0.45 * min(expansion, 1.06)))
        let visible = expansion > 0.02
        ZStack {
            if visible {
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .overlay(Capsule(style: .continuous).strokeBorder(notice.tint.opacity(0.35 * min(1, expansion)), lineWidth: 1))
                    .frame(width: width, height: height)
                TVNoticeContent(notice: notice)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(0.94 + 0.06 * content)
                    .opacity(content)
                    .mask(Capsule(style: .continuous).frame(width: width, height: height))
            }
        }
        .frame(width: size.width + Self.horizontalMargin * 2, height: size.height + Self.verticalMargin * 2)
    }
}

@MainActor
enum TVNoticeRenderer {
    /// PNG con fondo transparente y su ancho en píxeles
    static func png(for notice: TVNotifier.Notice, scale: CGFloat) -> (Data, Int)? {
        let renderer = ImageRenderer(content: TVNoticeCard(notice: notice))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return (data, image.width)
    }

    // Tiempos de la animación (s)
    static let frameDelay = 0.04
    static let entrance = 0.6
    /// La salida va rápida (0.4 y 0.24 s se veían lentas al irse) y a 50 cuadros por segundo para que sea fluida
    static let exit = 0.16
    static let exitFrameDelay = 0.02

    /// GIF que entra con rebote, se queda y se recoge; dura `seconds` y termina transparente. Glide lo repite en
    /// bucle aunque se le pida una sola vez, así que el último cuadro (vacío) dura un minuto.
    static func gif(for notice: TVNotifier.Notice, seconds: Double, scale: CGFloat) -> (Data, Int)? {
        let measure = ImageRenderer(content: TVNoticeContent(notice: notice))
        measure.scale = 1
        guard let measured = measure.cgImage else { return nil }
        let size = CGSize(width: measured.width, height: measured.height)

        var frames: [(CGImage, Double)] = []
        func add(expansion: CGFloat, content: Double, delay: Double) -> Bool {
            let renderer = ImageRenderer(content: TVNoticeFrame(notice: notice, size: size, expansion: expansion, content: content))
            renderer.scale = scale
            renderer.isOpaque = false
            guard let image = renderer.cgImage else { return false }
            frames.append((image, delay))
            return true
        }

        // Entrada: la cápsula crece con rebote y luego aparece el contenido
        let entranceFrames = Int(entrance / frameDelay)
        for index in 0...entranceFrames {
            let t = Double(index) * frameDelay
            let grow = easeOutBack(min(1, t / 0.42))
            let show = smoothstep((t - 0.2) / 0.32)
            guard add(expansion: CGFloat(grow), content: show, delay: frameDelay) else { return nil }
        }
        // Quieta
        let hold = max(1, seconds - entrance - exit)
        guard add(expansion: 1, content: 1, delay: hold) else { return nil }
        // Salida: se va el contenido y la cápsula se recoge hacia el centro
        let exitFrames = Int((exit / exitFrameDelay).rounded())
        for index in 1...exitFrames {
            let t = Double(index) * exitFrameDelay
            let content = 1 - smoothstep(t / 0.06)
            let shrink = 1 - easeInQuad(t / exit)
            guard add(expansion: CGFloat(shrink), content: content, delay: exitFrameDelay) else { return nil }
        }
        guard add(expansion: 0, content: 0, delay: 60) else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 1]] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, frames[0].0.width)
    }

    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private static func easeInQuad(_ x: Double) -> Double { pow(min(max(x, 0), 1), 2) }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
