import Foundation

/// Sintetizador de "groove" para el visualizador, sin capturar audio.
///
/// Es una función pura del tiempo de la canción: dado el segundo `t`, el tempo y la semilla de la pista,
/// devuelve el nivel de 6 barras (graves → agudos). Imita lo que un analizador vería en música real:
/// - Bombo en los graves, caja en los medios y hi-hats en los agudos, con patrones por pista.
/// - Ataque rápido (~18 ms) y caídas por instrumento, velocidad "humana" por golpe.
/// - Capas sostenidas (bajo, voz, ambiente) que se mueven lento para que nunca se vea mecánico.
/// - Secciones de 8 compases con más o menos energía y redobles al final de cada frase de 4.
/// Al ser determinista, varios visualizadores a la vez muestran exactamente lo mismo.
public enum GrooveSynth {
    public static let bandCount = 6

    /// Patrones de 16 semicorcheas por compás.
    private struct Pattern {
        let kick: Set<Int>
        let snare: Set<Int>
        let ghost: Set<Int>
        let hats: Set<Int>
        let hatAccents: Set<Int>
    }

    private static let patterns: [Pattern] = [
        // Four-on-the-floor (pop/electrónica)
        Pattern(kick: [0, 4, 8, 12], snare: [4, 12], ghost: [], hats: [2, 6, 10, 14], hatAccents: [2, 6, 10, 14]),
        // Rock/pop clásico
        Pattern(kick: [0, 8, 10], snare: [4, 12], ghost: [7], hats: [0, 2, 4, 6, 8, 10, 12, 14], hatAccents: [0, 4, 8, 12]),
        // Hip-hop / R&B
        Pattern(kick: [0, 7, 10], snare: [4, 12], ghost: [14], hats: Set(0..<16), hatAccents: [0, 4, 8, 12]),
        // Pop sincopado / reggaetón ligero
        Pattern(kick: [0, 6, 8], snare: [3, 6, 11, 14], ghost: [], hats: [0, 2, 4, 6, 8, 10, 12, 14], hatAccents: [2, 6, 10, 14]),
    ]

    // MARK: - API

    /// Tempo por defecto derivado de la pista (88–126 BPM) cuando no se conoce el real.
    public static func fallbackBPM(seed: UInt64) -> Double {
        88 + Double(seed % 39)
    }

    /// Niveles 0...1 de las 6 barras en el segundo `t` de la canción.
    public static func levels(at t: Double, bpm: Double, seed: UInt64) -> [Float] {
        let pattern = patterns[Int(seed % UInt64(patterns.count))]
        let secPerStep = 60.0 / max(40, bpm) / 4.0 // duración de una semicorchea
        let stepPos = max(0, t) / secPerStep
        let step = Int(stepPos.rounded(.down))
        let bar = step / 16

        // Energía por sección (8 compases) y entrada más suave en los primeros 2 compases
        let section = bar / 8
        var energy = 0.70 + 0.30 * unit(seed, section, 991)
        if bar < 2 { energy *= 0.78 }

        let kick = hits(pattern.kick, stepPos: stepPos, secPerStep: secPerStep, decay: 0.16, seed: seed, salt: 1)
        let snareMain = hits(pattern.snare, stepPos: stepPos, secPerStep: secPerStep, decay: 0.19, seed: seed, salt: 2)
        let ghost = hits(pattern.ghost, stepPos: stepPos, secPerStep: secPerStep, decay: 0.09, seed: seed, salt: 3) * 0.45
        let hatsBase = hits(pattern.hats, stepPos: stepPos, secPerStep: secPerStep, decay: 0.10, seed: seed, salt: 4)
        let hatsAccent = hits(pattern.hatAccents, stepPos: stepPos, secPerStep: secPerStep, decay: 0.13, seed: seed, salt: 5)
        let hats = max(hatsBase * 0.62, hatsAccent)

        // Redoble en la última negra de cada frase de 4 compases
        let stepInBar = step % 16
        var fill = 0.0
        if bar % 4 == 3 && stepInBar >= 12 {
            fill = hits(Set(12..<16), stepPos: stepPos, secPerStep: secPerStep, decay: 0.08, seed: seed, salt: 6) * 0.8
        }
        let snare = max(snareMain, ghost, fill)

        // Capas sostenidas: bajo (sigue al bombo con cola larga), voz/melodía y ambiente
        // El bajo acompaña al bombo con una cola más larga, sobre un piso que se mueve lento
        let kickTail = hits(pattern.kick, stepPos: stepPos, secPerStep: secPerStep, decay: 0.34, seed: seed, salt: 1)
        let bass = 0.15 + 0.55 * kickTail + 0.30 * smoothNoise(t * 0.9, seed, 11)
        let vocalGate = smoothstep(0.35, 0.65, smoothNoise(t * 0.22, seed, 12)) // la voz entra y sale por frases
        let vocal = vocalGate * (0.45 + 0.55 * smoothNoise(t * 2.4, seed, 13))
        func pad(_ i: UInt64, _ rate: Double) -> Double { smoothNoise(t * rate, seed, 20 + i) }

        let raw: [Double] = [
            0.86 * kick + 0.16 * bass + 0.12 * pad(0, 0.45),
            0.48 * kick + 0.46 * bass + 0.16 * pad(1, 0.55) + 0.10 * snare,
            0.40 * snare + 0.30 * vocal + 0.18 * pad(2, 0.70) + 0.14 * kick,
            0.46 * snare + 0.42 * vocal + 0.16 * pad(3, 0.85),
            0.50 * hats + 0.24 * snare + 0.20 * vocal + 0.14 * pad(4, 1.00),
            0.66 * hats + 0.14 * snare + 0.20 * pad(5, 1.20),
        ]

        return raw.map { value in
            // Compresión suave: los golpes llegan arriba sin saturar todas las barras a la vez
            let compressed = 1.0 - exp(-1.9 * value * energy)
            return Float(min(1.0, max(0.0, compressed / 0.85)))
        }
    }

    // MARK: - Piezas

    /// Envolvente del golpe más reciente del patrón (busca hasta un compás atrás).
    private static func hits(_ steps: Set<Int>, stepPos: Double, secPerStep: Double, decay: Double, seed: UInt64, salt: UInt64) -> Double {
        guard !steps.isEmpty else { return 0 }
        let current = Int(stepPos.rounded(.down))
        var best = 0.0
        // Dos golpes recientes: si se encadenan rápido, la caída del anterior sigue sumando
        var found = 0
        var k = current
        while k >= current - 16 && k >= 0 && found < 2 {
            if steps.contains(k % 16) {
                // Micro-desfase humano de hasta ±6 ms
                let jitter = (unit(seed, k, salt &+ 50) - 0.5) * 0.012
                let since = (stepPos - Double(k)) * secPerStep - jitter
                if since >= 0 {
                    let velocity = 0.72 + 0.28 * unit(seed, k, salt)
                    best = max(best, envelope(since, decay: decay) * velocity)
                    found += 1
                }
            }
            k -= 1
        }
        return best
    }

    /// Ataque de 18 ms (curva cóncava) y caída exponencial.
    private static func envelope(_ x: Double, decay: Double) -> Double {
        let attack = 0.018
        if x < attack { return sqrt(x / attack) }
        return exp(-(x - attack) / decay)
    }

    /// Ruido de valor suavizado en 0...1 (interpolación coseno entre puntos pseudoaleatorios).
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
    private static func unit(_ seed: UInt64, _ index: Int, _ salt: UInt64) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}
