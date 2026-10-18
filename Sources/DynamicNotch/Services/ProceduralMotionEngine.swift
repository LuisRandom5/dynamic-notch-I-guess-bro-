import Foundation
import QuartzCore
import Combine

/// Proveedor predeterminado del visualizador: movimiento procedural conectado al estado de reproducción,
/// sin capturar audio ni micrófono (ver AudioSpectrumEngine.systemCaptureAllowed).
///
/// - El movimiento sale de `VisualizerMotion` y depende del reloj real, no de cuántas veces se le llame:
///   varios visualizadores a la vez muestran exactamente lo mismo.
/// - Al cambiar de canción, la variación anterior se funde con la nueva (no hay reinicio brusco).
/// - Reproducir/pausar lo resuelve la vista con un fundido; aquí el movimiento sigue corriendo para que
///   las barras nunca se congelen en alturas accidentales.
public final class ProceduralMotionEngine {
    public static let shared = ProceduralMotionEngine()

    private let lock = NSLock()
    private var trackKey: String = ""
    private var seed: UInt64 = 5381
    private var previousSeed: UInt64 = 5381
    private var trackChangedAt: Double = -1_000
    /// Momento en que llegó el tempo real de la pista actual (para fundirlo sin salto)
    private var tempoArrivedAt: Double?

    private var tempoPrefetch: AnyCancellable?

    private init() {}

    /// Analiza el tempo de cada canción en cuanto empieza (no sólo cuando el audio llega en silencio), para
    /// tenerlo listo si el contenido resulta protegido. Se llama una vez al arrancar.
    public func startPrefetchingTempo() {
        guard tempoPrefetch == nil else { return }
        tempoPrefetch = MusicService.shared.$currentTrack
            .map { ($0.title, $0.artist) }
            .removeDuplicates { $0 == $1 }
            .sink { title, artist in
                guard !title.isEmpty else { return }
                let key = "\(title.lowercased())|\(artist.lowercased())"
                SongTempoAnalyzer.shared.request(title: title, artist: artist, key: key)
            }
    }

    /// Niveles 0...1 para `barCount` barras (6 = una por barra; 4 = mezcla de vecinas).
    public func getMagnitudes(barCount: Int = 6) -> [Float] {
        let track = MusicService.shared.currentTrack
        let now = CACurrentMediaTime()

        lock.lock()
        let key = "\(track.title.lowercased())|\(track.artist.lowercased())"
        if key != trackKey {
            // Cambio rápido de canción a media transición: partir de la variación que domina en pantalla
            let previousBlend = Self.smoothstep((now - trackChangedAt) / VisualizerMotionMetrics.trackCrossfade)
            previousSeed = previousBlend >= 0.5 ? seed : previousSeed
            trackKey = key
            seed = Self.seed(for: key)
            trackChangedAt = now
            tempoArrivedAt = nil
            // Tempo real de la canción (por si el audio llega protegido y en silencio)
            SongTempoAnalyzer.shared.request(title: track.title, artist: track.artist, key: key)
        }
        let blend = Self.smoothstep((now - trackChangedAt) / VisualizerMotionMetrics.trackCrossfade)
        let current = VisualizerMotion.musicLevels(at: now, seed: seed)
        let levels: [Float]
        if blend < 1 {
            let previous = VisualizerMotion.musicLevels(at: now, seed: previousSeed)
            levels = zip(previous, current).map { $0 + ($1 - $0) * Float(blend) }
        } else {
            levels = current
        }
        var output = levels
        if let tempo = SongTempoAnalyzer.shared.profile(for: key), track.isPlaying {
            if tempoArrivedAt == nil { tempoArrivedAt = now }
            let fade = Self.smoothstep((now - (tempoArrivedAt ?? now)) / 1.0)
            output = Self.beatLevels(organic: levels, tempo: tempo, fade: fade)
        }
        lock.unlock()
        return Self.resample(output, to: barCount)
    }
    
    /// Golpes al tempo real de la canción, sobre la posición de reproducción (lo que se oye, con la latencia
    /// de la salida): bombo en cada tiempo en los graves, caja en 2 y 4 en los medios, contratiempos de
    /// platillo en los agudos. Se mezcla con el movimiento orgánico según qué tan rítmica es la pista.
    private static func beatLevels(organic: [Float], tempo: SongTempoAnalyzer.Profile, fade: Double) -> [Float] {
        let position = LyricsService.shared.estimatedPosition - AudioSpectrumEngine.shared.outputLatencySec
        let beats = max(0, position) * tempo.bpm / 60
        let beatIndex = beats.rounded(.down)
        let phase = beats - beatIndex
        let kick = exp(-phase * 7)
        let backbeat = Int(beatIndex) % 2 == 1 ? exp(-phase * 9) : 0
        let eighths = beats * 2
        let hat = exp(-(eighths - eighths.rounded(.down)) * 14)
        let pattern: [Double] = [
            0.22 + 0.78 * kick,
            0.24 + 0.64 * kick + 0.12 * backbeat,
            0.28 + 0.22 * kick + 0.48 * backbeat,
            0.28 + 0.52 * backbeat + 0.18 * hat,
            0.24 + 0.16 * backbeat + 0.58 * hat,
            0.20 + 0.70 * hat,
        ]
        let mix = (0.45 + 0.30 * tempo.beatStrength) * fade
        return (0..<organic.count).map { i in
            let beat = Float(pattern[min(i, pattern.count - 1)] * VisualizerMotionMetrics.profile[min(i, 5)])
            let value = organic[i] * Float(1 - mix) + beat * Float(mix)
            return min(Float(VisualizerMotionMetrics.ceiling), max(0, value))
        }
    }
    
    // MARK: - Utilidades

    private static func seed(for key: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private static func resample(_ levels: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard count != levels.count else { return levels }
        return (0..<count).map { i in
            let pos = (Double(i) + 0.5) / Double(count) * Double(levels.count) - 0.5
            let lo = max(0, min(levels.count - 1, Int(pos.rounded(.down))))
            let hi = min(levels.count - 1, lo + 1)
            let f = Float(max(0, min(1, pos - Double(lo))))
            return levels[lo] * (1 - f) + levels[hi] * f
        }
    }
}
