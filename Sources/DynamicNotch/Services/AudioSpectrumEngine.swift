import Foundation
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
    
    // Estados públicos
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isRealAudioActive: Bool = false
    @Published public private(set) var isSilent: Bool = true
    @Published public var isSimulatedMode: Bool = false
    @Published public var enableMicrophoneCapture: Bool = false
    @Published public var enableSystemAudioTap: Bool = UserDefaults.standard.object(forKey: "enableSystemAudioTap") != nil
        ? UserDefaults.standard.bool(forKey: "enableSystemAudioTap")
        : true {
        didSet {
            UserDefaults.standard.set(enableSystemAudioTap, forKey: "enableSystemAudioTap")
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
    @Published public private(set) var hardwareSampleRate: Float = 44100.0
    
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
    
    // Parámetros FFT multirresolución (Paso 2: FFT 4096 puntos a 48 kHz = 11.7 Hz/bin, latencia < 25ms con salto 512)
    private let fftSize: Int = 4096
    private let halfFFT: Int = 2048
    private let hopSize: Int = 512
    private var log2n: vDSP_Length = 12
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float] = []
    
    // Ring buffer para muestras de entrada
    private var sampleBuffer: [Float] = []
    private let maxBufferCapacity: Int = 8192
    
    // Envelope & AGC state
    private var envelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var filteredBandEnergies: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var prevRawEnergies: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var agcPeakDB: Float = -12.0
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
    
    // Simulación suave cuando no hay audio real
    private var simBeatClock: Double = 0.0
    private var simEnvelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    
    // Generador orgánico tipo ruido Perlin / armónico (Paso 5)
    private var organicNoisePhase: Double = 0.0
    
    private init() {
        setupAccelerate()
        startCapture()
    }
    
    deinit {
        stopCapture()
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Configuración de Accelerate (vDSP con 4096 puntos)
    private func setupAccelerate() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
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
                self.isRealAudioActive = false
            }
        }
    }
    
    // MARK: - Captura de Hardware (Micrófono / Entrada Predeterminada)
    private func setupHardwareInputCapture() {
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
        
        var sr: Float64 = 44100.0
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
        withUnsafeMutablePointer(to: &outUID) { ptr in
            _ = AudioObjectGetPropertyData(defaultOutID, &outUIDAddress, 0, nil, &outUIDSize, ptr)
        }
        return outUID as String
    }
    
    private func setupProcessTapCapture() {
        guard #available(macOS 14.2, *) else { return }
        
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        
        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != 0 else { return }
        self.tapID = newTapID
        
        var tapUID: CFString = "" as CFString
        var propSize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioTapPropertyUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        withUnsafeMutablePointer(to: &tapUID) { ptr in
            _ = AudioObjectGetPropertyData(newTapID, &address, 0, nil, &propSize, ptr)
        }
        
        guard let outputUID = getDefaultOutputDeviceUID() else { return }
        
        let aggregateUID = "com.dynamicnotch.tap.agg.\(UUID().uuidString)"
        let subDevices: [[String: Any]] = [
            [
                kAudioSubDeviceUIDKey as String: tapUID as String,
                kAudioSubDeviceExtraInputLatencyKey as String: 0
            ]
        ]
        
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Dynamic Notch Tap",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
            kAudioAggregateDeviceIsPrivateKey as String: true
        ]
        
        var newAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != 0 else { return }
        self.aggregateDeviceID = newAggID
        
        var sr: Float64 = 44100.0
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
        guard procStatus == noErr, let validProcID = procID else { return }
        self.tapIOProcID = validProcID
        
        let startStatus = AudioDeviceStart(newAggID, validProcID)
        if startStatus == noErr {
            DispatchQueue.main.async {
                self.isRunning = true
                self.isRealAudioActive = true
            }
            registerDefaultOutputChangeListener()
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
            self?.restartProcessTap()
        }
        if status == noErr {
            hasOutputListener = true
        }
    }
    
    private func restartProcessTap() {
        teardownProcessTap()
        if enableSystemAudioTap {
            setupProcessTapCapture()
        }
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
    }
    
    public func startCapture() {
        guard !isRunning else { return }
        isRunning = true
        if enableMicrophoneCapture {
            setupHardwareInputCapture()
            registerDefaultInputChangeListener()
        }
        if enableSystemAudioTap {
            setupProcessTapCapture()
        }
    }
    
    public func stopCapture() {
        if inputDeviceID != 0, let proc = inputIOProcID {
            AudioDeviceStop(inputDeviceID, proc)
            AudioDeviceDestroyIOProcID(inputDeviceID, proc)
            inputIOProcID = nil
            inputDeviceID = 0
        }
        teardownProcessTap()
        DispatchQueue.main.async {
            self.isRunning = false
            self.isRealAudioActive = false
        }
    }
    
    // MARK: - Procesamiento de Buffers de Audio en tiempo real (IOProc)
    private func processIncomingAudioBuffer(_ inputBufferList: UnsafePointer<AudioBufferList>, sampleRate: Float) {
        let numBuffers = inputBufferList.pointee.mNumberBuffers
        guard numBuffers > 0 else { return }
        
        let buffer = inputBufferList.pointee.mBuffers
        guard let rawData = buffer.mData, buffer.mDataByteSize > 0 else { return }
        
        let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let channels = max(1, Int(buffer.mNumberChannels))
        let frames = floatCount / channels
        guard frames > 0 else { return }
        
        let floatPtr = rawData.assumingMemoryBound(to: Float.self)
        
        var monoFrames = [Float](repeating: 0, count: frames)
        if channels == 1 {
            for i in 0..<frames {
                monoFrames[i] = floatPtr[i]
            }
        } else {
            for i in 0..<frames {
                var sum: Float = 0
                for ch in 0..<channels {
                    sum += floatPtr[i * channels + ch]
                }
                monoFrames[i] = sum / Float(channels)
            }
        }
        
        processingQueue.async { [weak self] in
            self?.accumulateAndAnalyze(samples: monoFrames, sampleRate: sampleRate)
        }
    }
    
    // MARK: - Acumulación y Análisis Espectral (Paso 2: FFT 4096 multirresolución)
    private func accumulateAndAnalyze(samples: [Float], sampleRate: Float) {
        sampleBuffer.append(contentsOf: samples)
        if sampleBuffer.count > maxBufferCapacity {
            sampleBuffer.removeFirst(sampleBuffer.count - maxBufferCapacity)
        }
        
        guard sampleBuffer.count >= fftSize, let setup = fftSetup else { return }
        
        // Ventana de 4096 muestras con solape alto (salto de 512 muestras = 10.6 ms a 48 kHz)
        let windowSamples = Array(sampleBuffer.suffix(fftSize))
        sampleBuffer.removeFirst(min(sampleBuffer.count, hopSize))
        
        // 1. Aplicar ventana Hann
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(windowSamples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))
        
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
                        
                        // 3. Ejecutar FFT real con Accelerate (4096 puntos en < 0.15ms)
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
    
    // MARK: - Pipeline DSP en 4 Etapas (Paso 1, 2, 3, 4, 5)
    private func processMultiStageDSP(_ magnitudes: [Float], sampleRate: Float) {
        let binWidth = sampleRate / Float(fftSize) // ~10.7 a 11.7 Hz por bin
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
            let startBin = max(1, min(halfFFT - 1, Int(band.low / binWidth)))
            let endBin = max(startBin + 1, min(halfFFT, Int(band.high / binWidth)))
            
            var sumSq: Float = 0
            var peak: Float = 0
            for bin in startBin..<endBin {
                let m = magnitudes[bin]
                sumSq += m * m
                if m > peak { peak = m }
            }
            let binCount = Float(endBin - startBin)
            let rms = sqrt(sumSq / binCount)
            
            // 70% pico para transitorios ágiles y 30% RMS para densidad
            let rawE = (peak * 0.70 + rms * 0.30) / Float(halfFFT)
            rawEnergies[i] = rawE
            
            let db = 20.0 * log10(max(1e-5, rawE))
            bandDBs[i] = db
            if db > maxRawDB { maxRawDB = db }
        }
        
        // -------------------------------------------------------------
        // ETAPA 2: PONDERACIÓN PSICOACÚSTICA Y RUIDO ROSA (WEIGHTED)
        // Calibrada para que el Ruido Rosa produzca barras equilibradas (Paso 3)
        // -------------------------------------------------------------
        let pinkNoiseWeights: [Float] = [
            1.00,  // Banda 0: Sub-Bass (60 - 150 Hz)
            1.20,  // Banda 1: Bass (150 - 400 Hz)
            1.65,  // Banda 2: Low-Mids (400 - 1000 Hz)
            2.15,  // Banda 3: High-Mids (1000 - 2500 Hz)
            2.70,  // Banda 4: Presence (2500 - 6000 Hz)
            3.40   // Banda 5: Brilliance (6000 - 14000 Hz)
        ]
        
        var weightedEnergies: [Float] = [0, 0, 0, 0, 0, 0]
        for i in 0..<6 {
            let weighted = rawEnergies[i] * pinkNoiseWeights[i]
            // Filtro paso bajo de 1 polo en la energía ponderada
            filteredBandEnergies[i] += (weighted - filteredBandEnergies[i]) * 0.50
            weightedEnergies[i] = filteredBandEnergies[i]
        }
        
        // -------------------------------------------------------------
        // ETAPA 3: AGC GLOBAL, NOISE GATE CON HISTÉRESIS Y COMPRESIÓN TANH (NORMALIZED)
        // -------------------------------------------------------------
        // AGC Global único (no por banda) con ataque rápido (15ms) y liberación lenta (3s)
        let weightedPeak = weightedEnergies.max() ?? 1e-5
        let weightedPeakDB = 20.0 * log10(max(1e-5, weightedPeak))
        
        if weightedPeakDB > agcPeakDB {
            let agcAttackCoeff = 1.0 - exp(-dt / Float(SpectrumMetrics.agcAttackMs / 1000.0))
            agcPeakDB += (weightedPeakDB - agcPeakDB) * agcAttackCoeff
        } else {
            let decayDB = dt * (6.0 / Float(SpectrumMetrics.agcReleaseSec))
            agcPeakDB = max(-26.0, agcPeakDB - decayDB)
        }
        agcPeakDB = max(-26.0, min(0.0, agcPeakDB))
        
        // Noise Gate con Histéresis (-45 dB abre, -52 dB cierra) y retención (200 ms)
        let openThreshold: Float = SpectrumMetrics.noiseGateDB // -45 dB
        let closeThreshold: Float = SpectrumMetrics.noiseGateCloseDB // -52 dB
        
        if weightedPeakDB >= openThreshold {
            gateIsOpen = true
            lastAudibleTime = now
        } else if weightedPeakDB < closeThreshold {
            if (now - lastAudibleTime) > (SpectrumMetrics.noiseGateHoldMs / 1000.0) {
                gateIsOpen = false
            }
        }
        
        let dynamicRange: Float = max(18.0, agcPeakDB - closeThreshold)
        var normalizedEnergies: [Float] = [0, 0, 0, 0, 0, 0]
        
        for i in 0..<6 {
            if gateIsOpen {
                let db = 20.0 * log10(max(1e-5, weightedEnergies[i]))
                let ratio = (db - closeThreshold) / dynamicRange
                let clampedRatio = max(0.0, min(1.2, ratio))
                
                // Compresión tipo tanh para evitar recorte duro en saturaciones
                let tanhCompressed = tanh(clampedRatio * 1.5) / tanh(1.5)
                
                // Mapeo activo entre minActiveHeight (12%) y maxActiveHeight (92%)
                let minH = SpectrumMetrics.minActiveHeight
                let maxH = SpectrumMetrics.maxActiveHeight
                let activeMapped = minH + tanhCompressed * (maxH - minH) * SpectrumMetrics.gainMultiplier
                normalizedEnergies[i] = min(maxH, max(0.0, activeMapped))
            } else {
                normalizedEnergies[i] = 0.0
            }
        }
        
        // -------------------------------------------------------------
        // ETAPA 4: SUAVIZADO ASIMÉTRICO, DIFUSIÓN ESPACIAL Y SPECTRAL FLUX (SMOOTHED)
        // -------------------------------------------------------------
        // Detección de Spectral Flux (golpes y transitorios rítmicos)
        var spectralFlux: Float = 0.0
        for i in 0..<6 {
            let diff = max(0.0, rawEnergies[i] - prevRawEnergies[i])
            spectralFlux += diff
        }
        prevRawEnergies = rawEnergies
        
        if spectralFlux > SpectrumMetrics.fluxThreshold && gateIsOpen {
            transientBoostLevel = SpectrumMetrics.fluxPulseBoost // +12% pulso compartido
        } else {
            transientBoostLevel = max(0.0, transientBoostLevel - dt * 2.5)
        }
        
        // Difusión espacial entre barras vecinas (~16%)
        let diffCoeff = SpectrumMetrics.spatialDiffusion
        var spatiallyDiffused = normalizedEnergies
        for i in 0..<6 {
            let left = i > 0 ? normalizedEnergies[i - 1] : normalizedEnergies[i]
            let right = i < 5 ? normalizedEnergies[i + 1] : normalizedEnergies[i]
            spatiallyDiffused[i] = normalizedEnergies[i] * (1.0 - 2.0 * diffCoeff) + (left + right) * diffCoeff
        }
        
        // Balística asimétrica (Attack 14ms / Release 130ms)
        let attackCoeff = 1.0 - exp(-dt / Float(max(0.005, SpectrumMetrics.attackMs / 1000.0)))
        let releaseCoeff = 1.0 - exp(-dt / Float(max(0.02, SpectrumMetrics.releaseMs / 1000.0)))
        
        var smoothedLevels: [Float] = [0, 0, 0, 0, 0, 0]
        for i in 0..<6 {
            let targetWithFlux = min(1.0, spatiallyDiffused[i] + transientBoostLevel)
            let target = gateIsOpen ? targetWithFlux : 0.0
            
            if target > envelopeLevels[i] {
                envelopeLevels[i] += (target - envelopeLevels[i]) * attackCoeff
            } else {
                envelopeLevels[i] += (target - envelopeLevels[i]) * releaseCoeff
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
            peakDB: weightedPeakDB,
            timestamp: now
        )
        
        // Publicar estados de forma thread-safe
        os_unfair_lock_lock(&lock)
        currentBandDBs = bandDBs
        currentPeakDB = weightedPeakDB
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
        let delaySec = SpectrumMetrics.bluetoothDelayMs / 1000.0
        
        var outputLevels = levels
        if delaySec > 0.005 {
            delayQueue.append(DelayedFrame(timestamp: timestamp, values: levels))
            let targetTime = timestamp - delaySec
            while let first = delayQueue.first, first.timestamp < targetTime {
                outputLevels = first.values
                delayQueue.removeFirst()
            }
        }
        
        os_unfair_lock_lock(&lock)
        currentMagnitudes = outputLevels
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
        let dbs = getBandDecibels()
        return dbs.max() ?? -60.0
    }
    
    // MARK: - Lectura desde la UI (a 60 fps)
    public func getMagnitudes() -> [Float] {
        if isSimulatedMode {
            if CallActivityProvider.shared.isCallActive {
                return generateRealisticCallMagnitudes()
            }
            return generateRealisticMusicMagnitudes()
        }
        
        if isRealAudioActive {
            os_unfair_lock_lock(&lock)
            let copy = currentMagnitudes
            os_unfair_lock_unlock(&lock)
            return copy
        }
        
        if CallActivityProvider.shared.isCallActive {
            return generateRealisticCallMagnitudes()
        }
        
        if MusicService.shared.currentTrack.isPlaying {
            return generateRealisticMusicMagnitudes()
        }
        
        return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    }
    
    // MARK: - Generador Dinámico para Llamadas de Voz (FaceTime / Teléfono)
    public func generateRealisticCallMagnitudes() -> [Float] {
        let dt = 0.028
        simBeatClock += dt
        
        let speechCadence = sin(simBeatClock * 3.5) * 0.45 + sin(simBeatClock * 7.2) * 0.25 + 0.30
        let syllabicBurst = max(0.0, sin(simBeatClock * 11.0)) * 0.35
        
        let band0 = Float(max(0.04, sin(simBeatClock * 1.8) * 0.08 + 0.06))
        let band1 = Float(max(0.08, speechCadence * 0.35 + 0.12))
        let band2 = Float(min(0.95, max(0.15, speechCadence * 0.75 + syllabicBurst + 0.18)))
        let band3 = Float(min(0.90, max(0.18, speechCadence * 0.82 + syllabicBurst * 0.8 + 0.16)))
        let band4 = Float(min(0.80, max(0.12, speechCadence * 0.55 + 0.14)))
        let band5 = Float(max(0.05, sin(simBeatClock * 8.5) * 0.12 + 0.08))
        
        let targets = [band0, band1, band2, band3, band4, band5]
        for i in 0..<6 {
            let rate: Float = targets[i] > simEnvelopeLevels[i] ? 0.38 : 0.16
            simEnvelopeLevels[i] += (targets[i] - simEnvelopeLevels[i]) * rate
        }
        return simEnvelopeLevels
    }
    
    // MARK: - Generador Psicoacústico Hiperrealista Multiespectral (Punchy & Rítmico)
    public func generateRealisticMusicMagnitudes() -> [Float] {
        let dt = 0.026
        simBeatClock += dt
        
        let bpm: Double = 124.0
        let beatDuration = 60.0 / bpm
        let beatProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration) / beatDuration
        let barProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration * 4.0) / (beatDuration * 4.0)
        let twoBarProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration * 8.0) / (beatDuration * 8.0)
        
        let kickDecay = exp(-beatProgress * 5.5)
        let subBassVal = max(0.0, kickDecay) * 0.85 + 0.12
        let subBassHit = Float(subBassVal)
        
        let bassPulse = (sin(barProgress * .pi * 8.0) * 0.5 + 0.5) * 0.40
        let bassHit = Float(kickDecay * 0.65 + bassPulse + 0.14)
        
        let halfBarProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration * 2.0) / (beatDuration * 2.0)
        let snarePhase = halfBarProgress - 0.5
        let snareHit: Double = snarePhase > 0 ? (exp(-snarePhase * 8.0) * 0.78) : 0.0
        let lowMidsVal = snareHit + (sin(barProgress * .pi * 4.0) * 0.5 + 0.5) * 0.20 + 0.16
        let lowMids = Float(lowMidsVal)
        
        let eighthProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration / 2.0) / (beatDuration / 2.0)
        let melodyPulse = exp(-eighthProgress * 6.0) * 0.45
        let melodyMod = (sin(twoBarProgress * .pi * 4.0) * 0.5 + 0.5) * 0.28
        let highMids = Float(melodyPulse + melodyMod + 0.18)
        
        let presencePulse = (sin(barProgress * .pi * 16.0) * 0.5 + 0.5) * 0.42
        let presenceHit = Float(presencePulse + 0.18)
        
        let sixteenthPhase = simBeatClock.truncatingRemainder(dividingBy: beatDuration / 4.0) / (beatDuration / 4.0)
        let hiHatVal = exp(-sixteenthPhase * 9.0) * 0.65 + 0.14
        let hiHatHit = Float(hiHatVal)
        
        let targets: [Float] = [
            min(1.0, max(0.08, subBassHit)),
            min(1.0, max(0.08, bassHit)),
            min(1.0, max(0.08, lowMids)),
            min(1.0, max(0.08, highMids)),
            min(1.0, max(0.08, presenceHit)),
            min(1.0, max(0.08, hiHatHit))
        ]
        
        for i in 0..<6 {
            let target = targets[i]
            let attackRate: Float = 0.55
            let releaseRate: Float = 0.22
            let rate = target > simEnvelopeLevels[i] ? attackRate : releaseRate
            simEnvelopeLevels[i] += (target - simEnvelopeLevels[i]) * rate
        }
        
        return simEnvelopeLevels
    }
}
