import SwiftUI

/// Parámetros del morfeo líquido de las bolitas. La animación real de la app los lee en cada cuadro, así que
/// el Animation Studio (Debug) los edita en vivo. Se guardan en UserDefaults; "Restablecer" vuelve a los de
/// fábrica.
public final class LiquidMotionTuning: ObservableObject {
    public static let shared = LiquidMotionTuning()

    public struct Values: Codable, Equatable {
        /// Unión suave del contorno: a mayor valor, el cuello se estira más antes de romperse (pt)
        public var blend: Double = 11
        /// Tramo de m (desde 1) en el que la gota nace desde tamaño cero
        public var birthSpan: Double = 0.22
        /// Alto mínimo de la gota mientras sale (relativo a su tamaño final)
        public var minHeight: Double = 0.52
        /// Alargamiento máximo del óvalo al salir (0.62 = 62 % más ancho que alto)
        public var elongation: Double = 0.62
        /// Estiramiento por tensión superficial justo antes del corte
        public var tension: Double = 0.07
        /// Temblor de gelatina al soltarse
        public var wobble: Double = 0.07
        /// Resorte al salir (response en s, amortiguamiento 0…1)
        public var emergeResponse: Double = 1.84
        public var emergeDamping: Double = 0.70
        /// Resorte al regresar
        public var absorbResponse: Double = 1.55
        public var absorbDamping: Double = 0.94
        /// La isla se ensancha al dejar salir la gota y se abulta al recibirla (pt)
        public var widenImpulse: Double = 6
        public var absorbBulge: Double = 7
    }

    private static let key = "liquidMotionTuningV1"

    @Published public var values: Values {
        didSet {
            if let data = try? JSONEncoder().encode(values) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Values.self, from: data) {
            values = saved
        } else {
            values = Values()
        }
    }

    public func reset() { values = Values() }

    // Atajos para el código de animación
    public static var v: Values { shared.values }
}

/// Estado geométrico de la gota para un instante de la animación (m = 1 dentro del notch · 0 en su lugar ·
/// negativo = sobrepaso del resorte). Lo usan la animación real y el Animation Studio, así que ambos muestran
/// exactamente lo mismo.
public struct LiquidDropProfile {
    public let m: CGFloat
    public let travel: CGFloat
    public let scaleX: CGFloat
    public let scaleY: CGFloat
    public let phase: String

    public init(raw: CGFloat, tuning t: LiquidMotionTuning.Values = LiquidMotionTuning.v) {
        let m = min(1, max(0, raw))
        self.m = m
        travel = raw < 0 ? raw : m * m * (3 - 2 * m)
        let birth = Self.smoothstep((1 - m) / CGFloat(max(0.05, t.birthSpan)))
        let minH = CGFloat(t.minHeight)
        let heightScale = birth * (minH + (1 - minH) * Self.smoothstep((0.62 - m) / 0.50))
        let elongation = 1 + CGFloat(t.elongation) * Self.smoothstep((m - 0.14) / 0.32) * (1 - 0.7 * Self.smoothstep((m - 0.58) / 0.24))
        let tension = (m > 0.05 && m < 0.26) ? sin(.pi * (0.26 - m) / 0.21) : 0
        let wobble: CGFloat = raw < 0 ? min(1, -raw / 0.06) : 0
        let settle: CGFloat = raw < 0 ? 1 + min(0.06, -raw * 0.5) : 1
        scaleY = heightScale * settle * (1 - CGFloat(t.tension) * 0.7 * tension - CGFloat(t.wobble) * wobble)
        scaleX = heightScale * elongation * settle * (1 + CGFloat(t.tension) * tension + CGFloat(t.wobble) * wobble)
        switch m {
        case 0.85...: phase = "A · superficie unida"
        case 0.62..<0.85: phase = "B · protuberancia"
        case 0.30..<0.62: phase = "C · cuello"
        case 0.10..<0.30: phase = "D · estrangulamiento"
        default: phase = raw < 0 ? "E · asentamiento (sobrepaso)" : "E · asentamiento"
        }
    }

    static func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}
