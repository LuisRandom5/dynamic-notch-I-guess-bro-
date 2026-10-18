import Foundation
import AppKit

/// Motor del visualizador musical sin captura de audio (ver AudioSpectrumEngine.systemCaptureAllowed).
///
/// Mantiene un reloj de canción alineado con la reproducción (avanza sólo mientras suena, se congela en
/// pausa y se re-sincroniza al adelantar/retroceder o cambiar de pista) y le pide a `GrooveSynth` los
/// niveles para ese instante. Usa el BPM real de la pista cuando Apple Music lo conoce; si no, un tempo
/// estable derivado de la canción.
///
/// Todos los visualizadores leen el mismo reloj: llamar varias veces en el mismo cuadro devuelve lo mismo,
/// sin importar cuántas barras haya en pantalla.
public final class ProceduralMotionEngine {
    public static let shared = ProceduralMotionEngine()

    private let lock = NSLock()
    private var trackKey: String = ""
    private var seed: UInt64 = 5381
    private var bpm: Double = 112
    private var songTime: Double = 0
    private var lastReportedPosition: Double = -1
    private var lastClock: Double = CACurrentMediaTime()
    private let bpmQueue = DispatchQueue(label: "com.luisrandom.DynamicNotch.bpm", qos: .utility)

    private init() {}

    /// Niveles 0...1 para `barCount` barras (6 = una por banda; 4 = mezcla de bandas vecinas).
    public func getMagnitudes(barCount: Int = 6) -> [Float] {
        let track = MusicService.shared.currentTrack
        let now = CACurrentMediaTime()

        lock.lock()
        let key = "\(track.title.lowercased())|\(track.artist.lowercased())"
        if key != trackKey {
            startTrack(key: key, track: track)
        }
        if track.isPlaying {
            songTime += min(0.25, now - lastClock) // un salto largo (app dormida) no adelanta la canción de golpe
        }
        lastClock = now
        // Adelantar/retroceder: sólo cuando llega una posición NUEVA que se separa del reloj.
        // (Algunos reproductores web reportan siempre 0; eso no debe reiniciar el ritmo.)
        if track.playbackPosition != lastReportedPosition {
            lastReportedPosition = track.playbackPosition
            if abs(track.playbackPosition - songTime) > 2.5 {
                songTime = max(0, track.playbackPosition)
            }
        }
        let levels = GrooveSynth.levels(at: songTime, bpm: bpm, seed: seed)
        lock.unlock()

        return Self.resample(levels, to: barCount)
    }

    // MARK: - Pista y tempo

    private func startTrack(key: String, track: MusicTrack) {
        trackKey = key
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        seed = hash
        bpm = GrooveSynth.fallbackBPM(seed: hash)
        songTime = max(0, track.playbackPosition)
        lastReportedPosition = track.playbackPosition

        guard track.appSource.lowercased().contains("music") else { return }
        bpmQueue.async { [weak self] in
            guard let found = Self.appleMusicBPM(), (50...220).contains(found) else { return }
            guard let self = self else { return }
            self.lock.lock()
            if self.trackKey == key {
                self.bpm = found
            }
            self.lock.unlock()
        }
    }

    /// BPM que Apple Music guarda en la pista (suele existir en la biblioteca local; 0 en mucho streaming).
    private static func appleMusicBPM() -> Double? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first != nil else { return nil }
        let source = """
        tell application "Music"
            if player state is not stopped then return bpm of current track
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let value = Double(result.int32Value)
        return value > 0 ? value : nil
    }

    // MARK: - Remuestreo

    private static func resample(_ levels: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard count != levels.count else { return levels }
        return (0..<count).map { i in
            // Posición proporcional dentro de las 6 bandas, interpolando entre vecinas
            let pos = (Double(i) + 0.5) / Double(count) * Double(levels.count) - 0.5
            let lo = max(0, min(levels.count - 1, Int(pos.rounded(.down))))
            let hi = min(levels.count - 1, lo + 1)
            let f = Float(max(0, min(1, pos - Double(lo))))
            return levels[lo] * (1 - f) + levels[hi] * f
        }
    }
}
