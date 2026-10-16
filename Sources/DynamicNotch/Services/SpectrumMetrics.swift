import Foundation

public enum SpectrumResponsePreset: String, CaseIterable, Identifiable {
    case smooth = "smooth"
    case balanced = "balanced"
    case punchy = "punchy"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .smooth: return "Suave (Orgánico)"
        case .balanced: return "Balanceado (Estándar)"
        case .punchy: return "Punchy (Ultra Reactivo)"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .smooth: return "Suave"
        case .balanced: return "Balanceado"
        case .punchy: return "Punchy"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .smooth: return "24ms / 240ms"
        case .balanced: return "12ms / 150ms"
        case .punchy: return "6ms / 95ms"
        }
    }
}

// MARK: - Spectrum Analysis & Envelope Metrics
public struct SpectrumMetrics {
    public static var attackMs: Double = UserDefaults.standard.object(forKey: "spectrumAttackMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumAttackMs")
        : 10.0 {
        didSet { UserDefaults.standard.set(attackMs, forKey: "spectrumAttackMs") }
    }
    
    public static var releaseMs: Double = UserDefaults.standard.object(forKey: "spectrumReleaseMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumReleaseMs")
        : 140.0 {
        didSet { UserDefaults.standard.set(releaseMs, forKey: "spectrumReleaseMs") }
    }
    
    public static var noiseGateDB: Float = UserDefaults.standard.object(forKey: "spectrumNoiseGateDB") != nil
        ? UserDefaults.standard.float(forKey: "spectrumNoiseGateDB")
        : -42.0 {
        didSet { UserDefaults.standard.set(noiseGateDB, forKey: "spectrumNoiseGateDB") }
    }
    
    public static var agcDecayDBPerSec: Float = 5.0
    
    public static var gainMultiplier: Float = UserDefaults.standard.object(forKey: "spectrumGainMultiplier") != nil
        ? UserDefaults.standard.float(forKey: "spectrumGainMultiplier")
        : 1.25 {
        didSet { UserDefaults.standard.set(gainMultiplier, forKey: "spectrumGainMultiplier") }
    }
    
    public static var bluetoothDelayMs: Double = UserDefaults.standard.object(forKey: "spectrumBluetoothDelayMs") != nil
        ? UserDefaults.standard.double(forKey: "spectrumBluetoothDelayMs")
        : 0.0 {
        didSet { UserDefaults.standard.set(bluetoothDelayMs, forKey: "spectrumBluetoothDelayMs") }
    }
    
    public static func applyPreset(_ preset: SpectrumResponsePreset) {
        switch preset {
        case .smooth:
            attackMs = 24.0
            releaseMs = 240.0
            noiseGateDB = -46.0
            gainMultiplier = 1.10
        case .balanced:
            attackMs = 12.0
            releaseMs = 150.0
            noiseGateDB = -42.0
            gainMultiplier = 1.25
        case .punchy:
            attackMs = 6.0
            releaseMs = 95.0
            noiseGateDB = -38.0
            gainMultiplier = 1.45
        }
    }
    
    // 6 Bandas en escala logarítmica (Hz)
    public static let bands: [(low: Float, high: Float, label: String)] = [
        (40.0, 120.0, "Sub-Bass"),
        (120.0, 300.0, "Bass"),
        (300.0, 800.0, "Low-Mids"),
        (800.0, 2000.0, "High-Mids"),
        (2000.0, 5000.0, "Presence"),
        (5000.0, 12000.0, "Brilliance")
    ]
}
