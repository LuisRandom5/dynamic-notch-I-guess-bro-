import Foundation
import AppKit
import SwiftUI
import ApplicationServices

/// Servicio en segundo plano para detección de mensajes entrantes de iMessage / Mensajes (macOS)
/// y despacho de respuestas rápidas (Quick Reply) de forma no invasiva.
public final class MessagesObserverService: ObservableObject {
    public static let shared = MessagesObserverService()
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enableMessagesObserver")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }
    
    private var timer: Timer?
    private var isQuerying: Bool = false
    private let queue = DispatchQueue(label: "com.dynamicnotch.messages.observer", qos: .utility)
    
    private struct ChatRecord {
        let message: String
        let time: String
        let isUnread: Bool
        var lastAlertedAt: Date
    }
    private var knownRecords: [String: ChatRecord] = [:]
    private var lastBannerSignature: String = ""
    private var lastBannerAlertedAt: Date = .distantPast
    private var airDropCloseAttempts = 0
    private var lastAirDropCloseAttemptAt: Date = .distantPast
    private var lastAirDropBannerSignature: String = ""
    private var isFirstCheck: Bool = true
    
    private init() {
        if UserDefaults.standard.object(forKey: "enableMessagesObserver") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "enableMessagesObserver")
        }
    }
    
    public func start() {
        guard isEnabled, timer == nil else { return }
        
        // Sondeo ultra-rápido a 0.12s para interceptar y sustituir notificaciones al instante sin latencia visual
        let newTimer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.pollMessages()
        }
        newTimer.tolerance = 0.02
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private var tick = 0
    private static var pidCache: [String: pid_t] = [:]
    private static var pidCacheObservers: [NSObjectProtocol] = []

    /// pid de una app (en caché; se limpia al abrir o cerrar apps). Sólo en el hilo principal
    private static func cachedPid(for bundleId: String) -> pid_t? {
        if pidCacheObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                pidCacheObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    pidCache.removeAll()
                })
            }
        }
        if let pid = pidCache[bundleId] { return pid > 0 ? pid : nil }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier ?? 0
        pidCache[bundleId] = pid
        return pid > 0 ? pid : nil
    }

    public func pollMessages() {
        guard isEnabled, !isQuerying else { return }
        isQuerying = true
        // Los procesos se buscan en caché (pedir la lista de apps 8 veces por segundo costaba ~2 % de CPU) y la
        // lista de conversaciones de Mensajes se revisa una vez por segundo, no en cada vuelta
        let ncPid = Self.cachedPid(for: "com.apple.notificationcenterui")
        tick &+= 1
        let smsPid = tick % 8 == 0 ? Self.cachedPid(for: "com.apple.MobileSMS") : nil
        
        queue.async { [weak self] in
            defer { self?.isQuerying = false }
            guard let self = self else { return }
            
            // 1. Detección en tiempo real de Banners de Notificación del Sistema (com.apple.notificationcenterui)
            let didDetectBanner = self.checkNotificationCenterBanners(pid: ncPid)
            
            // 2. Si la app Mensajes (com.apple.MobileSMS) está abierta, inspección profunda de la lista de conversaciones
            if !didDetectBanner, let smsPid {
                self.checkMessagesAppConversations(pid: smsPid)
            }
            
            if self.isFirstCheck {
                self.isFirstCheck = false
            }
        }
    }
    
    // MARK: - Canal 1: Banners del Centro de Notificaciones (Intercepción y Reemplazo)
    private func checkNotificationCenterBanners(pid: pid_t?) -> Bool {
        guard let pid else { return false }
        
        let appRef = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winRef) == .success,
              let wins = winRef as? [AXUIElement], wins.count > 2 else {
            return false
        }
        
        for win in wins {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""
            
            // Los banners activos tienen títulos distintos a las áreas de estado/previsión
            if title == "Estado" || title == "Previsión" { continue }
            
            let strings = collectAXStrings(win)
            guard !strings.isEmpty else { continue }
            
            // Regla estricta: Notificaciones de Instagram NUNCA deben generar pop-up en Dynamic Notch
            // y NUNCA se debe descartar su banner nativo de macOS
            let isInstagram = strings.contains { s in
                let l = s.lowercased()
                return l.contains("instagram") || l.contains("threads")
            }
            if isInstagram {
                continue
            }
            
            // AirDrop: Dynamic Notch muestra su propia animación (AirDropTransferMonitor), así que el aviso
            // nativo de macOS se cierra al instante
            let isAirDrop = strings.contains { $0.lowercased().contains("airdrop") }
            // Ajuste "Reemplazar avisos de AirDrop" apagado: el aviso nativo se respeta
            if isAirDrop && !AppState.shared.airDropReplacesNative { continue }
            if isAirDrop {
                let signature = strings.prefix(3).joined(separator: "|")
                let now = Date()
                if signature != lastAirDropBannerSignature {
                    lastAirDropBannerSignature = signature
                    airDropCloseAttempts = 0
                    lastAirDropCloseAttemptAt = .distantPast
                }
                // macOS 27 acepta "Cerrar" (.success) sin quitar el aviso si llega mientras éste aún está entrando:
                // se reintenta con pausas mientras siga en pantalla
                if airDropCloseAttempts < 8 && now.timeIntervalSince(lastAirDropCloseAttemptAt) >= 0.3 {
                    airDropCloseAttempts += 1
                    lastAirDropCloseAttemptAt = now
                    let used = dismissNativeBanner(win)
                    if airDropCloseAttempts == 1 || airDropCloseAttempts == 8 {
                        DNDLogger.log("MessagesObserverService: aviso nativo de AirDrop, intento \(airDropCloseAttempts) → \(used ?? "sin acción"): \(strings.prefix(2))")
                    }
                }
                continue
            }
            
            // Detectar el origen
            let isWhatsApp = strings.contains { s in
                let l = s.lowercased()
                return l.contains("whatsapp")
            }
            let isAgent = strings.contains { s in
                let l = s.lowercased()
                return l.contains("antigravity") || l.contains("editor de scripts") || l.contains("terminal") || l.contains("tarea completada") || l.contains("cortex")
            }
            
            // Por requerimiento del usuario: los pop-ups en Dynamic Notch son exclusivamente para WhatsApp por ahora (y avisos de agentes)
            // Cualquier otra app (Instagram, correo, recordatorios, sistema) se mantiene nativa en macOS sin interferencia
            guard isWhatsApp || isAgent else {
                continue
            }
            
            // Cerrar y descartar el banner nativo de macOS ÚNICAMENTE para las apps autorizadas a reemplazarlo
            _ = dismissNativeBanner(win)
            
            // Filtrar etiquetas del sistema
            let cleanStrings = strings.filter { s in
                let l = s.lowercased()
                return !l.contains("whatsapp") &&
                       l != "notification center" && l != "centro de notificaciones" &&
                       l != "editor de scripts" &&
                       !l.isEmpty
            }
            
            guard !cleanStrings.isEmpty else { continue }
            
            let sender = cleanStrings[0]
            let message = cleanStrings.count > 1 ? cleanStrings[1] : (isWhatsApp ? "Nuevo mensaje" : "Notificación")
            
            let sig = "\(sender): \(message)"
            if sig == self.lastBannerSignature && Date().timeIntervalSince(self.lastBannerAlertedAt) < 4.0 {
                return true
            }
            
            self.lastBannerSignature = sig
            self.lastBannerAlertedAt = Date()
            
            if isAgent {
                DNDLogger.log("MessagesObserverService: 🤖 Notificación nativa de Antigravity interceptada y reemplazada en Dynamic Notch: '\(sender)' - \(DNDLogger.redact(message))")
                DispatchQueue.main.async {
                    AgentActivityProvider.shared.showInteraction(
                        type: .notification,
                        title: sender.isEmpty ? "Antigravity" : sender,
                        subtitle: "Antigravity",
                        message: message,
                        duration: 5.5
                    )
                }
            } else if isWhatsApp {
                DNDLogger.log("MessagesObserverService: 🔔 Notificación de WhatsApp interceptada para Dynamic Notch: '\(sender)': \(DNDLogger.redact(message))")
                DispatchQueue.main.async {
                    NotificationActivityProvider.shared.showNotification(
                        title: sender,
                        message: message,
                        handle: sender,
                        appIcon: "message.fill",
                        appName: "WhatsApp",
                        tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                        enableQuickReply: true,
                        duration: 6.0
                    )
                }
            }
            return true
        }
        
        return false
    }
    
    /// Palabras de las acciones/botones que cierran un aviso (español e inglés)
    private static let closeWords = ["cerrar", "close", "dismiss", "descartar", "borrar", "clear", "eliminar"]
    
    /// Texto con la estructura de Accesibilidad de un elemento (roles, textos, identificadores y acciones)
    private func axTreeDescription(_ elem: AXUIElement, depth: Int = 0) -> String {
        guard depth <= 8 else { return "" }
        func attr(_ name: String) -> String {
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, name as CFString, &ref)
            return (ref as? String) ?? ""
        }
        var acts: CFArray?
        AXUIElementCopyActionNames(elem, &acts)
        let actions = (acts as? [String] ?? []).map { $0.replacingOccurrences(of: "\n", with: " ") }
        var line = String(repeating: "  ", count: depth)
            + "\(attr("AXRole")) [\(attr("AXSubrole"))] id='\(attr("AXIdentifier"))' t='\(attr("AXTitle"))' d='\(attr("AXDescription"))' acts=\(actions)\n"
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement] ?? []) {
            line += axTreeDescription(child, depth: depth + 1)
        }
        return line
    }
    
    @discardableResult
    /// Cierra un aviso nativo. Devuelve qué acción se usó ("rol/acción@identificador"), o nil si no hubo ninguna.
    /// `skipping` excluye acciones ya intentadas que no lo cerraron.
    private func dismissNativeBanner(_ elem: AXUIElement, skipping: Set<String> = [], depth: Int = 0) -> String? {
        if depth > 8 { return nil }
        func attr(_ name: String) -> String {
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, name as CFString, &ref)
            return (ref as? String) ?? ""
        }
        let role = attr(kAXRoleAttribute)
        let where_ = "\(role)#\(depth)@\(attr(kAXIdentifierAttribute))"
        
        var actRef: CFArray?
        AXUIElementCopyActionNames(elem, &actRef)
        if let actions = actRef as? [String] {
            for a in actions {
                let l = a.lowercased()
                let key = "\(where_)/\(a.replacingOccurrences(of: "\n", with: " "))"
                guard !skipping.contains(key) else { continue }
                if Self.closeWords.contains(where: { l.contains($0) }) || a == "AXCancel" {
                    if AXUIElementPerformAction(elem, a as CFString) == .success {
                        return key
                    }
                }
            }
        }
        
        if role == "AXButton" || role == "AXPressable" {
            let label = [attr(kAXDescriptionAttribute), attr(kAXTitleAttribute), attr(kAXIdentifierAttribute)]
                .joined(separator: " ").lowercased()
            let key = "\(where_)/AXPress"
            if !skipping.contains(key), Self.closeWords.contains(where: { label.contains($0) }) {
                if AXUIElementPerformAction(elem, "AXPress" as CFString) == .success {
                    return key
                }
            }
        }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for c in children {
                if let used = dismissNativeBanner(c, skipping: skipping, depth: depth + 1) { return used }
            }
        }
        return nil
    }
    
    // MARK: - Canal 2: App Mensajes Abierta (com.apple.MobileSMS)
    private func checkMessagesAppConversations(pid: pid_t) {
        let appRef = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winRef) == .success,
              let wins = winRef as? [AXUIElement], let mainWindow = wins.first else {
            return
        }
        
        guard let convosGroup = findAXGroup(elem: mainWindow, descName: "Conversaciones") else {
            return
        }
        
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(convosGroup, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }
        
        for item in children.prefix(12) {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descRef)
            guard let desc = descRef as? String, !desc.isEmpty else { continue }
            
            // El formato estándar de macOS para cada ítem de conversación es:
            // "Nombre Del Contacto, No leídos, Texto del mensaje , 9:58 p. m."
            // o en inglés: "Sender Name, Unread, Message text , 9:58 PM"
            // o si ya está leído: "Nombre Del Contacto, Texto del mensaje , 9:58 p. m."
            let parts = desc.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2 else { continue }
            
            let contact = parts[0]
            guard !contact.isEmpty else { continue }
            
            let isUnread = parts.contains(where: {
                let l = $0.lowercased()
                return l == "no leídos" || l == "no leído" || l == "unread"
            })
            
            let time = parts.last ?? ""
            let messageParts = parts.dropFirst().filter { p in
                let l = p.lowercased()
                return l != "no leídos" && l != "no leído" && l != "unread" && l != "fijada" && l != "pinned" && p != time
            }
            let message = messageParts.joined(separator: ", ")
            
            let prev = knownRecords[contact]
            
            if isFirstCheck {
                knownRecords[contact] = ChatRecord(
                    message: message,
                    time: time,
                    isUnread: isUnread,
                    lastAlertedAt: Date()
                )
                continue
            }
            
            var shouldAlert = false
            if isUnread {
                if let p = prev {
                    if !p.isUnread || p.message != message || p.time != time {
                        shouldAlert = true
                    }
                } else {
                    shouldAlert = true
                }
            } else if let p = prev {
                // Si la conversación está abierta en primer plano pero la ventana no tiene foco
                let isFrontmost = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.MobileSMS")
                if !isFrontmost && p.message != message && !message.isEmpty && p.time != time {
                    // Verificar que no sea mensaje saliente
                    let lower = message.lowercased()
                    if !lower.hasPrefix("tu mensaje") && !lower.hasPrefix("you:") && !lower.hasPrefix("tú:") {
                        shouldAlert = true
                    }
                }
            }
            
            if shouldAlert, let p = prev, Date().timeIntervalSince(p.lastAlertedAt) < 2.5 && p.message == message {
                shouldAlert = false
            }
            
            knownRecords[contact] = ChatRecord(
                message: message,
                time: time,
                isUnread: isUnread,
                lastAlertedAt: shouldAlert ? Date() : (prev?.lastAlertedAt ?? Date())
            )
            
            if shouldAlert {
                DNDLogger.log("MessagesObserverService: 🔔 NUEVO MENSAJE DETECTADO en app Mensajes de '\(contact)': \(DNDLogger.redact(message)) (hora: \(time))")
                dispatchNotification(sender: contact, message: message.isEmpty ? "Nuevo mensaje" : message)
                break
            }
        }
    }
    
    // MARK: - Despacho de Notificación a Dynamic Notch
    private func dispatchNotification(sender: String, message: String) {
        DispatchQueue.main.async {
            if NotificationActivityProvider.shared.isNotificationActive &&
                NotificationActivityProvider.shared.isQuickReplyExpanded {
                return
            }
            
            // Buscar avatar en Contactos nativos de macOS
            let contactInfo = ContactLookupService.shared.lookupContact(name: sender)
            
            NotificationActivityProvider.shared.showNotification(
                title: contactInfo?.name ?? sender,
                message: message,
                handle: sender,
                avatar: contactInfo?.avatar,
                appIcon: "message.fill",
                appName: "iMessage",
                tint: Color(red: 0.18, green: 0.52, blue: 0.98), // Azul vibrante iMessage
                enableQuickReply: true,
                duration: 6.0
            )
        }
    }
    
    // MARK: - Envío de Respuesta Rápida (Quick Reply)
    public func deliverQuickReply(message: String, recipient: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let escapedMsg = trimmed.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedRecipient = recipient.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = """
        tell application "Messages"
            set targetChat to missing value
            repeat with c in chats
                try
                    if (name of c as string) contains "\(escapedRecipient)" or (id of c as string) contains "\(escapedRecipient)" then
                        set targetChat to c
                        exit repeat
                    end if
                end try
                repeat with p in participants of c
                    try
                        if (name of p as string) contains "\(escapedRecipient)" or (full name of p as string) contains "\(escapedRecipient)" or (handle of p as string) contains "\(escapedRecipient)" then
                            set targetChat to c
                            exit repeat
                        end if
                    end try
                end repeat
                if targetChat is not missing value then exit repeat
            end repeat
            
            if targetChat is not missing value then
                send "\(escapedMsg)" to targetChat
            else
                try
                    set iMessageService to 1st service whose service type is iMessage
                    set newBuddy to participant "\(escapedRecipient)" of iMessageService
                    send "\(escapedMsg)" to newBuddy
                end try
            end if
        end tell
        """
        
        queue.async {
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    DNDLogger.log("MessagesObserverService: Error enviando respuesta AppleScript: \(err)")
                } else {
                    DNDLogger.log("MessagesObserverService: ✅ Respuesta enviada exitosamente a '\(recipient)' vía iMessage: '\(trimmed)'")
                }
            }
        }
    }
    
    // MARK: - Simulación para Pruebas
    public func simulateTestNotification() {
        let contactInfo = ContactLookupService.shared.lookupContact(name: "Hermano")
        NotificationActivityProvider.shared.showNotification(
            title: "Hermano",
            message: "¡Hola! ¿Cómo vas con el notch dinámico?",
            handle: "Hermano",
            avatar: contactInfo?.avatar,
            appIcon: "message.fill",
            appName: "iMessage",
            tint: Color(red: 0.18, green: 0.52, blue: 0.98),
            enableQuickReply: true,
            duration: 6.0
        )
    }
    
    // MARK: - Helpers AXUIElement
    private func findAXGroup(elem: AXUIElement, descName: String, depth: Int = 0) -> AXUIElement? {
        if depth > 10 { return nil }
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        if (descRef as? String) == descName { return elem }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for c in children {
                if let f = findAXGroup(elem: c, descName: descName, depth: depth + 1) { return f }
            }
        }
        return nil
    }
    
    private func collectAXStrings(_ elem: AXUIElement, depth: Int = 0) -> [String] {
        if depth > 8 { return [] }
        var results: [String] = []
        var valRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valRef)
        AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        
        if let v = valRef as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(v) }
        if let t = titleRef as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(t) }
        if let d = descRef as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(d) }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for c in children.prefix(20) {
                results.append(contentsOf: collectAXStrings(c, depth: depth + 1))
            }
        }
        return results
    }
}
