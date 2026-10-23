import SwiftUI
import AppKit

/// Vista interactiva para notificaciones con soporte de Swipe Down y Respuesta Rápida (Quick Reply)
/// Diseñada con estética Liquid Glass, esquinas amplias y despeje total del notch físico.
public struct QuickReplyNotificationView: View {
    public let id: String
    private let initialTitle: String
    private let initialMessage: String
    private let initialHandle: String
    private let initialAvatar: NSImage?
    public let appName: String
    public let appIcon: String
    public let tintColor: Color
    private let initialQuickReply: Bool
    
    // Fuente de verdad única: el proveedor.
    @ObservedObject private var provider = NotificationActivityProvider.shared
    
    /// Datos en vivo: si el proveedor actualizó esta notificación (p. ej. descubrió el remitente real),
    /// la vista los refleja en lugar de quedarse con los que tenía al crearse.
    private var livePayload: NotificationPayload? {
        provider.currentPayload?.id == id ? provider.currentPayload : nil
    }
    public var title: String { livePayload?.title ?? initialTitle }
    public var message: String { livePayload?.message ?? initialMessage }
    private var senderIsTheApp: Bool {
        title.lowercased() == appName.lowercased() || title.lowercased().hasPrefix("whatsapp")
    }

    /// Lo que se muestra: "Mensaje nuevo" si el ajuste de privacidad lo pide (p. ej. grabando la pantalla)
    private var displayedMessage: String {
        NotificationActivityProvider.hidesMessageText ? L("Mensaje nuevo") : message
    }
    public var handle: String { livePayload?.handle ?? initialHandle }
    public var avatar: NSImage? { livePayload?.avatar ?? initialAvatar }
    public var enableQuickReply: Bool { livePayload?.enableQuickReply ?? initialQuickReply }
    private var isExpanded: Bool {
        provider.isQuickReplyExpanded && (provider.currentNotificationId == id || provider.currentNotificationId == nil)
    }
    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var isSentSuccess: Bool = false
    @State private var dragOffsetY: CGFloat = 0
    @State private var isHoveringCard = false
    @FocusState private var isInputFocused: Bool
    
    // Geometría calibrada sincronizada con NotificationActivityProvider
    private let compactWidth: CGFloat = NotificationActivityProvider.compactWidth
    private let compactHeight: CGFloat = NotificationActivityProvider.compactHeight
    private let expandedWidth: CGFloat = NotificationActivityProvider.expandedWidth
    private let expandedHeight: CGFloat = NotificationActivityProvider.expandedHeight
    
    public init(
        id: String,
        title: String,
        message: String,
        handle: String = "",
        avatar: NSImage? = nil,
        appName: String = "WhatsApp",
        appIcon: String = "message.fill",
        tintColor: Color = Color(red: 0.15, green: 0.78, blue: 0.45),
        enableQuickReply: Bool = true
    ) {
        self.id = id
        self.initialTitle = title
        self.initialMessage = message
        self.initialHandle = handle.isEmpty ? title : handle
        self.initialAvatar = avatar
        self.appName = appName
        self.appIcon = appIcon
        self.tintColor = tintColor
        self.initialQuickReply = NotificationActivityProvider.canQuickReply(title: title, message: message) && enableQuickReply
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                compactNotificationView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                expandedQuickReplyView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(width: isExpanded ? expandedWidth : compactWidth)
        .offset(y: (dragOffsetY + provider.dragPullOffset) * 0.40)
        .onAppear {
            // NO sobrescribir isQuickReplyExpanded en onAppear (evita revertir la expansión si SwiftUI reconstruye la vista)
            if provider.currentNotificationId == nil {
                NotificationActivityProvider.shared.setNotificationState(active: true, expanded: provider.isQuickReplyExpanded, id: id)
            }
            NotificationActivityProvider.shared.onDismissRequested = {
                NotchWindowManager.shared.setAllowsKeyInput(false)
                ActivityCenter.shared.dismissWithAnimation(id: id)
            }
            syncContainerDimensions(expanded: isExpanded)
            if isExpanded {
                focusReplyField()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            applyExpansion(expanded)
        }
        .onDisappear {
            // Solo limpiar si esta notificación ya no es la actividad actual en ActivityCenter
            if ActivityCenter.shared.currentActivity?.id != id {
                NotificationActivityProvider.shared.handleActivityRemoved(id: id)
            }
        }
    }
    
    // MARK: - Estado Compacto (aviso de mensaje como el del iPhone)
    /// Como la notificación de un mensaje en el iPhone: foto del contacto con el icono de la app en la esquina,
    /// el nombre en negritas con "ahora" a la derecha y el mensaje en hasta dos líneas. Sin botones ni textos de
    /// ayuda: tocar o deslizar hacia abajo responde, deslizar hacia arriba lo descarta (la X sólo al pasar el puntero).
    private var compactNotificationView: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatar = avatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if senderIsTheApp {
                        // Sin remitente: el ícono de la app, como el iPhone
                        ZStack {
                            Circle().fill(tintColor)
                            Image(systemName: appIcon)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else {
                        ZStack {
                            Circle().fill(LinearGradient(
                                colors: [Color(white: 0.62), Color(white: 0.42)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            Image(systemName: "person.fill")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                if !senderIsTheApp {
                    // Icono de la app, como en las notificaciones de comunicación del iPhone
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(tintColor)
                        .frame(width: 17, height: 17)
                        .overlay(
                            Image(systemName: appIcon)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .stroke(Color.black, lineWidth: 1.5)
                        )
                        .offset(x: 4, y: 3)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isHoveringCard {
                        Button(action: { dismissActivity() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.7))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Descartar aviso")
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    } else {
                        Text("ahora")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.45))
                            .transition(.opacity)
                    }
                }
                .frame(height: 18)

                Text(displayedMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.88))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHoveringCard = hovering }
        }
        .padding(.horizontal, 18)
        .padding(.top, NotificationActivityProvider.cardTopInset) // Libra la cámara del notch (en la isla flotante no hay)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        // Gesto unificado omnidireccional:
        // - Deslizar hacia abajo (dy >= 8 o inercia >= 14) -> Expandir respuesta rápida o abrir app si es genérico
        // - Deslizar hacia arriba (dy <= -8 o inercia <= -14) -> Descartar notificación al notch
        // - Tap directo (dy y dx < 6) -> Expandir respuesta rápida o abrir app si es genérico
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !self.isExpanded else { return }
                    let dy = value.translation.height
                    if dy > 0 {
                        self.dragOffsetY = min(dy, 45)
                    } else {
                        self.dragOffsetY = max(dy, -35)
                    }
                }
                .onEnded { value in
                    guard !self.isExpanded else { return }
                    let dy = value.translation.height
                    let dx = value.translation.width
                    let pdy = value.predictedEndTranslation.height
                    
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        self.dragOffsetY = 0
                    }
                    
                    // 1. Swipe hacia arriba -> Descartar notificación
                    if dy <= -6 || pdy <= -10 {
                        AppState.shared.hapticService.triggerSnap()
                        dismissActivity()
                    }
                    // 2. Swipe hacia abajo -> Expandir respuesta rápida (o abrir app si no hay remitente)
                    else if dy >= 6 || pdy >= 10 {
                        if enableQuickReply {
                            AppState.shared.hapticService.triggerExpand()
                            expandToQuickReply()
                        } else {
                            openAssociatedApp()
                        }
                    }
                    // 3. Tap directo
                    else if abs(dy) < 6 && abs(dx) < 6 {
                        if enableQuickReply {
                            AppState.shared.hapticService.triggerExpand()
                            expandToQuickReply()
                        } else {
                            openAssociatedApp()
                        }
                    }
                }
        )
    }
    
    // MARK: - Estado Expandido (Quick Reply con Espacio Amplio y Diseño Apple)
    private var expandedQuickReplyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fila 1: Cabecera con avatar pequeño, nombre y botón de colapsar
            HStack(spacing: 9) {
                if let avatar = avatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                } else {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: appIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                Text("Respondiendo a \(title)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("• \(appName)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(tintColor)
                
                Spacer()
                
                // Botón abrir app / pestaña en navegador
                Button(action: {
                    if appName.lowercased().contains("whatsapp") {
                        WhatsAppWebObserverService.shared.activateWhatsAppWeb()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .bold))
                        Text("Abrir chat")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(tintColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tintColor.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Ir a la conversación")
                
                // Botón retraer
                Button(action: {
                    collapseBack()
                }) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.50))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            
            // Fila 2: Cita clara del mensaje recibido con píldora verde y soporte multilínea
            let isMedia = message.lowercased().contains("foto") || message.lowercased().contains("video") || message.lowercased().contains("audio") || message.lowercased().contains("imagen")
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tintColor)
                    .frame(width: 3)
                
                VStack(alignment: .leading, spacing: 3) {
                    if isMedia {
                        HStack(spacing: 4) {
                            Image(systemName: message.lowercased().contains("video") ? "video.fill" : (message.lowercased().contains("audio") ? "waveform" : "photo.fill"))
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(message.lowercased().contains("video") ? "Video" : (message.lowercased().contains("audio") ? "Mensaje de voz" : "Foto"))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(tintColor)
                    }
                    
                    Text(displayedMessage)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            
            // Fila 3: Campo de texto con botón de enviar estilizado y expansión vertical animada
            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    TextField("Escribe una respuesta a \(title)...", text: $replyText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendReply()
                        }
                    
                    if !replyText.isEmpty {
                        Button(action: {
                            replyText = ""
                            updateHeightForText("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusReplyField()
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isInputFocused ? tintColor.opacity(0.80) : Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                
                // Botón Enviar con animación de confirmación
                let canSend = !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: {
                    sendReply()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                            canSend
                                ? LinearGradient(colors: [tintColor, tintColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: canSend ? tintColor.opacity(0.45) : .clear, radius: 6, x: 0, y: 2)
                        
                        if isSentSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(canSend ? .white : Color.white.opacity(0.28))
                        }
                    }
                    .scaleEffect(canSend ? 1.04 : 0.96)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, NotificationActivityProvider.expandedTopInset) // Despeje para la cámara del notch
        .padding(.bottom, 16)
        .onChange(of: replyText) { _, newText in
            updateHeightForText(newText)
        }
        .onChange(of: provider.dynamicReplyHeight) { _, _ in
            syncContainerDimensions(expanded: isExpanded)
        }
        .onAppear {
            focusReplyField()
            updateHeightForText(replyText)
        }
    }
    
    // MARK: - Control de Animaciones y Dimensiones
    
    private func updateHeightForText(_ text: String) {
        guard isExpanded else { return }
        let newlines = text.components(separatedBy: "\n").count
        let approxWrap = max(1, (text.count + 28) / 30)
        let estimatedLines = min(max(newlines, approxWrap), 4)
        let extraHeight = CGFloat((estimatedLines - 1) * 20)
        let targetHeight = NotificationActivityProvider.expandedHeight + extraHeight
        NotificationActivityProvider.shared.updateReplyHeight(targetHeight)
    }
    
    private func focusReplyField() {
        NotchWindowManager.shared.setAllowsKeyInput(true)
        isInputFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard self.isExpanded else { return }
            NotchWindowManager.shared.setAllowsKeyInput(true)
            self.isInputFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard self.isExpanded else { return }
            self.isInputFocused = true
        }
    }
    
    private func syncContainerDimensions(expanded: Bool) {
        if expanded {
            ActivityCenter.shared.customCardWidth = expandedWidth
            ActivityCenter.shared.customCardHeight = provider.dynamicReplyHeight
            ActivityCenter.shared.customTopRadius = NotificationActivityProvider.topRadius
            ActivityCenter.shared.customBottomRadius = NotificationActivityProvider.expandedBottomRadius
        } else {
            ActivityCenter.shared.customCardWidth = compactWidth
            ActivityCenter.shared.customCardHeight = compactHeight
            ActivityCenter.shared.customTopRadius = NotificationActivityProvider.topRadius
            ActivityCenter.shared.customBottomRadius = NotificationActivityProvider.compactBottomRadius
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    // Tap, drag y swipe del trackpad pasan TODOS por el proveedor; la vista reacciona en applyExpansion.
    private func expandToQuickReply() {
        guard enableQuickReply else {
            openAssociatedApp()
            return
        }
        NotificationActivityProvider.shared.expandQuickReply()
    }
    
    private func openAssociatedApp() {
        AppState.shared.hapticService.triggerSnap()
        if appName.lowercased().contains("whatsapp") {
            WhatsAppWebObserverService.shared.activateWhatsAppWeb()
        } else if appName.lowercased().contains("mensaje") || appName.lowercased().contains("messages") || appName.lowercased().contains("imessage") {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
        dismissActivity()
    }
    
    private func collapseBack() {
        NotificationActivityProvider.shared.collapseQuickReply()
    }
    
    /// Efectos secundarios del cambio de estado (tamaño del contenedor, foco, teclado, timer)
    private func applyExpansion(_ expanded: Bool) {
        if expanded {
            ActivityCenter.shared.pauseDismissTimer(for: id)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                self.dragOffsetY = 0
                syncContainerDimensions(expanded: true)
            }
            focusReplyField()
        } else {
            isInputFocused = false
            NotchWindowManager.shared.setAllowsKeyInput(false)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                self.dragOffsetY = 0
                syncContainerDimensions(expanded: false)
            }
        }
    }
    
    private func sendReply() {
        let textToSend = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty, !isSending else { return }
        
        isSending = true
        isSentSuccess = true
        AppState.shared.hapticService.triggerSnap()
        
        let isDemo = DemoMessages.isDemo(handle) || DemoMessages.isDemo(title)
        
        if isDemo {
            DNDLogger.log("QuickReplyNotificationView: 🧪 Demo detectada ('\(handle)'). Respuesta simulada: '\(textToSend)'. Envío omitido.")
        } else {
            // Despachar respuesta hacia WhatsApp Web / Desktop (inyectando en DOM o pegando en el chat activo)
            MessageReplyService.shared.sendReply(to: handle, message: textToSend, app: appName, openBrowser: false)
        }
        
        // Micro-animación de éxito antes de desvanecer hacia el notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            NotificationActivityProvider.shared.dismissNotification()
        }
    }
    
    private func dismissActivity() {
        NotificationActivityProvider.shared.dismissNotification()
    }
}
