import SwiftUI
import AppKit

/// Proveedor de Live Activities para Notificaciones Dinámicas estilo Dynamic Island (WhatsApp, Mensajes, Slack, Alertas)
/// con soporte para Swipe Down y Respuesta Rápida interactiva (Quick Reply).
public final class NotificationActivityProvider {
    public static let shared = NotificationActivityProvider()
    
    private init() {}
    
    /// Muestra una notificación interactiva en la isla con soporte de swipe down para responder
    public func showNotification(
        title: String,
        message: String,
        handle: String = "",
        avatar: NSImage? = nil,
        appIcon: String = "message.fill",
        appName: String = "WhatsApp Web",
        tint: Color = Color(red: 0.15, green: 0.78, blue: 0.45),
        enableQuickReply: Bool = true,
        duration: TimeInterval? = 7.0
    ) {
        let activityId = "notification_\(UUID().uuidString)"
        
        // Consultar avatar real de contactos si no se suministró uno
        var contactAvatar = avatar
        if contactAvatar == nil {
            let contactInfo = ContactLookupService.shared.lookupContact(name: title, handle: handle)
            contactAvatar = contactInfo?.avatar
        }
        
        if enableQuickReply {
            let replyView = QuickReplyNotificationView(
                id: activityId,
                title: title,
                message: message,
                handle: handle.isEmpty ? title : handle,
                avatar: contactAvatar,
                appName: appName,
                appIcon: appIcon,
                tintColor: tint
            )
            
            let activity = LiveActivity(
                id: activityId,
                priority: 85,
                style: .card,
                customView: AnyView(replyView),
                tint: tint,
                duration: duration
            )
            
            ActivityCenter.shared.publish(activity)
            AppState.shared.hapticService.triggerSnap()
            return
        }
        
        // Fallback para notificaciones puramente informativas sin cuadro de texto
        let leading = AnyView(
            ZStack {
                Circle()
                    .fill(tint.opacity(0.20))
                    .frame(width: 44, height: 44)
                
                Image(systemName: appIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
            }
        )
        
        let center = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("ahora")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
        )
        
        let activity = LiveActivity(
            id: activityId,
            priority: 85,
            style: .card,
            leading: leading,
            center: center,
            tint: tint,
            duration: duration,
            onTap: {
                AppState.shared.hapticService.triggerSnap()
            }
        )
        
        ActivityCenter.shared.publish(activity)
        AppState.shared.hapticService.triggerSnap()
    }
}
