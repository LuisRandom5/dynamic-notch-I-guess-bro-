import Foundation
import QuartzCore
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
    @Published public private(set) var currentLineIndex: Int = -1
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasSyncedLyrics: Bool = false
    @Published public private(set) var isInstrumental: Bool = false
    
    private var currentTrackKey: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    
    // Caché en memoria para evitar re-descargas entre saltos de pista
    private var lyricsCache: [String: [LyricLine]] = [:]
    private var cachedSyncedFlags: [String: Bool] = [:]
    
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
                self.currentLineIndex = -1
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
                self.hasSyncedLyrics = self.cachedSyncedFlags[key] ?? false
                self.isInstrumental = false
                self.currentLineIndex = -1
            }
            return
        }
        
        fetchLyrics(title: cleanTitle, artist: cleanArtist, duration: track.duration, key: key)
    }
    
    public func fetchLyrics(title: String, artist: String, duration: Double, key: String) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let cleanTitle = Self.cleanTitle(title)
            let primaryArtist = Self.primaryArtist(artist)
            
            // 1. Coincidencia exacta (título original y limpio) → 2. búsqueda flexible eligiendo la versión
            //    sincronizada cuya duración más se parezca a la de la canción que suena
            var best: (synced: String?, plain: String?, instrumental: Bool)? = nil
            for candidateTitle in Array(Set([title, cleanTitle])) {
                if let found = self.requestGet(title: candidateTitle, artist: primaryArtist, duration: duration),
                   found.synced != nil {
                    best = found
                    break
                } else if best == nil, let found = self.requestGet(title: candidateTitle, artist: primaryArtist, duration: duration) {
                    best = found
                }
            }
            if best?.synced == nil, let searched = self.requestSearch(title: cleanTitle, artist: primaryArtist, duration: duration) {
                if searched.synced != nil || best == nil {
                    best = searched
                }
            }
            
            if let synced = best?.synced, !synced.isEmpty {
                let parsed = Self.parseLRC(synced)
                if !parsed.isEmpty {
                    self.publish(parsed, synced: true, instrumental: best?.instrumental ?? false, key: key)
                    return
                }
            }
            if let plain = best?.plain, !plain.isEmpty {
                // Sin tiempos: se muestra como letra fija, sin fingir sincronía
                self.publish(Self.parsePlainLyrics(plain), synced: false, instrumental: best?.instrumental ?? false, key: key)
                return
            }
            if best?.instrumental == true {
                self.publish([], synced: false, instrumental: true, key: key)
                return
            }
            self.fallbackToAppleMusicOrDemo(title: title, artist: artist, key: key)
        }
    }
    
    private func publish(_ lines: [LyricLine], synced: Bool, instrumental: Bool, key: String) {
        DispatchQueue.main.async {
            guard self.currentTrackKey == key else { return }
            self.lines = lines
            self.hasSyncedLyrics = synced
            self.isInstrumental = instrumental
            self.isLoading = false
            self.currentLineIndex = -1
            // Sólo las canciones recientes (la caché no crece sin fin en sesiones largas)
            if self.lyricsCache.count > 40 {
                self.lyricsCache.removeAll(keepingCapacity: true)
                self.cachedSyncedFlags.removeAll(keepingCapacity: true)
            }
            self.lyricsCache[key] = lines
            self.cachedSyncedFlags[key] = synced
        }
    }
    
    private func requestGet(title: String, artist: String, duration: Double) -> (synced: String?, plain: String?, instrumental: Bool)? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration > 10 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components?.queryItems = items
        guard let url = components?.url, let json = Self.fetchJSON(url) as? [String: Any] else { return nil }
        return Self.entry(json)
    }
    
    private func requestSearch(title: String, artist: String, duration: Double) -> (synced: String?, plain: String?, instrumental: Bool)? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        guard let url = components?.url, let results = Self.fetchJSON(url) as? [[String: Any]], !results.isEmpty else { return nil }
        // Preferir con letra sincronizada y duración cercana (±4 s); si no, la más cercana en duración
        let scored = results.map { item -> (item: [String: Any], score: Double) in
            let d = item["duration"] as? Double ?? 0
            let durationGap = duration > 10 && d > 0 ? abs(d - duration) : 30
            let hasSynced = (item["syncedLyrics"] as? String)?.isEmpty == false
            return (item, (hasSynced ? 0 : 1000) + durationGap)
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        if duration > 10, let d = best.item["duration"] as? Double, d > 0, abs(d - duration) > 8 { return nil }
        return Self.entry(best.item)
    }
    
    private static func entry(_ json: [String: Any]) -> (synced: String?, plain: String?, instrumental: Bool) {
        (json["syncedLyrics"] as? String, json["plainLyrics"] as? String, json["instrumental"] as? Bool ?? false)
    }
    
    private static func fetchJSON(_ url: URL) -> Any? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("DynamicNotch/1.0 (macOS; github.com/LuisRandom5)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Any?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = try? JSONSerialization.jsonObject(with: data)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 7)
        return result
    }
    
    /// "Song (feat. X) - Remastered 2011" → "Song"
    static func cleanTitle(_ title: String) -> String {
        var t = title
        for pattern in [#"\s*[\(\[](feat|ft|with|con)\.?[^\)\]]*[\)\]]"#,
                        #"\s*[\(\[][^\)\]]*(remaster|version|versión|live|en vivo|edit|mix|explicit|mono|stereo)[^\)\]]*[\)\]]"#,
                        #"\s+-\s+.*(remaster|version|versión|live|en vivo|edit|mix).*$"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// "Eminem, Dr. Dre & 50 Cent" → "Eminem"
    static func primaryArtist(_ artist: String) -> String {
        let separators = [",", " & ", " x ", " X ", " feat", " ft.", " y "]
        var a = artist
        for sep in separators {
            if let r = a.range(of: sep) { a = String(a[..<r.lowerBound]) }
        }
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func fallbackToAppleMusicOrDemo(title: String, artist: String, key: String) {
        // Última opción: la letra que Apple Music tenga guardada en la pista (sin tiempos)
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
        var errorInfo: NSDictionary?
        if let script = NSAppleScript(source: appleMusicScript) {
            let res = script.executeAndReturnError(&errorInfo)
            let lyrics = res.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !lyrics.isEmpty {
                publish(Self.parsePlainLyrics(lyrics), synced: false, instrumental: false, key: key)
                return
            }
        }
        // Sin letra: nunca se inventa una (antes se mostraba una letra de demostración ajena a la canción)
        publish([], synced: false, instrumental: false, key: key)
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
    
    public static func parsePlainLyrics(_ plain: String) -> [LyricLine] {
        plain.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricLine(timestamp: 0, text: $0) }
    }
    
    // MARK: - Sincronización en Tiempo Real
    
    // Reloj de canción interpolado: MusicService reporta la posición en pasos de ~1 s; entre reportes
    // se avanza con el reloj real para que el cambio de línea caiga en el momento justo.
    private var anchorPosition: Double = 0
    private var anchorTime: Double = CACurrentMediaTime()
    private var lastReportedPosition: Double = -1
    /// Las líneas aparecen un poco antes de cantarse, como en Apple Music
    private static let lineLead: Double = 0.15
    
    /// Posición estimada de la canción (s), continua entre reportes.
    public var estimatedPosition: Double {
        let track = MusicService.shared.currentTrack
        let now = CACurrentMediaTime()
        let estimate = anchorPosition + (track.isPlaying ? now - anchorTime : 0)
        return estimate
    }
    
    private func startSyncTimer() {
        syncTimer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCurrentLine()
        }
        t.tolerance = 0.01
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
    }
    
    private func updateClock() {
        let track = MusicService.shared.currentTrack
        let now = CACurrentMediaTime()
        let estimate = anchorPosition + (now - anchorTime)
        if !track.isPlaying {
            // En pausa el reloj se congela en la última posición conocida
            if track.playbackPosition != lastReportedPosition {
                lastReportedPosition = track.playbackPosition
                anchorPosition = track.playbackPosition
            }
            anchorTime = now
            return
        }
        if track.playbackPosition != lastReportedPosition {
            let reported = track.playbackPosition
            // MusicService rellena entre lecturas reales sumando +1 s con un temporizador: esos pasos no
            // marcan el instante real, así que se ignoran (sólo cuentan las lecturas de la app de música)
            let isSyntheticTick = abs(reported - lastReportedPosition - 1.0) < 0.0001
            lastReportedPosition = reported
            guard !isSyntheticTick else { return }
            let error = reported - estimate
            if abs(error) > 1.0 {
                // Salto (búsqueda, cambio de canción): re-anclar
                anchorPosition = reported
                anchorTime = now
            } else {
                // Lectura real: corregir con suavidad hacia ella. Antes sólo se corregía con > 1.2 s de
                // error y la letra podía ir hasta un segundo adelantada o atrasada sin arreglarse nunca
                anchorPosition += error * 0.35
            }
        }
    }
    
    private func updateCurrentLine() {
        updateClock()
        guard hasSyncedLyrics, !lines.isEmpty else { return }
        // Lo que se OYE va atrasado respecto a la reproducción por la latencia de la salida (AirPods ~170 ms):
        // la letra se sincroniza con lo que se oye
        let position = estimatedPosition - AudioSpectrumEngine.shared.outputLatencySec + Self.lineLead
        
        var activeIndex = -1
        for (i, line) in lines.enumerated() {
            if position >= line.timestamp {
                activeIndex = i
            } else {
                break
            }
        }
        
        if activeIndex != currentLineIndex {
            currentLineIndex = activeIndex
        }
    }
    
    /// Segundos hasta la siguiente línea (para mostrar los puntos "•••" en partes instrumentales)
    public var gapUntilNextLine: Double? {
        let next = currentLineIndex + 1
        guard hasSyncedLyrics, next < lines.count else { return nil }
        return lines[next].timestamp - estimatedPosition
    }
    
    /// Salto interactivo a una línea específica
    public func seekToLine(_ line: LyricLine) {
        guard hasSyncedLyrics else { return }
        MusicService.shared.seek(to: line.timestamp)
        // Re-anclar el reloj al instante elegido para que la línea se ilumine de inmediato
        anchorPosition = line.timestamp
        anchorTime = CACurrentMediaTime()
    }
}
