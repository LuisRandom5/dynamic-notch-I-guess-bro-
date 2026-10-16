import Foundation
import AppKit
import SwiftUI

/// Servicio en segundo plano para detección automática de mensajes entrantes en WhatsApp Web
/// Funciona de forma no invasiva inspeccionando navegadores compatibles (Safari, Chrome, Arc, Brave, Edge).
public final class WhatsAppWebObserverService: ObservableObject {
    public static let shared = WhatsAppWebObserverService()
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enableWhatsAppWebObserver")
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }
    
    @Published public var pollInterval: Double {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: "whatsAppWebPollInterval")
            if isEnabled && timer != nil {
                stop()
                start()
            }
        }
    }
    
    private var timer: Timer?
    private var lastUnreadCount: Int? = nil
    private var lastSeenTitle: String = ""
    private var lastSeenMessageContent: String = ""
    private var isFirstCheck: Bool = true
    private var isQuerying: Bool = false
    private let scriptQueue = DispatchQueue(label: "com.dynamicnotch.whatsapp.applescript", qos: .utility)
    private var compiledScripts: [String: NSAppleScript] = [:]
    
    private init() {
        if UserDefaults.standard.object(forKey: "enableWhatsAppWebObserver") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "enableWhatsAppWebObserver")
        }
        let savedInterval = UserDefaults.standard.double(forKey: "whatsAppWebPollInterval")
        self.pollInterval = savedInterval >= 1.0 ? savedInterval : 2.0
    }
    
    /// Inicia el monitor en segundo plano
    public func start() {
        guard isEnabled, timer == nil else { return }
        
        // Ejecutar primer sondeo suavemente tras 2 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pollWhatsAppWeb()
        }
        
        let interval = max(1.5, pollInterval)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollWhatsAppWeb()
        }
        newTimer.tolerance = interval * 0.25
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Realiza un sondeo inmediato de WhatsApp Web
    public func pollWhatsAppWeb() {
        guard isEnabled && !isQuerying else { return }
        
        // Verificar en el hilo principal qué navegadores están activos antes de despachar
        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let supportedBrowsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.microsoft.edgemac"
        ]
        let activeBrowsers = supportedBrowsers.filter { runningBundleIds.contains($0) }
        guard !activeBrowsers.isEmpty else { return }
        
        isQuerying = true
        
        scriptQueue.async { [weak self] in
            defer { self?.isQuerying = false }
            guard let self = self else { return }
            
            let titles = self.fetchWhatsAppTitlesFromBrowsers(activeBrowsers: activeBrowsers)
            guard !titles.isEmpty else { return }
            
            // Seleccionar la mejor pestaña de WhatsApp Web en el ciclo actual (evita que múltiples pestañas
            // con "WhatsApp" en el título reinicien lastUnreadCount a 0 y disparen notificaciones cada 2s)
            let bestTitle = titles.first(where: { $0.range(of: #"^\(\d+\)"#, options: .regularExpression) != nil })
                ?? titles.first(where: { $0 == "WhatsApp" || $0.hasPrefix("WhatsApp") })
                ?? titles[0]
            
            self.processWhatsAppTitle(bestTitle)
        }
    }
    
    // MARK: - Extracción de Títulos vía AppleScript Pre-compilado
    private func fetchWhatsAppTitlesFromBrowsers(activeBrowsers: [String]) -> [String] {
        var results: [String] = []
        let sep = "___NOTCH_SEP___"
        
        for bundleId in activeBrowsers {
            if let output = runCachedAppleScript(for: bundleId, sep: sep) {
                results.append(contentsOf: parseScriptList(output, sep: sep))
            }
        }
        return results
    }
    
    private func scriptSource(for bundleId: String, sep: String) -> String? {
        switch bundleId {
        case "com.apple.Safari":
            return """
            tell application "Safari"
                set AppleScript's text item delimiters to "\(sep)"
                set res to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "web.whatsapp.com") or (name of t contains "WhatsApp") then
                            set end of res to (name of t as text)
                        end if
                    end repeat
                end repeat
                return res as text
            end tell
            """
        case "com.google.Chrome":
            return chromiumScript(appName: "Google Chrome", sep: sep)
        case "company.thebrowser.Browser":
            return chromiumScript(appName: "Arc", sep: sep)
        case "com.brave.Browser":
            return chromiumScript(appName: "Brave Browser", sep: sep)
        case "com.microsoft.edgemac":
            return chromiumScript(appName: "Microsoft Edge", sep: sep)
        default:
            return nil
        }
    }
    
    private func chromiumScript(appName: String, sep: String) -> String {
        return """
        tell application "\(appName)"
            set AppleScript's text item delimiters to "\(sep)"
            set res to {}
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t contains "web.whatsapp.com") or (title of t contains "WhatsApp") then
                        set end of res to (title of t as text)
                    end if
                end repeat
            end repeat
            return res as text
        end tell
        """
    }
    
    private func runCachedAppleScript(for bundleId: String, sep: String) -> String? {
        let script: NSAppleScript
        if let cached = compiledScripts[bundleId] {
            script = cached
        } else {
            guard let src = scriptSource(for: bundleId, sep: sep),
                  let created = NSAppleScript(source: src) else {
                return nil
            }
            var compileErr: NSDictionary?
            created.compileAndReturnError(&compileErr)
            if compileErr != nil {
                return nil
            }
            compiledScripts[bundleId] = created
            script = created
        }
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
        
        // Un mensaje nuevo real ocurre cuando:
        // 1. El conteo de no leídos aumenta (ej. de 101 a 102)
        // 2. O el título muestra un contacto y mensaje explícito con ':' que no habíamos procesado antes
        let countIncreased = currentCount > previousCount
        let hasNewExplicitMessage = contentAfterCount.contains(":") && contentAfterCount != lastSeenMessageContent
        let hasNewMessage = countIncreased || hasNewExplicitMessage
        
        self.lastUnreadCount = unreadCount
        self.lastSeenTitle = title
        if contentAfterCount.contains(":") {
            self.lastSeenMessageContent = contentAfterCount
        }
        
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
        
        // Disparar en el hilo principal la Live Activity interactiva (sin interrumpir si ya está escribiendo un Quick Reply)
        DispatchQueue.main.async {
            if NotificationActivityProvider.shared.isNotificationActive &&
                NotificationActivityProvider.shared.isQuickReplyExpanded {
                return
            }
            NotificationActivityProvider.shared.showNotification(
                title: senderName,
                message: messageText,
                handle: senderName,
                appIcon: "message.fill",
                appName: "WhatsApp Web",
                tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                enableQuickReply: true,
                duration: 6.0
            )
            AppState.shared.hapticService.triggerSnap()
        }
    }
    
    /// Envía una respuesta rápida a WhatsApp Web (intentando primero inyección DOM silenciosa y como respaldo activación + pegado)
    public func deliverQuickReply(message: String, recipient: String) {
        let escapedJS = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        
        let jsSnippet = "(function(){var box=document.querySelector('#main footer div[contenteditable=\\\"true\\\"]')||document.querySelector('div[contenteditable=\\\"true\\\"][data-tab=\\\"10\\\"]');if(!box)return 'NO_BOX';box.focus();document.execCommand('selectAll',false,null);document.execCommand('insertText',false,'\(escapedJS)');setTimeout(function(){var btn=document.querySelector('#main footer button[aria-label=\\\"Enviar\\\"]')||document.querySelector('#main footer button[aria-label=\\\"Send\\\"]')||document.querySelector('#main footer span[data-icon=\\\"send\\\"]')||document.querySelector('#main footer span[data-icon=\\\"wds-ic-send-filled\\\"]');if(btn){(btn.closest('button')||btn).click();}else{box.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));}},60);return 'SENT_SILENT';})()"
        
        scriptQueue.async { [weak self] in
            guard let self = self else { return }
            if self.trySilentDOMSend(jsSnippet: jsSnippet) {
                DNDLogger.log("WhatsAppWebObserverService: Respuesta enviada silenciosamente vía DOM JS")
                return
            }
            // Fallback: activar pestaña de WhatsApp Web / App y pegar + enviar con System Events
            DNDLogger.log("WhatsAppWebObserverService: Activando WhatsApp Web y enviando respuesta desde portapapeles")
            self.activateAndPasteReply()
        }
    }
    
    private func trySilentDOMSend(jsSnippet: String) -> Bool {
        let appleScriptEscapedJS = jsSnippet
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let chromiumApps: [(String, String)] = [
            ("com.google.Chrome", "Google Chrome"),
            ("com.brave.Browser", "Brave Browser"),
            ("company.thebrowser.Browser", "Arc"),
            ("com.microsoft.edgemac", "Microsoft Edge")
        ]
        
        for (bundleId, appName) in chromiumApps where runningBundleIds.contains(bundleId) {
            let script = """
            tell application "\(appName)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "web.whatsapp.com") or (title of t contains "WhatsApp") then
                            return execute t javascript "\(appleScriptEscapedJS)"
                        end if
                    end repeat
                end repeat
            end tell
            """
            var err: NSDictionary?
            if let res = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue,
               res == "SENT_SILENT" {
                return true
            }
        }
        
        if runningBundleIds.contains("com.apple.Safari") {
            let script = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "web.whatsapp.com") or (name of t contains "WhatsApp") then
                            return do JavaScript "\(appleScriptEscapedJS)" in t
                        end if
                    end repeat
                end repeat
            end tell
            """
            var err: NSDictionary?
            if let res = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue,
               res == "SENT_SILENT" {
                return true
            }
        }
        
        return false
    }
    
    private func activateAndPasteReply() {
        activateWhatsAppWebSync()
        Thread.sleep(forTimeInterval: 0.35)
        let pasteScript = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.12
            key code 36
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: pasteScript)?.executeAndReturnError(&err)
    }
    
    /// Activa la pestaña o ventana de WhatsApp Web en el navegador
    public func activateWhatsAppWeb() {
        scriptQueue.async { [weak self] in
            self?.activateWhatsAppWebSync()
        }
    }
    
    private func activateWhatsAppWebSync() {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
        
        // 1. Safari (si está en ejecución)
        if runningBundleIds.contains("com.apple.Safari") {
            let script = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "web.whatsapp.com") or (name of t contains "WhatsApp") then
                            set current tab of w to t
                            set index of w to 1
                            activate
                            return "ACTIVATED"
                        end if
                    end repeat
                end repeat
            end tell
            return "NOT_FOUND"
            """
            var err: NSDictionary?
            if let res = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue, res == "ACTIVATED" {
                return
            }
        }
        
        // 2. Navegadores Chromium (Chrome, Brave, Arc, Edge) SOLO si están en ejecución actualmente
        let chromiumCandidates: [(String, String)] = [
            ("com.google.Chrome", "Google Chrome"),
            ("com.brave.Browser", "Brave Browser"),
            ("company.thebrowser.Browser", "Arc"),
            ("com.microsoft.edgemac", "Microsoft Edge")
        ]
        
        for (bundleId, appName) in chromiumCandidates where runningBundleIds.contains(bundleId) {
            let script: String
            if bundleId == "company.thebrowser.Browser" {
                script = """
                tell application "\(appName)"
                    activate
                    return "ACTIVATED"
                end tell
                """
            } else {
                script = """
                tell application "\(appName)"
                    repeat with w in windows
                        set i to 1
                        repeat with t in tabs of w
                            if (URL of t contains "web.whatsapp.com") or (title of t contains "WhatsApp") then
                                set active tab index of w to i
                                set index of w to 1
                                activate
                                return "ACTIVATED"
                            end if
                            set i to i + 1
                        end repeat
                    end repeat
                end tell
                return "NOT_FOUND"
                """
            }
            var err: NSDictionary?
            if let res = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue, res == "ACTIVATED" {
                return
            }
        }
        
        // 3. Aplicación nativa de escritorio WhatsApp (si está en ejecución)
        if let wa = runningApps.first(where: {
            $0.bundleIdentifier == "net.whatsapp.WhatsApp" ||
            $0.bundleIdentifier == "WhatsApp" ||
            $0.localizedName == "WhatsApp"
        }) {
            if #available(macOS 14.0, *) {
                wa.activate()
            } else {
                wa.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }
    
    /// Simula una notificación interactiva de WhatsApp para pruebas de UI y Quick Reply
    public func simulateTestNotification() {
        DNDLogger.log("WhatsAppWebObserverService.simulateTestNotification CALLED")
        NotificationActivityProvider.shared.showNotification(
            title: "Carlos (WhatsApp)",
            message: "¡Hola! ¿Cómo va el nuevo reproductor de pantalla de bloqueo?",
            handle: "Carlos",
            appIcon: "message.fill",
            appName: "WhatsApp Web",
            tint: Color(red: 0.15, green: 0.78, blue: 0.45),
            enableQuickReply: true,
            duration: 6.0
        )
        AppState.shared.hapticService.triggerSnap()
    }
}
