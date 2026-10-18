import SwiftUI
import AppKit

/// Vista interactiva para solicitudes de permisos, notificaciones y preguntas del Agente de IA (Antigravity).
/// Diseñada con estética Liquid Glass, gradientes Violet/Cyan, tipografía SF Pro & SF Mono,
/// y soporte completo para respuesta rápida por texto y botones de acción directa.
public struct AgentInteractionView: View {
    public let payload: AgentInteractionPayload
    
    @ObservedObject private var provider = AgentActivityProvider.shared
    private var isExpanded: Bool {
        provider.isExpanded && (provider.currentId == payload.id || provider.currentId == nil)
    }
    
    @State private var replyText: String = ""
    @State private var isCopiedCommand: Bool = false
    @State private var isActionSubmitted: Bool = false
    @State private var dragOffsetY: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    
    // Dimensiones calibradas
    private let compactWidth: CGFloat = AgentActivityProvider.compactWidth
    private let compactHeight: CGFloat = AgentActivityProvider.compactHeight
    private let expandedWidth: CGFloat = AgentActivityProvider.expandedWidth
    private let expandedHeight: CGFloat = AgentActivityProvider.expandedHeight
    
    /// Solicitudes de Claude Code (scripts/claude_permission_hook.py) usan la marca de Claude
    private var isClaude: Bool { payload.title == "Claude" }
    
    // Paleta: Antigravity (violeta/celeste) o Claude (naranja)
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: isClaude
                ? [ClaudeMarkView.orange, Color(red: 0.93, green: 0.58, blue: 0.40)]
                : [Color(red: 0.60, green: 0.35, blue: 1.00), Color(red: 0.18, green: 0.72, blue: 1.00)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private var accentColor: Color { isClaude ? ClaudeMarkView.orange : Color(red: 0.60, green: 0.35, blue: 1.00) }
    private var cyanColor: Color { isClaude ? Color(red: 0.96, green: 0.72, blue: 0.58) : Color(red: 0.18, green: 0.72, blue: 1.00) }
    
    /// Icono del orbe: la marca de Claude o el símbolo según el tipo de solicitud
    @ViewBuilder
    private func orbIcon(size: CGFloat) -> some View {
        if isClaude {
            ClaudeSparkShape().fill(Color.white).frame(width: size * 1.15, height: size * 1.15)
        } else {
            Image(systemName: iconForType(payload.type))
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    public init(payload: AgentInteractionPayload) {
        self.payload = payload
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                compactAgentView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                expandedAgentView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(width: isExpanded ? expandedWidth : compactWidth)
        .offset(y: (dragOffsetY + provider.dragPullOffset) * 0.40)
        .onAppear {
            syncContainerDimensions(expanded: isExpanded)
            if isExpanded {
                focusReplyField()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            applyExpansion(expanded)
        }
    }
    
    // MARK: - Vista Compacta (Píldora Flotante con Despeje del Notch Físico)
    private var compactAgentView: some View {
        HStack(alignment: .center, spacing: 12) {
            // Orbe de IA con gradiente violeta/celeste y halo radiante
            ZStack {
                Circle()
                    .fill(accentGradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: accentColor.opacity(0.50), radius: 8, x: 0, y: 2)
                
                orbIcon(size: 19)
            }
            .frame(width: 44, height: 44)
            
            // Textos de título, subtítulo e indicación
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(payload.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Badge del tipo de interacción
                    Text(badgeLabel(for: payload.type))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(badgeBackground(for: payload.type))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    Text("ahora")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.40))
                }
                
                if let cmd = payload.command, !cmd.isEmpty {
                    // Previsualización monospace del comando
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanColor)
                        Text(cmd)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text(payload.message.isEmpty ? payload.subtitle : payload.message)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.90))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                // Micro-hint interactivo
                HStack(spacing: 4) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(payload.enableTextReply ? "Desliza para responder o autorizar" : "Desliza para ver detalles")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(cyanColor.opacity(0.95))
                .padding(.top, 1)
            }
            
            // Botones de acción directa compacta
            HStack(spacing: 6) {
                if payload.type == .permission {
                    // Botón Rechazar rápido
                    Button(action: {
                        provider.submitDecision(actionId: "deny")
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.70))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Rechazar")
                    
                    // Botón Permitir rápido
                    Button(action: {
                        provider.submitDecision(actionId: "allow")
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                            Text("OK")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accentGradient))
                        .shadow(color: accentColor.opacity(0.40), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Permitir")
                } else {
                    // Botón descartar genérico
                    Button(action: {
                        provider.dismissActivity()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.45))
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 32) // Despeja el notch físico
        .padding(.bottom, 12)
        .contentShape(Rectangle())
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
                    
                    // Swipe hacia arriba -> descartar
                    if dy <= -6 || pdy <= -10 {
                        AppState.shared.hapticService.triggerSnap()
                        provider.dismissActivity()
                    }
                    // Swipe hacia abajo -> expandir
                    else if dy >= 6 || pdy >= 10 {
                        AppState.shared.hapticService.triggerExpand()
                        provider.expandInteraction()
                    }
                    // Tap directo
                    else if abs(dy) < 6 && abs(dx) < 6 {
                        AppState.shared.hapticService.triggerExpand()
                        provider.expandInteraction()
                    }
                }
        )
    }
    
    // MARK: - Vista Expandida (Diálogo Completo con Terminal Monospace y Entrada de Texto)
    private var expandedAgentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cabecera: Orbe pequeño, título, badge y botón de contraer
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 22, height: 22)
                    
                    orbIcon(size: 11)
                }
                
                Text(payload.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("• \(payload.subtitle)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cyanColor)
                
                Spacer()
                
                // Botón copiar comando (si existe)
                if let cmd = payload.command, !cmd.isEmpty {
                    Button(action: {
                        copyToClipboard(cmd)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isCopiedCommand ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(isCopiedCommand ? "Copiado" : "Copiar")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                
                // Botón colapsar
                Button(action: {
                    provider.collapseInteraction()
                }) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.50))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            
            // Tarjeta de comando monospace o mensaje explicativo
            if let cmd = payload.command, !cmd.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if !payload.message.isEmpty {
                        Text(payload.message)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanColor)
                        
                        Text(cmd)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.95))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.40))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(cyanColor.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
            } else if !payload.message.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accentGradient)
                        .frame(width: 3, height: 26)
                    
                    Text(payload.message)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
            }
            
            // Entrada de texto (si está habilitada)
            if payload.enableTextReply {
                HStack(spacing: 8) {
                    HStack {
                        TextField("Escribe una instrucción o motivo...", text: $replyText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white)
                            .focused($isInputFocused)
                            .onSubmit {
                                submitPrimaryAction()
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
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isInputFocused ? cyanColor.opacity(0.80) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }
            
            // Fila de botones de acción
            HStack(spacing: 10) {
                ForEach(payload.options) { option in
                    Button(action: {
                        provider.submitDecision(
                            actionId: option.id,
                            textReply: replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : replyText
                        )
                    }) {
                        HStack(spacing: 5) {
                            if option.isDestructive {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else if option.isPrimary {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            Text(option.label)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(buttonTextColor(for: option))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(buttonBackground(for: option))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(buttonBorderColor(for: option), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 34) // Despeje para la cámara del notch físico
        .padding(.bottom, 14)
        .onAppear {
            if payload.enableTextReply {
                focusReplyField()
            }
        }
    }
    
    // MARK: - Helpers Visuales y de Interacción
    
    private func iconForType(_ type: AgentInteractionType) -> String {
        switch type {
        case .permission:
            return "lock.shield.fill"
        case .notification:
            return "sparkles"
        case .question:
            return "brain.head.profile"
        }
    }
    
    private func badgeLabel(for type: AgentInteractionType) -> String {
        switch type {
        case .permission:
            return "PERMISO"
        case .notification:
            return "COMPLETADO"
        case .question:
            return "PREGUNTA"
        }
    }
    
    private func badgeBackground(for type: AgentInteractionType) -> some View {
        switch type {
        case .permission:
            return Color.orange.opacity(0.25)
        case .notification:
            return Color.green.opacity(0.25)
        case .question:
            return cyanColor.opacity(0.25)
        }
    }
    
    private func buttonBackground(for option: AgentActionOption) -> some View {
        Group {
            if option.isPrimary {
                accentGradient
            } else if option.isDestructive {
                Color.red.opacity(0.18)
            } else {
                Color.white.opacity(0.08)
            }
        }
    }
    
    private func buttonBorderColor(for option: AgentActionOption) -> Color {
        if option.isPrimary {
            return accentColor.opacity(0.60)
        } else if option.isDestructive {
            return Color.red.opacity(0.35)
        } else {
            return Color.white.opacity(0.12)
        }
    }
    
    private func buttonTextColor(for option: AgentActionOption) -> Color {
        if option.isPrimary {
            return .white
        } else if option.isDestructive {
            return Color(red: 1.0, green: 0.45, blue: 0.45)
        } else {
            return Color.white.opacity(0.85)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopiedCommand = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopiedCommand = false
            }
        }
    }
    
    private func submitPrimaryAction() {
        if let primaryOption = payload.options.first(where: { $0.isPrimary }) ?? payload.options.first {
            provider.submitDecision(
                actionId: primaryOption.id,
                textReply: replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : replyText
            )
        }
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
    
    private func applyExpansion(_ expanded: Bool) {
        syncContainerDimensions(expanded: expanded)
        if expanded {
            focusReplyField()
        } else {
            isInputFocused = false
            NotchWindowManager.shared.setAllowsKeyInput(false)
        }
    }
    
    private func syncContainerDimensions(expanded: Bool) {
        if expanded {
            ActivityCenter.shared.customCardWidth = expandedWidth
            ActivityCenter.shared.customCardHeight = expandedHeight
            ActivityCenter.shared.customTopRadius = AgentActivityProvider.topRadius
            ActivityCenter.shared.customBottomRadius = AgentActivityProvider.expandedBottomRadius
        } else {
            ActivityCenter.shared.customCardWidth = compactWidth
            ActivityCenter.shared.customCardHeight = compactHeight
            ActivityCenter.shared.customTopRadius = AgentActivityProvider.topRadius
            ActivityCenter.shared.customBottomRadius = AgentActivityProvider.compactBottomRadius
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
}
