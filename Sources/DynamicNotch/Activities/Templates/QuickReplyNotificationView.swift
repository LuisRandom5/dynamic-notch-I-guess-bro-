import SwiftUI
import AppKit

/// Vista interactiva para notificaciones con soporte de Swipe Down y Respuesta Rápida (Quick Reply)
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
    @State private var dragOffsetY: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    
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
        .frame(width: isExpanded ? 410 : 380)
        .offset(y: dragOffsetY * 0.35)
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isExpanded && value.translation.height > 0 {
                        self.dragOffsetY = value.translation.height
                    }
                }
                .onEnded { value in
                    if !isExpanded {
                        if value.translation.height > 18 || value.predictedEndTranslation.height > 40 {
                            expandToQuickReply()
                        } else {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                self.dragOffsetY = 0
                            }
                        }
                    }
                }
        )
        .onDisappear {
            NotchWindowManager.shared.setAllowsKeyInput(false)
        }
    }
    
    // MARK: - Estado Compacto (Tarjeta de Notificación con Micro-Hint)
    private var compactNotificationView: some View {
        HStack(spacing: 12) {
            // Avatar con insignia de WhatsApp
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
                            colors: [tintColor, tintColor.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: appIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Insignia de app pequeña
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
            
            // Texto principal
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    .lineLimit(2)
                
                // Micro-hint para invitar al swipe down
                HStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("Desliza hacia abajo para responder")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundColor(tintColor.opacity(0.90))
                .padding(.top, 1)
            }
            
            // Botón descartar
            Button(action: {
                dismissActivity()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.40))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            expandToQuickReply()
        }
    }
    
    // MARK: - Estado Expandido (Cuadro de Texto Interactivo)
    private var expandedQuickReplyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Cabecera de respuesta
            HStack(spacing: 8) {
                if let avatar = avatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: appIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                
                Text("Respondiendo a \(title)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    collapseBack()
                }) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.50))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            
            // Cita del mensaje previo
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tintColor)
                    .frame(width: 2.5, height: 26)
                
                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
            )
            
            // Campo de texto y botón Enviar
            HStack(spacing: 8) {
                HStack {
                    TextField("Escribe una respuesta...", text: $replyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
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
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isInputFocused ? tintColor.opacity(0.70) : Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                
                // Botón enviar
                let canSend = !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: {
                    sendReply()
                }) {
                    ZStack {
                        Circle()
                            .fill(canSend ? tintColor : Color.white.opacity(0.10))
                            .frame(width: 32, height: 32)
                            .shadow(color: canSend ? tintColor.opacity(0.40) : .clear, radius: 4, x: 0, y: 2)
                        
                        Image(systemName: isSending ? "checkmark" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(canSend ? .white : Color.white.opacity(0.30))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear {
            isInputFocused = true
        }
    }
    
    // MARK: - Lógica de Animaciones y Transición
    
    private func expandToQuickReply() {
        AppState.shared.hapticService.triggerExpand()
        NotchWindowManager.shared.setAllowsKeyInput(true)
        
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            self.dragOffsetY = 0
            self.isExpanded = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isInputFocused = true
        }
    }
    
    private func collapseBack() {
        isInputFocused = false
        NotchWindowManager.shared.setAllowsKeyInput(false)
        AppState.shared.hapticService.triggerSnap()
        
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            self.isExpanded = false
            self.dragOffsetY = 0
        }
    }
    
    private func sendReply() {
        let textToSend = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty else { return }
        
        isSending = true
        AppState.shared.hapticService.triggerSnap()
        
        // Enviar vía MessageReplyService
        MessageReplyService.shared.sendReply(to: handle, message: textToSend, app: appName)
        
        // Micro-animación de éxito antes de desvanecer hacia el notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotchWindowManager.shared.setAllowsKeyInput(false)
            dismissActivity()
        }
    }
    
    private func dismissActivity() {
        NotchWindowManager.shared.setAllowsKeyInput(false)
        ActivityCenter.shared.dismissWithAnimation(id: id)
    }
}
