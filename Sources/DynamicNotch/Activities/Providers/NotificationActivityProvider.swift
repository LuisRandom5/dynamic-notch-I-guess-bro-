import SwiftUI

/// Proveedor de Live Activities para Notificaciones Dinámicas estilo Dynamic Island (WhatsApp, Mensajes, Slack, Alertas)
public final class NotificationActivityProvider {
    public static let shared = NotificationActivityProvider()
    
    private init() {}
    
    public func showNotification(
        title: String,
        message: String,
        appIcon: String = "message.fill",
        tint: Color = DesignTokens.green,
        duration: TimeInterval = 4.0
    ) {
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
            id: "dynamic_notification_\(UUID().uuidString)",
            priority: 90,
            style: .card,
            leading: leading,
            center: center,
            tint: tint,
            duration: duration,
            onTap: {
                // Haptic de confirmación
                AppState.shared.hapticService.triggerSnap()
            }
        )
        
        ActivityCenter.shared.publish(activity)
        AppState.shared.hapticService.triggerSnap()
    }
}
