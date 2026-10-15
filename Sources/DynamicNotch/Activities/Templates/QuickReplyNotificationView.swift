import SwiftUI
import AppKit

/// Vista interactiva para notificaciones con soporte de Swipe Down y Respuesta Rápida (Quick Reply)
/// Diseñada con estética Liquid Glass, esquinas amplias y despeje total del notch físico.
public struct QuickReplyNotificationView: View {
    public let id: String
    public let title: String
    public let message: String
    public let handle: String
    public let avatar: NSImage?
    public let appName: String
    public let appIcon: String
    public let tintColor: Color
    
    @State private var isExpanded: Bool = false
    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var isSentSuccess: Bool = false
    @State private var dragOffsetY: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    
    // Geometría calibrada para que NADA quede recortado ni aplastado:
    // Altura compacta aumentada a 96pt para alojar holgadamente el despeje de 32pt de la cámara,
    // el avatar, el texto de 2 líneas y el hint inferior sin tocar las esquinas redondeadas.
    private let compactWidth: CGFloat = 396
    private let compactHeight: CGFloat = 96
    private let expandedWidth: CGFloat = 424
    private let expandedHeight: CGFloat = 180
    
    public init(
        id: String,
        title: String,
        message: String,
        handle: String = "",
        avatar: NSImage? = nil,
        appName: String = "WhatsApp",
        appIcon: String = "message.fill",
        tintColor: Color = Color(red: 0.15, green: 0.78, blue: 0.45)
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.handle = handle.isEmpty ? title : handle
        self.avatar = avatar
        self.appName = appName
        self.appIcon = appIcon
        self.tintColor = tintColor
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                compactNotificationView
            } else {
                expandedQuickReplyView
            }
        }
        .frame(width: isExpanded ? expandedWidth : compactWidth)
        .offset(y: dragOffsetY * 0.40)
        .onAppear {
            NotificationActivityProvider.shared.setNotificationState(active: true, expanded: false, id: id)
            NotificationActivityProvider.shared.onExpandRequested = {
                expandToQuickReply()
            }
            NotificationActivityProvider.shared.onCollapseRequested = {
                collapseBack()
            }
            NotificationActivityProvider.shared.onDismissRequested = {
                dismissActivity()
            }
            syncContainerDimensions(expanded: false)
        }
        .onDisappear {
            NotificationActivityProvider.shared.setNotificationState(active: false, expanded: false, id: nil)
            NotificationActivityProvider.shared.onExpandRequested = nil
            NotificationActivityProvider.shared.onCollapseRequested = nil
            NotificationActivityProvider.shared.onDismissRequested = nil
            NotchWindowManager.shared.setAllowsKeyInput(false)
            ActivityCenter.shared.customCardWidth = nil
            ActivityCenter.shared.customCardHeight = nil
        }
    }
    
    // MARK: - Estado Compacto (Tarjeta de Notificación con Despeje de Notch)
    private var compactNotificationView: some View {
        HStack(alignment: .center, spacing: 14) {
            // Avatar circular con halo y micro-insignia
            ZStack(alignment: .bottomTrailing) {
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
                            colors: [tintColor, tintColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: appIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Insignia verde de la app
                Circle()
                    .fill(tintColor)
                    .frame(width: 15, height: 15)
                    .overlay(
                        Image(systemName: appIcon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 2, y: 2)
            }
            .frame(width: 46, height: 46)
            
            // Textos del mensaje con formato claro y sin cortes
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("• \(appName)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(tintColor)
                    
                    Spacer()
                    
                    Text("ahora")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.40))
                }
                
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Micro-hint animado con holgura vertical
                HStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("Desliza hacia abajo o toca para responder")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(tintColor.opacity(0.95))
                .padding(.top, 1)
            }
            
            // Botón descartar
            Button(action: {
                dismissActivity()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 32) // Despeja perfectamente el notch físico sin desperdiciar espacio
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            expandToQuickReply()
        }
        // Gesto unificado bidireccional:
        // Arrastre hacia abajo o tap -> expandir respuesta rápida
        // Arrastre hacia arriba -> guardar/descartar la notificación hacia el notch
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if value.translation.height > 0 {
                        self.dragOffsetY = min(value.translation.height, 35)
                    } else {
                        self.dragOffsetY = max(value.translation.height, -25)
                    }
                }
                .onEnded { value in
                    let isSwipeUp = value.translation.height <= -10 || value.predictedEndTranslation.height <= -18
                    let isDragDown = value.translation.height >= 12 || value.predictedEndTranslation.height >= 22
                    let isTap = abs(value.translation.width) < 10 && abs(value.translation.height) < 10
                    
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        self.dragOffsetY = 0
                    }
                    
                    if isSwipeUp {
                        AppState.shared.hapticService.triggerSnap()
                        dismissActivity()
                    } else if isDragDown || isTap {
                        expandToQuickReply()
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
            
            // Fila 2: Cita sutil del mensaje recibido con píldora verde
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tintColor)
                    .frame(width: 3, height: 28)
                
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.70))
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            
            // Fila 3: Campo de texto con botón de enviar estilizado
            HStack(spacing: 8) {
                HStack {
                    TextField("Escribe una respuesta a \(title)...", text: $replyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendReply()
                        }
                    
                    if !replyText.isEmpty {
                        Button(action: {
                            replyText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
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
        .padding(.top, 34) // Despeje para la cámara del notch
        .padding(.bottom, 16)
        .onAppear {
            isInputFocused = true
        }
        // Gesto de swipe hacia arriba en la tarjeta expandida para retraerla suavemente
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height <= -15 || value.predictedEndTranslation.height <= -25 {
                        collapseBack()
                    }
                }
        )
    }
    
    // MARK: - Control de Animaciones y Dimensiones
    
    private func syncContainerDimensions(expanded: Bool) {
        if expanded {
            ActivityCenter.shared.customCardWidth = expandedWidth
            ActivityCenter.shared.customCardHeight = expandedHeight
            ActivityCenter.shared.customTopRadius = 24
            ActivityCenter.shared.customBottomRadius = 34
        } else {
            ActivityCenter.shared.customCardWidth = compactWidth
            ActivityCenter.shared.customCardHeight = compactHeight
            ActivityCenter.shared.customTopRadius = 24
            ActivityCenter.shared.customBottomRadius = 28
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    private func expandToQuickReply() {
        AppState.shared.hapticService.triggerExpand()
        NotchWindowManager.shared.setAllowsKeyInput(true)
        ActivityCenter.shared.pauseDismissTimer(for: id)
        NotificationActivityProvider.shared.setNotificationState(active: true, expanded: true, id: id)
        
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            self.dragOffsetY = 0
            self.isExpanded = true
            syncContainerDimensions(expanded: true)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isInputFocused = true
        }
    }
    
    private func collapseBack() {
        isInputFocused = false
        NotchWindowManager.shared.setAllowsKeyInput(false)
        AppState.shared.hapticService.triggerSnap()
        NotificationActivityProvider.shared.setNotificationState(active: true, expanded: false, id: id)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            self.isExpanded = false
            self.dragOffsetY = 0
            syncContainerDimensions(expanded: false)
        }
    }
    
    private func sendReply() {
        let textToSend = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty else { return }
        
        isSending = true
        isSentSuccess = true
        AppState.shared.hapticService.triggerSnap()
        
        // Despachar respuesta sin abrir la app de escritorio desactualizada
        MessageReplyService.shared.sendReply(to: handle, message: textToSend, app: appName, openBrowser: false)
        
        // Micro-animación de éxito antes de desvanecer hacia el notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            NotchWindowManager.shared.setAllowsKeyInput(false)
            dismissActivity()
        }
    }
    
    private func dismissActivity() {
        NotchWindowManager.shared.setAllowsKeyInput(false)
        ActivityCenter.shared.dismissWithAnimation(id: id)
    }
}
