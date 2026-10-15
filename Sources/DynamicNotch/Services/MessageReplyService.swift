import Foundation
import AppKit

/// Servicio encargado del envío de respuestas rápidas (Quick Reply)
/// hacia WhatsApp (Desktop / Web), Mensajes o notificaciones del sistema.
public final class MessageReplyService {
    public static let shared = MessageReplyService()
    
    private init() {}
    
    /// Despacha la respuesta redactada por el usuario desde la isla dinámica
    public func sendReply(to recipient: String, message: String, app: String = "WhatsApp") {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        print("[MessageReplyService] Enviando respuesta a '\(recipient)' vía \(app): \"\(trimmed)\"")
        
        let encodedMessage = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        
        if app.lowercased().contains("whatsapp") {
            let cleanNumber = recipient.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            
            let isDesktopInstalled = NSWorkspace.shared.runningApplications.contains(where: {
                $0.bundleIdentifier?.lowercased().contains("whatsapp") ?? false
            }) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") != nil
            
            if isDesktopInstalled {
                // 1. Envío prioritario a través de WhatsApp Desktop oficial
                let urlStr = cleanNumber.count >= 8 ?
                    "whatsapp://send?phone=\(cleanNumber)&text=\(encodedMessage)" :
                    "whatsapp://send?text=\(encodedMessage)"
                
                if let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                // 2. Envío a través de WhatsApp Web en el navegador por defecto
                let webUrlStr = cleanNumber.count >= 8 ?
                    "https://web.whatsapp.com/send?phone=\(cleanNumber)&text=\(encodedMessage)" :
                    "https://web.whatsapp.com/send?text=\(encodedMessage)"
                
                if let url = URL(string: webUrlStr) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        
        // Notificación distribuida para extensiones o automatizaciones
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
