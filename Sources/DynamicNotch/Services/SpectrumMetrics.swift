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
        case .island: return "22ms / 180ms • AGC Global"
        case .smooth: return "30ms / 240ms"
        case .balanced: return "20ms / 170ms"
        case .punchy: return "14ms / 130ms"
        }
    }
}

// MARK: - Spectrum Analysis & Envelope Metrics
public struct SpectrumMetrics {
    public static var activePreset: SpectrumResponsePreset = UserDefaults.standard.string(forKey: "spectrumActivePresetV2") != nil
        ? (SpectrumResponsePreset(rawValue: UserDefaults.standard.string(forKey: "spectrumActivePresetV2")!) ?? .island)
        : .island {
        didSet { UserDefaults.standard.set(activePreset.rawValue, forKey: "spectrumActivePresetV2") }
    }
    
    public static var attackMs: Double = UserDefaults.standard.object(forKey: "spectrumAttackMsV2") != nil
        ? UserDefaults.standard.double(forKey: "spectrumAttackMsV2")
        : 22.0 {
        didSet { UserDefaults.standard.set(attackMs, forKey: "spectrumAttackMsV2") }
    }
    
    public static var releaseMs: Double = UserDefaults.standard.object(forKey: "spectrumReleaseMsV2") != nil
        ? UserDefaults.standard.double(forKey: "spectrumReleaseMsV2")
        : 180.0 {
        didSet { UserDefaults.standard.set(releaseMs, forKey: "spectrumReleaseMsV2") }
    }
    
    public static var noiseGateDB: Float = UserDefaults.standard.object(forKey: "spectrumNoiseGateDB") != nil
        ? UserDefaults.standard.float(forKey: "spectrumNoiseGateDB")
        : -50.0 {
        didSet { UserDefaults.standard.set(noiseGateDB, forKey: "spectrumNoiseGateDB") }
    }
    
    public static var noiseGateCloseDB: Float = -56.0
    public static var noiseGateHoldMs: Double = 140.0
    
    public static var agcAttackMs: Double = 16.0
    public static var agcReleaseSec: Double = 2.5
    public static var agcDecayDBPerSec: Float = 4.5
    
    // AGC multibanda: cada banda sigue su propio pico además del pico global,
    // para que bandas tenues (agudos en voz/podcast, graves en música clásica) usen todo el rango visual.
    public static var perBandAGCAmount: Float = 0.80      // 0 = solo AGC global · 1 = solo AGC por banda
    public static var perBandMaxBoostDB: Float = 26.0     // Una banda nunca se amplifica más de esto respecto al pico global
    public static var perBandReleaseDBPerSec: Float = 3.0 // Caída del pico por banda (lenta: no "respira" entre golpes)
    
    // Histéresis adaptativa: la banda ignora cambios menores que su propio nivel de fluctuación reciente
    public static var hysteresisJitterFactor: Float = 0.8
    public static var hysteresisMax: Float = 0.06
    
    public static var spatialDiffusion: Float = 0.12 // Difusión espacial armónica (12%) para movimiento suave y cohesionado
    public static var fluxThreshold: Float = 0.24    // Umbral de transitorios para Spectral Flux por banda
    public static var fluxPulseBoost: Float = 0.08   // Impulso rítmico balanceado y controlado en transitorios
    
    public static var minActiveHeight: Float = 0.04  // Sin elevación artificial en bandas silenciosas
    public static var maxActiveHeight: Float = 0.88  // Techo seguro (~88%) para evitar saturación en el monitor
    
    public static var organicAmount: Double = UserDefaults.standard.object(forKey: "spectrumOrganicAmount") != nil
        ? UserDefaults.standard.double(forKey: "spectrumOrganicAmount")
        : 0.0 {
        didSet { UserDefaults.standard.set(organicAmount, forKey: "spectrumOrganicAmount") }
    }
    
    public static var includeAppAudioInTap: Bool = true // Incluye por defecto el generador de calibración en el Process Tap
    
    // Clave V2: una calibración vieja dejó guardada la ganancia en 0.62 y las barras nunca pasaban de la mitad
    public static var gainMultiplier: Float = UserDefaults.standard.object(forKey: "spectrumGainMultiplierV2") != nil
        ? UserDefaults.standard.float(forKey: "spectrumGainMultiplierV2")
        : 1.10 {
        didSet { UserDefaults.standard.set(gainMultiplier, forKey: "spectrumGainMultiplierV2") }
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
            attackMs = 22.0
            releaseMs = 180.0
            noiseGateDB = -50.0
            noiseGateCloseDB = -56.0
            gainMultiplier = 1.10
            spatialDiffusion = 0.12
            fluxPulseBoost = 0.08
        case .smooth:
            attackMs = 30.0
            releaseMs = 240.0
            noiseGateDB = -50.0
            noiseGateCloseDB = -56.0
            gainMultiplier = 1.05
            spatialDiffusion = 0.15
            fluxPulseBoost = 0.05
        case .balanced:
            attackMs = 20.0
            releaseMs = 170.0
            noiseGateDB = -48.0
            noiseGateCloseDB = -54.0
            gainMultiplier = 1.12
            spatialDiffusion = 0.10
            fluxPulseBoost = 0.08
        case .punchy:
            attackMs = 14.0
            releaseMs = 130.0
            noiseGateDB = -46.0
            noiseGateCloseDB = -52.0
            gainMultiplier = 1.20
            spatialDiffusion = 0.08
            fluxPulseBoost = 0.12
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
