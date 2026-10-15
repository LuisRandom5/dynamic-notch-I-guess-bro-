import Foundation

// MARK: - Spectrum Analysis & Envelope Metrics
public struct SpectrumMetrics {
    // Envelope attack & release calibrados para respuesta rítmica punchy y viva
    public static var attackMs: Double = 10.0          // Ataque supersónico (~10 ms: snap instantáneo en bombos y cajas)
    public static var releaseMs: Double = 140.0        // Caída ágil (~140 ms: permite a las barras rebotar al compás del ritmo)
    public static var noiseGateDB: Float = -40.0       // Puerta de ruido (~-40 dBFS: corta la reverberación continua para máximo contraste)
    public static var agcDecayDBPerSec: Float = 5.0    // Adaptación AGC dinámica (5.0 dB/s)
    public static var gainMultiplier: Float = 1.25     // Ganancia perceptual balanceada
    public static var bluetoothDelayMs: Double = 0.0   // Retardo para auriculares Bluetooth (0 a 350 ms)
    
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
