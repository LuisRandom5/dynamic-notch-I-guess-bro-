import Foundation

/// Parámetros del movimiento del visualizador, centralizados.
/// (Grosor, separación y alturas en pt viven en PlayerMetrics; esto es sólo el carácter del movimiento.)
public enum VisualizerMotionMetrics {
    /// Piso y techo normalizados mientras suena: las barras casi nunca tocan el máximo
    public static let floor: Double = 0.14
    public static let range: Double = 0.78
    public static let ceiling: Double = 0.90
    /// Perfil de altura por barra: las centrales un poco más altas, como un ecualizador de Apple
    public static let profile: [Double] = [0.80, 0.94, 1.00, 0.97, 0.88, 0.76]
    /// Tres capas de oscilación por barra (Hz mín–máx) y su peso: predomina lo lento y suave
    public static let layers: [(minHz: Double, maxHz: Double, weight: Double)] = [
        (0.22, 0.40, 0.50),
        (0.70, 1.10, 0.32),
        (1.55, 2.35, 0.18),
    ]
    /// Desfase entre barras vecinas: el conjunto se mueve como una ola coherente
    public static let spatialPhase: Double = 0.75
    /// Capas que comparten frecuencia entre todas las barras (sólo cambia la fase): dan la identidad común
    public static let sharedLayers: Int = 1
    /// Respiración global lenta (Hz) y cuánto modula la amplitud
    public static let breathHz: Double = 0.11
    public static let breathDepth: Double = 0.22
    /// Pulso redondeado muy sutil para dar sensación musical (NO es el ritmo real de la canción)
    public static let pulseRangeHz: (Double, Double) = (1.6, 2.1)
    public static let pulseAmount: Double = 0.07
    /// Cambio de canción: fundido entre la variación anterior y la nueva
    public static let trackCrossfade: Double = 1.2
    /// Fundidos al reproducir / pausar (los aplica la vista)
    public static let fadeIn: Double = 0.22
    public static let fadeOut: Double = 0.45
}

/// Generador del movimiento de las barras SIN audio: función pura del tiempo y de la semilla de la pista.
/// No representa frecuencias reales ni el ritmo exacto de la canción; es un movimiento orgánico y estable
/// que cambia de carácter con cada pista.
public enum VisualizerMotion {
    public static let bandCount = 6

    /// Niveles 0...1 de las barras en el instante `t` (segundos de reloj) para la pista `seed`.
    public static func musicLevels(at t: Double, seed: UInt64) -> [Float] {
        typealias M = VisualizerMotionMetrics
        let breath = 1 - M.breathDepth * (0.5 + 0.5 * sin(2 * .pi * M.breathHz * t + unit(seed, 0, 1) * 6.283))
        let pulseHz = M.pulseRangeHz.0 + (M.pulseRangeHz.1 - M.pulseRangeHz.0) * unit(seed, 0, 2)
        // Pulso de cresta redondeada (coseno a la cuarta): sube y baja suave, sin golpes
        let pulse = pow(0.5 + 0.5 * cos(2 * .pi * pulseHz * t), 4)

        return (0..<bandCount).map { i in
            var v = 0.0
            for (k, layer) in M.layers.enumerated() {
                // Capa compartida: misma frecuencia en todas las barras → ola coherente que recorre el conjunto.
                // Capas de detalle: frecuencia propia por barra → ninguna barra oscila idéntica a otra.
                let isShared = k < M.sharedLayers
                let hz = layer.minHz + (layer.maxHz - layer.minHz) * unit(seed, isShared ? 0 : i, UInt64(10 + k))
                let jitter = isShared ? 0.25 : 1.2
                let phase = Double(i) * M.spatialPhase * Double(k + 1) + unit(seed, i, UInt64(20 + k)) * jitter
                v += layer.weight * (0.5 + 0.5 * sin(2 * .pi * hz * t + phase))
            }
            // Los graves (izquierda) sienten más el pulso que los agudos
            let pulseWeight = M.pulseAmount * (1.0 - Double(i) / Double(bandCount) * 0.6)
            let level = M.profile[i] * (M.floor + M.range * v * breath) + pulseWeight * pulse
            return Float(min(M.ceiling, max(0, level)))
        }
    }

    /// Niveles de una voz hablando (llamadas): sílabas de ~4-6 Hz agrupadas en palabras y frases con pausas.
    /// La energía vive en los medios (voz humana) y casi nada en los extremos.
    public static func speechLevels(at t: Double, seed: UInt64) -> [Float] {
        let phraseGate = smoothstep(0.18, 0.38, smoothNoise(t / 2.6, seed, 70))
        let syllableRate = 4.6 + 1.4 * smoothNoise(t * 0.3, seed, 71)
        let syllablePhase = t * syllableRate
        let syllableIndex = Int(syllablePhase.rounded(.down))
        let within = syllablePhase - Double(syllableIndex)
        let stress = 0.55 + 0.45 * unit(seed, syllableIndex, 72)
        let syllable = envelope(within / syllableRate, decay: 0.09) * stress
        let voiced = phraseGate * (0.35 + 0.65 * syllable)

        func wobble(_ i: UInt64, _ rate: Double) -> Double { smoothNoise(t * rate, seed, 80 + i) }
        let raw: [Double] = [
            0.10 * voiced + 0.05 * wobble(0, 0.8),
            0.42 * voiced + 0.08 * wobble(1, 1.1),
            0.85 * voiced + 0.10 * wobble(2, 1.6),
            0.92 * voiced + 0.10 * wobble(3, 1.9),
            0.60 * voiced + 0.10 * wobble(4, 2.3),
            0.22 * voiced * syllable + 0.05 * wobble(5, 2.8),
        ]
        return raw.map { Float(min(1, max(0, $0))) }
    }

    // MARK: - Piezas

    private static func envelope(_ x: Double, decay: Double) -> Double {
        let attack = 0.018
        if x < attack { return sqrt(max(0, x) / attack) }
        return exp(-(x - attack) / decay)
    }

    private static func smoothNoise(_ x: Double, _ seed: UInt64, _ salt: UInt64) -> Double {
        let i = Int(x.rounded(.down))
        let f = x - Double(i)
        let a = unit(seed, i, salt)
        let b = unit(seed, i + 1, salt)
        let w = (1 - cos(f * .pi)) / 2
        return a + (b - a) * w
    }

    private static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// Hash determinista → 0...1
    static func unit(_ seed: UInt64, _ index: Int, _ salt: UInt64) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}
