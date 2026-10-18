import Foundation
import Accelerate

/// Tempo real de la canción para cuando el audio no se puede escuchar.
///
/// macOS entrega SILENCIO a cualquier captura de audio del sistema mientras suena contenido protegido
/// (DRM: Apple Music, Netflix, YouTube Music en Safari…). Ahí las barras no pueden seguir el audio, pero sí
/// el ritmo: se descarga el avance de 30 s de la canción (API pública de iTunes), se calcula su BPM con la
/// autocorrelación de la envolvente de golpes y el motor procedural late a ese tempo.
public final class SongTempoAnalyzer {
    public static let shared = SongTempoAnalyzer()

    public struct Profile {
        public let bpm: Double
        /// Qué tan marcado es el golpe (0…1): canciones muy rítmicas pulsan más
        public let beatStrength: Double
    }

    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.TempoAnalyzer", qos: .utility)
    private var cache: [String: Profile] = [:]
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    private init() {}

    /// Perfil ya calculado de la pista (nil mientras se analiza o si no hay avance disponible)
    public func profile(for key: String) -> Profile? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    public func request(title: String, artist: String, key: String) {
        lock.lock()
        let pending = cache[key] != nil || inFlight.contains(key)
        if !pending { inFlight.insert(key) }
        lock.unlock()
        guard !pending, !title.isEmpty else { return }

        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else { return }

        URLSession.shared.dataTask(with: searchURL) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let previewString = first["previewUrl"] as? String,
                  let previewURL = URL(string: previewString) else { return }
            URLSession.shared.dataTask(with: previewURL) { audio, _, _ in
                guard let audio = audio, !audio.isEmpty else { return }
                self.queue.async {
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("dn_tempo_\(abs(key.hashValue)).m4a")
                    guard (try? audio.write(to: file, options: .atomic)) != nil else { return }
                    let samples = AudioSpectrumEngine.decodeAudioFileToMonoPCM(url: file, targetSampleRate: Self.sampleRate)
                    try? FileManager.default.removeItem(at: file)
                    guard let profile = Self.analyze(samples) else { return }
                    self.lock.lock()
                    self.cache[key] = profile
                    self.inFlight.remove(key)
                    self.lock.unlock()
                    DNDLogger.log("SongTempoAnalyzer: \(title) → \(String(format: "%.1f", profile.bpm)) BPM (golpe \(String(format: "%.2f", profile.beatStrength)))")
                }
            }.resume()
        }.resume()
    }

    // MARK: - Análisis

    private static let sampleRate: Double = 11025
    private static let hop = 256 // ≈ 43 cuadros por segundo

    static func analyze(_ samples: [Float]) -> Profile? {
        let frameCount = samples.count / hop
        guard frameCount > 400 else { return nil }
        let fps = sampleRate / Double(hop)

        // Envolvente de golpes: energía por cuadro en escala logarítmica, sólo subidas (flux)
        var energy = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buf in
            for f in 0..<frameCount {
                var ms: Float = 0
                vDSP_measqv(buf.baseAddress! + f * hop, 1, &ms, vDSP_Length(hop))
                energy[f] = log10(1e-6 + ms)
            }
        }
        var onset = [Float](repeating: 0, count: frameCount)
        for f in 1..<frameCount { onset[f] = max(0, energy[f] - energy[f - 1]) }
        var mean: Float = 0
        vDSP_meanv(onset, 1, &mean, vDSP_Length(frameCount))
        var centered = onset.map { $0 - mean }

        // Autocorrelación en el rango 70–180 BPM, con preferencia suave por 90–140 (tempo percibido)
        let minLag = Int(fps * 60 / 180), maxLag = Int(fps * 60 / 70)
        var best = (lag: 0, score: -Float.infinity)
        var scores = [Float](repeating: 0, count: maxLag + 2)
        centered.withUnsafeMutableBufferPointer { c in
            for lag in max(1, minLag - 1)...(maxLag + 1) {
                var dot: Float = 0
                vDSP_dotpr(c.baseAddress!, 1, c.baseAddress! + lag, 1, &dot, vDSP_Length(frameCount - lag))
                scores[lag] = dot
            }
        }
        for lag in minLag...maxLag {
            let bpm = 60 * fps / Double(lag)
            let preference = Float(exp(-pow(log2(bpm / 118), 2) / 0.5))
            let score = scores[lag] * (0.6 + 0.4 * preference)
            if score > best.score { best = (lag, score) }
        }
        guard best.lag > 0 else { return nil }
        // Refinar con interpolación parabólica para no perder precisión (la deriva se acumula en minutos)
        let y0 = scores[best.lag - 1], y1 = scores[best.lag], y2 = scores[best.lag + 1]
        let denom = y0 - 2 * y1 + y2
        let offset = denom != 0 ? Double(0.5 * (y0 - y2) / denom) : 0
        let lag = Double(best.lag) + max(-0.5, min(0.5, offset))
        let bpm = 60 * fps / lag

        var zeroLag: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &zeroLag, vDSP_Length(frameCount))
        let strength = zeroLag > 0 ? Double(max(0, min(1, y1 / zeroLag * 3))) : 0.5
        return Profile(bpm: bpm, beatStrength: strength)
    }
}
