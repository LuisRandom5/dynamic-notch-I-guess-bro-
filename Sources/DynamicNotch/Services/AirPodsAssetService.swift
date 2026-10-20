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

    /// Tipo de producto de Apple para el modelo (nil = no hay animación oficial: Beats, desconocidos)
    public static func productType(for model: AirPodsModel) -> String? {
        switch model {
        case .airPods1: return "AirPods1,1"
        case .airPods2, .unknownAirPods: return "AirPods1,2"
        case .airPods3: return "AirPods1,3"
        case .airPods4: return "AirPods1,4"
        case .airPods4ANC: return "AirPods1,5"
        case .airPodsPro1: return "AirPodsPro1,1"
        case .airPodsPro2: return "AirPodsPro1,2"
        case .airPodsMax: return "AirPodsMax1,1"
        case .beatsStudio, .beatsSolo, .beatsFit, .beatsEarphones: return nil
        }
    }

    /// Video ya guardado para el modelo (nil si todavía no se ha bajado; en ese caso empieza a bajarlo)
    public func clipURL(_ clip: Clip, for model: AirPodsModel) -> URL? {
        guard let product = Self.productType(for: model) else { return nil }
        let url = bundleDirectory(for: product).appendingPathComponent(clip.rawValue + ".mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        prefetch(model: model)
        return nil
    }

    /// Baja (una vez) el paquete del modelo en segundo plano
    public func prefetch(model: AirPodsModel) {
        guard let product = Self.productType(for: model) else { return }
        let marker = bundleDirectory(for: product).appendingPathComponent(Clip.connectEngage.rawValue + ".mov")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        lock.lock()
        let isNew = inFlight.insert(product).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.inFlight.remove(product)
                self.lock.unlock()
            }
            do {
                try self.download(product: product)
                DNDLogger.log("AirPodsAssetService: animaciones oficiales de \(product) listas")
            } catch {
                DNDLogger.log("AirPodsAssetService: no se pudieron bajar las animaciones de \(product): \(error)")
            }
        }
    }

    private func bundleDirectory(for product: String) -> URL {
        cacheRoot.appendingPathComponent(product, isDirectory: true)
    }

    // MARK: Descarga

    private struct AssetEntry {
        let url: URL
        let sha1: Data?
    }

    private func download(product: String) throws {
        let entry = try findEntry(product: product)
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
        let destination = bundleDirectory(for: product)
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: bundle, to: destination)
    }

    /// Entrada del catálogo para el modelo (prefiere blanco o plata)
    private func findEntry(product: String) throws -> AssetEntry {
        let catalog = try catalogData()
        guard let plist = try PropertyListSerialization.propertyList(from: catalog, format: nil) as? [String: Any],
              let assets = plist["Assets"] as? [[String: Any]] else {
            throw NSError(domain: "AirPodsAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "catálogo ilegible"])
        }
        let matches = assets.filter { ($0["ProductType"] as? String) == product + "-v2" || ($0["ProductType"] as? String) == product }
        let preferred = matches.first { ["White", "Silver"].contains($0["VariantName"] as? String ?? "") } ?? matches.first
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
