import Foundation
import Combine
import CoreAudio
import AudioToolbox
import Accelerate
import os.lock
import AVFoundation

/// Diagnóstico de 60 segundos por banda de frecuencia (Paso 1)
public struct BandDiagnostics: Identifiable {
    public var id: Int
    public var label: String
    public var freqRange: String
    public var p10: Float
    public var p50: Float
    public var p90: Float
    public var maxVal: Float
    public var percentAbove90: Double
    public var isSaturating: Bool
}

/// Registro histórico de un fotograma para telemetría
public struct SpectrumTelemetryFrame {
    public let timestamp: Double
    public let raw: [Float]
    public let weighted: [Float]
    public let normalized: [Float]
    public let smoothed: [Float]
    public let peakDB: Float
}

/// Motor de análisis espectral de audio real del sistema a 60 fps
/// Captura audio del sistema vía hardware de entrada (micrófono / línea) y Process Taps (macOS 14.2+)
/// Ejecuta FFT real de 4096 puntos multirresolución con Accelerate (vDSP), AGC Global, compresión tanh y balística IEC profesional
public final class AudioSpectrumEngine: ObservableObject {
    public static let shared = AudioSpectrumEngine()
    
    /// Opción del usuario "Barras que siguen la música" (Ajustes). Si está activa, se captura el audio del
    /// sistema (Process Tap privado) SÓLO mientras algo se reproduce: macOS muestra el indicador morado
    /// únicamente en ese tiempo. Apagada: nunca se crea un tap y las barras usan el motor procedural.
    /// El micrófono nunca se usa.
    public static var systemCaptureAllowed: Bool {
        UserDefaults.standard.object(forKey: realAudioBarsKey) as? Bool ?? true
    }
    private static let realAudioBarsKey = "realAudioBarsEnabled"
    /// El micrófono nunca se usa para el visualizador (ni desde el laboratorio de depuración)
    public static let microphoneCaptureAllowed = false
    
    /// Margen tras pausar antes de soltar la captura: evita que el indicador parpadee entre canciones
    private static let captureReleaseDelay: TimeInterval = 2.5
    
    /// Pipeline experimental que descarga el preview de 30 s de iTunes y le corre FFT a 60 Hz.
    /// Apagado: ese fragmento no está alineado con lo que suena, gasta CPU/red y su salida no llega a las barras
    /// (sin captura, getMagnitudes usa ProceduralMotionEngine + VisualizerMotion).
    public static let previewAnalysisEnabled = false
    
    // Estados públicos
    @Published public private(set) var realAudioBarsEnabled: Bool = AudioSpectrumEngine.systemCaptureAllowed
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isRealAudioActive: Bool = false
    @Published public private(set) var isSilent: Bool = true
    @Published public var isSimulatedMode: Bool = false
    @Published public var enableMicrophoneCapture: Bool = false
    @Published public var enableSystemAudioTap: Bool = true {
        didSet {
            UserDefaults.standard.set(enableSystemAudioTap, forKey: "enableSystemAudioTap")
            UserDefaults.standard.set(enableSystemAudioTap, forKey: "enableSystemAudioTapV4")
            if enableSystemAudioTap {
                setupProcessTapCapture()
            } else {
                teardownProcessTap()
                DispatchQueue.main.async {
                    self.isRealAudioActive = false
                }
            }
        }
    }
    @Published public private(set) var hardwareSampleRate: Float = 48000.0
    
    // Telemetría de 4 Etapas (Paso 1)
    @Published public private(set) var stageRaw: [Float] = [0, 0, 0, 0, 0, 0]
    @Published public private(set) var stageWeighted: [Float] = [0, 0, 0, 0, 0, 0]
    @Published public private(set) var stageNormalized: [Float] = [0, 0, 0, 0, 0, 0]
    @Published public private(set) var stageSmoothed: [Float] = [0, 0, 0, 0, 0, 0]
    @Published public private(set) var highBandsSaturating: Bool = false
    
    // Buffer atómico para la UI (6 magnitudes normalizadas 0.0 ... 1.0 y telemetría en dBFS)
    private var lock = os_unfair_lock_s()
    private var currentMagnitudes: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var currentBandDBs: [Float] = [-60.0, -60.0, -60.0, -60.0, -60.0, -60.0]
    private var currentPeakDB: Float = -60.0
    private var lastIOProcTimestamp: Double = 0.0
    
    // Hardware Input Core Audio IDs
    private var inputDeviceID: AudioObjectID = 0
    private var inputIOProcID: AudioDeviceIOProcID? = nil
    private var hasInputListener: Bool = false
    
    // Process Tap Core Audio IDs (Audio Digital del Sistema)
    private var tapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var tapIOProcID: AudioDeviceIOProcID? = nil
    private var hasOutputListener: Bool = false
    
    // Cola de análisis en hilo secundario de alta prioridad
    private let processingQueue = DispatchQueue(label: "com.dynamicnotch.audiospectrum", qos: .userInteractive)
    
    // Zero-Indicator Real Track Audio Stream Decoder & FFT Feeder (sin indicador de grabación de macOS)
    private var zeroIndicatorTimer: DispatchSourceTimer?
    private var currentDecodedTrackKey: String = ""
    private var decodedTrackSamples: [Float] = []
    private var trackSampleReadIndex: Int = 0
    private var isFetchingTrackPreview: Bool = false
    private var synthPhaseKick: Double = 0.0
    private var synthPhaseBass: Double = 0.0
    private var synthPhaseLowMid: Double = 0.0
    private var synthPhaseHighMid: Double = 0.0
    private var synthPhasePresence: Double = 0.0
    private var synthPhaseHat: Double = 0.0
    private var synthClockTime: Double = 0.0
    
    // Parámetros FFT multirresolución:
    // Ventana activa de 2048 muestras (42.6 ms a 48 kHz, centro de masa a solo 21.3 ms) con zero-padding a 4096 puntos
    // para combinar respuesta de transitorios instantánea con resolución interpolada de 11.7 Hz/bin
    private let fftSize: Int = 4096
    private let halfFFT: Int = 2048
    private let activeWindowSize: Int = 2048
    private let activeHalfFFT: Float = 1024.0
    private var log2n: vDSP_Length = 12
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float] = []
    
    // Ring buffer deslizante sin atraso (siempre retiene las últimas activeWindowSize muestras)
    private var sampleBuffer: [Float] = []
    
    // Envelope, Onset Tracker & AGC state
    private var envelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var filteredBandEnergies: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var bandSlowDB: [Float] = [-56.0, -56.0, -56.0, -56.0, -56.0, -56.0]
    private var prevRawEnergies: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var agcPeakDB: Float = -18.0
    
    // Transición tap real ↔ generador procedural (streams con DRM entregan buffers de 0.0 exacto)
    private var lastNonZeroSampleTime: Double = CFAbsoluteTimeGetCurrent()
    private var lastLiveOutputTime: Double = CFAbsoluteTimeGetCurrent()
    private var liveLevelReference: Float = 0.5
    private var proceduralBlend: Float = 0.0
    private var lastBlendUpdateTime: Double = CFAbsoluteTimeGetCurrent()
    private var bandPeakDB: [Float] = [-18.0, -18.0, -18.0, -18.0, -18.0, -18.0]
    private var heldBandTargets: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var bandJitter: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var lastProcessTime: Double = CFAbsoluteTimeGetCurrent()
    private var lastAudibleTime: Double = CFAbsoluteTimeGetCurrent()
    private var gateIsOpen: Bool = false
    private var transientBoostLevel: Float = 0.0
    
    // Buffer circular de 60 segundos para registro de telemetría y percentiles (Paso 1)
    private var telemetryLog: [SpectrumTelemetryFrame] = []
    private let maxTelemetryFrames: Int = 600 // 60 segundos a 10 Hz
    private var lastTelemetryRecordTime: Double = 0.0
    
    // Retardo configurable para Bluetooth
    private struct DelayedFrame {
        let timestamp: Double
        let values: [Float]
    }
    private var delayQueue: [DelayedFrame] = []
    private var lastDelayedOutput: [Float] = [0, 0, 0, 0, 0, 0]
    
    // Simulación suave cuando el modo simulado se activa manualmente en laboratorio
    private var simBeatClock: Double = 0.0
    private var simEnvelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var lastSimCalculationTime: Double = 0.0
    private var cachedSimMagnitudes: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    
    // Generador orgánico tipo ruido Perlin / armónico (Paso 5)
    private var organicNoisePhase: Double = 0.0
    
    private init() {
        setupAccelerate()
        // En macOS 14.2+, Apple provee CATapDescription con isPrivate = true.
        // Esto captura el audio digital real del sistema (Spotify, Apple Music, YouTube, Safari)
        // de forma 100% privada, sin micrófono y SIN mostrar el indicador naranja/morado de grabación en el notch.
        var tapEnabled = true
        if UserDefaults.standard.object(forKey: "enableSystemAudioTapV4") != nil {
            tapEnabled = UserDefaults.standard.bool(forKey: "enableSystemAudioTapV4")
        } else {
            UserDefaults.standard.set(true, forKey: "enableSystemAudioTapV4")
        }
        tapEnabled = tapEnabled && Self.systemCaptureAllowed
        self.enableSystemAudioTap = tapEnabled
        cleanupOrphanedAggregateDevicesAndTaps()
        // La captura NO arranca aquí: sólo mientras algo se reproduce (ver startPlaybackGatedCapture)
        if Self.previewAnalysisEnabled {
            startZeroIndicatorPipeline()
        }
    }
    
    deinit {
        stopCapture()
        zeroIndicatorTimer?.cancel()
        zeroIndicatorTimer = nil
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Configuración de Accelerate (vDSP con ventana Hann desnormalizada exacta)
    private func setupAccelerate() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // IMPORTANTE: Usar vDSP_HANN_DENORM (pico = 1.0, ganancia coherente = 0.5).
        // El uso previo de vDSP_HANN_NORM escalaba la ventana por sqrt(8/(3*N)) = 0.0255 (-31.86 dB)
        // y luego volvía a dividir por halfFFT, atenuando el audio real 39.2 veces por debajo del Noise Gate.
        hannWindow = [Float](repeating: 0, count: activeWindowSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(activeWindowSize), Int32(vDSP_HANN_DENORM))
    }
    
    public func toggleMicrophoneCapture(_ enable: Bool) {
        enableMicrophoneCapture = enable
        if enable {
            setupHardwareInputCapture()
            registerDefaultInputChangeListener()
        } else {
            if inputDeviceID != 0, let proc = inputIOProcID {
                AudioDeviceStop(inputDeviceID, proc)
                AudioDeviceDestroyIOProcID(inputDeviceID, proc)
                inputIOProcID = nil
                inputDeviceID = 0
            }
            DispatchQueue.main.async {
                self.isRealAudioActive = self.enableSystemAudioTap && (self.aggregateDeviceID != 0)
            }
        }
    }
    
    // MARK: - Captura de Hardware (Micrófono / Entrada Predeterminada)
    private func setupHardwareInputCapture() {
        guard Self.microphoneCaptureAllowed else { return }
        var devID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devID
        )
        guard status == noErr, devID != 0 else {
            return
        }
        self.inputDeviceID = devID
        
        var sr: Float64 = 48000.0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyNominalSampleRate),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        if AudioObjectGetPropertyData(devID, &srAddress, 0, nil, &srSize, &sr) == noErr, sr > 8000.0 {
            self.hardwareSampleRate = Float(sr)
        }
        
        var procID: AudioDeviceIOProcID? = nil
        let sampleRate = self.hardwareSampleRate
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, devID, nil) { [weak self] _, inInputData, _, _, _ in
            self?.processIncomingAudioBuffer(inInputData, sampleRate: sampleRate)
        }
        guard procStatus == noErr, let validProcID = procID else {
            return
        }
        self.inputIOProcID = validProcID
        
        let startStatus = AudioDeviceStart(devID, validProcID)
        if startStatus == noErr {
            DispatchQueue.main.async {
                self.isRunning = true
                self.isRealAudioActive = true
            }
        }
    }
    
    private func registerDefaultInputChangeListener() {
        guard !hasInputListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.restartHardwareInputCapture()
        }
        if status == noErr {
            hasInputListener = true
        }
    }
    
    private func restartHardwareInputCapture() {
        if inputDeviceID != 0, let proc = inputIOProcID {
            AudioDeviceStop(inputDeviceID, proc)
            AudioDeviceDestroyIOProcID(inputDeviceID, proc)
            inputIOProcID = nil
            inputDeviceID = 0
        }
        setupHardwareInputCapture()
    }
    
    // MARK: - Core Audio Process Tap (macOS 14.2+)
    private func getDefaultOutputDeviceUID() -> String? {
        var defaultOutID = AudioObjectID(0)
        var devSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var devAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devAddress, 0, nil, &devSize, &defaultOutID)
        guard status == noErr, defaultOutID != 0 else { return nil }
        
        var outUID: CFString = "" as CFString
        var outUIDSize = UInt32(MemoryLayout<CFString>.size)
        var outUIDAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let uidStatus = withUnsafeMutablePointer(to: &outUID) { ptr in
            AudioObjectGetPropertyData(defaultOutID, &outUIDAddress, 0, nil, &outUIDSize, ptr)
        }
        guard uidStatus == noErr else { return nil }
        let uidStr = outUID as String
        return uidStr.isEmpty ? nil : uidStr
    }
    
    /// Retraso real entre que el tap recibe el audio y que se escucha (s). Con AirPods/Bluetooth son
    /// ~0.15–0.25 s: sin compensarlo las barras se adelantan a lo que se oye.
    public private(set) var outputLatencySec: Double = 0
    
    private func measureOutputLatency() {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { outputLatencySec = 0; return }
        
        func uint32(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput, object: AudioObjectID) -> UInt32 {
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(object, &addr, 0, nil, &valueSize, &value) == noErr ? value : 0
        }
        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &rateSize, &rate)
        let sampleRate = rate > 0 ? rate : 48_000
        
        // Latencia del dispositivo + margen de seguridad + búfer + latencia del primer stream de salida
        var frames = uint32(kAudioDevicePropertyLatency, object: deviceID)
            + uint32(kAudioDevicePropertySafetyOffset, object: deviceID)
            + uint32(kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeGlobal, object: deviceID)
        var streamsSize: UInt32 = 0
        var streamsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 {
            var streams = [AudioStreamID](repeating: 0, count: Int(streamsSize) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streams) == noErr, let first = streams.first {
                frames += uint32(kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal, object: first)
            }
        }
        var latency = Double(frames) / sampleRate
        
        // Bluetooth: CoreAudio no siempre reporta el retraso del códec; usar al menos el típico de AirPods
        let transport = uint32(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal, object: deviceID)
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        if isBluetooth { latency = max(latency, 0.17) }
        outputLatencySec = min(0.40, latency)
        DNDLogger.log("AudioSpectrumEngine: retraso de salida \(Int(outputLatencySec * 1000)) ms\(isBluetooth ? " (Bluetooth)" : "") → barras sincronizadas a lo que se oye")
    }
    
    private func setupProcessTapCapture() {
        measureOutputLatency()
        guard #available(macOS 14.2, *) else { return }
        guard Self.systemCaptureAllowed, enableSystemAudioTap else { return }
        
        // Evitar duplicar taps si ya está activo y corriendo
        if aggregateDeviceID != 0 && tapIOProcID != nil {
            return
        }
        teardownProcessTap()
        
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        
        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != 0 else {
            return
        }
        self.tapID = newTapID
        
        // Leer sampleRate real directamente del formato del Process Tap (usualmente 48000 Hz)
        var tapFormat = AudioStreamBasicDescription()
        var tapFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var tapFormatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(newTapID, &tapFormatAddr, 0, nil, &tapFormatSize, &tapFormat) == noErr,
           tapFormat.mSampleRate > 8000.0 {
            self.hardwareSampleRate = Float(tapFormat.mSampleRate)
        }
        
        let outputUID = getDefaultOutputDeviceUID()
        let aggregateUID = "com.dynamicnotch.tap.agg.\(UUID().uuidString)"
        
        var aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Dynamic Notch Tap",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: desc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]
        if let outputUID = outputUID {
            aggDesc[kAudioAggregateDeviceMainSubDeviceKey as String] = outputUID
            aggDesc[kAudioAggregateDeviceSubDeviceListKey as String] = [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ]
        }
        
        var newAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != 0 else {
            teardownProcessTap()
            return
        }
        self.aggregateDeviceID = newAggID
        
        var sr: Float64 = Float64(self.hardwareSampleRate)
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyNominalSampleRate),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        if AudioObjectGetPropertyData(newAggID, &srAddress, 0, nil, &srSize, &sr) == noErr, sr > 8000.0 {
            self.hardwareSampleRate = Float(sr)
        }
        
        var procID: AudioDeviceIOProcID? = nil
        let sampleRate = self.hardwareSampleRate
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggID, nil) { [weak self] _, inInputData, _, _, _ in
            self?.processIncomingAudioBuffer(inInputData, sampleRate: sampleRate)
        }
        guard procStatus == noErr, let validProcID = procID else {
            teardownProcessTap()
            return
        }
        self.tapIOProcID = validProcID
        
        let startStatus = AudioDeviceStart(newAggID, validProcID)
        if startStatus == noErr {
            os_unfair_lock_lock(&lock)
            lastIOProcTimestamp = CFAbsoluteTimeGetCurrent()
            os_unfair_lock_unlock(&lock)
            DispatchQueue.main.async {
                self.isRunning = true
                self.isRealAudioActive = true
            }
            registerDefaultOutputChangeListener()
        } else {
            teardownProcessTap()
        }
    }
    
    private func registerDefaultOutputChangeListener() {
        guard !hasOutputListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            // Pequeño margen para que CoreAudio estabilice el nuevo dispositivo (AirPods / Bluetooth / HDMI)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.restartProcessTap()
            }
        }
        if status == noErr {
            hasOutputListener = true
        }
    }
    
    private func restartProcessTap() {
        // Cambio de salida (AirPods, HDMI…): rehacer el tap sólo si estaba capturando
        let wasCapturing = tapIOProcID != nil
        teardownProcessTap()
        if enableSystemAudioTap && wasCapturing {
            setupProcessTapCapture()
        }
    }
    
    // MARK: - Captura sólo durante la reproducción
    
    private var playbackObserver: AnyCancellable?
    private var pendingCaptureRelease: DispatchWorkItem?
    
    /// Enciende la captura cuando algo empieza a sonar y la suelta (con margen) al pausar o terminar.
    /// Se llama una vez al arrancar la app.
    public func startPlaybackGatedCapture() {
        guard playbackObserver == nil else { return }
        playbackObserver = MusicService.shared.$currentTrack
            .map(\.isPlaying)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.updateCaptureForPlayback(isPlaying: isPlaying)
            }
    }
    
    /// Opción de Ajustes "Barras que siguen la música".
    public func setRealAudioBarsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.realAudioBarsKey)
        realAudioBarsEnabled = enabled
        pendingCaptureRelease?.cancel()
        if enabled {
            // Sólo captura si en este momento algo suena
            updateCaptureForPlayback(isPlaying: MusicService.shared.currentTrack.isPlaying)
        } else {
            enableSystemAudioTap = false // didSet destruye el tap: el indicador morado se va de inmediato
        }
    }
    
    private func updateCaptureForPlayback(isPlaying: Bool) {
        pendingCaptureRelease?.cancel()
        pendingCaptureRelease = nil
        
        if isPlaying && Self.systemCaptureAllowed {
            if !enableSystemAudioTap {
                enableSystemAudioTap = true // didSet ya arranca el tap
            }
            if tapIOProcID == nil {
                DNDLogger.log("AudioSpectrumEngine: ▶️ Reproducción detectada → captura de audio encendida")
                setupProcessTapCapture()
            }
            return
        }
        
        guard tapIOProcID != nil || aggregateDeviceID != 0 || tapID != 0 else { return }
        let release = DispatchWorkItem { [weak self] in
            guard let self = self, !MusicService.shared.currentTrack.isPlaying else { return }
            DNDLogger.log("AudioSpectrumEngine: ⏸ Sin reproducción → captura de audio apagada (sin indicador morado)")
            self.teardownProcessTap()
            self.isRealAudioActive = false
            self.isRunning = false
        }
        pendingCaptureRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureReleaseDelay, execute: release)
    }
    
    private func teardownProcessTap() {
        if aggregateDeviceID != 0, let proc = tapIOProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            tapIOProcID = nil
        }
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if tapID != 0 {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = 0
        }
        cleanupOrphanedAggregateDevicesAndTaps()
    }
    
    /// Limpia cualquier dispositivo agregado residual ("Dynamic Notch Tap") en coreaudiod
    /// para garantizar que macOS jamás muestre el punto morado/naranja de grabación en la barra de menús.
    private func cleanupOrphanedAggregateDevicesAndTaps() {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return }
        
        for dev in devices {
            if dev == aggregateDeviceID { continue }
            var nameCF: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            let st = withUnsafeMutablePointer(to: &nameCF) { ptr in
                AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, ptr)
            }
            if st == noErr {
                let name = nameCF as String
                if name.contains("Dynamic Notch Tap") {
                    AudioHardwareDestroyAggregateDevice(dev)
                }
            }
        }
    }
    
    /// Ingesta directa de muestras PCM (para el generador de laboratorio y análisis en memoria sin indicador)
    public func ingestDirectPCM(samples: [Float], sampleRate: Float) {
        guard !enableSystemAudioTap && !enableMicrophoneCapture else { return }
        os_unfair_lock_lock(&lock)
        lastIOProcTimestamp = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&lock)
        processingQueue.async { [weak self] in
            self?.accumulateAndAnalyze(samples: samples, sampleRate: sampleRate)
        }
    }
    
    // MARK: - Motor FFT Sin Indicador de Grabación (Zero-Indicator Real Track Audio Stream + vDSP FFT)
    private func startZeroIndicatorPipeline() {
        zeroIndicatorTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + 0.05, repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            self?.tickZeroIndicatorFFT()
        }
        timer.resume()
        zeroIndicatorTimer = timer
        DispatchQueue.main.async {
            self.isRunning = true
            self.isRealAudioActive = true
        }
    }
    
    private func tickZeroIndicatorFFT() {
        // Si el usuario activó manualmente el tap de hardware o el generador de laboratorio ya inyecta PCM, no duplicar
        if (enableSystemAudioTap && tapIOProcID != nil) || (enableMicrophoneCapture && inputIOProcID != nil) {
            return
        }
        if AudioSignalGenerator.shared.activeSignal != .off {
            return
        }
        
        let track = MusicService.shared.currentTrack
        let isCall = CallActivityProvider.shared.isCallActive
        
        guard track.isPlaying || isCall else {
            return
        }
        
        let sr: Float = 48000.0
        let frameSamples = 800 // 48000 Hz / 60 fps = 800 muestras por frame (16.67 ms)
        var pcmChunk = [Float](repeating: 0.0, count: frameSamples)
        
        if isCall && !track.isPlaying {
            pcmChunk = synthesizeCallPCMSamples(count: frameSamples, sampleRate: sr)
        } else {
            let trackKey = "\(track.title.trimmingCharacters(in: .whitespacesAndNewlines))|\(track.artist.trimmingCharacters(in: .whitespacesAndNewlines))"
            if !track.title.isEmpty && trackKey != currentDecodedTrackKey && !isFetchingTrackPreview {
                loadTrackAudioPreviewIfNeeded(title: track.title, artist: track.artist, trackKey: trackKey)
            }
            
            if !decodedTrackSamples.isEmpty && currentDecodedTrackKey == trackKey {
                // Extraer muestras PCM reales decodificadas de la canción actual
                let total = decodedTrackSamples.count
                for i in 0..<frameSamples {
                    let idx = (trackSampleReadIndex + i) % total
                    pcmChunk[i] = decodedTrackSamples[idx]
                }
                trackSampleReadIndex = (trackSampleReadIndex + frameSamples) % total
            } else {
                // Mientras descarga el stream o para pistas locales/videos sin preview en iTunes:
                // Síntesis PCM multiespectral real (a 48 kHz) con tempo, bombo, bajo, caja, voz y hi-hats propios de la canción
                pcmChunk = synthesizeTrackPCMSamples(count: frameSamples, sampleRate: sr, title: track.title, artist: track.artist)
            }
        }
        
        os_unfair_lock_lock(&lock)
        lastIOProcTimestamp = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&lock)
        
        accumulateAndAnalyze(samples: pcmChunk, sampleRate: sr)
    }
    
    /// Descarga y decodifica en memoria (vía AVAssetReader) el stream de audio real (.m4a) de la canción en reproducción.
    /// No utiliza micrófono ni Process Tap, por lo que macOS jamás muestra el punto morado/naranja de grabación.
    private func loadTrackAudioPreviewIfNeeded(title: String, artist: String, trackKey: String) {
        isFetchingTrackPreview = true
        currentDecodedTrackKey = trackKey
        decodedTrackSamples = []
        trackSampleReadIndex = 0
        
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
            isFetchingTrackPreview = false
            return
        }
        
        URLSession.shared.dataTask(with: searchURL) { [weak self] data, _, error in
            guard let self = self else { return }
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let previewUrlStr = first["previewUrl"] as? String,
                  let previewURL = URL(string: previewUrlStr) else {
                self.processingQueue.async {
                    self.isFetchingTrackPreview = false
                }
                return
            }
            
            URLSession.shared.dataTask(with: previewURL) { [weak self] audioData, _, audioErr in
                guard let self = self else { return }
                guard audioErr == nil, let audioData = audioData, !audioData.isEmpty else {
                    self.processingQueue.async {
                        self.isFetchingTrackPreview = false
                    }
                    return
                }
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dn_preview_\( abs(trackKey.hashValue) ).m4a")
                do {
                    try audioData.write(to: tempURL, options: .atomic)
                    let samples = Self.decodeAudioFileToMonoPCM(url: tempURL, targetSampleRate: 48000.0)
                    try? FileManager.default.removeItem(at: tempURL)
                    self.processingQueue.async {
                        if self.currentDecodedTrackKey == trackKey && !samples.isEmpty {
                            self.decodedTrackSamples = samples
                            self.trackSampleReadIndex = 0
                        }
                        self.isFetchingTrackPreview = false
                    }
                } catch {
                    self.processingQueue.async {
                        self.isFetchingTrackPreview = false
                    }
                }
            }.resume()
        }.resume()
    }
    
    static func decodeAudioFileToMonoPCM(url: URL, targetSampleRate: Double) -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else {
            return []
        }
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        
        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(targetSampleRate * 15))
        
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                let floatCount = length / MemoryLayout<Float>.size
                if floatCount > 0 {
                    var chunk = [Float](repeating: 0, count: floatCount)
                    chunk.withUnsafeMutableBytes { rawPtr in
                        if let base = rawPtr.baseAddress {
                            _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                        }
                    }
                    allSamples.append(contentsOf: chunk)
                }
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }
        return allSamples
    }
    
    /// Sintetiza una señal PCM real a 48 kHz cuyas frecuencias reales (60 Hz a 12 kHz) alimentan la FFT vDSP de 4096 puntos
    private func synthesizeTrackPCMSamples(count: Int, sampleRate: Float, title: String, artist: String) -> [Float] {
        var hash: UInt64 = 5381
        for b in "\(title)|\(artist)".utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        // BPM armónico por canción entre 92 y 136 BPM
        let bpm = 92.0 + Double(hash % 45)
        let beatDur = 60.0 / bpm
        let grooveStyle = Int((hash >> 8) % 4)
        let dt = 1.0 / Double(sampleRate)
        
        let track = MusicService.shared.currentTrack
        let duration = track.duration > 0 ? track.duration : 210.0
        let currentPos = track.playbackPosition
        
        // Sincronizar el reloj al tiempo real de reproducción de la pista si está activo
        if currentPos > 0.05 && abs(synthClockTime - currentPos) > 0.35 {
            synthClockTime = currentPos
        }
        
        let progress = min(1.0, max(0.0, (currentPos > 0 ? currentPos : synthClockTime) / duration))
        
        // Curva de energía dinámica de la canción (Intro suave -> Versos -> Estribillo potente -> Outro)
        let songEnergy: Double
        if progress < 0.08 {
            songEnergy = 0.60 + (progress / 0.08) * 0.22
        } else if progress < 0.28 {
            songEnergy = 0.82
        } else if progress < 0.52 {
            songEnergy = 0.98
        } else if progress < 0.72 {
            songEnergy = 0.86
        } else if progress < 0.88 {
            songEnergy = 1.00
        } else {
            songEnergy = max(0.35, 1.0 - (progress - 0.88) * 4.5)
        }
        
        var out = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            synthClockTime += dt
            let t = synthClockTime
            let beatPos = t.truncatingRemainder(dividingBy: beatDur) / beatDur
            let barPos = t.truncatingRemainder(dividingBy: beatDur * 4.0) / (beatDur * 4.0)
            let beatIndex = Int(floor(barPos * 4.0)) % 4
            let sixteenthPos = t.truncatingRemainder(dividingBy: beatDur * 0.25) / (beatDur * 0.25)
            let sixteenthIndex = Int(floor(barPos * 16.0)) % 16
            
            // 1. Sub-Bass & Kick (55-120 Hz sweep con ataque rápido y decaimiento limpio)
            let isKickBeat: Bool
            switch grooveStyle {
            case 0: isKickBeat = (sixteenthIndex == 0 || sixteenthIndex == 4 || sixteenthIndex == 8 || sixteenthIndex == 12)
            case 1: isKickBeat = (sixteenthIndex == 0 || sixteenthIndex == 6 || sixteenthIndex == 8 || sixteenthIndex == 14)
            case 2: isKickBeat = (sixteenthIndex == 0 || sixteenthIndex == 3 || sixteenthIndex == 8 || sixteenthIndex == 10)
            default: isKickBeat = (sixteenthIndex == 0 || sixteenthIndex == 4 || sixteenthIndex == 10 || sixteenthIndex == 12)
            }
            let kickEnv = isKickBeat ? exp(-sixteenthPos * 5.6) : exp(-beatPos * 6.8) * 0.24
            let kickFreq = 58.0 + 64.0 * exp(-sixteenthPos * 15.0)
            synthPhaseKick += 2.0 * .pi * kickFreq * dt
            if synthPhaseKick > 2.0 * .pi { synthPhaseKick -= 2.0 * .pi }
            let kickSample = sin(synthPhaseKick) * kickEnv * 0.44
            
            // 2. Bassline (160-320 Hz)
            let bassNotes: [Double] = [174.6, 196.0, 220.0, 246.9]
            let bassFreq = bassNotes[(beatIndex + Int(hash % 4)) % 4]
            let bassEnv = 0.22 + 0.40 * exp(-sixteenthPos * 4.0)
            synthPhaseBass += 2.0 * .pi * bassFreq * dt
            if synthPhaseBass > 2.0 * .pi { synthPhaseBass -= 2.0 * .pi }
            let bassSample = (sin(synthPhaseBass) * 0.80 + sin(synthPhaseBass * 2.0) * 0.20) * bassEnv * 0.28
            
            // 3. Snare & Low-Mids (480-820 Hz) en tiempos 2 y 4 (acentuación rítmica)
            let isSnare = (beatIndex == 1 || beatIndex == 3) && (sixteenthIndex % 4 == 0)
            let snareEnv = isSnare ? exp(-sixteenthPos * 6.5) : 0.06 * (0.5 + 0.5 * sin(barPos * 2.0 * .pi))
            let lowMidFreq = 520.0 + 80.0 * sin(barPos * 4.0 * .pi)
            synthPhaseLowMid += 2.0 * .pi * lowMidFreq * dt
            if synthPhaseLowMid > 2.0 * .pi { synthPhaseLowMid -= 2.0 * .pi }
            let lowMidSample = sin(synthPhaseLowMid) * snareEnv * 0.24
            
            // 4. High-Mids / Voz y Melodía (1400-2200 Hz) modulados con frases musicales suaves
            let vocalPhrase = max(0.0, sin(t * 2.2 + Double(hash % 7)) * 0.60 + sin(t * 5.4) * 0.40)
            let highMidFreq = 1620.0 + 280.0 * sin(t * 2.8)
            synthPhaseHighMid += 2.0 * .pi * highMidFreq * dt
            if synthPhaseHighMid > 2.0 * .pi { synthPhaseHighMid -= 2.0 * .pi }
            let highMidSample = sin(synthPhaseHighMid) * vocalPhrase * 0.16
            
            // 5. Presence (3200-5200 Hz)
            let presEnv = (sixteenthIndex % 2 == 1) ? exp(-sixteenthPos * 6.0) * 0.65 : vocalPhrase * 0.35
            synthPhasePresence += 2.0 * .pi * 4100.0 * dt
            if synthPhasePresence > 2.0 * .pi { synthPhasePresence -= 2.0 * .pi }
            let presSample = sin(synthPhasePresence) * presEnv * 0.11
            
            // 6. Brilliance / Hi-Hats (8200-11800 Hz) con resonancia armónica precisa (cero ruido blanco aleatorio)
            let hatEnv = exp(-sixteenthPos * ((sixteenthIndex % 2 == 0) ? 9.2 : 5.8))
            synthPhaseHat += 2.0 * .pi * 8600.0 * dt
            if synthPhaseHat > 2.0 * .pi { synthPhaseHat -= 2.0 * .pi }
            let hatMetallic = sin(synthPhaseHat) * 0.70 + sin(synthPhaseHat * 1.38) * 0.30
            let hatSample = hatMetallic * hatEnv * 0.08 * (isSnare ? 1.25 : 1.0)
            
            let mixed = Float(kickSample + bassSample + lowMidSample + highMidSample + presSample + hatSample) * Float(songEnergy)
            out[i] = mixed
        }
        return out
    }
    
    private func synthesizeCallPCMSamples(count: Int, sampleRate: Float) -> [Float] {
        let dt = 1.0 / Double(sampleRate)
        var out = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            synthClockTime += dt
            let t = synthClockTime
            let syllable = max(0.05, sin(t * 3.8) * 0.50 + sin(t * 8.3) * 0.35 + 0.25)
            synthPhaseBass += 2.0 * .pi * 210.0 * dt
            synthPhaseLowMid += 2.0 * .pi * 640.0 * dt
            synthPhaseHighMid += 2.0 * .pi * 1720.0 * dt
            synthPhasePresence += 2.0 * .pi * 3400.0 * dt
            let s = (sin(synthPhaseBass) * 0.20 + sin(synthPhaseLowMid) * 0.42 + sin(synthPhaseHighMid) * 0.38 + sin(synthPhasePresence) * 0.18) * syllable * 0.28
            out[i] = Float(s)
        }
        return out
    }
    
    public func startCapture() {
        if enableMicrophoneCapture && inputIOProcID == nil {
            setupHardwareInputCapture()
            registerDefaultInputChangeListener()
        }
        if enableSystemAudioTap && tapIOProcID == nil {
            setupProcessTapCapture()
        }
        if zeroIndicatorTimer == nil && Self.previewAnalysisEnabled {
            startZeroIndicatorPipeline()
        }
        isRunning = true
        isRealAudioActive = true
    }
    
    public func stopCapture() {
        if inputDeviceID != 0, let proc = inputIOProcID {
            AudioDeviceStop(inputDeviceID, proc)
            AudioDeviceDestroyIOProcID(inputDeviceID, proc)
            inputIOProcID = nil
            inputDeviceID = 0
        }
        teardownProcessTap()
    }
    
    // MARK: - Procesamiento de Buffers de Audio en tiempo real (IOProc)
    private func processIncomingAudioBuffer(_ inputBufferList: UnsafePointer<AudioBufferList>, sampleRate: Float) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))
        guard !abl.isEmpty else { return }
        
        // Determinar el número de frames válidos iterando todos los buffers (soporta tanto interleaved como planar/multi-buffer)
        var targetFrames = 0
        for buf in abl {
            guard buf.mData != nil, buf.mDataByteSize > 0 else { continue }
            let ch = max(1, Int(buf.mNumberChannels))
            let floats = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let f = floats / ch
            if f > targetFrames {
                targetFrames = f
            }
        }
        guard targetFrames > 0 else { return }
        
        var monoFrames = [Float](repeating: 0, count: targetFrames)
        var contributingChannels = 0
        
        for buf in abl {
            guard let rawData = buf.mData, buf.mDataByteSize > 0 else { continue }
            let channels = max(1, Int(buf.mNumberChannels))
            let floatCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let frames = min(targetFrames, floatCount / channels)
            guard frames > 0 else { continue }
            
            let floatPtr = rawData.assumingMemoryBound(to: Float.self)
            for ch in 0..<channels {
                for i in 0..<frames {
                    let s = floatPtr[i * channels + ch]
                    if s.isFinite {
                        monoFrames[i] += s
                    }
                }
                contributingChannels += 1
            }
        }
        
        guard contributingChannels > 0 else { return }
        if contributingChannels > 1 {
            var inv = 1.0 / Float(contributingChannels)
            vDSP_vsmul(monoFrames, 1, &inv, &monoFrames, 1, vDSP_Length(targetFrames))
        }
        
        // Silencio digital exacto (todas las muestras en 0.0): típico de audio protegido con FairPlay,
        // a diferencia del silencio musical real, que conserva dither / ruido de fondo
        var peakSample: Float = 0
        vDSP_maxmgv(monoFrames, 1, &peakSample, vDSP_Length(targetFrames))
        
        let callbackTime = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_lock(&lock)
        lastIOProcTimestamp = callbackTime
        if peakSample > 0 {
            lastNonZeroSampleTime = callbackTime
        }
        os_unfair_lock_unlock(&lock)
        
        processingQueue.async { [weak self] in
            self?.accumulateAndAnalyze(samples: monoFrames, sampleRate: sampleRate)
        }
    }
    
    // MARK: - Acumulación sin atraso y Análisis Espectral (FFT 4096 con ventana rápida de 2048 muestras)
    private func accumulateAndAnalyze(samples: [Float], sampleRate: Float) {
        sampleBuffer.append(contentsOf: samples)
        // Mantener exactamente las muestras más recientes sin acumular cola de latencia
        if sampleBuffer.count > activeWindowSize {
            sampleBuffer.removeFirst(sampleBuffer.count - activeWindowSize)
        }
        
        guard sampleBuffer.count >= activeWindowSize, let setup = fftSetup else { return }
        
        // 1. Aplicar ventana Hann desnormalizada sobre las 2048 muestras más recientes (42.6 ms)
        // y colocar en un bloque FFT de 4096 puntos (zero-padded) para resolución fina de 11.7 Hz/bin sin latencia
        var windowed = [Float](repeating: 0, count: fftSize)
        sampleBuffer.withUnsafeBufferPointer { sPtr in
            hannWindow.withUnsafeBufferPointer { hPtr in
                windowed.withUnsafeMutableBufferPointer { wPtr in
                    guard let sBase = sPtr.baseAddress,
                          let hBase = hPtr.baseAddress,
                          let wBase = wPtr.baseAddress else { return }
                    vDSP_vmul(sBase, 1, hBase, 1, wBase.advanced(by: fftSize - activeWindowSize), 1, vDSP_Length(activeWindowSize))
                }
            }
        }
        
        // 2. Preparar datos para FFT real (DSPSplitComplex)
        var realp = [Float](repeating: 0, count: halfFFT)
        var imagp = [Float](repeating: 0, count: halfFFT)
        
        windowed.withUnsafeBufferPointer { wPtr in
            guard let baseAddr = wPtr.baseAddress else { return }
            baseAddr.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
                realp.withUnsafeMutableBufferPointer { rPtr in
                    imagp.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfFFT))
                        
                        // 3. Ejecutar FFT real con Accelerate
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        
                        // 4. Calcular magnitudes
                        var magnitudes = [Float](repeating: 0, count: halfFFT)
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfFFT))
                        
                        // 5. Procesar etapas (Raw -> Weighted -> Normalized -> Smoothed)
                        self.processMultiStageDSP(magnitudes, sampleRate: sampleRate)
                    }
                }
            }
        }
    }
    
    // MARK: - Pipeline DSP en 4 Etapas (Calibrado Psicoacústicamente y Reactivo a Transitorios Reales)
    private func processMultiStageDSP(_ magnitudes: [Float], sampleRate: Float) {
        let binWidth = sampleRate / Float(fftSize) // ~11.7 Hz por bin a 48 kHz
        let now = CFAbsoluteTimeGetCurrent()
        let dt = Float(max(0.001, min(0.05, now - lastProcessTime)))
        lastProcessTime = now
        
        // -------------------------------------------------------------
        // ETAPA 1: ENERGÍA BRUTA (RAW) POR BANDA
        // -------------------------------------------------------------
        var rawEnergies: [Float] = [0, 0, 0, 0, 0, 0]
        var bandDBs: [Float] = [-60, -60, -60, -60, -60, -60]
        var maxRawDB: Float = -100.0
        
        for (i, band) in SpectrumMetrics.bands.enumerated() {
            let startBin = max(1, min(halfFFT - 1, Int(floor(band.low / binWidth))))
            let endBin = max(startBin + 1, min(halfFFT, Int(ceil(band.high / binWidth))))
            
            var sumSq: Float = 0
            var peak: Float = 0
            for bin in startBin..<endBin {
                let m = magnitudes[bin]
                sumSq += m * m
                if m > peak { peak = m }
            }
            let binCount = Float(max(1, endBin - startBin))
            let rms = sqrt(sumSq / binCount)
            
            // 45% pico para capturar transitorios y 55% RMS para densidad armónica balanceada
            let rawE = (peak * 0.45 + rms * 0.55) / activeHalfFFT
            rawEnergies[i] = rawE
            
            let db = 20.0 * log10(max(1e-5, rawE))
            bandDBs[i] = max(-60.0, db)
            if db > maxRawDB { maxRawDB = db }
        }
        
        // -------------------------------------------------------------
        // ETAPA 2: PONDERACIÓN PSICOACÚSTICA 1/f (RUIDO ROSA REAL BALANCEADO)
        // Calibrado para dar un nivel armónico uniforme entre graves y agudos sin saturación
        // -------------------------------------------------------------
        // La música pierde energía hacia los agudos (~4–5 dB por octava): sin compensarlo, las barras de
        // medios-altos y agudos se quedaban casi en cero. Inclinación de +17 dB repartida entre las 6 bandas.
        let pinkNoiseWeights: [Float] = [
            1.00,  // Banda 0: Sub-Bass (60 - 150 Hz)       0 dB
            1.26,  // Banda 1: Bass (150 - 400 Hz)         +2 dB
            1.78,  // Banda 2: Low-Mids (400 - 1000 Hz)    +5 dB
            2.82,  // Banda 3: High-Mids (1.0 - 2.5 kHz)   +9 dB
            4.47,  // Banda 4: Presence (2.5 - 6.0 kHz)   +13 dB
            7.08   // Banda 5: Brilliance (6.0 - 14 kHz)  +17 dB
        ]
        
        var weightedEnergies: [Float] = [0, 0, 0, 0, 0, 0]
        var weightedDBs: [Float] = [-60, -60, -60, -60, -60, -60]
        // Filtro IIR dependiente del tiempo: constante de tiempo de ~50ms (~0.28 a 60fps) para eliminar ruido rápido
        let lpCoeff = 1.0 - exp(-dt / 0.050)
        for i in 0..<6 {
            let weighted = rawEnergies[i] * pinkNoiseWeights[i]
            filteredBandEnergies[i] += (weighted - filteredBandEnergies[i]) * lpCoeff
            weightedEnergies[i] = filteredBandEnergies[i]
            weightedDBs[i] = 20.0 * log10(max(1e-5, weightedEnergies[i]))
        }
        
        // -------------------------------------------------------------
        // ETAPA 3: AGC HÍBRIDO + CONTRASTE DE TRANSITORIOS POR BANDA + NOISE GATE
        // -------------------------------------------------------------
        let weightedPeak = weightedEnergies.max() ?? 1e-5
        let weightedPeakDB = 20.0 * log10(max(1e-5, weightedPeak))
        
        if weightedPeakDB > agcPeakDB {
            let agcAttackCoeff = 1.0 - exp(-dt / Float(max(0.005, SpectrumMetrics.agcAttackMs / 1000.0)))
            agcPeakDB += (weightedPeakDB - agcPeakDB) * agcAttackCoeff
        } else {
            let decayDB = dt * (6.0 / Float(max(0.5, SpectrumMetrics.agcReleaseSec)))
            agcPeakDB = max(-34.0, agcPeakDB - decayDB)
        }
        agcPeakDB = max(-34.0, min(0.0, agcPeakDB))
        
        // Noise Gate con Histéresis (-50 dB abre, -56 dB cierra) y retención corta (120 ms)
        let openThreshold: Float = SpectrumMetrics.noiseGateDB
        let closeThreshold: Float = SpectrumMetrics.noiseGateCloseDB
        
        if weightedPeakDB >= openThreshold {
            gateIsOpen = true
            lastAudibleTime = now
        } else if weightedPeakDB < closeThreshold {
            if (now - lastAudibleTime) > (SpectrumMetrics.noiseGateHoldMs / 1000.0) {
                gateIsOpen = false
            }
        }
        
        // AGC multibanda: pico propio por banda (ataque rápido, caída lenta), limitado a perBandMaxBoostDB
        // por debajo del pico global para no convertir ruido de fondo en barras llenas.
        let bandAttackCoeff = 1.0 - exp(-dt / Float(max(0.005, SpectrumMetrics.agcAttackMs / 1000.0)))
        let bandFloorDB = agcPeakDB - SpectrumMetrics.perBandMaxBoostDB
        let perBandAmount = max(0.0, min(1.0, SpectrumMetrics.perBandAGCAmount))
        var bandReferenceDB: [Float] = [0, 0, 0, 0, 0, 0]
        for i in 0..<6 {
            let db = weightedDBs[i]
            if gateIsOpen && db > bandPeakDB[i] {
                bandPeakDB[i] += (db - bandPeakDB[i]) * bandAttackCoeff
            } else {
                bandPeakDB[i] -= dt * SpectrumMetrics.perBandReleaseDBPerSec
            }
            bandPeakDB[i] = max(bandFloorDB, min(agcPeakDB, bandPeakDB[i]))
            bandReferenceDB[i] = agcPeakDB * (1.0 - perBandAmount) + bandPeakDB[i] * perBandAmount
        }
        
        var normalizedEnergies: [Float] = [0, 0, 0, 0, 0, 0]
        
        // Constante de tiempo del seguidor lento por banda (~250 ms) para extraer golpes rítmicos (onsets)
        let slowFloorCoeff = 1.0 - exp(-dt / 0.250)
        let slowRiseCoeff = 1.0 - exp(-dt / 0.160)
        let jitterCoeff = 1.0 - exp(-dt / 0.300)
        
        for i in 0..<6 {
            let db = weightedDBs[i]
            if gateIsOpen && db > closeThreshold {
                // Seguimiento del promedio local de la banda para detectar bombos, bajos, cajas y sílabas
                if db > bandSlowDB[i] {
                    bandSlowDB[i] += (db - bandSlowDB[i]) * slowRiseCoeff
                } else {
                    bandSlowDB[i] += (db - bandSlowDB[i]) * slowFloorCoeff
                }
                
                // 1) Nivel espectral continuo dentro de la ventana AGC de esta banda (0.0 ... 1.0),
                //    15 dB debajo de su pico de referencia
                // Ventana de 15 dB: los golpes llegan arriba y los huecos regresan abajo (con 28 dB las barras
                // vivían entre 25% y 50% y se veían como un bloque que no seguía la canción)
                // Graves (bombo y bajo): ventana más estrecha → cada golpe destaca más sobre el nivel sostenido
                let isBass = i <= 1
                let floorDB = max(closeThreshold, bandReferenceDB[i] - (isBass ? 12.0 : 15.0))
                let dynamicRange: Float = max(isBass ? 8.0 : 10.0, bandReferenceDB[i] - floorDB)
                let sustainedRatio = max(0.0, min(1.15, (db - floorDB) / dynamicRange))
                
                // 2) Contraste dinámico de transitorio (onset) en esta banda específica
                let onsetDeltaDB = max(0.0, db - bandSlowDB[i])
                let onsetNormalized = min(1.0, onsetDeltaDB / (isBass ? 7.0 : 10.0))
                
                // Combinación: nivel sostenido + transitorio rítmico. En los graves pesa más el golpe (el bombo
                // "patea" la barra); en el resto, 72/28 para que la voz y los platillos no salten de más.
                let onsetWeight: Float = isBass ? 0.42 : 0.28
                let combined = sustainedRatio * (1 - onsetWeight) + onsetNormalized * onsetWeight * min(1.0, sustainedRatio * 1.3)
                
                // Compresión suave tipo tanh para evitar saturación en bandas altas
                let tanhCompressed = tanh(combined * 1.30) / tanh(1.30)
                
                let maxH = SpectrumMetrics.maxActiveHeight
                // Los golpes de graves llegan un poco más alto que el resto
                let activeMapped = tanhCompressed * maxH * SpectrumMetrics.gainMultiplier * (isBass ? 1.14 : 1.0)
                let target = min(maxH, max(0.0, activeMapped))
                
                // 3) Histéresis adaptativa: el umbral crece con la fluctuación reciente de la banda
                //    (platillos rápidos) y se reduce en bandas estables (bajo sostenido, voz)
                let change = abs(target - heldBandTargets[i])
                bandJitter[i] += (change - bandJitter[i]) * jitterCoeff
                let hysteresis = min(SpectrumMetrics.hysteresisMax, bandJitter[i] * SpectrumMetrics.hysteresisJitterFactor)
                if change > hysteresis {
                    heldBandTargets[i] = target
                }
                normalizedEnergies[i] = heldBandTargets[i]
            } else {
                heldBandTargets[i] = 0.0
                bandJitter[i] = 0.0
                bandSlowDB[i] = max(closeThreshold, bandSlowDB[i] - dt * 20.0)
                normalizedEnergies[i] = 0.0
            }
        }
        
        // -------------------------------------------------------------
        // ETAPA 4: SUAVIZADO ASIMÉTRICO POR BANDA, DIFUSIÓN ESPACIAL Y SPECTRAL FLUX (SMOOTHED)
        // -------------------------------------------------------------
        var spectralFlux: Float = 0.0
        let totalRaw = max(1e-4, rawEnergies.reduce(0, +))
        for i in 0..<6 {
            let diff = max(0.0, rawEnergies[i] - prevRawEnergies[i])
            spectralFlux += diff
        }
        prevRawEnergies = rawEnergies
        
        let relativeFlux = spectralFlux / totalRaw
        let fluxTarget: Float
        if relativeFlux > SpectrumMetrics.fluxThreshold && spectralFlux > 0.02 && gateIsOpen {
            fluxTarget = min(SpectrumMetrics.fluxPulseBoost, relativeFlux * 0.06)
        } else {
            fluxTarget = 0.0
        }
        let fluxCoeff = 1.0 - exp(-dt / (fluxTarget > transientBoostLevel ? 0.025 : 0.140))
        transientBoostLevel += (fluxTarget - transientBoostLevel) * fluxCoeff
        
        // Difusión espacial sutil entre barras vecinas (~6% por defecto)
        let diffCoeff = SpectrumMetrics.spatialDiffusion
        var spatiallyDiffused = normalizedEnergies
        if diffCoeff > 0.001 {
            for i in 0..<6 {
                let left = i > 0 ? normalizedEnergies[i - 1] : normalizedEnergies[i]
                let right = i < 5 ? normalizedEnergies[i + 1] : normalizedEnergies[i]
                spatiallyDiffused[i] = normalizedEnergies[i] * (1.0 - 2.0 * diffCoeff) + (left + right) * diffCoeff
            }
        }
        
        // Balística asimétrica profesional:
        // Sub-Bass y Bass tienen ataque 20% más rápido para clavar el bombo con precisión rítmica
        let baseAttackSec = Float(max(0.005, SpectrumMetrics.attackMs / 1000.0))
        let baseReleaseSec = Float(max(0.030, SpectrumMetrics.releaseMs / 1000.0))
        
        var smoothedLevels: [Float] = [0, 0, 0, 0, 0, 0]
        for i in 0..<6 {
            let bandAttackScale: Float = (i <= 1) ? 0.80 : 1.0
            let bandReleaseScale: Float = (i == 0) ? 0.90 : (i >= 4 ? 0.95 : 1.0)
            let attackCoeff = 1.0 - exp(-dt / (baseAttackSec * bandAttackScale))
            let releaseCoeff = 1.0 - exp(-dt / (baseReleaseSec * bandReleaseScale))
            
            // El impulso de flux solo refuerza bandas que ya tienen energía activa
            let bandFluxBoost = spatiallyDiffused[i] > 0.08 ? transientBoostLevel * min(1.0, spatiallyDiffused[i] * 1.4) : 0.0
            let target = gateIsOpen ? min(1.0, spatiallyDiffused[i] + bandFluxBoost) : 0.0
            
            if target > envelopeLevels[i] {
                envelopeLevels[i] += (target - envelopeLevels[i]) * attackCoeff
            } else {
                envelopeLevels[i] += (target - envelopeLevels[i]) * releaseCoeff
                if envelopeLevels[i] < 0.008 && target == 0.0 {
                    envelopeLevels[i] = 0.0
                }
            }
            smoothedLevels[i] = max(0.0, min(1.0, envelopeLevels[i]))
        }
        
        // -------------------------------------------------------------
        // ETAPA 5: MODO ORGÁNICO HÍBRIDO (Paso 5)
        // Modula la amplitud según la energía RMS real del audio
        // -------------------------------------------------------------
        let organicAmt = Float(SpectrumMetrics.organicAmount)
        var finalOutputLevels = smoothedLevels
        
        if organicAmt > 0.01 && gateIsOpen {
            organicNoisePhase += Double(dt) * 3.8
            let rmsEnergy = sqrt(smoothedLevels.reduce(0) { $0 + $1 * $1 } / 6.0)
            
            for i in 0..<6 {
                let wave1 = sin(organicNoisePhase * 2.2 + Double(i) * 0.75)
                let wave2 = cos(organicNoisePhase * 4.1 + Double(i) * 1.10)
                let wave3 = sin(organicNoisePhase * 6.5 - Double(i) * 0.45)
                let organicNoise = Float((wave1 * 0.45 + wave2 * 0.35 + wave3 * 0.20 + 1.0) / 2.0)
                
                let organicModulated = organicNoise * rmsEnergy * 1.15
                let blended = (1.0 - organicAmt) * smoothedLevels[i] + organicAmt * organicModulated
                finalOutputLevels[i] = max(0.0, min(1.0, blended))
            }
        }
        
        // -------------------------------------------------------------
        // REGISTRO DE TELEMETRÍA (60 SEGUNDOS) Y DETECCIÓN DE SATURACIÓN (Paso 1)
        // -------------------------------------------------------------
        recordTelemetryFrame(
            raw: rawEnergies,
            weighted: weightedEnergies,
            normalized: normalizedEnergies,
            smoothed: finalOutputLevels,
            peakDB: maxRawDB,
            timestamp: now
        )
        
        // Publicar estados de forma thread-safe
        os_unfair_lock_lock(&lock)
        currentBandDBs = bandDBs
        currentPeakDB = maxRawDB
        os_unfair_lock_unlock(&lock)
        
        publishProcessedMagnitudes(finalOutputLevels, timestamp: now, isSilent: !gateIsOpen)
    }
    
    // MARK: - Registro de Telemetría (60 Segundos)
    private func recordTelemetryFrame(
        raw: [Float],
        weighted: [Float],
        normalized: [Float],
        smoothed: [Float],
        peakDB: Float,
        timestamp: Double
    ) {
        if timestamp - lastTelemetryRecordTime >= 0.10 { // Registro a 10 Hz
            lastTelemetryRecordTime = timestamp
            
            let frame = SpectrumTelemetryFrame(
                timestamp: timestamp,
                raw: raw,
                weighted: weighted,
                normalized: normalized,
                smoothed: smoothed,
                peakDB: peakDB
            )
            
            telemetryLog.append(frame)
            if telemetryLog.count > maxTelemetryFrames {
                telemetryLog.removeFirst(telemetryLog.count - maxTelemetryFrames)
            }
            
            // Evaluar saturación de bandas altas (High-Mids, Presence, Brilliance)
            let highBandSaturating = evaluateHighBandsSaturation()
            
            DispatchQueue.main.async {
                self.stageRaw = raw
                self.stageWeighted = weighted
                self.stageNormalized = normalized
                self.stageSmoothed = smoothed
                self.highBandsSaturating = highBandSaturating
            }
        }
    }
    
    private func evaluateHighBandsSaturation() -> Bool {
        guard telemetryLog.count >= 30 else { return false }
        let recent = telemetryLog.suffix(100) // Últimos 10 segundos
        
        // Bandas 3, 4 y 5 (High-Mids, Presence, Brilliance)
        for bandIdx in 3...5 {
            let countAbove90 = recent.filter { $0.smoothed[bandIdx] >= 0.90 }.count
            let ratio = Double(countAbove90) / Double(recent.count)
            if ratio > 0.22 {
                return true
            }
        }
        return false
    }
    
    // MARK: - Diagnóstico de 60 Segundos con Percentiles (Paso 1)
    public func computeDiagnostics() -> [BandDiagnostics] {
        guard !telemetryLog.isEmpty else {
            return (0..<6).map { i in
                BandDiagnostics(
                    id: i,
                    label: SpectrumMetrics.bands[i].label,
                    freqRange: "\(Int(SpectrumMetrics.bands[i].low))-\(Int(SpectrumMetrics.bands[i].high))Hz",
                    p10: 0, p50: 0, p90: 0, maxVal: 0,
                    percentAbove90: 0,
                    isSaturating: false
                )
            }
        }
        
        var results: [BandDiagnostics] = []
        let totalCount = Float(telemetryLog.count)
        
        for i in 0..<6 {
            let values = telemetryLog.map { $0.smoothed[i] }.sorted()
            let n = values.count
            let p10Idx = min(n - 1, max(0, Int(Float(n) * 0.10)))
            let p50Idx = min(n - 1, max(0, Int(Float(n) * 0.50)))
            let p90Idx = min(n - 1, max(0, Int(Float(n) * 0.90)))
            
            let p10 = values[p10Idx]
            let p50 = values[p50Idx]
            let p90 = values[p90Idx]
            let maxV = values.last ?? 0.0
            
            let above90Count = values.filter { $0 >= 0.90 }.count
            let pctAbove90 = (Double(above90Count) / Double(totalCount)) * 100.0
            let saturating = (i >= 3 && pctAbove90 > 20.0)
            
            results.append(BandDiagnostics(
                id: i,
                label: SpectrumMetrics.bands[i].label,
                freqRange: "\(Int(SpectrumMetrics.bands[i].low))-\(Int(SpectrumMetrics.bands[i].high))Hz",
                p10: p10,
                p50: p50,
                p90: p90,
                maxVal: maxV,
                percentAbove90: pctAbove90,
                isSaturating: saturating
            ))
        }
        return results
    }
    
    // MARK: - Exportación a CSV de Telemetría (Paso 6)
    public func exportTelemetryToCSV() -> URL? {
        guard !telemetryLog.isEmpty else { return nil }
        
        var csv = "Timestamp,Peak_dB,Raw_0,Raw_1,Raw_2,Raw_3,Raw_4,Raw_5,Weighted_0,Weighted_1,Weighted_2,Weighted_3,Weighted_4,Weighted_5,Norm_0,Norm_1,Norm_2,Norm_3,Norm_4,Norm_5,Smooth_0,Smooth_1,Smooth_2,Smooth_3,Smooth_4,Smooth_5\n"
        
        for f in telemetryLog {
            let rawStr = f.raw.map { String(format: "%.4f", $0) }.joined(separator: ",")
            let wStr = f.weighted.map { String(format: "%.4f", $0) }.joined(separator: ",")
            let nStr = f.normalized.map { String(format: "%.4f", $0) }.joined(separator: ",")
            let sStr = f.smoothed.map { String(format: "%.4f", $0) }.joined(separator: ",")
            csv.append("\(String(format: "%.2f", f.timestamp)),\(String(format: "%.2f", f.peakDB)),\(rawStr),\(wStr),\(nStr),\(sStr)\n")
        }
        
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("DynamicNotch_AudioTelemetry_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("[AudioSpectrumEngine] Error al exportar CSV: \(error)")
            return nil
        }
    }
    
    // MARK: - Manejo de Retardo Bluetooth y Publicación Thread-Safe
    private func publishProcessedMagnitudes(_ levels: [Float], timestamp: Double, isSilent: Bool) {
        // Retrasar lo que se ve hasta el momento en que realmente se oye (latencia de la salida + ajuste manual)
        let delaySec = outputLatencySec + SpectrumMetrics.bluetoothDelayMs / 1000.0
        
        var outputLevels = levels
        if delaySec > 0.005 {
            delayQueue.append(DelayedFrame(timestamp: timestamp, values: levels))
            let targetTime = timestamp - delaySec
            outputLevels = lastDelayedOutput
            while let first = delayQueue.first, first.timestamp <= targetTime {
                outputLevels = first.values
                delayQueue.removeFirst()
            }
            lastDelayedOutput = outputLevels
        }
        
        os_unfair_lock_lock(&lock)
        currentMagnitudes = outputLevels
        if !isSilent {
            // Nivel típico del audio real reciente (τ ≈ 3 s): el generador procedural se escala a él
            // para que el relevo no cambie la "energía" visible de las barras
            lastLiveOutputTime = timestamp
            let mean = outputLevels.reduce(0, +) / Float(max(1, outputLevels.count))
            liveLevelReference += (mean - liveLevelReference) * 0.006
        }
        os_unfair_lock_unlock(&lock)
        
        if self.isSilent != isSilent {
            DispatchQueue.main.async {
                self.isSilent = isSilent
            }
        }
    }
    
    public func getBandDecibels() -> [Float] {
        if isRealAudioActive {
            os_unfair_lock_lock(&lock)
            let copy = currentBandDBs
            os_unfair_lock_unlock(&lock)
            return copy
        }
        let mags = getMagnitudes()
        return mags.map { -60.0 + ($0 * 56.0) }
    }
    
    public func getPeakDecibels() -> Float {
        if isRealAudioActive {
            os_unfair_lock_lock(&lock)
            let peak = currentPeakDB
            let lastTime = lastIOProcTimestamp
            os_unfair_lock_unlock(&lock)
            if CFAbsoluteTimeGetCurrent() - lastTime > 0.25 {
                return -60.0
            }
            return peak
        }
        let dbs = getBandDecibels()
        return dbs.max() ?? -60.0
    }
    
    // MARK: - Lectura desde la UI (a 60 fps, < 0.05 ms con os_unfair_lock)
    /// Diagnóstico para GET /debug/audio: de dónde salen las barras en este momento
    public func debugSnapshot() -> [String: Any] {
        os_unfair_lock_lock(&lock)
        let live = currentMagnitudes
        let lastTime = lastIOProcTimestamp
        let lastNonZero = lastNonZeroSampleTime
        let lastLive = lastLiveOutputTime
        os_unfair_lock_unlock(&lock)
        let now = CFAbsoluteTimeGetCurrent()
        return [
            "isPlaying": MusicService.shared.currentTrack.isPlaying,
            "enableSystemAudioTap": enableSystemAudioTap,
            "tapRunning": tapIOProcID != nil,
            "isSimulatedMode": isSimulatedMode,
            "secondsSinceCallback": now - lastTime,
            "secondsSinceNonZero": now - lastNonZero,
            "secondsSinceLiveOutput": now - lastLive,
            "proceduralBlend": proceduralBlend,
            "agcPeakDB": agcPeakDB,
            "bandPeakDB": bandPeakDB,
            "liveMagnitudes": live,
            "output": getMagnitudes()
        ]
    }
    
    public func getMagnitudes() -> [Float] {
        // 1. Modo Simulación forzado explícitamente en el laboratorio de diagnóstico
        if isSimulatedMode {
            if CallActivityProvider.shared.isCallActive {
                return generateRealisticCallMagnitudes()
            }
            if AudioSignalGenerator.shared.activeSignal != .off || MusicService.shared.currentTrack.isPlaying {
                return generateRealisticMusicMagnitudes()
            }
            return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        }
        
        // 2. Motor Procedimental Armónico Predeterminado (solo si no hay tap ni micrófono activo)
        if !enableMicrophoneCapture && (!enableSystemAudioTap || tapIOProcID == nil) && AudioSignalGenerator.shared.activeSignal == .off {
            if CallActivityProvider.shared.isCallActive {
                return generateRealisticCallMagnitudes()
            }
            return ProceduralMotionEngine.shared.getMagnitudes(barCount: 6)
        }
        
        // 3. Motor FFT vDSP Hardware/Tap (solo si fue activado explícitamente en diagnósticos)
        os_unfair_lock_lock(&lock)
        var copy = currentMagnitudes
        let lastTime = lastIOProcTimestamp
        let lastNonZero = lastNonZeroSampleTime
        let lastLive = lastLiveOutputTime
        let levelReference = liveLevelReference
        os_unfair_lock_unlock(&lock)
        
        let elapsedSinceCallback = CFAbsoluteTimeGetCurrent() - lastTime
        if elapsedSinceCallback > 0.12 {
            // Si la reproducción se pausó o entró en silencio, decaer limpiamente a 0.0 (< 80 ms)
            let decay = Float(max(0.0, 1.0 - (elapsedSinceCallback - 0.12) * 12.0))
            for i in 0..<copy.count {
                copy[i] *= decay
            }
            if decay <= 0.01 {
                copy = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            }
        }
        
        if CallActivityProvider.shared.isCallActive && copy.allSatisfy({ $0 < 0.01 }) {
            return generateRealisticCallMagnitudes()
        }
        return blendWithProceduralIfStarved(copy, lastCallback: lastTime, lastNonZero: lastNonZero, lastLive: lastLive, levelReference: levelReference)
    }
    
    /// Si hay música reproduciéndose pero el tap no entrega señal útil (DRM, tap caído o silencio prolongado),
    /// cruza suavemente hacia el generador procedural y regresa al audio real en cuanto vuelve.
    private func blendWithProceduralIfStarved(_ live: [Float], lastCallback: Double, lastNonZero: Double, lastLive: Double, levelReference: Float) -> [Float] {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = Float(min(0.1, max(0.001, now - lastBlendUpdateTime)))
        lastBlendUpdateTime = now
        
        let isPlaying = MusicService.shared.currentTrack.isPlaying
        let digitalZero = now - lastNonZero > 0.6       // buffers de 0.0 exacto (audio protegido)
        let tapStarved = now - lastCallback > 0.5 // el tap dejó de llamar
        let longSilence = now - lastLive > 4.0           // gate cerrado demasiado tiempo para ser una pausa musical
        let wantsProcedural = isPlaying && (digitalZero || tapStarved || longSilence)
        
        // Entrada lenta (τ 300 ms) para no notar el relevo; salida rápida (τ 120 ms) cuando vuelve el audio real
        let target: Float = wantsProcedural ? 1.0 : 0.0
        let tau: Float = wantsProcedural ? 0.30 : 0.12
        proceduralBlend += (target - proceduralBlend) * (1.0 - exp(-dt / tau))
        if proceduralBlend < 0.002 {
            proceduralBlend = 0
            return live
        }
        
        let procedural = ProceduralMotionEngine.shared.getMagnitudes(barCount: 6)
        // El procedural rinde ~0.4–0.5 de media; escalarlo al nivel típico de la pista real
        let scale = max(0.6, min(1.6, levelReference / 0.5))
        var blended = live
        for i in 0..<min(blended.count, procedural.count) {
            let proc = min(1.0, procedural[i] * scale)
            blended[i] = live[i] * (1.0 - proceduralBlend) + proc * proceduralBlend
        }
        return blended
    }
    
    private var lastSimTime: Double = CFAbsoluteTimeGetCurrent()
    
    // MARK: - Generador Dinámico para Llamadas de Voz (FaceTime / Teléfono)
    public func generateRealisticCallMagnitudes() -> [Float] {
        // Voz sintética determinista (misma lógica para todas las vistas de llamada)
        VisualizerMotion.speechLevels(at: CACurrentMediaTime(), seed: 0xC0FFEE)
    }
    
    // MARK: - Generador Psicoacústico Hiperrealista Multiespectral (Punchy & Rítmico)
    public func generateRealisticMusicMagnitudes() -> [Float] {
        guard MusicService.shared.currentTrack.isPlaying || AudioSignalGenerator.shared.activeSignal != .off else {
            resetEnvelopes()
            return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        }
        
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastSimCalculationTime
        if elapsed < 0.012 && !cachedSimMagnitudes.allSatisfy({ $0 == 0 }) {
            return cachedSimMagnitudes
        }
        
        let dt = Float(max(0.008, min(0.05, elapsed > 1.0 ? 0.016 : elapsed)))
        lastSimCalculationTime = now
        lastSimTime = now
        
        let bpm: Double = 124.0
        let beatDuration = 60.0 / bpm
        
        // Reloj maestro anclado al tiempo del sistema (inmune a la frecuencia de muestreo de la UI)
        let beatProgress = now.truncatingRemainder(dividingBy: beatDuration) / beatDuration
        let barProgress = now.truncatingRemainder(dividingBy: beatDuration * 4.0) / (beatDuration * 4.0)
        let twoBarProgress = now.truncatingRemainder(dividingBy: beatDuration * 8.0) / (beatDuration * 8.0)
        
        let kickDecay = exp(-beatProgress * 4.8)
        let subBassVal = max(0.0, kickDecay) * 0.85
        let subBassHit = Float(subBassVal)
        
        let bassPulse = (sin(barProgress * .pi * 8.0) * 0.5 + 0.5) * 0.35
        let bassHit = Float(kickDecay * 0.65 + bassPulse)
        
        let halfBarProgress = now.truncatingRemainder(dividingBy: beatDuration * 2.0) / (beatDuration * 2.0)
        let snarePhase = halfBarProgress - 0.5
        let snareHit: Double = snarePhase > 0 ? (exp(-snarePhase * 6.5) * 0.70) : 0.0
        let lowMidsVal = snareHit + (sin(barProgress * .pi * 4.0) * 0.5 + 0.5) * 0.22
        let lowMids = Float(lowMidsVal)
        
        let eighthProgress = now.truncatingRemainder(dividingBy: beatDuration / 2.0) / (beatDuration / 2.0)
        let melodyPulse = exp(-eighthProgress * 5.0) * 0.40
        let melodyMod = (sin(twoBarProgress * .pi * 4.0) * 0.5 + 0.5) * 0.25
        let highMids = Float(melodyPulse + melodyMod)
        
        let presencePulse = (sin(barProgress * .pi * 16.0) * 0.5 + 0.5) * 0.35
        let presenceHit = Float(presencePulse)
        
        let sixteenthPhase = now.truncatingRemainder(dividingBy: beatDuration / 4.0) / (beatDuration / 4.0)
        let hiHatVal = exp(-sixteenthPhase * 7.5) * 0.55
        let hiHatHit = Float(hiHatVal)
        
        let targets: [Float] = [
            min(0.92, max(0.0, subBassHit)),
            min(0.90, max(0.0, bassHit)),
            min(0.88, max(0.0, lowMids)),
            min(0.85, max(0.0, highMids)),
            min(0.82, max(0.0, presenceHit)),
            min(0.80, max(0.0, hiHatHit))
        ]
        
        let attackCoeff = 1.0 - exp(-dt / 0.022) // Ataque 22ms
        let releaseCoeff = 1.0 - exp(-dt / 0.135) // Caída 135ms
        
        for i in 0..<6 {
            let target = targets[i]
            let coeff = target > simEnvelopeLevels[i] ? attackCoeff : releaseCoeff
            simEnvelopeLevels[i] += (target - simEnvelopeLevels[i]) * coeff
        }
        
        cachedSimMagnitudes = simEnvelopeLevels
        
        // Registrar telemetría a 10 Hz para que el monitor en vivo MDAETR muestre datos estables y calibrados
        if now - lastTelemetryRecordTime >= 0.10 {
            lastTelemetryRecordTime = now
            recordTelemetryFrame(
                raw: targets,
                weighted: targets.map { $0 * 1.05 },
                normalized: simEnvelopeLevels,
                smoothed: simEnvelopeLevels,
                peakDB: -14.0 + (simEnvelopeLevels.max() ?? 0) * 12.0,
                timestamp: now
            )
        }
        
        return simEnvelopeLevels
    }
    
    // MARK: - Reseteo Inmediato de Envolventes al Cambiar Canción o Pausar
    public func resetEnvelopes() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.lock)
            self.currentMagnitudes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.currentBandDBs = [-60.0, -60.0, -60.0, -60.0, -60.0, -60.0]
            self.currentPeakDB = -60.0
            os_unfair_lock_unlock(&self.lock)
            
            self.envelopeLevels = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.filteredBandEnergies = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.bandSlowDB = [-56.0, -56.0, -56.0, -56.0, -56.0, -56.0]
            self.bandPeakDB = [-18.0, -18.0, -18.0, -18.0, -18.0, -18.0]
            self.heldBandTargets = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.bandJitter = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.prevRawEnergies = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.simEnvelopeLevels = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.cachedSimMagnitudes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            self.gateIsOpen = false
            DispatchQueue.main.async {
                self.stageRaw = [0, 0, 0, 0, 0, 0]
                self.stageWeighted = [0, 0, 0, 0, 0, 0]
                self.stageNormalized = [0, 0, 0, 0, 0, 0]
                self.stageSmoothed = [0, 0, 0, 0, 0, 0]
                self.highBandsSaturating = false
            }
        }
    }
}
