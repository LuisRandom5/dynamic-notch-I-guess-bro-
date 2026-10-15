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
    
    private init() {
        startBridgeProcess()
    }
    
    deinit {
        stopBridgeProcess()
    }
    
    // MARK: - Ciclo de vida del Proceso Puente
    private func locateBridgeScript() -> String? {
        // 1. Recursos empaquetados en la app (.app/Contents/Resources/MediaRemoteBridge.swift)
        if let bundlePath = Bundle.main.path(forResource: "MediaRemoteBridge", ofType: "swift") {
            if FileManager.default.fileExists(atPath: bundlePath) {
                return bundlePath
            }
        }
        
        // 2. Ruta relativa a Resources en el bundle
        let resourceURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MediaRemoteBridge.swift")
        if FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL.path
        }
        
        // 3. Ruta en el código fuente del proyecto
        let devPath = "/Users/luisangelceroncastro/Documents/Dynamic Notch/Resources/MediaRemoteBridge.swift"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        
        return nil
    }
    
    private func startBridgeProcess() {
        guard let scriptPath = locateBridgeScript() else {
            print("[NowPlayingService] Error: No se encontró MediaRemoteBridge.swift")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath]
        
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
        
        process.terminationHandler = { [weak self] _ in
            guard let self = self, !self.isTerminating else { return }
            print("[NowPlayingService] MediaRemoteBridge terminado. Reiniciando en 1.5s...")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
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
        
        // Resolver y cachear duración real
        var resolvedDuration = rawDuration
        if rawDuration > 2.0 {
            durationCache[title] = rawDuration
        } else if let cachedDur = durationCache[title], cachedDur > 2.0 {
            resolvedDuration = cachedDur
        }
        
        // Carátula opcional en Base64 con preservación en caché por título
        var artworkImage: NSImage? = nil
        if let b64 = json["artwork"] as? String, !b64.isEmpty, let artData = Data(base64Encoded: b64) {
            artworkImage = NSImage(data: artData)
            lastArtworkImage = artworkImage
            lastArtworkTitle = title
            if !title.isEmpty && artworkImage != nil {
                artworkCache[title] = artworkImage
            }
        } else if let cached = artworkCache[title] {
            artworkImage = cached
        } else if !title.isEmpty && title == lastArtworkTitle {
            artworkImage = lastArtworkImage
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
