import Foundation
import SwiftUI
import AppKit

/// Motor procedimental de movimiento armónico para el visualizador musical.
/// 100% privado: cero hardware de entrada, cero capturas de micrófono ni audio global.
/// Genera ondas continuas armónicas, balística analógica (ataque ~45ms, decaimiento ~180ms)
/// y coherencia espacial entre barras sincronizada con el estado de reproducción y la canción.
public final class ProceduralMotionEngine: ObservableObject {
    public static let shared = ProceduralMotionEngine()
    
    // Cache de fases y semillas armónicas por pista
    private var currentSeed: UInt64 = 0
    private var currentTrackKey: String = ""
    private var lastUpdateTime: Double = CACurrentMediaTime()
    
    // Fases continuas para interpolación sin discontinuidades
    private var phases: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var baseFrequencies: [Double] = [1.4, 2.1, 1.8, 2.6, 3.1, 3.7]
    
    // Envolvente balística E(t)
    private var currentEnvelope: Double = 0.0
    private var smoothedLevels: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    
    private let lock = NSLock()
    
    private init() {
        resetWithTrack(title: "", artist: "")
    }
    
    public func resetWithTrack(title: String, artist: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = "\(title.lowercased())|\(artist.lowercased())"
        guard key != currentTrackKey else { return }
        currentTrackKey = key
        
        // Generar semilla determinista a partir del título y artista
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        currentSeed = hash
        
        // Frecuencias base derivadas de la identidad de la canción (1.2 Hz a 3.8 Hz)
        let s0 = Double((hash & 0xFF)) / 255.0
        let s1 = Double(((hash >> 8) & 0xFF)) / 255.0
        let s2 = Double(((hash >> 16) & 0xFF)) / 255.0
        let s3 = Double(((hash >> 24) & 0xFF)) / 255.0
        let s4 = Double(((hash >> 32) & 0xFF)) / 255.0
        let s5 = Double(((hash >> 40) & 0xFF)) / 255.0
        
        baseFrequencies = [
            1.2 + s0 * 0.9,  // Sub-bass rhythm: ~1.2 - 2.1 Hz
            1.6 + s1 * 1.0,  // Bass: ~1.6 - 2.6 Hz
            2.0 + s2 * 1.1,  // Low-mids: ~2.0 - 3.1 Hz
            2.2 + s3 * 1.2,  // High-mids: ~2.2 - 3.4 Hz
            2.5 + s4 * 1.1,  // Presence: ~2.5 - 3.6 Hz
            2.8 + s5 * 1.0   // Brilliance: ~2.8 - 3.8 Hz
        ]
    }
    
    /// Calcula las magnitudes normalizadas [0.0 ... 1.0] para N barras (4 o 6)
    public func getMagnitudes(barCount: Int = 6) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let track = MusicService.shared.currentTrack
        let isPlaying = track.isPlaying
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0.001, now - lastUpdateTime))
        lastUpdateTime = now
        
        // Actualizar semilla si cambió la pista
        if !track.title.isEmpty {
            let key = "\(track.title.lowercased())|\(track.artist.lowercased())"
            if key != currentTrackKey {
                let oldPhases = phases
                lock.unlock()
                resetWithTrack(title: track.title, artist: track.artist)
                lock.lock()
                // Preservar continuidad de fases
                for i in 0..<min(phases.count, oldPhases.count) {
                    phases[i] = oldPhases[i].truncatingRemainder(dividingBy: 2.0 * .pi)
                }
            }
        }
        
        // Envolvente balística: Ataque rápido (tau ~45ms), Decaimiento suave (tau ~180ms)
        let targetEnvelope: Double = isPlaying ? 1.0 : 0.0
        let tau: Double = (targetEnvelope > currentEnvelope) ? 0.045 : 0.180
        let alpha = 1.0 - exp(-dt / tau)
        currentEnvelope += (targetEnvelope - currentEnvelope) * alpha
        
        if currentEnvelope < 0.005 {
            currentEnvelope = 0.0
            return [Float](repeating: 0.0, count: barCount)
        }
        
        // Reducir movimiento: devolver alturas fijas armónicas sin oscilar
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let staticProfile: [Double] = [0.45, 0.70, 0.55, 0.80, 0.60, 0.50]
            var out = [Float]()
            for i in 0..<barCount {
                let val = Float((staticProfile[safe: i] ?? 0.5) * currentEnvelope)
                out.append(val)
            }
            return out
        }
        
        // Multiplicador de velocidad de animación
        let speed = AnimationSpeedManager.shared.speedMultiplier
        
        // Síntesis armónica coherente por barra
        var results = [Float]()
        results.reserveCapacity(barCount)
        
        let count = max(1, barCount)
        for i in 0..<count {
            let freqIndex = min(i, baseFrequencies.count - 1)
            let w1 = baseFrequencies[freqIndex] * speed
            
            // Avanzar fases continuas
            phases[i] = (phases[i] + w1 * 2.0 * .pi * dt).truncatingRemainder(dividingBy: 2.0 * .pi * 1000.0)
            
            let t = phases[i]
            // Desfase espacial armónico para curvatura orgánica continua tipo Apple Music entre barras vecinas
            let spatialPhase = (Double(i) / Double(count)) * (1.2 * .pi)
            
            let phi1 = spatialPhase
            let phi2 = spatialPhase * 1.5 + 0.4
            let phi3 = spatialPhase * 0.7 + 0.9
            
            let h1 = 0.55 * sin(t + phi1)
            let h2 = 0.30 * sin(t * 1.48 + phi2)
            let h3 = 0.15 * cos(t * 0.68 + phi3)
            
            let rawWave = abs(h1 + h2 + h3)
            
            // Modulación de energía por barra
            let barWeight: Double
            if count == 4 {
                let weights = [0.85, 1.05, 0.95, 0.88]
                barWeight = weights[safe: i] ?? 1.0
            } else {
                let weights = [0.88, 1.08, 1.02, 0.96, 0.92, 0.82]
                barWeight = weights[safe: i] ?? 1.0
            }
            
            // Escalar a rango nominal (30% a 85% de amplitud activa)
            let waveMagnitude = min(1.0, max(0.04, rawWave * barWeight))
            let finalLevel = waveMagnitude * currentEnvelope
            
            // Suavizado balístico por barra
            let prev = smoothedLevels[safe: i] ?? 0.0
            let smoothTau = (finalLevel > prev) ? 0.035 : 0.075
            let smoothAlpha = 1.0 - exp(-dt / smoothTau)
            let smoothed = prev + (finalLevel - prev) * smoothAlpha
            if i < smoothedLevels.count {
                smoothedLevels[i] = smoothed
            }
            
            results.append(Float(smoothed))
        }
        
        return results
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
