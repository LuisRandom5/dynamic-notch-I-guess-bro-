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
    
    // TelephonyUtilities (Llamadas Celulares / FaceTime de macOS)
    private var tuCallCenter: NSObject?
    private var hasActiveTelephonyCall: Bool = false
    private var isIncomingTelephonyCall: Bool = false
    
    // Discord
    private var isDiscordIncomingCall: Bool = false
    
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
                    
                    NotificationCenter.default.addObserver(
                        forName: nil,
                        object: center,
                        queue: .main
                    ) { [weak self] _ in
                        self?.checkTelephonyCalls()
                    }
                }
            }
        }
    }
    
    public func startMonitoring() {
        registerDefaultDeviceListener()
        updateCurrentInputDeviceAndAttachListener()
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkTelephonyCalls()
                self?.checkDiscordState()
                self?.checkInputDeviceRunningState()
            }
        }
        RunLoop.main.add(heartbeatTimer!, forMode: .common)
    }
    
    public func stopMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        detachListenerFromCurrentInputDevice()
        removeDefaultDeviceListener()
    }
    
    public func recheckNow() {
        checkTelephonyCalls()
        checkDiscordState()
        checkInputDeviceRunningState()
    }
    
    // MARK: - Detección de Llamadas de TelephonyUtilities (FaceTime y Celular)
    private func checkTelephonyCalls() {
        guard let center = tuCallCenter else { return }
        
        // 1. Comprobar llamada entrante real (FaceTime / Llamada celular de iPhone)
        if let incoming = center.value(forKey: "incomingCall") as? NSObject {
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
            if isIncomingTelephonyCall {
                self.isIncomingTelephonyCall = false
                if CallActivityProvider.shared.isIncomingCall && !CallActivityProvider.shared.isSimulation {
                    CallActivityProvider.shared.declineCall()
                }
            }
        }
        
        // 2. Comprobar llamadas activas (conectadas)
        if let currentCalls = center.value(forKey: "currentCalls") as? [NSObject], !currentCalls.isEmpty {
            guard !isCallDismissedByUser else { return }
            let active = currentCalls.first!
            
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
    
    // MARK: - Detección de Llamadas y Voz en Discord
    private func checkDiscordState() {
        guard let discordApp = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord"
        }) else { return }
        
        // Si el usuario ya rechazó o cerró, respetar
        guard !isCallDismissedByUser else { return }
        
        // 1. Detección de Llamada Entrante en Discord mediante AXUIElement
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let appRef = AXUIElementCreateApplication(discordApp.processIdentifier)
            var winListRef: AnyObject?
            AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
            
            guard let windows = winListRef as? [AXUIElement] else { return }
            
            var foundIncoming = false
            var callerName = "Discord"
            
            for win in windows {
                func searchIncoming(elem: AXUIElement, depth: Int) {
                    if foundIncoming || depth > 20 { return }
                    var titleRef: AnyObject?
                    var descRef: AnyObject?
                    var valRef: AnyObject?
                    AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
                    AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
                    AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valRef)
                    
                    let title = (titleRef as? String ?? "")
                    let desc = (descRef as? String ?? "")
                    let val = (valRef as? String ?? "")
                    let combined = "\(title) \(desc) \(val)".lowercased()
                    
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
                        for c in children {
                            searchIncoming(elem: c, depth: depth + 1)
                            if foundIncoming { return }
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
        if let center = tuCallCenter,
           let incoming = center.value(forKey: "incomingCall") as? NSObject {
            print("[CallDetectorService] Contestando llamada nativamente vía TUCallCenter...")
            center.perform(NSSelectorFromString("answerCall:"), with: incoming)
            return
        }
        
        // Discord fallback
        pressDiscordIncomingButton(accept: true)
    }
    
    /// Rechaza la llamada entrante nativa
    public func declineCurrentIncomingCall() {
        if let center = tuCallCenter,
           let incoming = center.value(forKey: "incomingCall") as? NSObject {
            print("[CallDetectorService] Rechazando llamada nativamente vía TUCallCenter...")
            center.perform(NSSelectorFromString("disconnectCall:"), with: incoming)
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
