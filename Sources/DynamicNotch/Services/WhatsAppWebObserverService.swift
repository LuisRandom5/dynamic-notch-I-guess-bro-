import Foundation
import AppKit
import SwiftUI

/// Servicio en segundo plano para detección automática de mensajes entrantes en WhatsApp Web
/// Funciona de forma no invasiva inspeccionando navegadores compatibles (Safari, Chrome, Arc, Brave, Edge).
public final class WhatsAppWebObserverService {
    public static let shared = WhatsAppWebObserverService()
    
    public var isEnabled: Bool = true
    
    private var timer: Timer?
    private var lastUnreadCount: Int? = nil
    private var lastSeenTitle: String = ""
    private var isFirstCheck: Bool = true
    private var isQuerying: Bool = false
    
    private init() {}
    
    /// Inicia el monitor en segundo plano
    public func start() {
        guard timer == nil else { return }
        
        // Ejecutar primer sondeo suavemente tras 2 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pollWhatsAppWeb()
        }
        
        // Bucle periódico cada 2.5 segundos en segundo plano
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.pollWhatsAppWeb()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Realiza un sondeo inmediato de WhatsApp Web
    public func pollWhatsAppWeb() {
        guard isEnabled && !isQuerying else { return }
        
        // Verificar si algún navegador compatible está ejecutándose
        let runningApps = NSWorkspace.shared.runningApplications
        let hasBrowser = runningApps.contains { app in
            guard let bid = app.bundleIdentifier?.lowercased() else { return false }
            return bid.contains("safari") || bid.contains("chrome") || bid.contains("browser") || bid.contains("brave") || bid.contains("edge")
        }
        guard hasBrowser else { return }
        
        isQuerying = true
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.isQuerying = false }
            guard let self = self else { return }
            
            let titles = self.fetchWhatsAppTitlesFromBrowsers()
            guard !titles.isEmpty else { return }
            
            for rawTitle in titles {
                self.processWhatsAppTitle(rawTitle)
            }
        }
    }
    
    // MARK: - Extracción de Títulos vía AppleScript Ligero
    private func fetchWhatsAppTitlesFromBrowsers() -> [String] {
        var results: [String] = []
        let sep = "___NOTCH_SEP___"
        
        // 1. Safari (Búsqueda en todas las pestañas de todas las ventanas)
        if isAppRunning("com.apple.Safari") {
            let script = """
            tell application "Safari"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "WhatsApp" then
                            set end of res to (name of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
            if let output = runAppleScript(script) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        
        // 2. Google Chrome
        if isAppRunning("com.google.Chrome") {
            let script = """
            tell application "Google Chrome"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "WhatsApp" then
                            set end of res to (title of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
            if let output = runAppleScript(script) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        
        // 3. Arc
        if isAppRunning("company.thebrowser.Browser") {
            let script = """
            tell application "Arc"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "WhatsApp" then
                            set end of res to (title of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
            if let output = runAppleScript(script) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        
        // 4. Brave Browser
        if isAppRunning("com.brave.Browser") {
            let script = """
            tell application "Brave Browser"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "WhatsApp" then
                            set end of res to (title of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
            if let output = runAppleScript(script) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        
        // 5. Microsoft Edge
        if isAppRunning("com.microsoft.edgemac") {
            let script = """
            tell application "Microsoft Edge"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "WhatsApp" then
                            set end of res to (title of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
            if let output = runAppleScript(script) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        
        return results
    }
    
    private func isAppRunning(_ bundleId: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }
    
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if errorInfo == nil {
            return result.stringValue
        }
        return nil
    }
    
    private func parseScriptList(_ raw: String, sep: String) -> [String] {
        return raw.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    
    // MARK: - Detección de Mensajes Nuevos y Notificación en la Isla
    private func processWhatsAppTitle(_ title: String) {
        // Ejemplos comunes de títulos en WhatsApp Web:
        // "(101) WhatsApp"
        // "(102) WhatsApp"
        // "(1) Carlos: ¡Hola bro!"
        // "(1) Mamá: ¿A qué hora vienes?"
        // "WhatsApp"
        
        // Extraer número de no leídos dentro de los paréntesis iniciales "(N)"
        var unreadCount: Int? = nil
        var contentAfterCount = title
        
        if let match = title.range(of: #"^\((\d+)\)\s*"#, options: .regularExpression) {
            let countStr = title[match].filter { $0.isNumber }
            unreadCount = Int(countStr)
            contentAfterCount = String(title[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Si es el primer chequeo, registrar estado base sin disparar falsas alarmas
        if isFirstCheck {
            isFirstCheck = false
            lastUnreadCount = unreadCount
            lastSeenTitle = title
            return
        }
        
        let previousCount = lastUnreadCount ?? 0
        let currentCount = unreadCount ?? 0
        
        // Si el usuario abrió chats y el conteo bajó, sincronizar silenciosamente
        if currentCount < previousCount {
            self.lastUnreadCount = currentCount
            self.lastSeenTitle = title
            return
        }
        
        // Si el conteo de no leídos aumentó, o si el título cambió con un mensaje específico:
        let hasNewMessage = (currentCount > previousCount) ||
                            (title != lastSeenTitle && currentCount > 0 && currentCount >= previousCount) ||
                            (contentAfterCount.contains(":") && title != lastSeenTitle)
        
        self.lastUnreadCount = unreadCount
        self.lastSeenTitle = title
        
        guard hasNewMessage else { return }
        
        // Formatear remitente y texto
        var senderName = "WhatsApp Web"
        var messageText = "Nuevo mensaje recibido"
        
        if contentAfterCount.contains(":") {
            let parts = contentAfterCount.components(separatedBy: ":")
            if parts.count >= 2 {
                senderName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                messageText = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if contentAfterCount != "WhatsApp" && !contentAfterCount.isEmpty {
            senderName = contentAfterCount
            if currentCount > 0 {
                messageText = "\(currentCount) mensajes nuevos sin leer"
            }
        } else if currentCount > 0 {
            messageText = "Tienes \(currentCount) mensajes sin leer"
        }
        
        // Disparar en el hilo principal la Live Activity interactiva
        DispatchQueue.main.async {
            NotificationActivityProvider.shared.showNotification(
                title: senderName,
                message: messageText,
                handle: senderName,
                appIcon: "message.fill",
                appName: "WhatsApp Web",
                tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                enableQuickReply: true,
                duration: 10.0
            )
            AppState.shared.hapticService.triggerSnap()
        }
    }
}
