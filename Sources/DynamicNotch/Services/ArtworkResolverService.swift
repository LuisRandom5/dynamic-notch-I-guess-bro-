import Foundation
import AppKit

/// Servicio de resolución y caché persistente de carátulas de alta resolución (Apple Music, Spotify, YouTube)
public final class ArtworkResolverService {
    public static let shared = ArtworkResolverService()
    
    private let cacheLock = NSLock()
    private var memoryCache: [String: NSImage] = [:]
    private var activeRequests: Set<String> = []
    
    private var diskCacheDirectory: URL? {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesURL.appendingPathComponent("com.luisrandom.DynamicNotch/Artworks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {}
    
    private func cacheKey(title: String, artist: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = "\(cleanTitle)_\(cleanArtist)"
        return combined.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? combined
    }
    
    /// Obtiene la carátula desde la memoria o el disco
    public func cachedArtwork(title: String, artist: String) -> NSImage? {
        guard !title.isEmpty else { return nil }
        let key = cacheKey(title: title, artist: artist)
        
        cacheLock.lock()
        if let mem = memoryCache[key] {
            cacheLock.unlock()
            return mem
        }
        cacheLock.unlock()
        
        if let dir = diskCacheDirectory {
            let fileURL = dir.appendingPathComponent("\(key).jpg")
            if let data = try? Data(contentsOf: fileURL), let img = NSImage.decodedImage(from: data) {
                cacheLock.lock()
                // Mismo límite que al guardar (sin él, cada carátula leída del disco se quedaba en memoria)
                if memoryCache.count > 12 { memoryCache.removeAll(keepingCapacity: true) }
                memoryCache[key] = img
                cacheLock.unlock()
                return img
            }
        }
        return nil
    }
    
    /// Almacena una carátula conocida en memoria y disco
    public func storeArtwork(_ image: NSImage, title: String, artist: String) {
        guard !title.isEmpty else { return }
        let key = cacheKey(title: title, artist: artist)
        // "Ahora suena" la vuelve a mandar en cada actualización: si es la misma, no se rasteriza ni se
        // escribe de nuevo en disco
        cacheLock.lock()
        let alreadyStored = memoryCache[key] === image
        cacheLock.unlock()
        if alreadyStored { return }
        let rasterizedImage = image.rasterized()
        
        cacheLock.lock()
        // Pocas carátulas en memoria: cada una decodificada pesa ~1–2 MB (antes 50 → la memoria crecía con las horas)
        if memoryCache.count > 12 { memoryCache.removeAll(keepingCapacity: true) }
        memoryCache[key] = rasterizedImage
        cacheLock.unlock()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let dir = self?.diskCacheDirectory else { return }
            let fileURL = dir.appendingPathComponent("\(key).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) { return }
            let rep = (rasterizedImage.representations.compactMap { $0 as? NSBitmapImageRep }.first)
                ?? rasterizedImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }
            if let jpeg = rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) {
                try? jpeg.write(to: fileURL)
            }
        }
    }
    
    /// Busca asíncronamente en la API oficial de iTunes Search la portada oficial en 600x600 px
    public func fetchArtworkAsync(title: String, artist: String, completion: @escaping (NSImage?) -> Void) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            completion(nil)
            return
        }
        
        if let cached = cachedArtwork(title: cleanTitle, artist: artist) {
            completion(cached)
            return
        }
        
        let key = cacheKey(title: cleanTitle, artist: artist)
        cacheLock.lock()
        if activeRequests.contains(key) {
            cacheLock.unlock()
            return
        }
        activeRequests.insert(key)
        cacheLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                self?.cacheLock.lock()
                self?.activeRequests.remove(key)
                self?.cacheLock.unlock()
            }
            
            // Construir término de búsqueda limpio (eliminando sufijos como "- A COLORS SHOW", "(Official Video)", etc.)
            var searchTitle = cleanTitle
            let regexSuffixes = [
                "\\s*\\([^)]*\\)",
                "\\s*\\[[^\\]]*\\]",
                "\\s*-\\s*(official video|audio|remix|colors show|single|lyric video|video oficial).*"
            ]
            for pattern in regexSuffixes {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    searchTitle = regex.stringByReplacingMatches(
                        in: searchTitle,
                        range: NSRange(location: 0, length: searchTitle.utf16.count),
                        withTemplate: ""
                    )
                }
            }
            
            let query = "\(searchTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let apiURL = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=1") else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            var request = URLRequest(url: apiURL)
            request.timeoutInterval = 4.0
            
            let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let rawArtworkUrl = first["artworkUrl100"] as? String else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                // Reemplazar 100x100 por 600x600 para obtener calidad de estudio Retina
                let highResUrlString = rawArtworkUrl.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                guard let imgURL = URL(string: highResUrlString),
                      let imgData = try? Data(contentsOf: imgURL),
                      let image = NSImage.decodedImage(from: imgData) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                self?.storeArtwork(image, title: cleanTitle, artist: artist)
                DispatchQueue.main.async {
                    completion(image)
                }
            }
            task.resume()
        }
    }
}
