import SwiftUI
import Combine
import AppKit
import ApplicationServices

/// Proveedor de Live Activity para Llamadas en Vivo (FaceTime / Teléfono)
/// Incorpora el espectro de audio reactivo en tiempo real a la voz / micrófono,
/// integración con Contactos del sistema para mostrar avatar real y mute de hardware.
public final class CallActivityProvider: ObservableObject {
    public static let shared = CallActivityProvider()
      @Published public private(set) var isCallActive: Bool = false
    @Published public private(set) var isIncomingCall: Bool = false
    @Published public private(set) var isSimulation: Bool = false
    @Published public private(set) var callerName: String = "FaceTime Audio"
    @Published public private(set) var callerHandle: String = "Mamá"
    @Published public private(set) var callerAvatar: NSImage? = nil
    @Published public private(set) var callDurationSeconds: Int = 0
    @Published public var isMuted: Bool = false
    @Published public var isExpandedCard: Bool = false
    
    private var callTimer: Timer?
    
    private init() {}
    
    public var formattedDuration: String {
        let m = callDurationSeconds / 60
        let s = callDurationSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    /// Inicia una sesión de llamada en curso (real o simulación)
    public func startCall(
        name: String = "FaceTime Audio",
        handle: String = "Mamá",
        avatar: NSImage? = nil,
        asCard: Bool = false,
        isSimulation: Bool = false
    ) {
        endCall(internalReset: true)
        
        self.callerName = name
        self.callerHandle = handle
        self.callDurationSeconds = 0
        self.isMuted = AudioDeviceService.shared.isMicrophoneMuted()
        self.isExpandedCard = asCard
        self.isCallActive = true
        self.isIncomingCall = false
        self.isSimulation = isSimulation
        self.callerAvatar = avatar
        
        // Si no se proporcionó avatar, consultar Contactos del sistema
        if avatar == nil {
            lookupContactAvatar(query: handle.isEmpty ? name : handle)
        }
        
        publishCurrentState()
        
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.isCallActive else { return }
                self.callDurationSeconds += 1
                self.publishCurrentState()
            }
        }
        
        AppState.shared.hapticService.triggerExpand()
    }
    
    /// Inicia la alerta interactiva de llamada entrante con botones Contestar y Rechazar
    public func startIncomingCall(
        name: String = "FaceTime Audio",
        handle: String = "Mamá",
        avatar: NSImage? = nil,
        isSimulation: Bool = false
    ) {
        endCall(internalReset: true)
        
        self.callerName = name
        self.callerHandle = handle
        self.isIncomingCall = true
        self.isCallActive = false
        self.isSimulation = isSimulation
        self.callerAvatar = avatar
        
        if avatar == nil {
            lookupContactAvatar(query: handle.isEmpty ? name : handle)
        }
        
        publishIncomingCallActivity()
        AppState.shared.hapticService.triggerExpand()
    }
    
    /// El usuario contesta la llamada: transiciona de inmediato a la tarjeta de llamada activa
    public func answerCall() {
        guard isIncomingCall else { return }
        let currentSim = isSimulation
        let currentAvatar = callerAvatar
        let name = callerName
        let handle = callerHandle
        self.isIncomingCall = false
        
        if !currentSim {
            CallDetectorService.shared.answerCurrentIncomingCall()
        }
        
        startCall(name: name, handle: handle, avatar: currentAvatar, asCard: true, isSimulation: currentSim)
    }
    
    /// El usuario rechaza la llamada entrante
    public func declineCall() {
        let currentSim = isSimulation
        self.isIncomingCall = false
        
        if !currentSim {
            CallDetectorService.shared.declineCurrentIncomingCall()
        }
        
        DispatchQueue.main.async {
            ActivityCenter.shared.dismissWithAnimation(id: "call_live_activity")
        }
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Consulta el avatar del contacto solicitando autorización si aún no se tiene
    private func lookupContactAvatar(query: String) {
        ContactLookupService.shared.requestAccess { [weak self] _ in
            guard let self = self else { return }
            if let result = ContactLookupService.shared.lookupContact(name: query, handle: query) {
                DispatchQueue.main.async {
                    if let img = result.avatar {
                        self.callerAvatar = img
                        if self.isIncomingCall {
                            self.publishIncomingCallActivity()
                        } else if self.isCallActive {
                            self.publishCurrentState()
                        }
                    }
                }
            }
        }
    }
    
    /// Silencia/reactiva el micrófono físico real del sistema (CoreAudio nativo, 100% seguro)
    public func toggleMute() {
        isMuted.toggle()
        AudioDeviceService.shared.setMicrophoneMuted(isMuted)
        AppState.shared.hapticService.triggerSnap()
        
        // Confirmación auditiva nativa para avisar al usuario cuando se silencia o reactiva
        if isMuted {
            NSSound(named: "Bottle")?.play()
        } else {
            NSSound(named: "Tink")?.play()
        }
        
        publishCurrentState()
    }
    
    /// Finaliza la llamada activa (limpia estado visual y cuelga en app real si aplica)
    public func endCall(internalReset: Bool = false) {
        if isIncomingCall && !internalReset {
            declineCall()
            return
        }
        guard isCallActive || internalReset else { return }
        let currentSim = isSimulation
        
        callTimer?.invalidate()
        callTimer = nil
        isCallActive = false
        isExpandedCard = false
        callDurationSeconds = 0
        callerAvatar = nil
        
        // Restaurar micrófono físico si estaba silenciado
        if isMuted {
            isMuted = false
            AudioDeviceService.shared.setMicrophoneMuted(false)
        }
        
        if !internalReset {
            CallDetectorService.shared.markCallDismissedByUser()
            
            // Colgar de forma segura y no destructiva SOLO si es una llamada real detectada
            if !currentSim {
                CallDetectorService.shared.hangupActiveCall()
            }
            
            DispatchQueue.main.async {
                ActivityCenter.shared.dismissWithAnimation(id: "call_live_activity")
            }
            AppState.shared.hapticService.triggerSnap()
        }
    }
    
    @discardableResult
    public func disconnectDiscordNatively() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.contains("discord") ?? false) || $0.localizedName == "Discord"
        }) else { return false }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        
        var winRef: AnyObject?
        AXUIElementCopyAttributeValue(appRef, "AXMainWindow" as CFString, &winRef)
        guard let win = winRef as! AXUIElement? else { return false }
        
        var foundBtn: AXUIElement?
        func search(elem: AXUIElement, depth: Int) {
            if foundBtn != nil || depth > 30 { return }
            var descRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
            let d = (descRef as? String ?? "").lowercased()
            let t = (titleRef as? String ?? "").lowercased()
            if d == "desconectar" || d == "disconnect" || t == "desconectar" || t == "disconnect" {
                foundBtn = elem
                return
            }
            var childrenRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
            if let children = childrenRef as? [AXUIElement] {
                for c in children {
                    search(elem: c, depth: depth + 1)
                    if foundBtn != nil { return }
                }
            }
        }
        search(elem: win, depth: 0)
        
        if let btn = foundBtn {
            let res = AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return res == .success
        }
        return false
    }
    
    @discardableResult
    public func disconnectFaceTimeNatively() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier?.lowercased().contains("facetime") ?? false) || $0.localizedName == "FaceTime"
        }) else { return false }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var foundBtn: AXUIElement?
        func search(elem: AXUIElement, depth: Int) {
            if foundBtn != nil || depth > 25 { return }
            
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            
            var descRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
            
            let d = (descRef as? String ?? "").lowercased()
            let t = (titleRef as? String ?? "").lowercased()
            
            let isHangupWord = d.contains("finalizar") || d.contains("end call") || d.contains("colgar") || d.contains("leave") || d.contains("terminar") ||
                               t.contains("finalizar") || t.contains("end call") || t.contains("colgar") || t.contains("leave") || t.contains("terminar")
            
            if (role == (kAXButtonRole as String) || role == "AXButton") && isHangupWord {
                foundBtn = elem
                return
            }
            
            var childrenRef: AnyObject?
            AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef)
            if let children = childrenRef as? [AXUIElement] {
                for c in children {
                    search(elem: c, depth: depth + 1)
                    if foundBtn != nil { return }
                }
            }
        }
        
        var winListRef: AnyObject?
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &winListRef)
        if let windows = winListRef as? [AXUIElement] {
            for win in windows {
                search(elem: win, depth: 0)
                if foundBtn != nil { break }
            }
        }
        if foundBtn == nil {
            search(elem: appRef, depth: 0)
        }
        
        if let btn = foundBtn {
            let res = AXUIElementPerformAction(btn, kAXPressAction as CFString)
            return res == .success
        }
        return false
    }
    
    public func toggleExpandedMode() {
        isExpandedCard.toggle()
        publishCurrentState()
    }
    
    /// Contrae la tarjeta extendida de vuelta al notch compacto
    public func collapseToPill() {
        guard isExpandedCard else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            self.isExpandedCard = false
            self.publishCurrentState()
        }
        AppState.shared.hapticService.triggerSnap()
    }
    
    /// Expande la píldora compacta a la tarjeta extendida
    public func expandToCard() {
        guard !isExpandedCard else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
            self.isExpandedCard = true
            self.publishCurrentState()
        }
        AppState.shared.hapticService.triggerExpand()
    }
    
    private func publishCurrentState() {
        guard isCallActive else { return }
        
        if isExpandedCard {
            publishCardActivity()
        } else {
            publishPillActivity()
        }
    }
    
    // MARK: - Modo Píldora Compacta (Notch Compacto con Ondas de Voz)
    private func publishPillActivity() {
        let durationStr = formattedDuration
        let muted = isMuted
        let avatar = callerAvatar
        
        let leading = AnyView(
            HStack(spacing: 5) {
                ZStack {
                    if let avatar = avatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 17, height: 17)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(DesignTokens.green.opacity(0.25))
                            .frame(width: 17, height: 17)
                        
                        Image(systemName: muted ? "mic.slash.fill" : "phone.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(muted ? DesignTokens.orange : DesignTokens.green)
                    }
                }
                
                Text(durationStr)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(DesignTokens.green)
            }
        )
        
        let trailing = AnyView(
            AudioVisualizer(
                isPlaying: !muted,
                customGradient: LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.88, blue: 0.50),   // Verde manzana brillante
                        Color(red: 0.98, green: 0.80, blue: 0.20)    // Ámbar dinámico de voz
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.trailing, 2)
        )
        
        let activity = LiveActivity(
            id: "call_live_activity",
            priority: 60, // Prioridad de sesión continua en curso (permite que alertas transitorias como WhatsApp o volumen se muestren temporalmente)
            style: .pill,
            leading: leading,
            center: nil,
            trailing: trailing,
            tint: DesignTokens.green,
            duration: nil,
            onTap: { [weak self] in
                self?.expandToCard()
            }
        )
        
        ActivityCenter.shared.publish(activity)
    }
    
    // MARK: - Modo Tarjeta Extendida (.card)
    private func publishCardActivity() {
        let durationStr = formattedDuration
        let name = callerName
        let handle = callerHandle
        let muted = isMuted
        let avatar = callerAvatar
        
        let leading = AnyView(
            ZStack(alignment: .bottomTrailing) {
                // Avatar circular perfectamente centrado
                ZStack(alignment: .center) {
                    if let avatar = avatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    } else {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.20, green: 0.75, blue: 0.40), Color(red: 0.10, green: 0.50, blue: 0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                
                // Pequeña insignia de teléfono verde en la esquina inferior derecha
                Circle()
                    .fill(DesignTokens.green)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "phone.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 2, y: 2)
            }
        )
        
        let center = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(handle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("• \(durationStr)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(DesignTokens.green)
                }
                
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.60))
                
                // Visualizador de audio reactivo en el cuerpo de la tarjeta
                AudioVisualizer(
                    isPlaying: !muted,
                    customGradient: LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.90, blue: 0.55),
                            Color(red: 0.98, green: 0.85, blue: 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 20)
                .padding(.top, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                CallActivityProvider.shared.collapseToPill()
            }
        )
        
        let trailing = AnyView(
            HStack(spacing: 10) {
                // Botón silenciar micrófono físico
                Button(action: {
                    CallActivityProvider.shared.toggleMute()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(muted ? 0.35 : 0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(muted ? DesignTokens.orange : .white)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(muted ? "Reactivar micrófono" : "Silenciar micrófono")
                
                // Botón colgar llamada
                Button(action: {
                    CallActivityProvider.shared.endCall()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 34, height: 34)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Colgar llamada")
            }
        )
        
        let activity = LiveActivity(
            id: "call_live_activity",
            priority: 60,
            style: .card,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: DesignTokens.green,
            duration: nil,
            onTap: { [weak self] in
                self?.collapseToPill()
            }
        )
        
        ActivityCenter.shared.publish(activity)
    }
    
    // MARK: - Modo Llamada Entrante (Tarjeta con Responder y Rechazar)
    private func publishIncomingCallActivity() {
        guard isIncomingCall else { return }
        let handle = callerHandle
        let name = callerName
        let avatar = callerAvatar
        
        let leading = AnyView(
            ZStack {
                Circle()
                    .fill(DesignTokens.green.opacity(0.18))
                    .frame(width: 50, height: 50)
                
                if let avatar = avatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.20, green: 0.75, blue: 0.40), Color(red: 0.10, green: 0.50, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Insignia telefónica verde
                Circle()
                    .fill(DesignTokens.green)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "phone.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 15, y: 15)
            }
            .frame(width: 50, height: 50)
        )
        
        let center = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text(handle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 5) {
                    Image(systemName: "phone.arrow.down.left.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.green)
                    Text("Llamada entrante...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignTokens.green)
                }
                
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.60))
                    .lineLimit(1)
            }
        )
        
        let trailing = AnyView(
            HStack(spacing: 12) {
                // Botón Rechazar (Rojo)
                Button(action: {
                    CallActivityProvider.shared.declineCall()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.25, blue: 0.25))
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 3)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Rechazar llamada")
                
                // Botón Contestar (Verde)
                Button(action: {
                    CallActivityProvider.shared.answerCall()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.84, blue: 0.40))
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.green.opacity(0.40), radius: 6, x: 0, y: 3)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Contestar llamada")
            }
        )
        
        let activity = LiveActivity(
            id: "call_live_activity",
            priority: 100,
            style: .card,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: DesignTokens.green,
            duration: nil,
            onTap: nil
        )
        
        ActivityCenter.shared.publish(activity)
    }
}
