import AppKit
import Foundation

/// Servicio universal para detectar y controlar medios en reproducción en macOS
/// (YouTube en Safari/Chrome/Arc/Brave/Firefox/Edge, Spotify, Apple Music, VLC, IINA, etc.)
/// mediante un puente ligero con MediaRemote del sistema.
public final class NowPlayingService {
    public static let shared = NowPlayingService()
    
    public var onTrackChanged: ((MusicTrack, Bool) -> Void)?
    
    private var bridgeProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var readBuffer = Data()
    private var isTerminating = false
    private var lastActiveBundleId: String?
    private var lastArtworkImage: NSImage?
    private var lastArtworkTitle: String = ""
    private var artworkCache: [String: NSImage] = [:]
    private var durationCache: [String: Double] = [:]
    private var artworkRetryCount: Int = 0
    private var lastTrackTitle: String = ""
    
    private init() {
        startBridgeProcess()
    }
    
    deinit {
        stopBridgeProcess()
    }
    
    // MARK: - Ciclo de vida del Proceso Puente

    /// Puente ya preparado (script de perl + biblioteca), para no repetir la copia en cada reinicio
    private var preparedBridge: (script: String, library: String)?
    /// Caídas seguidas del puente poco después de arrancar (para espaciar los reintentos)
    private var quickFailures = 0

    /// El puente es una biblioteca que carga `/usr/bin/perl` (firmado por Apple, en todos los Mac): desde macOS 15.4
    /// MediaRemote sólo responde a procesos de Apple. La biblioteca se copia a Application Support como archivo NUEVO:
    /// la del paquete puede venir en cuarentena (descargada de internet) y Gatekeeper bloquearía que perl la cargue.
    private func prepareBridge() -> (script: String, library: String)? {
        if let preparedBridge { return preparedBridge }
        guard let script = Bundle.main.path(forResource: "MediaRemoteBridge", ofType: "pl"),
              let bundled = Bundle.main.url(forResource: "MediaRemoteBridge", withExtension: "dylib"),
              let bytes = try? Data(contentsOf: bundled),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            DNDLogger.log("NowPlayingService: no se encontró el puente de MediaRemote en el paquete")
            return nil
        }
        let dir = support.appendingPathComponent("com.luisrandom.DynamicNotch", isDirectory: true)
        let library = dir.appendingPathComponent("MediaRemoteBridge.dylib")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? Data(contentsOf: library)) != bytes {
                try? FileManager.default.removeItem(at: library)
                try bytes.write(to: library)
            }
        } catch {
            DNDLogger.log("NowPlayingService: no se pudo preparar el puente: \(error.localizedDescription)")
            return nil
        }
        let prepared = (script: script, library: library.path)
        preparedBridge = prepared
        return prepared
    }

    private func startBridgeProcess() {
        guard let bridge = prepareBridge() else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [bridge.script, bridge.library]
        
        let stdin = Pipe()
        let stdout = Pipe()
        
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.bridgeProcess = process
        
        // Manejo asíncrono de líneas entrantes de JSON
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let availableData = handle.availableData
            guard !availableData.isEmpty else { return }
            self?.processIncomingData(availableData)
        }
        
        let startedAt = Date()
        process.terminationHandler = { [weak self] _ in
            guard let self = self, !self.isTerminating else { return }
            // Si se cae enseguida una y otra vez (p. ej. un Mac donde no carga), se espera cada vez más en vez de
            // reintentar sin fin cada 1.5 s
            self.quickFailures = Date().timeIntervalSince(startedAt) < 10 ? self.quickFailures + 1 : 0
            let delay = min(60, 1.5 * pow(2, Double(max(0, self.quickFailures - 1))))
            DNDLogger.log("NowPlayingService: el puente terminó; reinicio en \(Int(delay)) s")
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                self.startBridgeProcess()
            }
        }
        
        do {
            try process.run()
            print("[NowPlayingService] MediaRemoteBridge iniciado con éxito (PID: \(process.processIdentifier)).")
        } catch {
            print("[NowPlayingService] Error iniciando MediaRemoteBridge: \(error)")
        }
    }
    
    public func stop() {
        stopBridgeProcess()
    }
    
    private func stopBridgeProcess() {
        isTerminating = true
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = bridgeProcess, proc.isRunning {
            proc.terminate()
        }
        bridgeProcess = nil
        stdinPipe = nil
        stdoutPipe = nil
    }
    
    public func cachedArtwork(title: String, artist: String) -> NSImage? {
        let trackKey = "\(title)_\(artist)"
        if let img = artworkCache[trackKey] ?? artworkCache[title] {
            return img
        }
        if !title.isEmpty && title == lastArtworkTitle, let img = lastArtworkImage {
            return img
        }
        return ArtworkResolverService.shared.cachedArtwork(title: title, artist: artist)
    }
    
    // MARK: - Procesamiento de eventos en tiempo real
    private func processIncomingData(_ data: Data) {
        readBuffer.append(data)
        
        while let newlineRange = readBuffer.range(of: Data([0x0A])) { // \n
            let lineData = readBuffer.subdata(in: 0..<newlineRange.lowerBound)
            readBuffer.removeSubrange(0..<newlineRange.upperBound)
            
            guard !lineData.isEmpty else { continue }
            parseTrackJSON(lineData)
        }
    }
    
    private func parseTrackJSON(_ lineData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return
        }
        
        let title = json["title"] as? String ?? ""
        let artist = json["artist"] as? String ?? ""
        let album = json["album"] as? String ?? ""
        let rawDuration = json["duration"] as? Double ?? 180.0
        let elapsed = json["elapsed"] as? Double ?? 0.0
        let isPlaying = json["isPlaying"] as? Bool ?? false
        let appSource = json["appSource"] as? String ?? "YouTube"
        let artworkUrlString = json["artworkUrl"] as? String ?? ""
        
        // Resolver y cachear duración real
        var resolvedDuration = rawDuration
        if rawDuration > 2.0 {
            if durationCache.count > 40 { durationCache.removeAll(keepingCapacity: true) }
            durationCache[title] = rawDuration
        } else if let cachedDur = durationCache[title], cachedDur > 2.0 {
            resolvedDuration = cachedDur
        }
        
        // Carátula opcional en Base64 con preservación en caché por título y artista
        var artworkImage: NSImage? = nil
        let trackKey = "\(title)_\(artist)"
        if let b64 = json["artwork"] as? String, !b64.isEmpty, let artData = Data(base64Encoded: b64) {
            artworkImage = NSImage.decodedImage(from: artData)
            lastArtworkImage = artworkImage
            lastArtworkTitle = title
            if !title.isEmpty && artworkImage != nil {
                if artworkCache.count > 25 { artworkCache.removeAll(keepingCapacity: true) }
                artworkCache[title] = artworkImage
                artworkCache[trackKey] = artworkImage
            }
        } else if let cached = artworkCache[trackKey] ?? artworkCache[title] {
            artworkImage = cached
        } else if !title.isEmpty && title == lastArtworkTitle, let last = lastArtworkImage {
            artworkImage = last
        } else if let diskCached = ArtworkResolverService.shared.cachedArtwork(title: title, artist: artist) {
            artworkImage = diskCached
        }
        
        if let art = artworkImage, !title.isEmpty {
            ArtworkResolverService.shared.storeArtwork(art, title: title, artist: artist)
        } else if artworkImage == nil && !artworkUrlString.isEmpty, let url = URL(string: artworkUrlString) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let data = try? Data(contentsOf: url), let img = NSImage.decodedImage(from: data) {
                    DispatchQueue.main.async {
                        if (self?.artworkCache.count ?? 0) > 25 { self?.artworkCache.removeAll(keepingCapacity: true) }
                        self?.artworkCache[trackKey] = img
                        self?.artworkCache[title] = img
                        self?.lastArtworkImage = img
                        self?.lastArtworkTitle = title
                        ArtworkResolverService.shared.storeArtwork(img, title: title, artist: artist)
                        MusicService.shared.updateCurrentArtwork(img)
                    }
                }
            }
        }
        
        // Si no tenemos carátula para esta pista y está reproduciendo, solicitar reenvío inmediato
        if artworkImage == nil && isPlaying && !title.isEmpty {
            if title != lastTrackTitle {
                lastTrackTitle = title
                artworkRetryCount = 0
            }
            if artworkRetryCount < 3 {
                artworkRetryCount += 1
                sendCommandString("getArtwork")
            }
        }
        
        let track = MusicTrack(
            title: title,
            artist: artist,
            album: album,
            artwork: artworkImage,
            isPlaying: isPlaying,
            playbackPosition: elapsed,
            duration: max(resolvedDuration, 1.0),
            appSource: appSource
        )
        
        if appSource.lowercased().contains("safari") || appSource.lowercased().contains("youtube") {
            lastActiveBundleId = "com.apple.Safari"
        } else if appSource.lowercased().contains("chrome") {
            lastActiveBundleId = "com.google.Chrome"
        } else if appSource.lowercased().contains("spotify") {
            lastActiveBundleId = "com.spotify.client"
        } else if appSource.lowercased().contains("music") {
            lastActiveBundleId = "com.apple.Music"
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onTrackChanged?(track, isPlaying)
        }
    }
    
    // MARK: - Control de Reproducción Universal
    private func sendCommandString(_ command: String) {
        guard let data = "\(command)\n".data(using: .utf8),
              let stdin = stdinPipe?.fileHandleForWriting else { return }
        try? stdin.write(contentsOf: data)
    }
    
    public func refreshNowPlaying() {
        sendCommandString("refresh")
    }
    
    @discardableResult
    public func togglePlayPause() -> Bool {
        sendCommandString("toggle")
        return true
    }
    
    @discardableResult
    public func nextTrack() -> Bool {
        sendCommandString("next")
        return true
    }
    
    @discardableResult
    public func previousTrack() -> Bool {
        sendCommandString("prev")
        return true
    }
    
    @discardableResult
    public func toggleShuffle() -> Bool {
        sendCommandString("shuffle")
        return true
    }
    
    @discardableResult
    public func toggleRepeat() -> Bool {
        sendCommandString("repeat")
        return true
    }
    
    public func openActiveApp() {
        guard let bundleId = lastActiveBundleId else {
            if let safariUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                NSWorkspace.shared.openApplication(at: safariUrl, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        } else if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
