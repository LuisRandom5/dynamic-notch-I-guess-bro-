import SwiftUI
import AppKit
import Combine

/// Datos estructurados de la notificación activa para renderizado directo sin pérdida de identidad en SwiftUI
public struct NotificationPayload: Equatable {
    public let id: String
    public let title: String
    public let message: String
    public let handle: String
    public let avatar: NSImage?
    public let appName: String
    public let appIcon: String
    public let tintColor: Color
    public let enableQuickReply: Bool
    
    public init(
        id: String,
        title: String,
        message: String,
        handle: String,
        avatar: NSImage?,
        appName: String,
        appIcon: String,
        tintColor: Color,
        enableQuickReply: Bool = true
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.handle = handle
        self.avatar = avatar
        self.appName = appName
        self.appIcon = appIcon
        self.tintColor = tintColor
        self.enableQuickReply = enableQuickReply
    }
    
    public static func == (lhs: NotificationPayload, rhs: NotificationPayload) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.message == rhs.message &&
        lhs.handle == rhs.handle &&
        lhs.appName == rhs.appName &&
        lhs.appIcon == rhs.appIcon &&
        lhs.enableQuickReply == rhs.enableQuickReply
    }
}

/// Proveedor de Live Activities para Notificaciones Dinámicas estilo Dynamic Island (WhatsApp, Mensajes, Slack, Alertas)
/// con soporte para Swipe Down y Respuesta Rápida interactiva (Quick Reply).
public final class NotificationActivityProvider: ObservableObject {
    public static let shared = NotificationActivityProvider()
    
    // Dimensiones canónicas de la tarjeta de notificación compacta y expandida (Quick Reply)
    public static let compactWidth: CGFloat = 396
    public static let compactHeight: CGFloat = 96
    public static let expandedWidth: CGFloat = 424
    public static let expandedHeight: CGFloat = 186
    public static let topRadius: CGFloat = 24
    public static let compactBottomRadius: CGFloat = 28
    public static let expandedBottomRadius: CGFloat = 34
    
    @Published public private(set) var isNotificationActive: Bool = false
    @Published public private(set) var isQuickReplyExpanded: Bool = false
    @Published public private(set) var currentNotificationId: String? = nil
    @Published public private(set) var currentPayload: NotificationPayload? = nil
    @Published public var dragPullOffset: CGFloat = 0
    @Published public var dynamicReplyHeight: CGFloat = 186
    
    // Callbacks opcionales por compatibilidad
    public var onExpandRequested: (() -> Void)?
    public var onCollapseRequested: (() -> Void)?
    public var onDismissRequested: (() -> Void)?
    
    private init() {}
    
    public func updateReplyHeight(_ height: CGFloat) {
        let clamped = max(NotificationActivityProvider.expandedHeight, min(height, 280))
        if abs(dynamicReplyHeight - clamped) > 1.0 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.dynamicReplyHeight = clamped
            }
        }
    }
    
    public func setNotificationState(active: Bool, expanded: Bool, id: String?) {
        self.isNotificationActive = active
        self.isQuickReplyExpanded = expanded
        self.currentNotificationId = id
        if !active {
            self.dragPullOffset = 0
            self.dynamicReplyHeight = NotificationActivityProvider.expandedHeight
        } else if !expanded {
            self.dynamicReplyHeight = NotificationActivityProvider.expandedHeight
        }
    }
    
    /// Limpia el estado si la actividad removida en ActivityCenter corresponde a la notificación actual
    public func handleActivityRemoved(id: String) {
        guard currentNotificationId == id else { return }
        DNDLogger.log("NotificationActivityProvider.handleActivityRemoved -> limpiando estado para id=\(id)")
        NotchWindowManager.shared.setAllowsKeyInput(false)
        setNotificationState(active: false, expanded: false, id: nil)
        currentPayload = nil
    }
    
    /// Actualiza en caliente el título, mensaje y avatar de la notificación activa sin parpadeo
    public func updateActiveNotification(title: String, message: String, handle: String? = nil, avatar: NSImage? = nil, enableQuickReply: Bool? = nil) {
        guard let current = currentPayload else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.currentPayload = NotificationPayload(
                id: current.id,
                title: title,
                message: message,
                handle: handle ?? title,
                avatar: avatar ?? current.avatar,
                appName: current.appName,
                appIcon: current.appIcon,
                tintColor: current.tintColor,
                enableQuickReply: enableQuickReply ?? current.enableQuickReply
            )
        }
    }
    
    /// Expande la notificación activa al modo Quick Reply actualizando directamente dimensiones, foco de teclado y timer
    public func expandQuickReply() {
        guard isNotificationActive else {
            DNDLogger.log("NotificationActivityProvider.expandQuickReply ignorado: isNotificationActive=false")
            return
        }
        guard !isQuickReplyExpanded else { return }
        
        // Si la notificación no admite Quick Reply (p. ej. "Tienes mensajes sin leer" genérico),
        // abrir la app asociada en lugar de abrir un campo de texto inútil
        guard currentPayload?.enableQuickReply ?? true else {
            DNDLogger.log("NotificationActivityProvider.expandQuickReply -> Quick Reply deshabilitado para esta notificación, abriendo app asociada")
            if currentPayload?.appName.lowercased().contains("whatsapp") == true {
                WhatsAppWebObserverService.shared.activateWhatsAppWeb()
            }
            dismissNotification()
            return
        }
        
        DNDLogger.log("NotificationActivityProvider.expandQuickReply -> EXPANDIENDO Quick Reply (id=\(currentNotificationId ?? "nil"))")
        
        // Si el reproductor o la bandeja estaban abiertos, colapsarlos para que no tapen la notificación
        if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
            AppState.shared.isPlayerDetailExpanded = false
            AppState.shared.mode = AppState.shared.shouldShowCompact ? .compact : .idle
        }
        
        // Pausar de inmediato el temporizador de cierre automático para que el usuario pueda escribir sin límite de tiempo
        if let id = currentNotificationId {
            ActivityCenter.shared.pauseDismissTimer(for: id)
        }
        
        // Habilitar entrada de teclado en el panel del Notch antes de enfocar el TextField
        NotchWindowManager.shared.setAllowsKeyInput(true)
        AppState.shared.hapticService.triggerExpand()
        
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            self.dragPullOffset = 0
            self.isQuickReplyExpanded = true
            ActivityCenter.shared.customCardWidth = Self.expandedWidth
            ActivityCenter.shared.customCardHeight = Self.expandedHeight
            ActivityCenter.shared.customTopRadius = Self.topRadius
            ActivityCenter.shared.customBottomRadius = Self.expandedBottomRadius
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
        onExpandRequested?()
    }
    
    /// Colapsa el cuadro de respuesta rápida de vuelta a la tarjeta compacta de notificación
    public func collapseQuickReply() {
        guard isNotificationActive && isQuickReplyExpanded else { return }
        
        DNDLogger.log("NotificationActivityProvider.collapseQuickReply -> COLAPSANDO Quick Reply (id=\(currentNotificationId ?? "nil"))")
        NotchWindowManager.shared.setAllowsKeyInput(false)
        AppState.shared.hapticService.triggerSnap()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            self.dragPullOffset = 0
            self.isQuickReplyExpanded = false
            ActivityCenter.shared.customCardWidth = Self.compactWidth
            ActivityCenter.shared.customCardHeight = Self.compactHeight
            ActivityCenter.shared.customTopRadius = Self.topRadius
            ActivityCenter.shared.customBottomRadius = Self.compactBottomRadius
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
        onCollapseRequested?()
    }
    
    /// Descarta la notificación activa y la contrae hacia el notch
    public func dismissNotification() {
        guard isNotificationActive else { return }
        let idToDismiss = currentNotificationId
        DNDLogger.log("NotificationActivityProvider.dismissNotification -> DESCARTANDO (id=\(idToDismiss ?? "nil"))")
        
        NotchWindowManager.shared.setAllowsKeyInput(false)
        setNotificationState(active: false, expanded: false, id: nil)
        currentPayload = nil
        
        if let onDismiss = onDismissRequested {
            onDismiss()
        } else if let id = idToDismiss {
            ActivityCenter.shared.dismissWithAnimation(id: id)
        }
    }
    
    /// Muestra una notificación interactiva en la isla con soporte de swipe down para responder
    public func showNotification(
        title: String,
        message: String,
        handle: String = "",
        avatar: NSImage? = nil,
        appIcon: String = "message.fill",
        appName: String = "WhatsApp",
        tint: Color = Color(red: 0.15, green: 0.78, blue: 0.45),
        enableQuickReply: Bool = true,
        duration: TimeInterval? = 6.0
    ) {
        let lowerApp = appName.lowercased()
        let isWhatsApp = lowerApp.contains("whatsapp")
        let isDemoOrTest = title.lowercased().contains("demo") ||
                           message.lowercased().contains("demo") ||
                           handle.lowercased().contains("demo") ||
                           lowerApp.contains("demo") ||
                           lowerApp.contains("test")
        
        // REGLA: Los pop-ups en Dynamic Notch están restringidos exclusivamente a WhatsApp por ahora.
        // Las notificaciones de Instagram o cualquier otra app no deben ser pop up.
        guard isWhatsApp || isDemoOrTest else {
            DNDLogger.log("NotificationActivityProvider.showNotification: 🚫 Pop-up omitido para '\(appName)'. Pop-ups reservados para WhatsApp por ahora.")
            return
        }
        
        DNDLogger.log("NotificationActivityProvider.showNotification CALLED: title='\(title)', message='\(message)', handle='\(handle)'")
        let activityId = "notification_\(UUID().uuidString)"
        let resolvedHandle = handle.isEmpty ? title : handle
        
        // Generar avatar monograma instantáneo para jamás bloquear el hilo principal en ContactStore
        var contactAvatar = avatar
        if contactAvatar == nil {
            let initials = ContactLookupService.shared.extractInitials(from: resolvedHandle)
            contactAvatar = ContactLookupService.shared.generateMonogramAvatar(for: resolvedHandle, initials: initials)
            
            // Enriquecer en segundo plano con la foto real de Contactos si existe
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if let contactInfo = ContactLookupService.shared.lookupContact(name: title, handle: resolvedHandle),
                   let realAvatar = contactInfo.avatar {
                    DispatchQueue.main.async {
                        guard let self = self,
                              self.currentNotificationId == activityId,
                              let current = self.currentPayload else { return }
                        self.currentPayload = NotificationPayload(
                            id: current.id,
                            title: current.title,
                            message: current.message,
                            handle: current.handle,
                            avatar: realAvatar,
                            appName: current.appName,
                            appIcon: current.appIcon,
                            tintColor: current.tintColor
                        )
                    }
                }
            }
        }
        
        // Si el reproductor o la bandeja estaban abiertos, cerrarlos suavemente para dar prioridad visual a la notificación
        if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
            AppState.shared.isPlayerDetailExpanded = false
            AppState.shared.mode = AppState.shared.shouldShowCompact ? .compact : .idle
        }
        AppState.shared.setHoverState(false)
        NotchWindowManager.shared.setAllowsKeyInput(false)
        
        // Limpiar notificaciones previas en cola para que no queden timers huérfanos
        if let prevId = currentNotificationId, prevId != activityId {
            ActivityCenter.shared.remove(id: prevId)
        }
        
        let payload = NotificationPayload(
            id: activityId,
            title: title,
            message: message,
            handle: resolvedHandle,
            avatar: contactAvatar,
            appName: appName,
            appIcon: appIcon,
            tintColor: tint,
            enableQuickReply: enableQuickReply
        )
        self.currentPayload = payload
        setNotificationState(active: true, expanded: false, id: activityId)
        
        // Pre-configurar dimensiones del contenedor ANTES de publicar para que el hit-test y la geometría sean inmediatos
        ActivityCenter.shared.customCardWidth = Self.compactWidth
        ActivityCenter.shared.customCardHeight = Self.compactHeight
        ActivityCenter.shared.customTopRadius = Self.topRadius
        ActivityCenter.shared.customBottomRadius = Self.compactBottomRadius
        
        let replyView = QuickReplyNotificationView(
            id: activityId,
            title: title,
            message: message,
            handle: resolvedHandle,
            avatar: contactAvatar,
            appName: appName,
            appIcon: appIcon,
            tintColor: tint,
            enableQuickReply: enableQuickReply
        )
        
        let activity = LiveActivity(
            id: activityId,
            priority: 95,
            style: .card,
            customView: AnyView(replyView),
            tint: tint,
            duration: duration,
            onTap: {
                if enableQuickReply {
                    NotificationActivityProvider.shared.expandQuickReply()
                } else {
                    if appName.lowercased().contains("whatsapp") {
                        WhatsAppWebObserverService.shared.activateWhatsAppWeb()
                    } else if appName.lowercased().contains("mensaje") || appName.lowercased().contains("messages") || appName.lowercased().contains("imessage") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        }
                    }
                    NotificationActivityProvider.shared.dismissNotification()
                }
            }
        )
        
        DNDLogger.log("NotificationActivityProvider.showNotification -> publicada id=\(activityId), title='\(title)', enableQuickReply=\(enableQuickReply)")
        ActivityCenter.shared.publish(activity)
        NotchWindowManager.shared.updateHitAreaForCurrentState()
        AppState.shared.hapticService.triggerSnap()
        DNDLogger.log("NotificationActivityProvider.showNotification completado con éxito!")
    }
}
