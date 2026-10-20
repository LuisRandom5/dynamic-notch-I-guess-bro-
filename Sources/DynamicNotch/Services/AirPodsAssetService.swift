import Foundation
import CryptoKit

/// Animaciones oficiales de los AirPods (las de la tarjeta de proximidad del iPhone: el estuche que se abre, los
/// auriculares, cargando…). Igual que iOS, se bajan de los servidores de Apple la primera vez que hacen falta y se
/// guardan en la caché de la app: no vienen dentro de Dynamic Notch ni del repositorio.
///
/// Catálogo: `mesu.apple.com/assets/com_apple_MobileAsset_SharingDeviceAssets/…xml` (un paquete .zip por modelo,
/// ~4–12 MB, con videos HEVC con transparencia).
public final class AirPodsAssetService {
    public static let shared = AirPodsAssetService()

    public enum Clip: String {
        /// El estuche se abre y los AirPods se muestran (al conectar)
        case connectEngage = "ProxCard_connect-engage"
        case connectLoop = "ProxCard_connect-loop"
        case charging = "ProxCard_loop-charging"
        case charged = "ProxCard_loop-charged"
        /// AirPods Max: girando en bucle (no tienen estuche ni auriculares separados)
        case maxLoop = "ProxCard_loop"
    }

    private static let catalogURL = URL(string: "https://mesu.apple.com/assets/com_apple_MobileAsset_SharingDeviceAssets/com_apple_MobileAsset_SharingDeviceAssets.xml")!
    private static let catalogMaxAge: TimeInterval = 7 * 24 * 3600

    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.AirPodsAssets", qos: .utility)
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    private init() {}

    private var cacheRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.luisrandom.DynamicNotch/AirPodsAssets", isDirectory: true)
    }

    /// Qué paquete del catálogo: producto de Apple + color
    public struct Identity: Hashable {
        public let product: String
        public let variant: String
        var folder: String { "\(product)-\(variant)" }
    }

    /// Producto de Apple por código Bluetooth (exacto: distingue Lightning de USB-C) o, si no se conoce, por modelo
    public static func product(productId: String, model: AirPodsModel) -> String? {
        switch productId.lowercased() {
        case "0x2002": return "AirPods1,1"
        case "0x200f": return "AirPods1,2"
        case "0x2013": return "AirPods1,3"
        case "0x2019": return "AirPods1,4"
        case "0x201a", "0x201b", "0x201e": return "AirPods1,5"
        case "0x200e": return "AirPodsPro1,1"
        case "0x2014": return "AirPodsPro1,2"
        case "0x2024": return "AirPodsPro1,3"
        case "0x2027": return "AirPods3,7"
        case "0x200a": return "AirPodsMax1,1"
        case "0x201f": return "AirPodsMax1,2"
        default: break
        }
        switch model {
        case .airPods1: return "AirPods1,1"
        case .airPods2, .unknownAirPods: return "AirPods1,2"
        case .airPods3: return "AirPods1,3"
        case .airPods4: return "AirPods1,4"
        case .airPods4ANC: return "AirPods1,5"
        case .airPodsPro1: return "AirPodsPro1,1"
        case .airPodsPro2: return "AirPodsPro1,2"
        case .airPodsPro3: return "AirPods3,7"
        case .airPodsMax: return "AirPodsMax1,1"
        case .beatsStudio, .beatsSolo, .beatsFit, .beatsEarphones: return nil
        }
    }

    /// Los AirPods Max vienen en colores (se elige en Ajustes); los demás son blancos
    public static func identity(productId: String, model: AirPodsModel) -> Identity? {
        guard let product = product(productId: productId, model: model) else { return nil }
        let variant = product.hasPrefix("AirPodsMax") ? AppState.shared.airPodsMaxColor.catalogVariant : "White"
        return Identity(product: product, variant: variant)
    }

    /// La del aviso: la que pidió el banco de pruebas o, si no, los AirPods conectados
    public static func identity(for state: AirPodsActivityState?) -> Identity? {
        if let product = state?.assetProduct {
            return Identity(product: product, variant: state?.assetVariant ?? (product.hasPrefix("AirPodsMax") ? "Silver" : "White"))
        }
        return currentIdentity
    }

    /// ¿Ya está guardado el paquete? (sin empezar a bajarlo)
    public func isAvailable(_ identity: Identity) -> Bool {
        FileManager.default.fileExists(atPath: bundleDirectory(for: identity).appendingPathComponent(Clip.connectEngage.rawValue + ".mov").path)
    }

    /// Baja el paquete (si hace falta) y avisa en el hilo principal: true si quedó listo
    public func ensureAvailable(_ identity: Identity, completion: @escaping (Bool) -> Void) {
        if isAvailable(identity) { completion(true); return }
        prefetch(identity)
        var waited = 0.0
        func poll() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                waited += 0.5
                if self.isAvailable(identity) { completion(true) } else if waited >= 90 { completion(false) } else { poll() }
            }
        }
        poll()
    }

    /// Los AirPods conectados ahora (o los últimos que se detectaron)
    public static var currentIdentity: Identity? {
        identity(productId: BluetoothAudioService.shared.currentProductId, model: BluetoothAudioService.shared.currentAirPodsModel)
    }

    /// Video ya guardado (nil si todavía no se ha bajado; en ese caso empieza a bajarlo)
    public func clipURL(_ clip: Clip, for identity: Identity?) -> URL? {
        fileURL(clip.rawValue + ".mov", for: identity)
    }

    /// Imagen oficial: "ProxCard_L", "ProxCard_R", "ProxCard_case-closed-charging"… (@2x)
    public func imageURL(_ name: String, for identity: Identity?) -> URL? {
        fileURL(name + "@2x.png", for: identity)
    }

    private func fileURL(_ name: String, for identity: Identity?) -> URL? {
        guard let identity else { return nil }
        let url = bundleDirectory(for: identity).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // Lo bajado antes de distinguir colores se guardaba sin el color en el nombre: se reusa
        let legacy = cacheRoot.appendingPathComponent(identity.product, isDirectory: true)
        if identity.variant == "White", FileManager.default.fileExists(atPath: legacy.path),
           (try? FileManager.default.moveItem(at: legacy, to: bundleDirectory(for: identity))) != nil,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        prefetch(identity)
        return nil
    }

    /// Baja (una vez) el paquete en segundo plano
    public func prefetch(_ identity: Identity?) {
        guard let identity else { return }
        let marker = bundleDirectory(for: identity).appendingPathComponent(Clip.connectEngage.rawValue + ".mov")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        lock.lock()
        let isNew = inFlight.insert(identity.folder).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.inFlight.remove(identity.folder)
                self.lock.unlock()
            }
            do {
                try self.download(identity)
                DNDLogger.log("AirPodsAssetService: animaciones oficiales de \(identity.folder) listas")
            } catch {
                DNDLogger.log("AirPodsAssetService: no se pudieron bajar las animaciones de \(identity.folder): \(error)")
            }
        }
    }

    private func bundleDirectory(for identity: Identity) -> URL {
        cacheRoot.appendingPathComponent(identity.folder, isDirectory: true)
    }

    // MARK: Descarga

    private struct AssetEntry {
        let url: URL
        let sha1: Data?
    }

    private func download(_ identity: Identity) throws {
        let entry = try findEntry(identity)
        let zipData = try fetch(entry.url, timeout: 120)
        // Integridad: la huella SHA-1 que publica Apple en el catálogo
        if let expected = entry.sha1 {
            let actual = Data(Insecure.SHA1.hash(data: zipData))
            guard actual == expected else { throw NSError(domain: "AirPodsAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "huella distinta"]) }
        }
        let fm = FileManager.default
        let work = cacheRoot.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let zipURL = work.appendingPathComponent("asset.zip")
        try zipData.write(to: zipURL)
        let unzipped = work.appendingPathComponent("x", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, unzipped.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw NSError(domain: "AirPodsAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "no se pudo descomprimir"]) }
        // Los videos e imágenes viven en AssetData/<modelo>.devicebundle/
        guard let bundle = fm.enumerator(at: unzipped, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.pathExtension == "devicebundle" }) else {
            throw NSError(domain: "AirPodsAssets", code: 4, userInfo: [NSLocalizedDescriptionKey: "paquete sin devicebundle"])
        }
        let destination = bundleDirectory(for: identity)
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: bundle, to: destination)
    }

    /// Entrada del catálogo para el producto y color (si ese color no existe para ese modelo: blanco o plata)
    private func findEntry(_ identity: Identity) throws -> AssetEntry {
        let product = identity.product
        let catalog = try catalogData()
        guard let plist = try PropertyListSerialization.propertyList(from: catalog, format: nil) as? [String: Any],
              let assets = plist["Assets"] as? [[String: Any]] else {
            throw NSError(domain: "AirPodsAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "catálogo ilegible"])
        }
        let matches = assets.filter { ($0["ProductType"] as? String) == product + "-v2" || ($0["ProductType"] as? String) == product }
        let preferred = matches.first { ($0["VariantName"] as? String) == identity.variant }
            ?? matches.first { ["White", "Silver"].contains($0["VariantName"] as? String ?? "") } ?? matches.first
        guard let asset = preferred,
              let base = asset["__BaseURL"] as? String, let relative = asset["__RelativePath"] as? String,
              let url = URL(string: base + relative), url.host?.hasSuffix("apple.com") == true else {
            throw NSError(domain: "AirPodsAssets", code: 5, userInfo: [NSLocalizedDescriptionKey: "\(product) no está en el catálogo"])
        }
        return AssetEntry(url: url, sha1: asset["_Measurement"] as? Data)
    }

    private func catalogData() throws -> Data {
        let cached = cacheRoot.appendingPathComponent("catalog.xml")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cached.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.catalogMaxAge,
           let data = try? Data(contentsOf: cached) {
            return data
        }
        let data = try fetch(Self.catalogURL, timeout: 30)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try? data.write(to: cached)
        return data
    }

    /// Descarga síncrona (ya estamos en la cola de fondo)
    private func fetch(_ url: URL, timeout: TimeInterval) throws -> Data {
        var result: Result<Data, Error> = .failure(URLError(.unknown))
        let done = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(URLError(.badServerResponse))
            } else {
                result = .success(data ?? Data())
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }
}
