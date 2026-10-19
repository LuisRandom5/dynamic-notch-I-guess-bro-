import Foundation

/// Escala única de relevancia (0–1000) para todas las actividades, como la `relevanceScore` de ActivityKit:
/// valores relativos; la más alta ocupa el notch y, con la misma, gana la que se inició primero
/// (ver PresentationEngine). Antes convivían dos escalas (40–100 y 500–1000) y, por ejemplo, un temporizador
/// (88) perdía contra el progreso de un agente (700).
///
/// Orden: avisos breves del sistema y lo que pide una respuesta, luego lo que está en curso.
public enum ActivityRelevance {
    /// Conexión de AirPods: evento de hardware de pocos segundos
    public static let hardwareEvent = 1000
    /// Llamada entrante
    public static let incomingCall = 950
    /// El temporizador terminó y está sonando
    public static let timerRinging = 950
    /// Llamada en curso, grabación
    public static let activeCall = 920
    /// Notificación con respuesta rápida (no tapa una llamada en curso)
    public static let notification = 900
    /// AirDrop enviando o recibiendo
    public static let transfer = 880
    /// Carga, batería baja
    public static let systemStatus = 860
    /// Temporizador en su último minuto (como la Isla Dinámica, sube de relevancia)
    public static let timerFinalMinute = 850
    /// Un agente pregunta o pide permiso
    public static let agentInteraction = 820
    /// Temporizador o cronómetro corriendo
    public static let timer = 800
    /// Progreso de un agente (Claude, Antigravity), descargas
    public static let backgroundTask = 700
    public static let generic = 600
    public static let music = 500
    /// Repisa con archivos: la más discreta, nunca desplaza a otra bolita
    public static let shelf = 400

    /// Una actividad que pide atención (p. ej. Claude esperando permiso) sube sobre las de su mismo tipo
    public static let attentionBoost = 100
    public static let maximum = 1000

    /// Relevancia efectiva para decidir la presentación
    public static func effective(base: Int, needsAttention: Bool) -> Int {
        needsAttention ? min(maximum, base + attentionBoost) : base
    }
}
