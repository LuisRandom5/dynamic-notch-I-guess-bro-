import Foundation
import AVFoundation

public enum SignalGeneratorType: String, CaseIterable, Identifiable {
    case off = "off"
    case pinkNoise = "pinkNoise"
    case sineSweep = "sineSweep"
    case tone1kHz = "tone1kHz"
    case metronome120 = "metronome120"
    case silence3s = "silence3s"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .off: return "Apagado"
        case .pinkNoise: return "Ruido Rosa (Pink Noise)"
        case .sineSweep: return "Barrido 20Hz-20kHz"
        case .tone1kHz: return "Tono 1kHz (2s On / 2s Off)"
        case .metronome120: return "Metrónomo (120 BPM)"
        case .silence3s: return "Silencio (3 segundos)"
        }
    }
}

/// Generador de señales de prueba nativo con AVAudioEngine y AVAudioSourceNode (Paso 6)
public final class AudioSignalGenerator: ObservableObject {
    public static let shared = AudioSignalGenerator()
    
    @Published public private(set) var activeSignal: SignalGeneratorType = .off
    @Published public var volume: Float = 0.5
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    
    // Generadores internos
    private var sampleRate: Double = 44100.0
    private var phase: Double = 0.0
    private var sweepTime: Double = 0.0
    private var toneTimer: Double = 0.0
    private var metronomeTimer: Double = 0.0
    private var silenceRemaining: Double = 0.0
    
    // Filtro Voss-McCartney para Ruido Rosa preciso (3 polos IIR -3dB/octava)
    private var b0: Float = 0.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0
    private var b3: Float = 0.0
    private var b4: Float = 0.0
    private var b5: Float = 0.0
    private var b6: Float = 0.0
    
    private init() {}
    
    public func setSignal(_ signal: SignalGeneratorType) {
        if signal == .off {
            stop()
            activeSignal = .off
            return
        }
        
        activeSignal = signal
        phase = 0.0
        sweepTime = 0.0
        toneTimer = 0.0
        metronomeTimer = 0.0
        if signal == .silence3s {
            silenceRemaining = 3.0
        }
        
        startEngineIfNeeded()
    }
    
    public func stop() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        sourceNode = nil
        activeSignal = .off
    }
    
    private func startEngineIfNeeded() {
        if audioEngine != nil && audioEngine!.isRunning { return }
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let format = engine.outputNode.outputFormat(forBus: 0)
        self.sampleRate = format.sampleRate > 8000 ? format.sampleRate : 44100.0
        
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            let dt = 1.0 / self.sampleRate
            let currentVol = self.volume
            let signal = self.activeSignal
            
            for frame in 0..<Int(frameCount) {
                var sample: Float = 0.0
                
                switch signal {
                case .off:
                    sample = 0.0
                    
                case .pinkNoise:
                    // Generador Voss-McCartney de Ruido Rosa (caída exacta de -3 dB/octava)
                    let white = Float.random(in: -1.0...1.0)
                    self.b0 = 0.99886 * self.b0 + white * 0.0555179
                    self.b1 = 0.99332 * self.b1 + white * 0.0750759
                    self.b2 = 0.96900 * self.b2 + white * 0.1538520
                    self.b3 = 0.86650 * self.b3 + white * 0.3104856
                    self.b4 = 0.55000 * self.b4 + white * 0.5329522
                    self.b5 = -0.7616 * self.b5 - white * 0.0168980
                    let pink = self.b0 + self.b1 + self.b2 + self.b3 + self.b4 + self.b5 + self.b6 + white * 0.5362
                    self.b6 = white * 0.115926
                    sample = pink * 0.12 * currentVol
                    
                case .sineSweep:
                    // Barrido logarítmico de 20 Hz a 20 kHz cada 5 segundos
                    let sweepPeriod = 5.0
                    self.sweepTime += dt
                    if self.sweepTime >= sweepPeriod { self.sweepTime = 0 }
                    let progress = self.sweepTime / sweepPeriod
                    let freq = 20.0 * pow(1000.0, progress) // 20 Hz a 20,000 Hz
                    self.phase += 2.0 * .pi * freq * dt
                    if self.phase >= 2.0 * .pi { self.phase -= 2.0 * .pi }
                    sample = Float(sin(self.phase)) * 0.45 * currentVol
                    
                case .tone1kHz:
                    // Tono puro de 1 kHz que alterna: 2 segundos encendido, 2 segundos apagado
                    self.toneTimer += dt
                    if self.toneTimer >= 4.0 { self.toneTimer = 0 }
                    let isOn = self.toneTimer < 2.0
                    if isOn {
                        self.phase += 2.0 * .pi * 1000.0 * dt
                        if self.phase >= 2.0 * .pi { self.phase -= 2.0 * .pi }
                        sample = Float(sin(self.phase)) * 0.40 * currentVol
                    } else {
                        sample = 0.0
                    }
                    
                case .metronome120:
                    // Metrónomo a 120 BPM (1 pulso cada 500 ms de 30 ms con click resonante)
                    let beatPeriod = 0.500
                    self.metronomeTimer += dt
                    if self.metronomeTimer >= beatPeriod { self.metronomeTimer = 0 }
                    if self.metronomeTimer < 0.035 {
                        let clickPhase = self.metronomeTimer / 0.035
                        let freq = 2200.0 * (1.0 - clickPhase) + 800.0
                        let click = sin(clickPhase * .pi * 2.0 * freq * 0.035) * exp(-clickPhase * 6.0)
                        sample = Float(click) * 0.70 * currentVol
                    } else {
                        sample = 0.0
                    }
                    
                case .silence3s:
                    if self.silenceRemaining > 0 {
                        self.silenceRemaining -= dt
                        sample = 0.0
                    } else {
                        sample = 0.0
                        DispatchQueue.main.async {
                            self.stop()
                        }
                    }
                }
                
                for buffer in ablPointer {
                    let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
                    ptr?[frame] = sample
                }
            }
            
            return noErr
        }
        
        self.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
        } catch {
            print("[AudioSignalGenerator] Error al iniciar AVAudioEngine: \(error)")
        }
    }
}
