import Foundation
import AppKit

/// Servicio encargado del envío de respuestas rápidas (Quick Reply)
/// hacia WhatsApp Web, WhatsApp Desktop o notificaciones del sistema.
public final class MessageReplyService {
    public static let shared = MessageReplyService()
    
    /// Por defecto usamos WhatsApp Web para no abrir apps de escritorio desactualizadas
    public var preferWhatsAppWeb: Bool = true
    
    private init() {}
    
    /// Despacha la respuesta redactada por el usuario desde la isla dinámica
    public func sendReply(
        to recipient: String,
        message: String,
        app: String = "WhatsApp",
        openBrowser: Bool = false
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        print("[MessageReplyService] ✅ Respuesta redactada para '\(recipient)' vía \(app): \"\(trimmed)\"")
        
        let encodedMessage = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        
        if app.lowercased().contains("whatsapp") {
            let cleanNumber = recipient.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            
            if preferWhatsAppWeb {
                // Solo si el usuario explícitamente lo solicita o hay un número real abrimos la pestaña web
                if openBrowser && cleanNumber.count >= 8 {
                    let webUrlStr = "https://web.whatsapp.com/send?phone=\(cleanNumber)&text=\(encodedMessage)"
                    if let url = URL(string: webUrlStr) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                // Modo Desktop App (solo si preferWhatsAppWeb es false)
                let urlStr = cleanNumber.count >= 8 ?
                    "whatsapp://send?phone=\(cleanNumber)&text=\(encodedMessage)" :
                    "whatsapp://send?text=\(encodedMessage)"
                
                if let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        
        // Notificación distribuida del sistema para extensiones de navegador / userscripts
        let userInfo: [String: Any] = [
            "recipient": recipient,
            "message": trimmed,
            "app": app,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.luisrandom.DynamicNotch.messageSent"),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}
