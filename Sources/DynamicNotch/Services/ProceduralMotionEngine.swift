import Foundation
import QuartzCore

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

    private init() {}

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
        lock.unlock()

        return Self.resample(levels, to: barCount)
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
