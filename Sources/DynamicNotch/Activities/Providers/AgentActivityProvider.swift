import SwiftUI
import AppKit
import Combine

public enum AgentInteractionType: String, Codable {
    case notification = "notification"        // Notificación pasiva (tarea terminada, build exitoso, etc.)
    case permission = "permission"            // Solicitud de permiso/autorización (comando, acceso)
    case question = "question"                // Pregunta con opciones múltiples o respuesta libre
}

public struct AgentActionOption: Identifiable, Equatable, Codable {
    public let id: String
    public let label: String
    public let isPrimary: Bool
    public let isDestructive: Bool
    
    public init(id: String, label: String, isPrimary: Bool = false, isDestructive: Bool = false) {
        self.id = id
        self.label = label
        self.isPrimary = isPrimary
        self.isDestructive = isDestructive
    }
}

public struct AgentInteractionPayload: Equatable {
    public let id: String
    public let type: AgentInteractionType
    public let title: String
    public let subtitle: String
    public let message: String
    public let command: String?
    public let options: [AgentActionOption]
    public let enableTextReply: Bool
    public let duration: TimeInterval?
    
    public init(
        id: String,
        type: AgentInteractionType,
        title: String,
        subtitle: String,
        message: String,
        command: String? = nil,
        options: [AgentActionOption] = [],
        enableTextReply: Bool = true,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.command = command
        self.options = options
        self.enableTextReply = enableTextReply
        self.duration = duration
    }
}

/// Proveedor de Live Activities para interacción en tiempo real con el Asistente de IA (Antigravity)
/// Soporta notificaciones de fin de tarea, aprobación de permisos de comandos y respuestas rápidas.
public final class AgentActivityProvider: ObservableObject {
    public static let shared = AgentActivityProvider()
    
    // Dimensiones canónicas de la tarjeta
    public static let compactWidth: CGFloat = 404
    public static let compactHeight: CGFloat = 98
    public static let expandedWidth: CGFloat = 432
    public static let expandedHeight: CGFloat = 210
    public static let topRadius: CGFloat = 24
    public static let compactBottomRadius: CGFloat = 28
    public static let expandedBottomRadius: CGFloat = 34
    
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var isExpanded: Bool = false
    @Published public private(set) var currentId: String? = nil
    @Published public private(set) var currentPayload: AgentInteractionPayload? = nil
    @Published public private(set) var currentProgressPayload: AgentLiveProgressPayload? = nil
    @Published public var dragPullOffset: CGFloat = 0
    
    // Estado de la Burbuja Satélite Dinámica (Estilo Dynamic Island Multi-Actividad)
    @Published public private(set) var isSatelliteActive: Bool = false
    @Published public var isProgressHUDExpanded: Bool = false
    
    /// Hay una tarjeta de pregunta/permiso del agente en pantalla.
    /// `isActive` también es true mientras sólo se muestra la bolita de progreso, que no debe capturar gestos.
    public var isInteractionActive: Bool { isActive && currentPayload != nil }
    @Published public private(set) var satelliteProgress: Double = 0.0
    @Published public private(set) var currentProgressStep: String = ""
    
    public let progressActivityId: String = "agent_live_progress"
    private var progressDismissTimer: Timer?
    
    public var onResponseSubmitted: ((String, String, String?) -> Void)?
    public var onActivityDismissed: ((String) -> Void)?
    
    private init() {}
    
    public func setActivityState(active: Bool, expanded: Bool, id: String?) {
        self.isActive = active
        self.isExpanded = expanded
        self.currentId = id
        if !active {
            self.dragPullOffset = 0
        }
    }
    
    public func handleActivityRemoved(id: String) {
        guard currentId == id else { return }
        DNDLogger.log("AgentActivityProvider.handleActivityRemoved: id=\(id)")
        NotchWindowManager.shared.setAllowsKeyInput(false)
        setActivityState(active: false, expanded: false, id: nil)
        currentPayload = nil
        currentProgressPayload = nil
        onActivityDismissed?(id)
    }
    
    /// Despliega o actualiza la burbuja satélite de la Dynamic Island con el progreso de IA
    @discardableResult
    public func showProgress(payload: AgentLiveProgressPayload) -> String {
        self.currentProgressPayload = payload
        let activityId = progressActivityId
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.progressDismissTimer?.invalidate()
            self.progressDismissTimer = nil
            
            let activeStep = payload.steps.first(where: { $0.isActive })?.title
                ?? payload.steps.last(where: { $0.isCompleted })?.title
                ?? payload.taskName
            let completedCount = payload.steps.filter { $0.isCompleted }.count
            let totalCount = payload.steps.count
            let progressValue: Double
            if let p = payload.progress {
                progressValue = max(0.04, min(1.0, p))
            } else if payload.isCompleted {
                progressValue = 1.0
            } else if let diffProg = payload.fileDiff?.progress, diffProg > 0 {
                progressValue = diffProg
            } else if totalCount > 0 {
                let base = Double(completedCount) / Double(totalCount)
                let activeBonus = payload.steps.contains(where: { $0.isActive }) ? (0.5 / Double(totalCount)) : 0.0
                progressValue = min(0.95, max(0.08, base + activeBonus))
            } else {
                progressValue = 0.12
            }
            
            self.isActive = !payload.isCompleted
            self.isSatelliteActive = true
            self.currentId = activityId
            self.currentProgressPayload = payload
            self.currentProgressStep = activeStep
            self.satelliteProgress = progressValue
            
            var liveActivity = LiveActivity(
                id: activityId,
                kind: .agentAI,
                priority: ActivityRelevance.backgroundTask,
                style: .pill,
                state: payload.isCompleted ? .finished : .active,
                title: "Antigravity AI",
                subtitle: activeStep,
                progress: progressValue,
                leading: AnyView(
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.72, green: 0.40, blue: 1.00))
                        Text("AI")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                ),
                trailing: AnyView(
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0.0, to: CGFloat(progressValue))
                            .stroke(Color(red: 0.72, green: 0.40, blue: 1.00), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 16, height: 16)
                    }
                ),
                bolitaVariant: .progressRing(
                    progress: progressValue,
                    strokeColor: Color(red: 0.72, green: 0.40, blue: 1.00),
                    iconName: "sparkle",
                    shortText: nil
                ),
                expandedView: AnyView(AgentLiveProgressView(payload: payload)),
                customExpandedWidth: AgentLiveProgressView.hudWidth,
                customExpandedHeight: AgentLiveProgressView.hudHeight,
                onTap: { [weak self] in
                    self?.toggleProgressHUD()
                }
            )
            // Sin pulso del agente en 30 s: el progreso ya no está al día (se atenúa; el watchdog la quita a los 45 s)
            if !payload.isCompleted {
                liveActivity.staleDate = Date().addingTimeInterval(30)
            }
            ActivityCenter.shared.publish(liveActivity)
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.isSatelliteActive = true
            }
            
            // Si el HUD de 2 columnas ya está expandido por el usuario, mantener sincronizado
            if self.isProgressHUDExpanded {
                self.syncExpandedHUDDimensions()
            }
            
            NotchWindowManager.shared.updateHitAreaForCurrentState()
            
            if payload.isCompleted {
                // Al terminar la tarea, el aro completo se queda como resumen (ajuste "Resumen al terminar") y se va
                self.isActive = false
                ActivityCenter.shared.end(id: activityId) { [weak self] in
                    self?.dismissProgress()
                }
            } else {
                // Watchdog de seguridad (45 s): si el agente no envía pulso en 45 s, retirar la bolita
                self.progressDismissTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    DNDLogger.log("AgentActivityProvider: Inactividad del agente. Ocultando bolita...")
                    self.dismissProgress()
                }
            }
        }
        return activityId
    }
    
    /// Expande la burbuja satélite hacia el centro del Notch mostrando el HUD de 2 columnas completo mediante morfeo líquido
    public func expandProgressHUD() {
        guard isSatelliteActive else { return }
        self.isProgressHUDExpanded = true
        if let act = ActivityCenter.shared.activeActivities.first(where: { $0.id == progressActivityId }) {
            ActivityCenter.shared.initiateFusion(for: act, fromSide: .right)
        } else {
            SoundFeedbackService.shared.playBubblePop()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                self.isProgressHUDExpanded = true
            }
            syncExpandedHUDDimensions()
        }
    }
    
    /// Colapsa el HUD de 2 columnas de vuelta a la burbuja satélite desprendida
    public func collapseProgressHUD() {
        self.isProgressHUDExpanded = false
        if ActivityCenter.shared.expandedActivity?.id == progressActivityId {
            ActivityCenter.shared.collapseExpandedActivity()
        } else {
            SoundFeedbackService.shared.playActionDismissed()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                self.isProgressHUDExpanded = false
            }
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    /// Alterna la expansión/colapso del HUD de progreso
    public func toggleProgressHUD() {
        if isProgressHUDExpanded {
            collapseProgressHUD()
        } else {
            expandProgressHUD()
        }
    }
    
    public func syncExpandedHUDDimensions() {
        ActivityCenter.shared.customCardWidth = AgentLiveProgressView.hudWidth
        ActivityCenter.shared.customCardHeight = AgentLiveProgressView.hudHeight
        ActivityCenter.shared.customTopRadius = Self.topRadius
        ActivityCenter.shared.customBottomRadius = 28
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    public func dismissProgress() {
        progressDismissTimer?.invalidate()
        progressDismissTimer = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                self.isActive = false
                self.isSatelliteActive = false
                self.isProgressHUDExpanded = false
                self.currentProgressPayload = nil
                self.satelliteProgress = 0.0
            }
            ActivityCenter.shared.remove(id: self.progressActivityId)
            ActivityCenter.shared.customCardWidth = nil
            ActivityCenter.shared.customCardHeight = nil
            ActivityCenter.shared.customTopRadius = nil
            ActivityCenter.shared.customBottomRadius = nil
            
            // Limpieza exhaustiva: asegurar que no quede ninguna actividad huérfana de IA
            let orphanAgentIds = ActivityCenter.shared.activeActivities
                .filter { $0.kind == .agentAI || $0.id.hasPrefix("agent_") }
                .map { $0.id }
            for orphanId in orphanAgentIds {
                ActivityCenter.shared.remove(id: orphanId)
            }
            self.currentId = nil
            self.currentPayload = nil
            
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    /// Despliega una interacción con el agente en el Notch
    @discardableResult
    public func showInteraction(
        type: AgentInteractionType = .permission,
        title: String = "Antigravity",
        subtitle: String = "Permiso requerido",
        message: String = "",
        command: String? = nil,
        options: [AgentActionOption]? = nil,
        enableTextReply: Bool = true,
        duration: TimeInterval? = nil
    ) -> String {
        let activityId = "agent_\(UUID().uuidString)"
        let resolvedOptions: [AgentActionOption]
        if let opts = options, !opts.isEmpty {
            resolvedOptions = opts
        } else {
            switch type {
            case .permission:
                resolvedOptions = [
                    AgentActionOption(id: "deny", label: "Rechazar", isDestructive: true),
                    AgentActionOption(id: "allow", label: "Permitir", isPrimary: true)
                ]
            case .notification:
                resolvedOptions = [
                    AgentActionOption(id: "ok", label: "Entendido", isPrimary: true)
                ]
            case .question:
                resolvedOptions = [
                    AgentActionOption(id: "submit", label: "Enviar", isPrimary: true)
                ]
            }
        }
        
        let payload = AgentInteractionPayload(
            id: activityId,
            type: type,
            title: title,
            subtitle: subtitle,
            message: message,
            command: command,
            options: resolvedOptions,
            enableTextReply: enableTextReply,
            duration: duration ?? (type == .notification ? 6.0 : nil)
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Cerrar menús de música o shelf si estuviesen abiertos
            if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
                AppState.shared.isPlayerDetailExpanded = false
                AppState.shared.mode = AppState.shared.shouldShowCompact ? .compact : .idle
            }
            AppState.shared.setHoverState(false)
            NotchWindowManager.shared.setAllowsKeyInput(false)
            
            if let prevId = self.currentId, prevId != activityId {
                ActivityCenter.shared.remove(id: prevId)
            }
            
            let startExpanded = (type == .permission)
            self.currentPayload = payload
            self.setActivityState(active: true, expanded: startExpanded, id: activityId)
            
            ActivityCenter.shared.customCardWidth = startExpanded ? Self.expandedWidth : Self.compactWidth
            ActivityCenter.shared.customCardHeight = startExpanded ? Self.expandedHeight : Self.compactHeight
            ActivityCenter.shared.customTopRadius = Self.topRadius
            ActivityCenter.shared.customBottomRadius = startExpanded ? Self.expandedBottomRadius : Self.compactBottomRadius
            
            if startExpanded {
                NotchWindowManager.shared.setAllowsKeyInput(true)
            }
            
            let view = AgentInteractionView(payload: payload)
            
            let activity = LiveActivity(
                id: activityId,
                priority: ActivityRelevance.agentInteraction,
                style: .card,
                customView: AnyView(view),
                tint: Color(red: 0.58, green: 0.35, blue: 0.98),
                duration: payload.duration,
                onTap: {
                    self.expandInteraction()
                }
            )
            
            DNDLogger.log("AgentActivityProvider: publicando actividad id=\(activityId), type=\(type.rawValue)")
            ActivityCenter.shared.publish(activity)
            NotchWindowManager.shared.updateHitAreaForCurrentState()
            AppState.shared.hapticService.triggerSnap()
        }
        
        return activityId
    }
    
    /// Expande la vista para mostrar detalles de comando y responder
    public func expandInteraction() {
        guard isActive, !isExpanded else { return }
        DNDLogger.log("AgentActivityProvider.expandInteraction")
        
        if let id = currentId {
            ActivityCenter.shared.pauseDismissTimer(for: id)
        }
        
        NotchWindowManager.shared.setAllowsKeyInput(true)
        AppState.shared.hapticService.triggerExpand()
        
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.dragPullOffset = 0
            self.isExpanded = true
            ActivityCenter.shared.customCardWidth = Self.expandedWidth
            ActivityCenter.shared.customCardHeight = Self.expandedHeight
            ActivityCenter.shared.customTopRadius = Self.topRadius
            ActivityCenter.shared.customBottomRadius = Self.expandedBottomRadius
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Colapsa de vuelta a píldora compacta
    public func collapseInteraction() {
        guard isExpanded else { return }
        DNDLogger.log("AgentActivityProvider.collapseInteraction")
        NotchWindowManager.shared.setAllowsKeyInput(false)
        AppState.shared.hapticService.triggerSnap()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            self.dragPullOffset = 0
            self.isExpanded = false
            ActivityCenter.shared.customCardWidth = nil
            ActivityCenter.shared.customCardHeight = nil
            ActivityCenter.shared.customTopRadius = nil
            ActivityCenter.shared.customBottomRadius = nil
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Despacha la decisión tomada por el usuario (botón u opción tecleada) y descarta la actividad
    public func submitDecision(actionId: String, textReply: String? = nil) {
        guard let id = currentId else { return }
        DNDLogger.log("AgentActivityProvider.submitDecision: id=\(id), action=\(actionId), text='\(textReply ?? "")'")
        onResponseSubmitted?(id, actionId, textReply)
        
        // Retroalimentación acústica y háptica minimalista tipo Apple
        if actionId == "allow" || actionId == "ok" {
            SoundFeedbackService.shared.playPermissionGranted()
        } else {
            SoundFeedbackService.shared.playActionDismissed()
        }
        
        dismissActivity()
    }
    
    public func dismissActivity() {
        guard let id = currentId else { return }
        DNDLogger.log("AgentActivityProvider.dismissActivity: id=\(id)")
        NotchWindowManager.shared.setAllowsKeyInput(false)
        ActivityCenter.shared.dismissWithAnimation(id: id)
    }
}

