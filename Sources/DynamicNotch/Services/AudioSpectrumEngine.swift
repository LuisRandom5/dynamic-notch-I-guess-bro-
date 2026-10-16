import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import os.lock
import AVFoundation

/// Motor de análisis espectral de audio real del sistema a 60 fps
/// Captura audio del sistema vía hardware de entrada (micrófono / línea) y Process Taps (macOS 14.2+)
/// Ejecuta FFT real de 1024 puntos con la librería Accelerate (vDSP) y balística IEC profesional
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
        : true { // Captura audio digital nativo del sistema macOS (Process Tap) sin puntito de privacidad
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
    
    // Parámetros FFT
    private let fftSize: Int = 1024
    private let halfFFT: Int = 512
    private var log2n: vDSP_Length = 10
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float] = []
    
    // Ring buffer para muestras de entrada
    private var sampleBuffer: [Float] = []
    private let maxBufferCapacity: Int = 4096
    
    // Envelope & AGC state
    private var envelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var filteredBandEnergies: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private var agcPeakDB: Float = -12.0
    private var lastProcessTime: Double = CFAbsoluteTimeGetCurrent()
    private var lastAudibleTime: Double = CFAbsoluteTimeGetCurrent()
    
    // Retardo configurable para Bluetooth
    private struct DelayedFrame {
        let timestamp: Double
        let values: [Float]
    }
    private var delayQueue: [DelayedFrame] = []
    
    // Simulación suave cuando no hay audio real
    private var simBeatClock: Double = 0.0
    private var simEnvelopeLevels: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    
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
    
    // MARK: - Configuración de Accelerate (vDSP)
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
            print("[AudioSpectrumEngine] No se pudo obtener el dispositivo de entrada predeterminado (\(status))")
            return
        }
        self.inputDeviceID = devID
        
        // Obtener la tasa de muestreo nominal real del hardware
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
            print("[AudioSpectrumEngine] Error al crear IOProc en hardware de entrada (\(procStatus))")
            return
        }
        self.inputIOProcID = validProcID
        
        let startStatus = AudioDeviceStart(devID, validProcID)
        if startStatus == noErr {
            print("[AudioSpectrumEngine] Captura de hardware de entrada iniciada con éxito en dispositivo \(devID) (\(self.hardwareSampleRate) Hz).")
            DispatchQueue.main.async {
                self.isRunning = true
                self.isRealAudioActive = true
            }
        } else {
            print("[AudioSpectrumEngine] Error al iniciar AudioDeviceStart en dispositivo de entrada: \(startStatus)")
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
            print("[AudioSpectrumEngine] Dispositivo de entrada predeterminado cambió. Reiniciando captura.")
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
        
        // Obtener dispositivo de salida y su tasa de muestreo nominal real
        var outSampleRate: Float = 48000.0
        var defaultOutID = AudioObjectID(0)
        var devSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var devAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devAddress, 0, nil, &devSize, &defaultOutID) == noErr, defaultOutID != 0 {
            var sr: Float64 = 48000.0
            var srSize = UInt32(MemoryLayout<Float64>.size)
            var srAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyNominalSampleRate),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            if AudioObjectGetPropertyData(defaultOutID, &srAddress, 0, nil, &srSize, &sr) == noErr, sr > 8000.0 {
                outSampleRate = Float(sr)
            }
        }
        self.hardwareSampleRate = outSampleRate
        
        let outUID = getDefaultOutputDeviceUID() ?? "BuiltInSpeakerDevice"
        let tapConfig: [String: Any] = [
            kAudioSubTapUIDKey: tapUID as String,
            kAudioSubTapDriftCompensationKey: true
        ]
        
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DynamicNotchAudioTapAggregate",
            kAudioAggregateDeviceUIDKey: "com.dynamicnotch.audiotap.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outUID]
            ],
            kAudioAggregateDeviceTapListKey: [tapConfig],
            kAudioAggregateDeviceIsPrivateKey: true
        ]
        
        var newAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != 0 else {
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapID = 0
            return
        }
        self.aggregateDeviceID = newAggID
        
        var newProcID: AudioDeviceIOProcID? = nil
        let sampleRate = self.hardwareSampleRate
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newAggID, nil) { [weak self] _, inInputData, _, _, _ in
            self?.processIncomingAudioBuffer(inInputData, sampleRate: sampleRate)
        }
        guard procStatus == noErr, let validProcID = newProcID else {
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            self.aggregateDeviceID = 0
            self.tapID = 0
            return
        }
        self.tapIOProcID = validProcID
        
        let startStatus = AudioDeviceStart(newAggID, validProcID)
        if startStatus == noErr {
            print("[AudioSpectrumEngine] Process Tap Aggregate iniciado (Tap: \(newTapID), Agg: \(newAggID), \(self.hardwareSampleRate) Hz).")
            DispatchQueue.main.async {
                self.isRunning = true
                self.isRealAudioActive = true
            }
        }
        registerDefaultOutputChangeListener()
    }
    
    private func registerDefaultOutputChangeListener() {
        guard !hasOutputListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            print("[AudioSpectrumEngine] Dispositivo de salida predeterminado cambió. Reiniciando Process Tap.")
            self?.restartProcessTapCapture()
        }
        if status == noErr {
            hasOutputListener = true
        }
    }
    
    private func restartProcessTapCapture() {
        teardownProcessTap()
        setupProcessTapCapture()
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
        
        // Convertir a mono (promedio de canales)
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
        
        // Enviar a la cola de análisis espectral
        processingQueue.async { [weak self] in
            self?.accumulateAndAnalyze(samples: monoFrames, sampleRate: sampleRate)
        }
    }
    
    // MARK: - Acumulación y Análisis Espectral (FFT + Envolvente)
    private func accumulateAndAnalyze(samples: [Float], sampleRate: Float) {
        sampleBuffer.append(contentsOf: samples)
        if sampleBuffer.count > maxBufferCapacity {
            sampleBuffer.removeFirst(sampleBuffer.count - maxBufferCapacity)
        }
        
        guard sampleBuffer.count >= fftSize, let setup = fftSetup else { return }
        
        // Ventana de 1024 muestras con 50% de solape (avanzar 512 muestras)
        let windowSamples = Array(sampleBuffer.suffix(fftSize))
        sampleBuffer.removeFirst(min(sampleBuffer.count, fftSize / 2))
        
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
                        
                        // 3. Ejecutar FFT con Accelerate
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        
                        // 4. Calcular magnitudes
                        var magnitudes = [Float](repeating: 0, count: halfFFT)
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfFFT))
                        
                        // 5. Agrupar en las 6 bandas logarítmicas con normalización
                        self.processMagnitudesIntoBands(magnitudes, sampleRate: sampleRate)
                    }
                }
            }
        }
    }
    
    // MARK: - Agrupación en 6 bandas, AGC, Compensación de Agudos y Envolvente
    private func processMagnitudesIntoBands(_ magnitudes: [Float], sampleRate: Float) {
        let binWidth = sampleRate / Float(fftSize)
        let now = CFAbsoluteTimeGetCurrent()
        let dt = Float(max(0.001, min(0.05, now - lastProcessTime)))
        lastProcessTime = now
        
        var bandDBs: [Float] = [0, 0, 0, 0, 0, 0]
        var maxDB: Float = -100.0
        
        // Ponderación psicoacústica que compensa la caída natural de energía musical (Pink Noise Curve):
        // Garantiza que medios (voces/cajas) y agudos (platos/hi-hats) tengan tanto movimiento visual como los bombos
        let bandBoosts: [Float] = [
            1.0,   // Sub-Bass (40 - 120 Hz)
            1.25,  // Bass (120 - 300 Hz)
            2.30,  // Low-Mids (300 - 800 Hz)
            4.00,  // High-Mids (800 - 2000 Hz)
            6.80,  // Presence (2000 - 5000 Hz)
            10.50  // Brilliance (5000 - 12000 Hz)
        ]
        
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
            
            // Combinar 75% pico para captar transitorios y 25% RMS para densidad
            let combined = (peak * 0.75 + rms * 0.25) / Float(halfFFT)
            let energy = combined * bandBoosts[i]
            
            // Filtro paso bajo de 1 polo en la energía cruda (ataque ágil a transitorios)
            filteredBandEnergies[i] += (energy - filteredBandEnergies[i]) * 0.55
            
            let db = 20.0 * log10(max(1e-5, filteredBandEnergies[i]))
            bandDBs[i] = db
            if db > maxDB { maxDB = db }
        }
        
        // Control adaptativo de ganancia (AGC)
        if maxDB > agcPeakDB {
            agcPeakDB += (maxDB - agcPeakDB) * min(1.0, dt * 4.0)
        } else {
            let decayDB = dt * SpectrumMetrics.agcDecayDBPerSec
            agcPeakDB = max(-24.0, agcPeakDB - decayDB)
        }
        agcPeakDB = max(-24.0, min(0.0, agcPeakDB))
        
        let gateDB: Float = SpectrumMetrics.noiseGateDB
        let dynamicRange: Float = max(16.0, agcPeakDB - gateDB)
        
        var targetLevels: [Float] = [0, 0, 0, 0, 0, 0]
        var hasAudibleSound = false
        
        for i in 0..<6 {
            let db = bandDBs[i]
            if db > gateDB {
                hasAudibleSound = true
                let normalized = (db - gateDB) / dynamicRange
                let perceptual = pow(max(0.0, min(1.0, normalized)), 1.25) * SpectrumMetrics.gainMultiplier
                targetLevels[i] = min(1.0, max(0.0, perceptual))
            } else {
                targetLevels[i] = 0.0
            }
        }
        
        if hasAudibleSound {
            lastAudibleTime = now
        }
        // Histeresis de silencio de 2.0 segundos (evita saltos bruscos en pausas breves de canciones)
        let isNowSilent = (now - lastAudibleTime) > 2.0
        
        // Filtro balístico IEC (Attack ~22ms / Release ~280ms)
        let attackCoeff = 1.0 - exp(-dt / Float(max(0.005, SpectrumMetrics.attackMs / 1000.0)))
        let releaseCoeff = 1.0 - exp(-dt / Float(max(0.02, SpectrumMetrics.releaseMs / 1000.0)))
        
        var smoothedLevels: [Float] = [0, 0, 0, 0, 0, 0]
        for i in 0..<6 {
            let target = isNowSilent ? 0.0 : targetLevels[i]
            if target > envelopeLevels[i] {
                envelopeLevels[i] += (target - envelopeLevels[i]) * attackCoeff
            } else {
                envelopeLevels[i] += (target - envelopeLevels[i]) * releaseCoeff
            }
            smoothedLevels[i] = max(0.0, min(1.0, envelopeLevels[i]))
        }
        
        os_unfair_lock_lock(&lock)
        currentBandDBs = bandDBs
        currentPeakDB = maxDB
        os_unfair_lock_unlock(&lock)
        
        publishProcessedMagnitudes(smoothedLevels, timestamp: now, isSilent: isNowSilent)
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
        
        // Escritura atómica sin contención
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
    /// Lee de forma thread-safe los 6 valores de magnitud normalizados (0.0 ... 1.0)
    public func getMagnitudes() -> [Float] {
        if isSimulatedMode {
            if CallActivityProvider.shared.isCallActive {
                return generateRealisticCallMagnitudes()
            }
            return generateRealisticMusicMagnitudes()
        }
        
        // 1. Audio Real Activo (Process Tap digital CoreAudio de 64 bits o micrófono explícito)
        if isRealAudioActive {
            os_unfair_lock_lock(&lock)
            let copy = currentMagnitudes
            os_unfair_lock_unlock(&lock)
            
            // Si el audio real capturado tiene energía audible (> 0.03 en alguna banda), usarlo con total fidelidad
            let maxEnergy = copy.max() ?? 0.0
            if maxEnergy > 0.03 {
                return copy
            }
        }
        
        // 2. Si hay llamada en curso y el audio real no está fluyendo en el tap, generar espectro de voz dinámico
        if CallActivityProvider.shared.isCallActive {
            return generateRealisticCallMagnitudes()
        }
        
        // 3. Fallback de cortesía: música activa o notch expandida
        if MusicService.shared.currentTrack.isPlaying || MusicService.shared.hasActiveMusic || AppState.shared.mode == .expanded {
            return generateRealisticMusicMagnitudes()
        }
        
        // 4. En reposo absoluto
        return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    }
    
    // MARK: - Generador Dinámico para Llamadas de Voz (FaceTime / Teléfono)
    public func generateRealisticCallMagnitudes() -> [Float] {
        let dt = 0.028
        simBeatClock += dt
        
        // Frecuencias vocales humanas: mayor energía en bandas 2 (Low-Mids), 3 (Mids) y 4 (Presence)
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
        
        // 1. Sub-Bass (Bombos / Kick drum punch con caída analógica rápida y punch contundente)
        let kickDecay = exp(-beatProgress * 5.5)
        let subBassVal = max(0.0, kickDecay) * 0.85 + 0.12
        let subBassHit = Float(subBassVal)
        
        // 2. Bass (Bajo melódico sincronizado con el compás de 4 tiempos)
        let bassPulse = (sin(barProgress * .pi * 8.0) * 0.5 + 0.5) * 0.40
        let bassHit = Float(kickDecay * 0.65 + bassPulse + 0.14)
        
        // 3. Low-Mids (Caja / Snare con golpe nítido en pulsos 2 y 4)
        let halfBarProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration * 2.0) / (beatDuration * 2.0)
        let snarePhase = halfBarProgress - 0.5
        let snareHit: Double = snarePhase > 0 ? (exp(-snarePhase * 8.0) * 0.78) : 0.0
        let lowMidsVal = snareHit + (sin(barProgress * .pi * 4.0) * 0.5 + 0.5) * 0.20 + 0.16
        let lowMids = Float(lowMidsVal)
        
        // 4. High-Mids (Melodía armónica en corcheas sincronizadas)
        let eighthProgress = simBeatClock.truncatingRemainder(dividingBy: beatDuration / 2.0) / (beatDuration / 2.0)
        let melodyPulse = exp(-eighthProgress * 6.0) * 0.45
        let melodyMod = (sin(twoBarProgress * .pi * 4.0) * 0.5 + 0.5) * 0.28
        let highMids = Float(melodyPulse + melodyMod + 0.18)
        
        // 5. Presence (Guitarras / voces / textura rítmica sincronizada)
        let presencePulse = (sin(barProgress * .pi * 16.0) * 0.5 + 0.5) * 0.42
        let presenceHit = Float(presencePulse + 0.18)
        
        // 6. Brilliance (Hi-hats rítmicos en semicorcheas limpias)
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
        
        // Filtro balístico: subida ágil (punch) y caída orgánica
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
