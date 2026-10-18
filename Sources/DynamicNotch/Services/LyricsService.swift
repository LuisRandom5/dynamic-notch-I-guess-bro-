import Foundation
import Combine
import AppKit

public struct LyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: TimeInterval
    public let text: String
    
    public init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

/// Servicio singleton para la obtención y sincronización de letras en tiempo real (Karaoke Synced Lyrics)
/// Consulta LRCLIB (API pública y gratuita sin keys) y AppleScript (Apple Music) con caché en memoria.
public final class LyricsService: ObservableObject {
    public static let shared = LyricsService()
    
    @Published public private(set) var lines: [LyricLine] = []
    @Published public private(set) var currentLineIndex: Int = 0
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasSyncedLyrics: Bool = false
    @Published public private(set) var isInstrumental: Bool = false
    
    private var currentTrackKey: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    
    // Caché en memoria para evitar re-descargas entre saltos de pista
    private var lyricsCache: [String: [LyricLine]] = [:]
    
    private init() {
        observeMusicService()
        startSyncTimer()
    }
    
    private func observeMusicService() {
        MusicService.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.handleTrackChanged(track)
            }
            .store(in: &cancellables)
    }
    
    private func handleTrackChanged(_ track: MusicTrack) {
        let cleanTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanTitle.isEmpty else {
            DispatchQueue.main.async {
                self.lines = []
                self.currentLineIndex = 0
                self.hasSyncedLyrics = false
                self.isInstrumental = false
                self.currentTrackKey = ""
            }
            return
        }
        
        let key = "\(cleanTitle)|\(cleanArtist)"
        guard key != currentTrackKey else { return }
        currentTrackKey = key
        
        // Verificar caché primero
        if let cached = lyricsCache[key] {
            DispatchQueue.main.async {
                self.lines = cached
                self.hasSyncedLyrics = !cached.isEmpty
                self.isInstrumental = false
                self.currentLineIndex = 0
            }
            return
        }
        
        fetchLyrics(title: cleanTitle, artist: cleanArtist, duration: track.duration, key: key)
    }
    
    public func fetchLyrics(title: String, artist: String, duration: Double, key: String) {
        isLoading = true
        
        // 1. Intentar consulta vía LRCLIB API
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if duration > 10 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            fallbackToAppleMusicOrDemo(title: title, artist: artist, key: key)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("DynamicNotch/1.0 (macOS; github.com/LuisRandom5)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let data = data,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                let isInst = json["instrumental"] as? Bool ?? false
                let synced = json["syncedLyrics"] as? String
                let plain = json["plainLyrics"] as? String
                
                if let syncedStr = synced, !syncedStr.isEmpty {
                    let parsed = Self.parseLRC(syncedStr)
                    if !parsed.isEmpty {
                        DispatchQueue.main.async {
                            guard self.currentTrackKey == key else { return }
                            self.lines = parsed
                            self.hasSyncedLyrics = true
                            self.isInstrumental = isInst
                            self.isLoading = false
                            self.lyricsCache[key] = parsed
                        }
                        return
                    }
                }
                
                if let plainStr = plain, !plainStr.isEmpty {
                    let plainLines = Self.parsePlainLyrics(plainStr, duration: duration)
                    DispatchQueue.main.async {
                        guard self.currentTrackKey == key else { return }
                        self.lines = plainLines
                        self.hasSyncedLyrics = false
                        self.isInstrumental = isInst
                        self.isLoading = false
                        self.lyricsCache[key] = plainLines
                    }
                    return
                }
            }
            
            // Si LRCLIB no encontró o no hubo internet, intentar Apple Music local o demo estética
            self.fallbackToAppleMusicOrDemo(title: title, artist: artist, key: key)
        }.resume()
    }
    
    private func fallbackToAppleMusicOrDemo(title: String, artist: String, key: String) {
        // Consultar script de Apple Music si la app nativa Música está corriendo
        let appleMusicScript = """
        tell application "System Events"
            if exists (process "Music") then
                tell application "Music"
                    try
                        return lyrics of current track
                    end try
                end tell
            end if
        end tell
        return ""
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: appleMusicScript) {
                let res = script.executeAndReturnError(&errorInfo)
                let lyrics = res.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !lyrics.isEmpty {
                    let parsed = Self.parsePlainLyrics(lyrics, duration: MusicService.shared.currentTrack.duration)
                    DispatchQueue.main.async {
                        guard self.currentTrackKey == key else { return }
                        self.lines = parsed
                        self.hasSyncedLyrics = false
                        self.isInstrumental = false
                        self.isLoading = false
                        self.lyricsCache[key] = parsed
                    }
                    return
                }
            }
            
            // Demo visual por defecto para canciones sin letra o pruebas
            let demo = Self.generateAestheticDemoLyrics(title: title, artist: artist)
            DispatchQueue.main.async {
                guard self.currentTrackKey == key else { return }
                self.lines = demo
                self.hasSyncedLyrics = true
                self.isInstrumental = false
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Parsers de Formato LRC
    
    public static func parseLRC(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let rawLines = lrc.components(separatedBy: "\n")
        
        let pattern = #"^\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = regex.firstMatch(in: trimmed, options: [], range: range) {
                if let minRange = Range(match.range(at: 1), in: trimmed),
                   let secRange = Range(match.range(at: 2), in: trimmed),
                   let msRange = Range(match.range(at: 3), in: trimmed),
                   let textRange = Range(match.range(at: 4), in: trimmed) {
                    
                    let min = Double(trimmed[minRange]) ?? 0
                    let sec = Double(trimmed[secRange]) ?? 0
                    let msStr = String(trimmed[msRange])
                    let ms = (Double(msStr) ?? 0) / (msStr.count == 2 ? 100.0 : 1000.0)
                    
                    let time = min * 60.0 + sec + ms
                    let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
                    
                    if !text.isEmpty {
                        result.append(LyricLine(timestamp: time, text: text))
                    }
                }
            }
        }
        
        return result.sorted { $0.timestamp < $1.timestamp }
    }
    
    public static func parsePlainLyrics(_ plain: String, duration: Double) -> [LyricLine] {
        let rawLines = plain.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !rawLines.isEmpty else { return [] }
        
        let total = duration > 10 ? duration : 180.0
        let step = total / Double(rawLines.count)
        
        var result: [LyricLine] = []
        for (i, line) in rawLines.enumerated() {
            result.append(LyricLine(timestamp: Double(i) * step, text: line))
        }
        return result
    }
    
    public static func generateAestheticDemoLyrics(title: String, artist: String) -> [LyricLine] {
        return [
            LyricLine(timestamp: 2.0, text: "counting the boats as they turned for home"),
            LyricLine(timestamp: 6.5, text: "Blue hour on the water"),
            LyricLine(timestamp: 11.0, text: "every light is finding its way back"),
            LyricLine(timestamp: 16.0, text: "hold the moment, hold it slower"),
            LyricLine(timestamp: 21.5, text: "I can hear the city start to glow"),
            LyricLine(timestamp: 26.0, text: "paper boats and silver weather"),
            LyricLine(timestamp: 31.0, text: "all the roads we used to know"),
            LyricLine(timestamp: 36.5, text: "silver tides under velvet skies"),
            LyricLine(timestamp: 42.0, text: "echoes floating through the night")
        ]
    }
    
    // MARK: - Sincronización en Tiempo Real
    
    private func startSyncTimer() {
        syncTimer?.invalidate()
        let t = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.updateCurrentLine()
        }
        t.tolerance = 0.03
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
    }
    
    private func updateCurrentLine() {
        guard !lines.isEmpty else { return }
        let currentPos = MusicService.shared.currentTrack.playbackPosition
        
        var activeIndex = 0
        for (i, line) in lines.enumerated() {
            if currentPos >= line.timestamp {
                activeIndex = i
            } else {
                break
            }
        }
        
        if activeIndex != currentLineIndex {
            currentLineIndex = activeIndex
        }
    }
    
    /// Salto interactivo a una línea específica
    public func seekToLine(_ line: LyricLine) {
        MusicService.shared.seek(to: line.timestamp)
    }
}
