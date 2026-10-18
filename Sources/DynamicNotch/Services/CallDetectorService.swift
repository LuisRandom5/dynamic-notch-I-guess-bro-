import Foundation
import CoreAudio
import AppKit

/// Servicio nativo de detección automática de llamadas y uso del micrófono
/// Integra TelephonyUtilities (FaceTime y llamadas celulares de iPhone),
/// Discord (llamadas y canales de voz vía Accessibility),
/// y CoreAudio hardware (monitoreo del micrófono).
public final class CallDetectorService: ObservableObject {
    public static let shared = CallDetectorService()
    
    @Published public private(set) var isCallActive: Bool = false
    @Published public private(set) var activeCallAppName: String = "FaceTime"
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enableCallDetector")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    // TelephonyUtilities (Llamadas Celulares / FaceTime de macOS)
    private var tuCallCenter: NSObject?
    private var hasActiveTelephonyCall: Bool = false
    private var isIncomingTelephonyCall: Bool = false
    private var currentIncomingCallObject: NSObject?
    
    // WhatsApp
    private var isWhatsAppIncomingCall: Bool = false
    private var isScanningWhatsApp: Bool = false
    private var whatsAppAcceptButton: AXUIElement?
    private var whatsAppDeclineButton: AXUIElement?
    
    // FaceTime UI
    private var isFaceTimeIncomingCall: Bool = false
    private var isScanningFaceTime: Bool = false
    private var faceTimeAcceptButton: AXUIElement?
    private var faceTimeDeclineButton: AXUIElement?
    
    // Discord
    private var isDiscordIncomingCall: Bool = false
    private var isScanningDiscord: Bool = false
    
    private var isCallDismissedByUser: Bool = false
    private var dismissResetTimer: Timer?
    
    public func markCallDismissedByUser() {
        self.isCallDismissedByUser = true
        self.isCallActive = false
        
        dismissResetTimer?.invalidate()
        dismissResetTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isCallDismissedByUser = false
            }
        }
    }
    
    private var currentInputDeviceID: AudioObjectID = 0
    private var isRunningListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var heartbeatTimer: Timer?
    
    private init() {
        if UserDefaults.standard.object(forKey: "enableCallDetector") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "enableCallDetector")
        }
        setupTelephonyUtilities()
    }
    
    // MARK: - Inicialización de TelephonyUtilities
    private func setupTelephonyUtilities() {
        if let bundle = Bundle(path: "/System/Library/PrivateFrameworks/TelephonyUtilities.framework") {
            bundle.load()
            if let cls = NSClassFromString("TUCallCenter") as? NSObject.Type {
                if let center = cls.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject {
                    self.tuCallCenter = center
                    print("[CallDetectorService] TelephonyUtilities (TUCallCenter) enlazado con éxito.")
                    
                    // Escuchar todas las notificaciones del sistema relativas a llamadas
                    // Nota crítica: object debe ser nil para no filtrar llamadas donde el object es un TUCall
                    let notifNames = [
                        "TUCallCenterCallStatusChangedNotification",
                        "TUCallCenterCallConnectedNotification",
                        "TUCallCenterCallStartedConnectingNotification",
                        "TUCallCenterCallContinuityStateChangedNotification",
                        "TUCallCenterVideoCallStatusChangedNotification",
                        "TUCallCenterConferenceParticipantsChangedNotification",
                        "TUCallServicesDaemonStartedNotification"
                    ]
                    
                    for name in notifNames {
                        NotificationCenter.default.addObserver(
                            forName: NSNotification.Name(name),
                            object: nil,
                            queue: .main
                        ) { [weak self] _ in
                            guard self?.isEnabled == true else { return }
                            self?.checkTelephonyCalls()
                        }
                        
                        DistributedNotificationCenter.default().addObserver(
                            forName: NSNotification.Name(name),
                            object: nil,
                            queue: .main
                        ) { [weak self] _ in
                            guard self?.isEnabled == true else { return }
                            self?.checkTelephonyCalls()
                        }
                    }
                }
            }
        }
    }
    
    public func startMonitoring() {
        guard isEnabled else { return }
        registerDefaultDeviceListener()
        updateCurrentInputDeviceAndAttachListener()
        
        heartbeatTimer?.invalidate()
        // Sondeo rápido a 0.35s para detectar llamadas entrantes al instante
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.isEnabled else { return }
                self.checkTelephonyCalls()
                self.checkFaceTimeState()
                self.checkWhatsAppState()
                self.checkDiscordState()
                self.checkInputDeviceRunningState()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }
    
    public func stopMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        detachListenerFromCurrentInputDevice()
        removeDefaultDeviceListener()
    }
    
    public func recheckNow() {
        guard isEnabled else { return }
        checkTelephonyCalls()
        checkFaceTimeState()
        checkWhatsAppState()
        checkDiscordState()
        checkInputDeviceRunningState()
    }
    
    // MARK: - Detección de Llamadas de TelephonyUtilities (FaceTime y Celular)
    private func checkTelephonyCalls() {
        guard let center = tuCallCenter else { return }
        
        // 1. Comprobar llamada entrante real (FaceTime / Llamada celular de iPhone)
        var incoming: NSObject? = center.value(forKey: "incomingCall") as? NSObject
        
        if incoming == nil {
            incoming = center.value(forKey: "incomingVideoCall") as? NSObject
        }
        
        if incoming == nil {
            incoming = center.value(forKey: "resolvedIncomingCall") as? NSObject
        }
        
        if incoming == nil {
            if let incomingList = center.value(forKey: "incomingCalls") as? [NSObject], let first = incomingList.first {
                incoming = first
            }
        }
        
        if incoming == nil {
            let candidates = (center.value(forKey: "displayedCalls") as? [NSObject] ?? []) +
                             (center.value(forKey: "currentCalls") as? [NSObject] ?? []) +
                             (center.value(forKey: "_allCalls") as? [NSObject] ?? [])
            for c in candidates {
                let isInc = (c.value(forKey: "isIncoming") as? Bool) ?? false
                let status = (c.value(forKey: "status") as? Int) ?? 0
                if isInc || status == 4 || status == 1 {
                    incoming = c
                    break
                }
            }
        }
        
        if let incoming = incoming {
            self.currentIncomingCallObject = incoming
            guard !isCallDismissedByUser else { return }
            
            let displayName = (incoming.value(forKey: "displayName") as? String) ??
                              (incoming.value(forKey: "suggestedDisplayName") as? String) ??
                              (incoming.value(forKey: "callerNameFromNetwork") as? String) ?? "Llamada Entrante"
            
            let handleObj = incoming.value(forKey: "handle") as? NSObject
            let handleVal = handleObj?.value(forKey: "value") as? String
            let contactId = incoming.value(forKey: "contactIdentifier") as? String
            let isVideo = (incoming.value(forKey: "isVideo") as? Bool) ?? false
            
            // Determinar tipo de llamada
            let providerName: String
            if isVideo {
                providerName = "FaceTime Video"
            } else if (incoming.value(forKey: "isEmergency") as? Bool) == true {
                providerName = "Llamada de Emergencia"
            } else if let handle = handleVal, handle.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                providerName = "Llamada celular de iPhone"
            } else {
                providerName = "FaceTime Audio"
            }
            
            if !CallActivityProvider.shared.isIncomingCall {
                self.isIncomingTelephonyCall = true
                
                // Buscar contacto con foto en tiempo real
                let info = ContactLookupService.shared.lookupContact(identifier: contactId, name: displayName, handle: handleVal)
                let contactName = info?.name ?? displayName
                let avatar = info?.avatar
                
                print("[CallDetectorService] 📞 Llamada entrante detectada vía TUCallCenter: '\(contactName)' (\(providerName))")
                CallActivityProvider.shared.startIncomingCall(
                    name: providerName,
                    handle: contactName,
                    avatar: avatar,
                    isSimulation: false
                )
            }
            return
        } else {
            self.currentIncomingCallObject = nil
            if isIncomingTelephonyCall {
                self.isIncomingTelephonyCall = false
                if CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isSimulation {
                    CallActivityProvider.shared.declineCall()
                }
            }
        }
        
        // 2. Comprobar llamadas activas (conectadas)
        let currentCalls = (center.value(forKey: "currentCalls") as? [NSObject] ?? []) +
                           (center.value(forKey: "displayedCalls") as? [NSObject] ?? [])
        let connectedCalls = currentCalls.filter { c in
            let isInc = (c.value(forKey: "isIncoming") as? Bool) ?? false
            let status = (c.value(forKey: "status") as? Int) ?? 0
            return !isInc && status != 4 && status != 1
        }
        
        if let active = connectedCalls.first {
            guard !isCallDismissedByUser else { return }
            
            let displayName = (active.value(forKey: "displayName") as? String) ??
                              (active.value(forKey: "suggestedDisplayName") as? String) ??
                              (active.value(forKey: "callerNameFromNetwork") as? String) ?? "Llamada Activa"
            
            let handleObj = active.value(forKey: "handle") as? NSObject
            let handleVal = handleObj?.value(forKey: "value") as? String
            let contactId = active.value(forKey: "contactIdentifier") as? String
            let isVideo = (active.value(forKey: "isVideo") as? Bool) ?? false
            
            let providerName: String
            if isVideo {
                providerName = "FaceTime Video"
            } else if let handle = handleVal, handle.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                providerName = "Llamada celular de iPhone"
            } else {
                providerName = "FaceTime Audio"
            }
            
            if !CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall {
                self.hasActiveTelephonyCall = true
                self.isCallActive = true
                self.activeCallAppName = providerName
                
                let info = ContactLookupService.shared.lookupContact(identifier: contactId, name: displayName, handle: handleVal)
                let contactName = info?.name ?? displayName
                let avatar = info?.avatar
                
                print("[CallDetectorService] 🟢 Llamada activa conectada vía TUCallCenter: '\(contactName)' (\(providerName))")
                CallActivityProvider.shared.startCall(
                    name: providerName,
                    handle: contactName,
                    avatar: avatar,
                    asCard: false,
                    isSimulation: false
                )
            }
            return
        } else {
            if hasActiveTelephonyCall {
                self.hasActiveTelephonyCall = false
                if CallActivityProvider.shared.isCallActive && !CallActivityProvider.shared.isSimulation {
                    print("[CallDetectorService] Llamada en TUCallCenter terminada.")
                    CallActivityProvider.shared.endCall()
                }
            }
        }
    }
    
    // MARK: - Detección de Llamadas Entrantes en WhatsApp
    private func checkWhatsAppState() {
        guard !isScanningWhatsApp, !isCallDismissedByUser else { return }
        guard let whatsApp = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.lowercased().contains("whatsapp") ?? false) || ($0.localizedName?.lowercased().contains("whatsapp") ?? false)
        }) else { return }
        
        isScanningWhatsApp = true
        let pid = whatsApp.processIdentifier
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isScanningWhatsApp = false
                }
            }
            guard let self = self else { return }
            let appRef = AXUIElementCreateApplication(pid)
            var winListRef: AnyObject?
            AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
            guard let windows = winListRef as? [AXUIElement] else { return }
            
            var foundIncoming = false
            var callerName = "WhatsApp"
            var acceptBtn: AXUIElement?
            var declineBtn: AXUIElement?
            
            for win in windows.prefix(4) {
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String ?? "")
                
                var localAccept: AXUIElement?
                var localDecline: AXUIElement?
                var visited = 0
                
                func search(elem: AXUIElement, depth: Int) {
                    if depth > 12 || visited > 100 { return }
                    visited += 1
                    var tRef: AnyObject?
                    var dRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &tRef)
                    AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &dRef)
                    let t = (tRef as? String ?? "").lowercased()
                    let d = (dRef as? String ?? "").lowercased()
                    
                    if t.contains("aceptar") || t.contains("contestar") || t.contains("unirse") || t.contains("accept") || t.contains("answer") ||
                       d.contains("aceptar") || d.contains("contestar") || d.contains("unirse") || d.contains("accept") || d.contains("answer") {
                        localAccept = elem
                    }
                    if t.contains("rechazar") || t.contains("decline") || t.contains("colgar") ||
                       d.contains("rechazar") || d.contains("decline") || d.contains("colgar") {
                        localDecline = elem
                    }
                    
                    var childrenRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
                    if let children = childrenRef as? [AXUIElement] {
                        for c in children.prefix(20) {
                            search(elem: c, depth: depth + 1)
                        }
                    }
                }
                search(elem: win, depth: 0)
                
                if localAccept != nil && localDecline != nil {
                    foundIncoming = true
                    acceptBtn = localAccept
                    declineBtn = localDecline
                    if !title.isEmpty && !title.lowercased().contains("whatsapp") {
                        callerName = title
                    }
                    break
                }
            }
            
            DispatchQueue.main.async {
                self.whatsAppAcceptButton = acceptBtn
                self.whatsAppDeclineButton = declineBtn
                
                if foundIncoming && !CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isCallActive {
                    self.isWhatsAppIncomingCall = true
                    let info = ContactLookupService.shared.lookupContact(name: callerName)
                    CallActivityProvider.shared.startIncomingCall(
                        name: "WhatsApp",
                        handle: callerName,
                        avatar: info?.avatar,
                        isSimulation: false
                    )
                } else if !foundIncoming && self.isWhatsAppIncomingCall {
                    self.isWhatsAppIncomingCall = false
                    if CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isSimulation {
                        CallActivityProvider.shared.declineCall()
                    }
                }
            }
        }
    }
    
    // MARK: - Detección de Llamadas Entrantes en FaceTime
    private func checkFaceTimeState() {
        guard !isScanningFaceTime, !isCallDismissedByUser else { return }
        
        let runningApps = NSWorkspace.shared.runningApplications
        // Candidatos que pueden mostrar el banner o ventana de llamada FaceTime:
        // 1. App FaceTime nativa
        // 2. Servicios de notificación de FaceTime (FaceTimeNotificationCenterService, etc.)
        // 3. Centro de notificaciones de macOS (com.apple.notificationcenterui)
        // Sólo por identificador: pedir `localizedName` de cada app es una consulta cara al sistema y esto
        // corre en el hilo principal cada 0.35 s (se comía cuadros de las animaciones del notch)
        let candidateApps = runningApps.filter { app in
            let b = app.bundleIdentifier?.lowercased() ?? ""
            return b.contains("facetime") || b == "com.apple.notificationcenterui"
        }
        
        guard !candidateApps.isEmpty else { return }
        
        isScanningFaceTime = true
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isScanningFaceTime = false
                }
            }
            guard let self = self else { return }
            
            var foundIncoming = false
            var callerName = "FaceTime"
            var isVideoCall = false
            var acceptBtn: AXUIElement?
            var declineBtn: AXUIElement?
            
            for app in candidateApps {
                let pid = app.processIdentifier
                let appRef = AXUIElementCreateApplication(pid)
                var winListRef: AnyObject?
                AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
                guard let windows = winListRef as? [AXUIElement] else { continue }
                
                for win in windows.prefix(6) {
                    var titleRef: AnyObject?
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                    let title = (titleRef as? String ?? "")
                    
                    // Omitir widgets estándar de centro de notificaciones
                    if title == "Estado" || title == "Previsión" { continue }
                    
                    var localAccept: AXUIElement?
                    var localDecline: AXUIElement?
                    var detectedName: String?
                    var mentionsFaceTime = (app.bundleIdentifier?.lowercased().contains("facetime") ?? false) ||
                                           (app.localizedName?.lowercased().contains("facetime") ?? false)
                    var visited = 0
                    
                    func search(elem: AXUIElement, depth: Int) {
                        if depth > 12 || visited > 120 { return }
                        visited += 1
                        
                        var tRef: AnyObject?
                        var dRef: AnyObject?
                        var vRef: AnyObject?
                        AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &tRef)
                        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &dRef)
                        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &vRef)
                        
                        let t = (tRef as? String ?? "").lowercased()
                        let d = (dRef as? String ?? "").lowercased()
                        let v = (vRef as? String ?? "").lowercased()
                        
                        if t.contains("facetime") || d.contains("facetime") || v.contains("facetime") {
                            mentionsFaceTime = true
                        }
                        if t.contains("video") || d.contains("video") || v.contains("video") {
                            isVideoCall = true
                        }
                        
                        // Botón Aceptar / Contestar / Unirse
                        let isAccept = t.contains("aceptar") || t.contains("contestar") || t.contains("unirse") ||
                                       t.contains("accept") || t.contains("answer") || t.contains("join") ||
                                       d.contains("aceptar") || d.contains("contestar") || d.contains("unirse") ||
                                       d.contains("accept") || d.contains("answer") || d.contains("join")
                        if isAccept && localAccept == nil {
                            localAccept = elem
                        }
                        
                        // Botón Rechazar / Colgar / Decline
                        let isDecline = t.contains("rechazar") || t.contains("decline") || t.contains("colgar") ||
                                        d.contains("rechazar") || d.contains("decline") || d.contains("colgar")
                        if isDecline && localDecline == nil {
                            localDecline = elem
                        }
                        
                        // Extracción de posible nombre del remitente si no es una acción o label genérico
                        if detectedName == nil {
                            let rawVal = (vRef as? String) ?? (tRef as? String) ?? ""
                            let clean = rawVal.trimmingCharacters(in: .whitespacesAndNewlines)
                            let l = clean.lowercased()
                            if !clean.isEmpty && l != "facetime" && l != "facetime audio" && l != "facetime video" &&
                               !l.contains("aceptar") && !l.contains("rechazar") && !l.contains("notification center") &&
                               !l.contains("centro de notificaciones") && clean.count < 60 {
                                detectedName = clean
                            }
                        }
                        
                        var childrenRef: AnyObject?
                        AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
                        if let children = childrenRef as? [AXUIElement] {
                            for c in children.prefix(20) {
                                search(elem: c, depth: depth + 1)
                            }
                        }
                    }
                    
                    search(elem: win, depth: 0)
                    
                    if localAccept != nil && localDecline != nil && mentionsFaceTime {
                        foundIncoming = true
                        acceptBtn = localAccept
                        declineBtn = localDecline
                        
                        if let name = detectedName, !name.isEmpty {
                            callerName = name
                        } else if !title.isEmpty && !title.lowercased().contains("facetime") && !title.lowercased().contains("notification") {
                            callerName = title
                        }
                        break
                    }
                }
                
                if foundIncoming { break }
            }
            
            DispatchQueue.main.async {
                self.faceTimeAcceptButton = acceptBtn
                self.faceTimeDeclineButton = declineBtn
                
                if foundIncoming && !CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isCallActive {
                    self.isFaceTimeIncomingCall = true
                    let info = ContactLookupService.shared.lookupContact(name: callerName)
                    let callType = isVideoCall ? "FaceTime Video" : "FaceTime Audio"
                    
                    print("[CallDetectorService] 📞 Llamada entrante FaceTime detectada: '\(callerName)' (\(callType))")
                    CallActivityProvider.shared.startIncomingCall(
                        name: callType,
                        handle: info?.name ?? callerName,
                        avatar: info?.avatar,
                        isSimulation: false
                    )
                } else if !foundIncoming && self.isFaceTimeIncomingCall {
                    self.isFaceTimeIncomingCall = false
                    if CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isSimulation {
                        CallActivityProvider.shared.declineCall()
                    }
                }
            }
        }
    }
    
    // MARK: - Detección de Llamadas y Voz en Discord
    private func checkDiscordState() {
        guard !isScanningDiscord, !isCallDismissedByUser else { return }
        guard let discordApp = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord"
        }) else { return }
        
        isScanningDiscord = true
        let pid = discordApp.processIdentifier
        
        // 1. Detección acotada de Llamada Entrante en Discord mediante AXUIElement
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isScanningDiscord = false
                }
            }
            guard let self = self else { return }
            let appRef = AXUIElementCreateApplication(pid)
            var winListRef: AnyObject?
            AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
            
            guard let windows = winListRef as? [AXUIElement] else { return }
            
            var foundIncoming = false
            var callerName = "Discord"
            var visitedNodes = 0
            
            for win in windows.prefix(2) {
                func searchIncoming(elem: AXUIElement, depth: Int) {
                    if foundIncoming || depth > 10 || visitedNodes > 150 { return }
                    visitedNodes += 1
                    var titleRef: AnyObject?
                    var descRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
                    AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
                    
                    let title = (titleRef as? String ?? "")
                    let desc = (descRef as? String ?? "")
                    let combined = "\(title) \(desc)".lowercased()
                    
                    if combined.contains("unirse a la llamada") || combined.contains("join call") {
                        foundIncoming = true
                        if !title.isEmpty && !title.lowercased().contains("unirse") && !title.lowercased().contains("join") {
                            callerName = title
                        }
                        return
                    }
                    
                    var childrenRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
                    if let children = childrenRef as? [AXUIElement] {
                        for c in children.prefix(25) {
                            searchIncoming(elem: c, depth: depth + 1)
                            if foundIncoming || visitedNodes > 150 { return }
                        }
                    }
                }
                searchIncoming(elem: win, depth: 0)
                if foundIncoming { break }
            }
            
            DispatchQueue.main.async {
                if foundIncoming && !CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isCallActive {
                    self.isDiscordIncomingCall = true
                    let info = ContactLookupService.shared.lookupContact(name: callerName)
                    CallActivityProvider.shared.startIncomingCall(
                        name: "Discord",
                        handle: callerName,
                        avatar: info?.avatar,
                        isSimulation: false
                    )
                } else if !foundIncoming && self.isDiscordIncomingCall {
                    self.isDiscordIncomingCall = false
                }
            }
        }
    }
    
    // MARK: - Acciones Nativas de Control de Llamada
    
    /// Contesta la llamada entrante nativa sin scripts ni atajos
    public func answerCurrentIncomingCall() {
        if let center = tuCallCenter {
            let incoming = (center.value(forKey: "incomingCall") as? NSObject) ?? currentIncomingCallObject
            if let incoming = incoming {
                print("[CallDetectorService] Contestando llamada nativamente vía TUCallCenter...")
                center.perform(NSSelectorFromString("answerCall:"), with: incoming)
                return
            }
        }
        
        // FaceTime UI
        if isFaceTimeIncomingCall, let btn = faceTimeAcceptButton {
            print("[CallDetectorService] Contestando llamada en FaceTime...")
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return
        }
        
        // WhatsApp
        if isWhatsAppIncomingCall, let btn = whatsAppAcceptButton {
            print("[CallDetectorService] Contestando llamada en WhatsApp...")
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return
        }
        
        // Discord fallback
        pressDiscordIncomingButton(accept: true)
    }
    
    /// Rechaza la llamada entrante nativa
    public func declineCurrentIncomingCall() {
        if let center = tuCallCenter {
            let incoming = (center.value(forKey: "incomingCall") as? NSObject) ?? currentIncomingCallObject
            if let incoming = incoming {
                print("[CallDetectorService] Rechazando llamada nativamente vía TUCallCenter...")
                center.perform(NSSelectorFromString("disconnectCall:"), with: incoming)
                return
            }
        }
        
        // FaceTime UI
        if isFaceTimeIncomingCall, let btn = faceTimeDeclineButton {
            print("[CallDetectorService] Rechazando llamada en FaceTime...")
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return
        }
        
        // WhatsApp
        if isWhatsAppIncomingCall, let btn = whatsAppDeclineButton {
            print("[CallDetectorService] Rechazando llamada en WhatsApp...")
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return
        }
        
        // Discord fallback
        pressDiscordIncomingButton(accept: false)
    }
    
    /// Cuelga la llamada activa de forma segura y sin efectos secundarios
    public func hangupActiveCall() {
        // 1. Si hay llamada en TUCallCenter, colgarla directamente
        if let center = tuCallCenter {
            if let calls = center.value(forKey: "currentCalls") as? [NSObject], !calls.isEmpty {
                print("[CallDetectorService] Colgando llamada activa nativamente vía TUCallCenter...")
                center.perform(NSSelectorFromString("disconnectCurrentCall"))
                return
            }
        }
        
        // 2. Si Discord está corriendo y activo, desconectar con AXPress
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord" }) {
            CallActivityProvider.shared.disconnectDiscordNatively()
        }
        
        // 3. Si FaceTime está corriendo, desconectar con AXPress sin interferir en otras ventanas
        if runningApps.contains(where: { ($0.bundleIdentifier?.lowercased().contains("facetime") ?? false) || $0.localizedName == "FaceTime" }) {
            CallActivityProvider.shared.disconnectFaceTimeNatively()
        }
    }
    
    private func pressDiscordIncomingButton(accept: Bool) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord"
        }) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var winListRef: AnyObject?
            AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
            guard let windows = winListRef as? [AXUIElement] else { return }
            
            var targetBtn: AXUIElement?
            for win in windows {
                func search(elem: AXUIElement, depth: Int) {
                    if targetBtn != nil || depth > 20 { return }
                    var titleRef: AnyObject?
                    var descRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
                    AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
                    let t = (titleRef as? String ?? "").lowercased()
                    let d = (descRef as? String ?? "").lowercased()
                    
                    if accept {
                        if t.contains("unirse") || t.contains("join") || d.contains("unirse") || d.contains("join") {
                            targetBtn = elem
                            return
                        }
                    } else {
                        if t.contains("rechazar") || t.contains("decline") || d.contains("rechazar") || d.contains("decline") {
                            targetBtn = elem
                            return
                        }
                    }
                    
                    var childrenRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
                    if let children = childrenRef as? [AXUIElement] {
                        for c in children {
                            search(elem: c, depth: depth + 1)
                            if targetBtn != nil { return }
                        }
                    }
                }
                search(elem: win, depth: 0)
                if targetBtn != nil { break }
            }
            
            if let btn = targetBtn {
                AXUIElementPerformAction(btn, kAXPressAction as CFString)
            }
        }
    }
    
    // MARK: - Listener de CoreAudio para Micrófono (Fallback Universal)
    private func registerDefaultDeviceListener() {
        removeDefaultDeviceListener()
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateCurrentInputDeviceAndAttachListener()
            }
        }
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        
        if status == noErr {
            self.defaultDeviceListenerBlock = block
        }
    }
    
    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        defaultDeviceListenerBlock = nil
    }
    
    private func updateCurrentInputDeviceAndAttachListener() {
        detachListenerFromCurrentInputDevice()
        
        var defaultInputDevice: AudioObjectID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultInputDevice
        )
        
        guard status == noErr, defaultInputDevice != 0 else { return }
        self.currentInputDeviceID = defaultInputDevice
        
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.checkInputDeviceRunningState()
            }
        }
        
        let attachStatus = AudioObjectAddPropertyListenerBlock(
            defaultInputDevice,
            &runAddress,
            DispatchQueue.main,
            block
        )
        
        if attachStatus == noErr {
            self.isRunningListenerBlock = block
        }
        
        checkInputDeviceRunningState()
    }
    
    private func detachListenerFromCurrentInputDevice() {
        guard currentInputDeviceID != 0, let block = isRunningListenerBlock else { return }
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            currentInputDeviceID,
            &runAddress,
            DispatchQueue.main,
            block
        )
        isRunningListenerBlock = nil
        currentInputDeviceID = 0
    }
    
    private func checkInputDeviceRunningState() {
        guard currentInputDeviceID != 0 else { return }
        
        var isRunning: UInt32 = 0
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            currentInputDeviceID,
            &runAddress,
            0,
            nil,
            &size,
            &isRunning
        )
        
        guard status == noErr else { return }
        let isDeviceRunning = (isRunning != 0)
        
        // Si ya está atendido por TelephonyUtilities o el usuario descartó conscientemente, no duplicar
        if hasActiveTelephonyCall || isIncomingTelephonyCall || isCallDismissedByUser {
            return
        }
        
        if isDeviceRunning {
            if !isCallActive || !CallActivityProvider.shared.isCallActive {
                let detectedApp = detectActiveCallingApp()
                self.activeCallAppName = detectedApp
                self.isCallActive = true
                print("[CallDetectorService] Micrófono activo en '\(detectedApp)'. Iniciando Live Activity...")
                
                let info = ContactLookupService.shared.lookupContact(name: detectedApp)
                CallActivityProvider.shared.startCall(
                    name: detectedApp,
                    handle: "Llamada Activa",
                    avatar: info?.avatar,
                    asCard: false,
                    isSimulation: false
                )
            }
        } else {
            self.isCallDismissedByUser = false
            if isCallActive && !hasActiveTelephonyCall {
                self.isCallActive = false
                print("[CallDetectorService] Micrófono desactivado. Finalizando Live Activity...")
                CallActivityProvider.shared.endCall()
            }
        }
    }
    
    private func detectActiveCallingApp() -> String {
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { ($0.bundleIdentifier?.contains("facetime") ?? false) || $0.localizedName == "FaceTime" }) {
            return "FaceTime Audio"
        }
        if runningApps.contains(where: { ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord" }) {
            return "Discord"
        }
        if runningApps.contains(where: { ($0.bundleIdentifier?.lowercased().contains("zoom") ?? false) || ($0.localizedName?.lowercased().contains("zoom") ?? false) }) {
            return "Zoom"
        }
        if runningApps.contains(where: { ($0.bundleIdentifier?.lowercased().contains("whatsapp") ?? false) || ($0.localizedName?.lowercased().contains("whatsapp") ?? false) }) {
            return "WhatsApp"
        }
        if runningApps.contains(where: { ($0.bundleIdentifier?.lowercased().contains("slack") ?? false) || ($0.localizedName?.lowercased().contains("slack") ?? false) }) {
            return "Slack Huddle"
        }
        if runningApps.contains(where: { ($0.bundleIdentifier?.lowercased().contains("teams") ?? false) || ($0.localizedName?.lowercased().contains("teams") ?? false) }) {
            return "Microsoft Teams"
        }
        return "Llamada de Audio"
    }
}
