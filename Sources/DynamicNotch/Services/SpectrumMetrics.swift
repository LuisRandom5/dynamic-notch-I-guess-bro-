import Foundation

public enum SpectrumResponsePreset: String, CaseIterable, Identifiable {
    case island = "island"
    case smooth = "smooth"
    case balanced = "balanced"
    case punchy = "punchy"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .island: return "Isla (Dynamic Island Calibrado)"
        case .smooth: return "Suave (Orgánico)"
        case .balanced: return "Balanceado (Estándar)"
        case .punchy: return "Punchy (Ultra Reactivo)"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .island: return "Isla"
        case .smooth: return "Suave"
        case .balanced: return "Balanceado"
        case .punchy: return "Punchy"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .island: return "14ms / 130ms • AGC Global"
        case .smooth: return "24ms / 240ms"
        case .balanced: return "12ms / 150ms"
        case .punchy: return "6ms / 95ms"
        }
    }
}

// MARK: - Spectrum Analysis & Envelope Metrics
public struct SpectrumMetrics {
    public static var activePreset: SpectrumResponsePreset = UserDefaults.standard.string(forKey: "spectrumActivePreset") != nil
        ? (SpectrumResponsePreset(rawValue: UserDefaults.standard.string(forKey: "spectrumActivePreset")!) ?? .island)
        : .island {
        didSet { UserDefaults.standard.set(activePreset.rawValue, forKey: "spectrumActivePreset") }
    }
    
    public static var attackMs: Double = UserDefaults.standard.object(forKey: "spectrumAttackMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumAttackMs")
        : 14.0 {
        didSet { UserDefaults.standard.set(attackMs, forKey: "spectrumAttackMs") }
    }
    
    public static var releaseMs: Double = UserDefaults.standard.object(forKey: "spectrumReleaseMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumReleaseMs")
        : 130.0 {
        didSet { UserDefaults.standard.set(releaseMs, forKey: "spectrumReleaseMs") }
    }
    
    public static var noiseGateDB: Float = UserDefaults.standard.object(forKey: "spectrumNoiseGateDB") != nil
        ? UserDefaults.standard.float(forKey: "spectrumNoiseGateDB")
        : -45.0 {
        didSet { UserDefaults.standard.set(noiseGateDB, forKey: "spectrumNoiseGateDB") }
    }
    
    public static var noiseGateCloseDB: Float = -52.0
    public static var noiseGateHoldMs: Double = 200.0
    
    public static var agcAttackMs: Double = 15.0
    public static var agcReleaseSec: Double = 3.0
    public static var agcDecayDBPerSec: Float = 4.0
    
    public static var spatialDiffusion: Float = 0.16 // Difusión espacial entre barras contiguas (16%)
    public static var fluxThreshold: Float = 0.25    // Umbral de transitorios para Spectral Flux
    public static var fluxPulseBoost: Float = 0.12   // Pulso compartido en transitorios (+12%)
    
    public static var minActiveHeight: Float = 0.12  // Altura mínima activa mientras suena (~12%)
    public static var maxActiveHeight: Float = 0.92  // Altura máxima activa (~92%, evita recorte duro)
    
    public static var organicAmount: Double = UserDefaults.standard.object(forKey: "spectrumOrganicAmount") != nil
        ? UserDefaults.standard.double(forKey: "spectrumOrganicAmount")
        : 0.0 {
        didSet { UserDefaults.standard.set(organicAmount, forKey: "spectrumOrganicAmount") }
    }
    
    public static var includeAppAudioInTap: Bool = false // Interruptor para pruebas del generador de señales
    
    public static var gainMultiplier: Float = UserDefaults.standard.object(forKey: "spectrumGainMultiplier") != nil
        ? UserDefaults.standard.float(forKey: "spectrumGainMultiplier")
        : 1.20 {
        didSet { UserDefaults.standard.set(gainMultiplier, forKey: "spectrumGainMultiplier") }
    }
    
    public static var bluetoothDelayMs: Double = UserDefaults.standard.object(forKey: "spectrumBluetoothDelayMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumBluetoothDelayMs")
        : 0.0 {
        didSet { UserDefaults.standard.set(bluetoothDelayMs, forKey: "spectrumBluetoothDelayMs") }
    }
    
    public static func applyPreset(_ preset: SpectrumResponsePreset) {
        activePreset = preset
        switch preset {
        case .island:
            attackMs = 14.0
            releaseMs = 130.0
            noiseGateDB = -45.0
            noiseGateCloseDB = -52.0
            gainMultiplier = 1.20
            spatialDiffusion = 0.16
            fluxPulseBoost = 0.12
        case .smooth:
            attackMs = 24.0
            releaseMs = 240.0
            noiseGateDB = -46.0
            noiseGateCloseDB = -54.0
            gainMultiplier = 1.10
            spatialDiffusion = 0.22
            fluxPulseBoost = 0.08
        case .balanced:
            attackMs = 12.0
            releaseMs = 150.0
            noiseGateDB = -42.0
            noiseGateCloseDB = -49.0
            gainMultiplier = 1.25
            spatialDiffusion = 0.14
            fluxPulseBoost = 0.10
        case .punchy:
            attackMs = 6.0
            releaseMs = 95.0
            noiseGateDB = -38.0
            noiseGateCloseDB = -46.0
            gainMultiplier = 1.45
            spatialDiffusion = 0.08
            fluxPulseBoost = 0.16
        }
    }
    
    // 6 Bandas optimizadas para evitar frecuencias < 60 Hz (invisibles en portátiles y AirPods)
    public static let bands: [(low: Float, high: Float, label: String)] = [
        (60.0, 150.0, "Sub-Bass"),      // Banda 0: Bombos y graves percusivos limpios
        (150.0, 400.0, "Bass"),         // Banda 1: Línea de bajo y cuerpo
        (400.0, 1000.0, "Low-Mids"),    // Banda 2: Medios graves / instrumentos acústicos
        (1000.0, 2500.0, "High-Mids"),  // Banda 3: Rango vocal principal
        (2500.0, 6000.0, "Presence"),   // Banda 4: Presencia / percusión / nitidez
        (6000.0, 14000.0, "Brilliance") // Banda 5: Brillo / platos y sibilancias
    ]
}
