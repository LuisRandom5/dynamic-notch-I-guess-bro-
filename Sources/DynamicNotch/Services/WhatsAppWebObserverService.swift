import Foundation
import AppKit
import SwiftUI
import ApplicationServices

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
    
    /// El navegador no deja leer la lista de chats con JavaScript: sin eso, con la pestaña en segundo plano sólo
    /// se sabe que hay mensajes nuevos, no de quién ni qué dicen (Ajustes lo explica)
    @Published public private(set) var javaScriptBlocked = false

    private var timer: Timer?
    private var burstTimer: Timer?
    private var burstAttemptsRemaining: Int = 0
    private var pendingBurstCount: Int = 0
    private var lastUnreadCount: Int? = nil
    private var lastSeenTitle: String = ""
    private var lastSeenMessageContent: String = ""
    private var isFirstCheck: Bool = true
    private var isQuerying: Bool = false
    private let scriptQueue = DispatchQueue(label: "com.dynamicnotch.whatsapp.applescript", qos: .utility)
    private var compiledScripts: [String: NSAppleScript] = [:]
    
    private struct ChatRecord {
        let message: String
        let time: String
        let unreadCount: Int
        let isMuted: Bool
        var lastAlertedAt: Date
    }
    private var knownChatRecords: [String: ChatRecord] = [:]
    
    // MARK: - Antiduplicados y antigüedad
    
    /// Huellas de mensajes ya notificados (contacto|texto|no leídos|hora) con su fecha; persisten 48 h entre reinicios.
    private var notifiedFingerprints: [String: Double] = (UserDefaults.standard.dictionary(forKey: "whatsAppNotifiedFingerprints") as? [String: Double]) ?? [:]
    private static let fingerprintLifetime: TimeInterval = 48 * 3600
    private static let maxFingerprints = 400
    
    /// Registra el mensaje como notificado. Devuelve false si ya lo estaba.
    @discardableResult
    private func rememberNotified(contact: String, message: String, unread: Int, time: String = "") -> Bool {
        let key = "\(contact.lowercased())|\(message.trimmingCharacters(in: .whitespacesAndNewlines))|\(unread)|\(time)"
        let now = Date().timeIntervalSince1970
        notifiedFingerprints = notifiedFingerprints.filter { now - $0.value < Self.fingerprintLifetime }
        if notifiedFingerprints[key] != nil { return false }
        notifiedFingerprints[key] = now
        if notifiedFingerprints.count > Self.maxFingerprints {
            let oldest = notifiedFingerprints.sorted { $0.value < $1.value }.prefix(notifiedFingerprints.count - Self.maxFingerprints)
            oldest.forEach { notifiedFingerprints.removeValue(forKey: $0.key) }
        }
        UserDefaults.standard.set(notifiedFingerprints, forKey: "whatsAppNotifiedFingerprints")
        return true
    }
    
    /// ¿La hora que muestra la lista de chats es reciente (≤ 10 min)?
    /// true = reciente · false = vieja ("Ayer", fecha, día de la semana o > 10 min) · nil = no se pudo leer.
    func isRecentChatTime(_ raw: String) -> Bool? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        let oldMarkers = ["ayer", "yesterday", "/", "lunes", "martes", "miércoles", "miercoles", "jueves", "viernes",
                          "sábado", "sabado", "domingo", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        if oldMarkers.contains(where: { text.contains($0) }) { return false }
        if text == "hoy" || text == "today" || text == "ahora" || text == "now" { return true }
        
        // "8:48 p.m.", "8:48 pm", "20:48"
        guard let match = text.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) else { return nil }
        let parts = text[match].split(separator: ":")
        guard parts.count == 2, var hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        let isPM = text.contains("p.") || text.contains("pm") || text.contains("p. m")
        let isAM = text.contains("a.") || text.contains("am") || text.contains("a. m")
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        
        let calendar = Calendar.current
        let now = Date()
        guard var stamp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if stamp.timeIntervalSince(now) > 120 {
            // Una hora "del futuro" es de ayer
            stamp = calendar.date(byAdding: .day, value: -1, to: stamp) ?? stamp
        }
        return now.timeIntervalSince(stamp) <= 10 * 60
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: "enableWhatsAppWebObserver") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "enableWhatsAppWebObserver")
        }
        let savedInterval = UserDefaults.standard.double(forKey: "whatsAppWebPollInterval")
        // 1.5 s por defecto (escanear el navegador por accesibilidad cuesta; 0.8 s gastaba ~5 % de CPU). El valor
        // viejo por defecto (0.8) se migra
        self.pollInterval = savedInterval >= 0.5 && abs(savedInterval - 0.8) > 0.001 ? savedInterval : 1.5
    }
    
    /// Inicia el monitor en segundo plano
    public func start() {
        guard isEnabled, timer == nil else { return }
        
        // Ejecutar primer sondeo suavemente tras 1 segundo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.pollWhatsAppWeb()
        }
        
        let interval = max(0.5, pollInterval)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollWhatsAppWeb()
        }
        newTimer.tolerance = 0.08
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Realiza un sondeo inmediato de WhatsApp Web
    private var runningBundleIdsCache: Set<String>?
    /// Último sondeo encontró WhatsApp Web (si no, se sondea más espaciado)
    private var foundWhatsAppLastTime = true
    private var idleSkips = 0
    /// App al frente al iniciar el sondeo
    private var frontmostBundleIdSnapshot = ""
    private var runningAppsObservers: [NSObjectProtocol] = []

    private func cachedRunningBundleIds() -> Set<String> {
        if let cache = runningBundleIdsCache { return cache }
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        runningBundleIdsCache = ids
        if runningAppsObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                runningAppsObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.runningBundleIdsCache = nil
                })
            }
        }
        return ids
    }

    public func pollWhatsAppWeb() {
        guard isEnabled && !isQuerying else { return }
        
        // Navegadores abiertos: lista en caché (pedirla a NSWorkspace en cada sondeo costaba tiempo del hilo
        // principal); se actualiza al abrir o cerrar apps
        let runningBundleIds = cachedRunningBundleIds()
        let supportedBrowsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.microsoft.edgemac"
        ]
        let activeBrowsers = supportedBrowsers.filter { runningBundleIds.contains($0) }
        guard !activeBrowsers.isEmpty else { return }
        // Sin pestaña de WhatsApp en el último sondeo: se revisa cada ~4 s en vez de cada 0.8 s (escanear los
        // navegadores por accesibilidad es lo más caro del app)
        idleSkips += 1
        if !foundWhatsAppLastTime && idleSkips < 5 { return }
        idleSkips = 0
        frontmostBundleIdSnapshot = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        isQuerying = true
        
        scriptQueue.async { [weak self] in
            defer { self?.isQuerying = false }
            guard let self = self else { return }
            
            // 1. Escaneo en tiempo real de chats vía Accessibility API
            let didScanAX = self.scanChatsViaAccessibility(activeBrowsers: activeBrowsers)
            if didScanAX { DispatchQueue.main.async { self.foundWhatsAppLastTime = true } }
            
            // 2. Si AX no encontró tablas activas, respaldo con título de ventana
            if !didScanAX {
                let titles = self.fetchWhatsAppTitlesFromBrowsers(activeBrowsers: activeBrowsers)
                DispatchQueue.main.async { self.foundWhatsAppLastTime = !titles.isEmpty }
                guard !titles.isEmpty else { return }
                
                // Seleccionar la mejor pestaña de WhatsApp Web en el ciclo actual
                let bestTitle = titles.first(where: { $0.range(of: #"^\(\d+\)"#, options: .regularExpression) != nil })
                    ?? titles.first(where: { $0 == "WhatsApp" || $0.hasPrefix("WhatsApp") })
                    ?? titles[0]
                
                // 3. La pestaña está en segundo plano (sin tabla de accesibilidad): se lee la lista de chats con
                // JavaScript para avisar con el mensaje real en vez de "mensajes sin leer"
                if self.shouldRunJavaScriptScan(title: bestTitle),
                   self.scanChatsViaJavaScript(activeBrowsers: activeBrowsers, title: bestTitle) {
                    self.syncTitleBaseline(bestTitle)
                    return
                }
                if self.javaScriptReaderWorks && bestTitle == self.lastJavaScriptTitle {
                    self.syncTitleBaseline(bestTitle)
                    return
                }
                self.processWhatsAppTitle(bestTitle, activeBrowsers: activeBrowsers)
            }
        }
    }

    // MARK: - Lectura de la lista de chats con JavaScript (pestaña en segundo plano)

    /// Hasta cuándo no se intenta JavaScript (el navegador no lo permite o WhatsApp no cargó)
    private var javaScriptBlockedUntil = Date.distantPast
    private var javaScriptReaderWorks = false
    private var javaScriptPrimed = false
    private var lastJavaScriptTitle = ""
    private var javaScriptSkips = 0
    private var loggedJavaScriptBlocked = false
    private var compiledJavaScriptScripts: [String: NSAppleScript] = [:]

    /// Se lee cuando cambia el título (llegó algo) y, por si acaso, cada ~6 s
    private func shouldRunJavaScriptScan(title: String) -> Bool {
        guard Date() >= javaScriptBlockedUntil else { return false }
        javaScriptSkips += 1
        if title != lastJavaScriptTitle || !javaScriptReaderWorks || javaScriptSkips >= 4 {
            javaScriptSkips = 0
            return true
        }
        return false
    }

    /// El conteo del título queda al día para que el respaldo por título no avise de lo que ya se avisó
    private func syncTitleBaseline(_ title: String) {
        if let match = title.range(of: #"^\((\d+)\)\s*"#, options: .regularExpression) {
            lastUnreadCount = Int(title[match].filter { $0.isNumber })
        } else {
            lastUnreadCount = nil
        }
        lastSeenTitle = title
    }

    /// Lee las primeras filas de `#pane-side`: nombre, vista previa, hora, no leídos, silenciado y el icono del
    /// tipo de mensaje (foto, sticker, audio…). Devuelve JSON.
    private static let chatListJavaScript = #"""
    (function(){
    var pane=document.querySelector('#pane-side');
    if(!pane)return 'NOPANE';
    var rows=pane.querySelectorAll('[role=listitem],[role=row]');
    var timeRe=/^(\d{1,2}:\d{2}(\s*[ap]\.?\s?m\.?)?|ayer|hoy|yesterday|today|lunes|martes|miércoles|jueves|viernes|sábado|domingo|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{1,2}\/\d{1,2}\/\d{2,4})$/i;
    var out=[];
    for(var i=0;i<rows.length&&out.length<15;i++){
      var r=rows[i];
      if(r.parentElement&&r.parentElement.closest('[role=listitem],[role=row]'))continue;
      var lines=(r.innerText||'').split('\n').map(function(x){return x.trim();}).filter(function(x){return x.length>0;});
      if(!lines.length)continue;
      var titled=r.querySelector('span[title]');
      var name=(titled&&titled.getAttribute('title'))||lines[0];
      var time='';
      for(var j=0;j<lines.length;j++){if(timeRe.test(lines[j])){time=lines[j];break;}}
      var unread=0;
      var badge=r.querySelector('[aria-label*=\'no leído\'],[aria-label*=\'unread\'],[aria-label*=\'sin leer\']');
      if(badge){var d=(badge.getAttribute('aria-label')||'').replace(/\D/g,'');unread=d?parseInt(d,10):0;}
      var icons=[].slice.call(r.querySelectorAll('[data-icon]')).map(function(e){return e.getAttribute('data-icon')||'';});
      var rest=[];var usedName=false,usedTime=false;
      for(var k=0;k<lines.length;k++){
        var l=lines[k];
        if(!usedName&&l===name){usedName=true;continue;}
        if(!usedTime&&l===time){usedTime=true;continue;}
        if(/^\d+$/.test(l)&&k===lines.length-1)continue;
        rest.push(l);
      }
      var preview=rest.join(' ').replace(/\s+:\s*/g,': ');
      out.push({n:name,m:preview,t:time,u:unread,
        mu:icons.some(function(x){return /mute/.test(x);}),
        p:icons.some(function(x){return /pin/.test(x);}),
        o:icons.some(function(x){return /check|msg-time/.test(x);}),
        i:icons.filter(function(x){return !/mute|pin|check|msg-time|default-|down|chevron|ephemeral/.test(x);})});
    }
    return JSON.stringify(out);
    })()
    """#

    private func javaScriptScript(for bundleId: String) -> NSAppleScript? {
        if let cached = compiledJavaScriptScripts[bundleId] { return cached }
        let js = Self.chatListJavaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let source: String
        switch bundleId {
        case "com.apple.Safari":
            source = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "web.whatsapp.com" then return (do JavaScript "\(js)" in t)
                    end repeat
                end repeat
            end tell
            return "NOTAB"
            """
        case "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            let appName = ["com.google.Chrome": "Google Chrome", "company.thebrowser.Browser": "Arc",
                           "com.brave.Browser": "Brave Browser", "com.microsoft.edgemac": "Microsoft Edge"][bundleId]!
            source = """
            tell application "\(appName)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "web.whatsapp.com" then return (execute t javascript "\(js)")
                    end repeat
                end repeat
            end tell
            return "NOTAB"
            """
        default:
            return nil
        }
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        script.compileAndReturnError(&error)
        guard error == nil else { return nil }
        compiledJavaScriptScripts[bundleId] = script
        return script
    }

    /// true si se pudo leer la lista de chats (y se procesaron sus filas)
    private func scanChatsViaJavaScript(activeBrowsers: [String], title: String) -> Bool {
        for bundleId in activeBrowsers {
            guard let script = javaScriptScript(for: bundleId) else { continue }
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error).stringValue ?? ""
            if let error {
                // Normalmente: Safari → Ajustes → Desarrollador → "Permitir JavaScript desde Apple Events"
                if !loggedJavaScriptBlocked {
                    loggedJavaScriptBlocked = true
                    DispatchQueue.main.async { self.javaScriptBlocked = true }
                    DNDLogger.log("WhatsAppWebObserverService: JavaScript no disponible en \(bundleId): \((error[NSAppleScript.errorMessage] as? String) ?? "\(error)")")
                }
                continue
            }
            guard output.hasPrefix("["), let data = output.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            if loggedJavaScriptBlocked {
                loggedJavaScriptBlocked = false
                DispatchQueue.main.async { self.javaScriptBlocked = false }
            }
            javaScriptReaderWorks = true
            lastJavaScriptTitle = title
            let rows = items.compactMap(Self.parseJavaScriptRow)
            // La primera lectura sólo toma la foto del estado actual (lo que ya estaba sin leer es viejo)
            if !javaScriptPrimed {
                isFirstCheck = true
                DNDLogger.log("WhatsAppWebObserverService: lista de chats leída con JavaScript (\(rows.count) filas)")
            }
            rows.forEach(processParsedRow)
            javaScriptPrimed = true
            isFirstCheck = false
            return true
        }
        javaScriptReaderWorks = false
        javaScriptBlockedUntil = Date().addingTimeInterval(30)
        return false
    }

    private static func parseJavaScriptRow(_ item: [String: Any]) -> ParsedChatRow? {
        let name = (item["n"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let icons = item["i"] as? [String] ?? []
        let media = icons.lazy.compactMap(WhatsAppMediaKind.init(webIcon:)).first
        var message = WhatsAppMessagePreview.describe(item["m"] as? String ?? "", media: media)
        if item["o"] as? Bool == true, !message.lowercased().hasPrefix("tú:") { message = "Tú: " + message }
        return ParsedChatRow(
            contact: name,
            message: message.isEmpty ? "Nuevo mensaje" : message,
            time: item["t"] as? String ?? "",
            unreadCount: item["u"] as? Int ?? 0,
            isMuted: item["mu"] as? Bool ?? false,
            isPinned: item["p"] as? Bool ?? false
        )
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
    
    // MARK: - Extractor Robusto de Remitente y Mensaje desde el Título
    private func extractSenderAndMessage(from title: String) -> (sender: String, message: String)? {
        var cleanTitle = title
        if let match = title.range(of: #"^\((\d+)\)\s*"#, options: .regularExpression) {
            cleanTitle = String(title[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let lower = cleanTitle.lowercased()
        guard lower != "whatsapp" && lower != "whatsapp web" && !cleanTitle.isEmpty else { return nil }
        
        // 1. Formato estándar con dos puntos: "Carlos: ¡Hola amigo!"
        if cleanTitle.contains(":") {
            let parts = cleanTitle.components(separatedBy: ":")
            if parts.count >= 2 {
                let sender = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                if !sender.isEmpty && sender.lowercased() != "whatsapp" {
                    return (sender: sender, message: msg.isEmpty ? "Nuevo mensaje" : msg)
                }
            }
        }
        
        // 2. Formatos con guion: "Carlos - Hola" o "Carlos – Hola"
        for sep in [" - ", " – ", " — "] {
            if cleanTitle.contains(sep) {
                let parts = cleanTitle.components(separatedBy: sep)
                if parts.count >= 2 {
                    let sender = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sender.isEmpty && sender.lowercased() != "whatsapp" {
                        return (sender: sender, message: msg.isEmpty ? "Nuevo mensaje" : msg)
                    }
                }
            }
        }
        
        // 3. Formato donde el título alternó directamente al contacto o grupo (ej. "(1) Carlos" o "(1) Familia"):
        let isSystemString = lower.contains("mensaje") || lower.contains("unread") || lower.contains("notification")
        if !isSystemString && cleanTitle.count >= 2 {
            return (sender: cleanTitle, message: "Nuevo mensaje recibido")
        }
        
        return nil
    }

    // MARK: - Detección de Mensajes Nuevos e Inspección Profunda de Remitente
    private func processWhatsAppTitle(_ title: String, activeBrowsers: [String]) {
        var unreadCount: Int? = nil
        if let match = title.range(of: #"^\((\d+)\)\s*"#, options: .regularExpression) {
            let countStr = title[match].filter { $0.isNumber }
            unreadCount = Int(countStr)
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
        
        // 1. ¿El título ya trae remitente y mensaje explícito? (p. ej. en versiones o navegadores que lo incluyan)
        if let details = extractSenderAndMessage(from: title) {
            let explicitSignature = "\(details.sender): \(details.message)"
            let isNewMessage = (currentCount > previousCount) || (explicitSignature != lastSeenMessageContent)
            self.lastUnreadCount = unreadCount
            self.lastSeenTitle = title
            self.lastSeenMessageContent = explicitSignature
            
            if isNewMessage {
                dispatchNotification(sender: details.sender, message: details.message)
            }
            return
        }
        
        // 2. Si el conteo aumentó (o hay un mensaje no leído nuevo):
        let countIncreased = currentCount > previousCount
        self.lastUnreadCount = unreadCount
        self.lastSeenTitle = title
        
        if countIncreased && currentCount > 0 {
            self.burstCheckWithDeepInspection(unreadCount: currentCount, activeBrowsers: activeBrowsers)
        }
    }
    
    // MARK: - Sondeo Rápido con Inspección Profunda (Accessibility + DOM)
    private func burstCheckWithDeepInspection(unreadCount: Int, activeBrowsers: [String]) {
        // WhatsApp Web actualiza el DOM de la lista de chats en ~100-350ms tras recibir el mensaje.
        // Hacemos hasta 4 intentos de sondeo directo para capturar el remitente real inmediatamente.
        for attempt in 0..<4 {
            if attempt > 0 {
                Thread.sleep(forTimeInterval: 0.28)
            }
            
            // Intentar inspección vía Accessibility API (Safari, Chrome, Arc, Brave, Edge, WhatsApp)
            if let details = fetchDetailsViaAccessibility(activeBrowsers: activeBrowsers) {
                let signature = "\(details.sender): \(details.message)"
                self.lastSeenMessageContent = signature
                self.dispatchNotification(sender: details.sender, message: details.message)
                return
            }
            
            // Si el título alternó en segundo plano con algún texto explícito
            let titles = self.fetchWhatsAppTitlesFromBrowsers(activeBrowsers: activeBrowsers)
            for t in titles {
                if let details = self.extractSenderAndMessage(from: t) {
                    let signature = "\(details.sender): \(details.message)"
                    self.lastSeenMessageContent = signature
                    self.dispatchNotification(sender: details.sender, message: details.message)
                    return
                }
            }
        }
        
        // Si tras la inspección profunda no se pudo identificar el contacto específico
        // (por ejemplo si la pestaña está en App Nap estricto o no cargó la tabla):
        // NO mostramos "Tienes mensajes sin leer" como si fuera un contacto.
        // Mostramos "WhatsApp" con Quick Reply deshabilitado y acción directa de abrir la app.
        let msg = unreadCount > 1 ? "\(unreadCount) mensajes nuevos sin leer" : "Nuevo mensaje recibido"
        self.dispatchNotification(sender: "WhatsApp", message: msg)
    }
    
    /// Diagnóstico (GET /debug/whatsapp): texto crudo y lectura de las primeras filas de chats
    public func debugRows() -> [[String: Any]] {
        var out: [[String: Any]] = []
        let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
                        "com.microsoft.edgemac", "net.whatsapp.WhatsApp"]
        for bundleId in browsers {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { continue }
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let windows = childrenRef as? [AnyObject] else { continue }
            for w in windows {
                guard let table = findAXChatTable(w as! AXUIElement) else { continue }
                var rowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(table, kAXRowsAttribute as CFString, &rowsRef) == .success,
                      let rows = rowsRef as? [AnyObject] else { continue }
                for r in rows.prefix(8) {
                    let row = r as! AXUIElement
                    let parsed = parseChatRow(row)
                    out.append([
                        "app": bundleId,
                        "raw": collectStringsFromAX(row),
                        "roles": collectRolesFromAX(row),
                        "contact": parsed?.contact ?? "",
                        "message": parsed?.message ?? "",
                        "unread": parsed?.unreadCount ?? 0
                    ])
                }
                return out
            }
        }
        return out
    }

    /// Roles y descripciones de los elementos de una fila (para ver cómo llegan iconos de foto, sticker…)
    private func collectRolesFromAX(_ elem: AXUIElement, depth: Int = 0) -> [String] {
        if depth > 8 { return [] }
        var out: [String] = []
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valueRef)
        let role = roleRef as? String ?? "?"
        if role == "AXImage" || (descRef as? String)?.isEmpty == false {
            out.append("\(role)[\(descRef as? String ?? "")|\(valueRef as? String ?? "")]")
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children { out.append(contentsOf: collectRolesFromAX(c as! AXUIElement, depth: depth + 1)) }
        }
        return out
    }

    // MARK: - Inspección Profunda y Tiempo Real vía Accessibility API (AXUIElement)
    private struct ParsedChatRow {
        let contact: String
        let message: String
        let time: String
        let unreadCount: Int
        let isMuted: Bool
        let isPinned: Bool
    }
    
    @discardableResult
    private func scanChatsViaAccessibility(activeBrowsers: [String]) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        var targetBundleIds = activeBrowsers
        if !targetBundleIds.contains("net.whatsapp.WhatsApp") {
            targetBundleIds.append("net.whatsapp.WhatsApp")
        }
        
        var didFindTable = false
        for bundleId in targetBundleIds {
            guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) else { continue }
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            
            var candidateWindows: [AXUIElement] = []
            for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                var winRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appRef, attr as CFString, &winRef) == .success, let w = winRef {
                    candidateWindows.append(w as! AXUIElement)
                }
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let arr = childrenRef as? [AnyObject] {
                for c in arr {
                    let elem = c as! AXUIElement
                    var roleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
                    if (roleRef as? String) == "AXWindow" {
                        candidateWindows.append(elem)
                    }
                }
            }
            
            for win in candidateWindows {
                guard let table = findAXChatTable(win) else { continue }
                var rowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(table, kAXRowsAttribute as CFString, &rowsRef) == .success,
                      let rowArray = rowsRef as? [AnyObject] else { continue }
                
                didFindTable = true
                let rows = rowArray.map { $0 as! AXUIElement }
                for r in rows.prefix(15) {
                    if let p = parseChatRow(r) {
                        processParsedRow(p)
                    }
                }
                
                if isFirstCheck {
                    isFirstCheck = false
                }
                return true
            }
        }
        return didFindTable
    }
    
    private func processParsedRow(_ row: ParsedChatRow) {
        let contact = row.contact
        guard !contact.isEmpty else { return }
        
        let lower = contact.lowercased()
        if lower.contains("whatsapp") && !lower.contains(" ") { return }
        
        let unread = row.unreadCount
        let msg = row.message
        let time = row.time
        let isMuted = row.isMuted
        
        if isFirstCheck {
            knownChatRecords[contact] = ChatRecord(
                message: msg,
                time: time,
                unreadCount: unread,
                isMuted: isMuted,
                lastAlertedAt: Date()
            )
            // Al arrancar sólo se toma la foto del estado actual: lo que ya estaba sin leer es viejo y no se
            // notifica (antes cada arranque de la app volvía a mostrar mensajes de hace horas)
            rememberNotified(contact: contact, message: msg, unread: unread, time: time)
            return
        }
        
        // Manejo especial para cuando el chat está seleccionado/abierto en WhatsApp Web (unread == 0):
        // WhatsApp Web reproduce el sonido de mensaje pero marca unread = 0 porque el chat está en pantalla.
        // Si el usuario no tiene la ventana del navegador en primer plano, debe recibir la notificación emergente.
        if unread == 0 {
            if let prev = knownChatRecords[contact] {
                // App al frente leída una vez por sondeo (antes se recorría la lista de apps por cada chat)
                let b = frontmostBundleIdSnapshot
                let isFrontmostBrowser = b == "com.apple.Safari" || b == "com.google.Chrome" || b == "company.thebrowser.Browser" || b == "com.brave.Browser" || b == "net.whatsapp.WhatsApp"
                
                let lowerMsg = msg.lowercased()
                let isOutgoing = lowerMsg.hasPrefix("tú:") || lowerMsg.hasPrefix("tu:") || lowerMsg.hasPrefix("you:") || lowerMsg.hasPrefix("✓")
                let isTyping = lowerMsg == "escribiendo..." || lowerMsg == "typing..."
                
                if !isFrontmostBrowser && !isOutgoing && !isTyping && !isMuted && !msg.isEmpty {
                    if prev.message != msg && Date().timeIntervalSince(prev.lastAlertedAt) >= 2.5 {
                        DNDLogger.log("WhatsAppWebObserverService: 🔔 NUEVO MENSAJE EN CHAT ACTIVO de '\(contact)': '\(msg)' (hora: \(time))")
                        knownChatRecords[contact] = ChatRecord(
                            message: msg,
                            time: time,
                            unreadCount: 0,
                            isMuted: isMuted,
                            lastAlertedAt: Date()
                        )
                        dispatchNotification(sender: contact, message: msg, time: time)
                        return
                    }
                }
                
                // "escribiendo..." no reemplaza el último mensaje real: si no, al terminar de escribir el
                // mensaje viejo parecía nuevo y se volvía a notificar
                if !isTyping {
                    knownChatRecords[contact] = ChatRecord(
                        message: msg,
                        time: time,
                        unreadCount: 0,
                        isMuted: isMuted,
                        lastAlertedAt: prev.lastAlertedAt
                    )
                }
            } else {
                knownChatRecords[contact] = ChatRecord(
                    message: msg,
                    time: time,
                    unreadCount: 0,
                    isMuted: isMuted,
                    lastAlertedAt: Date()
                )
            }
            return
        }
        
        guard !isMuted else { return }
        let lowerMsg = msg.lowercased()
        guard lowerMsg != "escribiendo..." && lowerMsg != "typing..." else { return }
        
        var shouldAlert = false
        if let prev = knownChatRecords[contact] {
            if prev.unreadCount == 0 {
                shouldAlert = true
            } else if unread > prev.unreadCount {
                shouldAlert = true
            } else if msg != prev.message {
                shouldAlert = true
            }
            // (Un cambio SOLO de hora — "10:32" → "Ayer" a medianoche — no es un mensaje nuevo)
            
            if shouldAlert && Date().timeIntervalSince(prev.lastAlertedAt) < 2.5 && msg == prev.message {
                shouldAlert = false
            }
        } else {
            // Chat que aparece por primera vez en la lista (scroll, recarga): sólo si su hora es reciente
            shouldAlert = isRecentChatTime(time) == true
        }
        if shouldAlert && isRecentChatTime(time) == false {
            shouldAlert = false // La hora del chat dice que el mensaje es viejo
        }
        
        knownChatRecords[contact] = ChatRecord(
            message: msg,
            time: time,
            unreadCount: unread,
            isMuted: isMuted,
            lastAlertedAt: shouldAlert ? Date() : (knownChatRecords[contact]?.lastAlertedAt ?? Date())
        )
        
        if shouldAlert {
            DNDLogger.log("WhatsAppWebObserverService: 🔔 NUEVO MENSAJE DETECTADO de '\(contact)': '\(msg)' (no leídos: \(unread), hora: \(time))")
            dispatchNotification(sender: contact, message: msg, unread: unread, time: time)
        }
    }
    
    private func fetchDetailsViaAccessibility(activeBrowsers: [String]) -> (sender: String, message: String)? {
        let runningApps = NSWorkspace.shared.runningApplications
        // Priorizar Safari y los navegadores activos detectados, o la app nativa de WhatsApp
        var targetBundleIds = activeBrowsers
        if !targetBundleIds.contains("net.whatsapp.WhatsApp") {
            targetBundleIds.append("net.whatsapp.WhatsApp")
        }
        
        for bundleId in targetBundleIds {
            guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) else { continue }
            if let details = extractChatFromBrowserAX(pid: app.processIdentifier) {
                return details
            }
        }
        return nil
    }
    
    private func extractChatFromBrowserAX(pid: pid_t) -> (sender: String, message: String)? {
        let appRef = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        
        var candidateWindows: [AXUIElement] = []
        for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, attr as CFString, &winRef) == .success, let w = winRef {
                candidateWindows.append(w as! AXUIElement)
            }
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let arr = childrenRef as? [AnyObject] {
            for c in arr {
                let elem = c as! AXUIElement
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
                if (roleRef as? String) == "AXWindow" {
                    candidateWindows.append(elem)
                }
            }
        }
        
        for win in candidateWindows {
            guard let table = findAXChatTable(win) else { continue }
            var rowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(table, kAXRowsAttribute as CFString, &rowsRef) == .success,
                  let rowArray = rowsRef as? [AnyObject] else { continue }
            
            let rows = rowArray.map { $0 as! AXUIElement }
            var parsedRows: [ParsedChatRow] = []
            for r in rows.prefix(15) {
                if let p = parseChatRow(r) {
                    parsedRows.append(p)
                }
            }
            
            // 1. Prioridad máxima: Primer chat con mensajes no leídos que NO esté silenciado
            if let target = parsedRows.first(where: { $0.unreadCount > 0 && !$0.isMuted }) {
                return (sender: target.contact, message: target.message)
            }
            // 2. Chat con mensajes no leídos (incluso si está silenciado)
            if let target = parsedRows.first(where: { $0.unreadCount > 0 }) {
                return (sender: target.contact, message: target.message)
            }
            // 3. Primer chat no fijado y no silenciado (el más reciente en la lista)
            if let target = parsedRows.first(where: { !$0.isPinned && !$0.isMuted }) {
                return (sender: target.contact, message: target.message)
            }
            
            // 4. Si el chat activo está abierto en pantalla
            if let active = findActiveChatConversation(win) {
                return (sender: active.contact, message: active.lastMsg.isEmpty ? "Nuevo mensaje" : active.lastMsg)
            }
        }
        return nil
    }
    
    private func findAXChatTable(_ elem: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 12 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        let role = (roleRef as? String) ?? ""
        let desc = (descRef as? String) ?? ""
        if role == "AXTable" || desc == "Lista de chats" { return elem }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                if let f = findAXChatTable(c as! AXUIElement, depth: depth + 1) { return f }
            }
        }
        return nil
    }
    
    private func collectStringsFromAX(_ elem: AXUIElement, depth: Int = 0) -> [String] {
        if depth > 8 { return [] }
        var results: [String] = []
        var valRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valRef)
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        
        if let v = valRef as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(v) }
        if let t = titleRef as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(t) }
        if let d = descRef as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results.append(d) }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                results.append(contentsOf: collectStringsFromAX(c as! AXUIElement, depth: depth + 1))
            }
        }
        return results
    }
    
    private func parseChatRow(_ row: AXUIElement) -> ParsedChatRow? {
        var rawList: [String] = []
        for s in collectStringsFromAX(row) {
            if rawList.last != s { rawList.append(s) }
        }
        
        let isMuted = rawList.contains { $0.lowercased().contains("silenciado") }
        let isPinned = rawList.contains { $0.lowercased().contains("fijó") }
        
        var unreadCount = 0
        for s in rawList {
            let lower = s.lowercased()
            if lower.contains("no leído") || lower.contains("unread") {
                let digits = s.filter { $0.isNumber }
                if let count = Int(digits), count > 0 {
                    unreadCount = count
                    break
                }
            }
        }
        
        // En WhatsApp Web la marca de tiempo (ej. "8:48 p.m.", "Ayer", "Hoy", "12/10/2026")
        // separa de forma canónica la cabecera (contacto y estado) del mensaje real
        let timeRegex = try? NSRegularExpression(
            pattern: #"^(?:\d{1,2}:\d{2}\s*(?:p\.?m\.?|a\.?m\.?)|ayer|hoy|\d{1,2}/\d{1,2}/\d{2,4})$"#,
            options: .caseInsensitive
        )
        var timeIndex = -1
        for (i, s) in rawList.enumerated() {
            if timeRegex?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                timeIndex = i
                break
            }
        }
        
        let contact: String
        let message: String
        
        if timeIndex > 0 {
            // Todo antes de timeIndex es el contacto / grupo (filtrando badges de sistema)
            let contactParts = rawList[0..<timeIndex].filter { s in
                let lower = s.lowercased()
                if lower.contains("ver estado") { return false }
                if lower.contains("no leído") || lower.contains("unread") { return false }
                if lower.contains("se fijó") || lower.contains("destacado") || lower.contains("silenciado") { return false }
                return true
            }
            contact = contactParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Todo después de timeIndex es el cuerpo del mensaje recibido
            let messageParts = rawList[(timeIndex + 1)...].filter { s in
                let lower = s.lowercased()
                if lower.contains("chat silenciado") { return false }
                if lower.contains("desaparecerán de este chat") { return false }
                if lower.contains("se fijó el chat") || lower.contains("chat destacado") { return false }
                if lower.contains("ver estado") { return false }
                return true
            }
            
            var msg = ""
            for p in messageParts {
                if p == ":" || p == ": " || p == ": " {
                    msg += ": "
                } else if msg.hasSuffix(": ") {
                    msg += p
                } else if msg.isEmpty {
                    msg = p
                } else {
                    msg += " " + p
                }
            }
            message = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback si no hubo coincidencia con formato de hora
            let filtered = rawList.filter { s in
                let lower = s.lowercased()
                if lower.contains("ver estado") { return false }
                if lower.contains("no leído") || lower.contains("unread") { return false }
                if lower.contains("se fijó") || lower.contains("destacado") || lower.contains("silenciado") { return false }
                if lower.contains("desaparecerán de este chat") { return false }
                if s == ":" || s == ": " || s == ": " { return false }
                return true
            }
            guard !filtered.isEmpty else { return nil }
            contact = filtered[0]
            message = filtered.count > 1 ? filtered.dropFirst().joined(separator: " ") : "Nuevo mensaje"
        }
        
        guard !contact.isEmpty else { return nil }
        
        let timeString = (timeIndex >= 0 && timeIndex < rawList.count) ? rawList[timeIndex] : ""
        return ParsedChatRow(
            contact: contact,
            message: message.isEmpty ? "Nuevo mensaje" : WhatsAppMessagePreview.describe(message),
            time: timeString,
            unreadCount: unreadCount,
            isMuted: isMuted,
            isPinned: isPinned
        )
    }
    
    private func findActiveChatConversation(_ elem: AXUIElement, depth: Int = 0) -> (contact: String, lastMsg: String)? {
        if depth > 12 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        
        let role = (roleRef as? String) ?? ""
        let desc = (descRef as? String) ?? ""
        
        if role == "AXTextArea" && (desc.contains("Escribir un mensaje para") || desc.contains("Type a message to")) {
            let contact = desc
                .replacingOccurrences(of: "Escribir un mensaje para", with: "")
                .replacingOccurrences(of: "Type a message to", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !contact.isEmpty {
                return (contact: contact, lastMsg: "")
            }
        }
        
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                if let f = findActiveChatConversation(c as! AXUIElement, depth: depth + 1) { return f }
            }
        }
        return nil
    }

    // MARK: - Despacho y Actualización de Notificaciones
    private func dispatchNotification(sender: String, message: String, unread: Int = 0, time: String = "") {
        // Un mismo mensaje (contacto + texto + no leídos + hora) nunca se notifica dos veces, ni tras reiniciar
        guard rememberNotified(contact: sender, message: message, unread: unread, time: time) else {
            DNDLogger.log("WhatsAppWebObserverService: ⏭️ Ya notificado, se omite: '\(sender)': '\(message)'")
            return
        }
        DispatchQueue.main.async {
            if NotificationActivityProvider.shared.isNotificationActive &&
                NotificationActivityProvider.shared.isQuickReplyExpanded {
                return
            }
            
            let isKnownContact = sender != "WhatsApp Web" &&
                                sender != "WhatsApp" &&
                                !sender.lowercased().contains("whatsapp") &&
                                !sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            // Si ya hay una notificación activa pero decía "WhatsApp Web", actualizarla en vivo con el remitente real
            if NotificationActivityProvider.shared.isNotificationActive,
               let current = NotificationActivityProvider.shared.currentPayload,
               (current.title == "WhatsApp Web" || current.title == "WhatsApp") && isKnownContact {
                let initials = ContactLookupService.shared.extractInitials(from: sender)
                let avatar = ContactLookupService.shared.generateMonogramAvatar(for: sender, initials: initials)
                NotificationActivityProvider.shared.updateActiveNotification(
                    title: sender,
                    message: message,
                    handle: sender,
                    avatar: avatar,
                    enableQuickReply: true
                )
                return
            }
            
            NotificationActivityProvider.shared.showNotification(
                title: sender,
                message: message,
                handle: sender,
                appIcon: "message.fill",
                appName: "WhatsApp",
                tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                enableQuickReply: isKnownContact,
                duration: 6.0
            )
            AppState.shared.hapticService.triggerSnap()
        }
    }
    
    /// Envía una respuesta rápida a WhatsApp Web sin redirigir al usuario ni sacarlo de su app actual
    public func deliverQuickReply(message: String, recipient: String) {
        let lower = recipient.lowercased()
        guard !lower.contains("carlos") && !lower.contains("demo") else {
            DNDLogger.log("WhatsAppWebObserverService: 🧪 Demo detectada ('\(recipient)'). Envío a WhatsApp Web omitido de forma segura.")
            return
        }
        
        // Guardar la app que el usuario tenía activa para no perder foco.
        // Mientras se escribe en el notch, la app activa es Dynamic Notch: usar la que guardó el panel al tomar el teclado.
        let previousApp = NotchWindowManager.shared.appToRestoreFocus ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        })
        
        scriptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Intentar entrega 100% silenciosa vía Accessibility API (sin activar Safari/Chrome ni cambiar de espacio)
            if self.deliverViaAccessibility(message: message, recipient: recipient) {
                DNDLogger.log("WhatsAppWebObserverService: ✅ Respuesta enviada silenciosamente vía AXUIElement")
                return
            }
            
            // 2. Si falla AX, intentar inyección DOM silenciosa vía JavaScript
            let escapedJS = message
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            let jsSnippet = "(function(){var box=document.querySelector('#main footer div[contenteditable=\\\"true\\\"]')||document.querySelector('div[contenteditable=\\\"true\\\"][data-tab=\\\"10\\\"]');if(!box)return 'NO_BOX';box.focus();document.execCommand('selectAll',false,null);document.execCommand('insertText',false,'\(escapedJS)');setTimeout(function(){var btn=document.querySelector('#main footer button[aria-label=\\\"Enviar\\\"]')||document.querySelector('#main footer button[aria-label=\\\"Send\\\"]')||document.querySelector('#main footer span[data-icon=\\\"send\\\"]')||document.querySelector('#main footer span[data-icon=\\\"wds-ic-send-filled\\\"]');if(btn){(btn.closest('button')||btn).click();}else{box.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));}},60);return 'SENT_SILENT';})()"
            
            if self.trySilentDOMSend(jsSnippet: jsSnippet) {
                DNDLogger.log("WhatsAppWebObserverService: ✅ Respuesta enviada silenciosamente vía DOM JS")
                return
            }
            
            // 3. Fallback: pegar, enviar y restaurar el foco inmediatamente a la aplicación previa
            DNDLogger.log("WhatsAppWebObserverService: Entregando respuesta con System Events y restaurando foco...")
            self.activatePasteAndRestore(message: message, recipient: recipient, previousApp: previousApp)
        }
    }
    
    private func deliverViaAccessibility(message: String, recipient: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let targetBundleIds = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "net.whatsapp.WhatsApp"
        ]
        
        for bundleId in targetBundleIds {
            guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) else { continue }
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            
            var winRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &winRef) == .success,
                  let win = winRef as! AXUIElement? else { continue }
            
            // 1. Si conocemos el destinatario, seleccionarlo en la tabla de chats
            if !recipient.isEmpty && recipient != "WhatsApp" {
                if let table = findAXChatTable(win) {
                    var rowsRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(table, kAXRowsAttribute as CFString, &rowsRef) == .success,
                       let rows = rowsRef as? [AnyObject] {
                        for r in rows.prefix(15) {
                            let row = r as! AXUIElement
                            if let p = parseChatRow(row), p.contact.lowercased() == recipient.lowercased() {
                                clickAXElement(row)
                                Thread.sleep(forTimeInterval: 0.12)
                                break
                            }
                        }
                    }
                }
            }
            
            // 2. Buscar el área de texto
            guard let textArea = findAXTextArea(win) else { continue }
            
            // 3. Escribir el mensaje en el área de texto vía AX
            let setRes = AXUIElementSetAttributeValue(textArea, kAXValueAttribute as CFString, message as CFTypeRef)
            guard setRes == .success else { continue }
            
            Thread.sleep(forTimeInterval: 0.10)
            
            // 4. Localizar y presionar el botón Enviar exacto
            if let sendBtn = findAXSendButton(win) {
                if clickAXElement(sendBtn) {
                    return true
                }
            }
        }
        return false
    }
    
    private func findAXTextArea(_ elem: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 15 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        if (roleRef as? String) == "AXTextArea" {
            return elem
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                if let found = findAXTextArea(c as! AXUIElement, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
    
    private func findAXSendButton(_ elem: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 16 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXButton" {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
            let t = (titleRef as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let d = (descRef as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "Enviar" || d == "Enviar" || t == "Send" || d == "Send" {
                return elem
            }
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                if let found = findAXSendButton(c as! AXUIElement, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
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
    
    private func activatePasteAndRestore(message: String, recipient: String, previousApp: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        let prevString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
        
        activateWhatsAppWebSync()
        Thread.sleep(forTimeInterval: 0.12)
        
        if !recipient.isEmpty && recipient != "WhatsApp" {
            selectChatViaAX(recipient: recipient)
            Thread.sleep(forTimeInterval: 0.10)
        }
        
        let pasteScript = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.05
            key code 36
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: pasteScript)?.executeAndReturnError(&err)
        
        if let prevStr = prevString {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(prevStr, forType: .string)
            }
        }
        
        // RESTAURAR INMEDIATAMENTE EL FOCO A LA APLICACIÓN PREVIA
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if let prev = previousApp, prev.bundleIdentifier != "com.apple.Safari" && prev.bundleIdentifier != "com.google.Chrome" {
                if #available(macOS 14.0, *) {
                    prev.activate()
                } else {
                    prev.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
    }
    
    private func selectChatViaAX(recipient: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps where app.bundleIdentifier == "com.apple.Safari" ||
                                     app.bundleIdentifier == "com.google.Chrome" ||
                                     app.bundleIdentifier == "net.whatsapp.WhatsApp" {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &winRef) == .success,
               let win = winRef as! AXUIElement?,
               let table = findAXChatTable(win) {
                var rowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(table, kAXRowsAttribute as CFString, &rowsRef) == .success,
                   let rows = rowsRef as? [AnyObject] {
                    for r in rows.prefix(15) {
                        let row = r as! AXUIElement
                        if let p = parseChatRow(row), p.contact.lowercased() == recipient.lowercased() {
                            clickAXElement(row)
                            return
                        }
                    }
                }
            }
        }
    }
    
    @discardableResult
    private func clickAXElement(_ elem: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        AXUIElementCopyActionNames(elem, &actionsRef)
        if let actions = actionsRef as? [String], actions.contains(kAXPressAction as String) {
            return AXUIElementPerformAction(elem, kAXPressAction as CFString) == .success
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AnyObject] {
            for c in children {
                if clickAXElement(c as! AXUIElement) { return true }
            }
        }
        return false
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
                if let safari = runningApps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
                    if #available(macOS 14.0, *) {
                        safari.activate()
                    } else {
                        safari.activate(options: [.activateIgnoringOtherApps])
                    }
                }
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
                if let browser = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                    if #available(macOS 14.0, *) {
                        browser.activate()
                    } else {
                        browser.activate(options: [.activateIgnoringOtherApps])
                    }
                }
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
    public func simulateTestNotification(message: String = "¡Hola! ¿Cómo va el nuevo reproductor de pantalla de bloqueo?") {
        DNDLogger.log("WhatsAppWebObserverService.simulateTestNotification CALLED")
        NotificationActivityProvider.shared.showNotification(
            title: "Carlos",
            message: message,
            handle: "Carlos",
            appIcon: "message.fill",
            appName: "WhatsApp",
            tint: Color(red: 0.15, green: 0.78, blue: 0.45),
            enableQuickReply: true,
            duration: 6.0
        )
        AppState.shared.hapticService.triggerSnap()
    }
}
