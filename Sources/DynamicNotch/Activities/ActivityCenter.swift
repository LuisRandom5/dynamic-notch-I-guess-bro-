import SwiftUI
import Combine
import AppKit

public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()
    
    // MARK: - Estado de Actividades
    @Published public private(set) var currentActivity: LiveActivity?
    @Published public private(set) var activeActivities: [LiveActivity] = []
    @Published public private(set) var dismissingActivityId: String? = nil
    @Published public private(set) var lastDismissedActivity: LiveActivity? = nil
    
    // MARK: - Roles Multi-Actividad (Modo A y Modo B)
    @Published public private(set) var secondaryActivities: [LiveActivity] = []
    @Published public private(set) var overflowActivities: [LiveActivity] = []
    @Published public private(set) var overflowCount: Int = 0
    
    // MARK: - Coordinador de Morfeo Líquido y Fusión (Bolita <-> Notch)
    @Published public var fusingActivityId: String? = nil
    @Published public var fusionProgress: CGFloat = 0.0 // 0.0 (satélite) -> 1.0 (en contacto con el notch)
    @Published public var fusionSide: SatelliteSide = .right
    @Published public var expandedActivity: LiveActivity? = nil
    @Published public var isFusing: Bool = false
    
    // Dimensiones y curvatura de tarjeta personalizada
    @Published public var customCardWidth: CGFloat? = nil
    @Published public var customCardHeight: CGFloat? = nil
    @Published public var customTopRadius: CGFloat? = nil
    @Published public var customBottomRadius: CGFloat? = nil
    
    private var dismissTimers: [String: Timer] = [:]
    private var fusionExpansionTimer: Timer?
    private var lastRoleChangeTime: Date = Date.distantPast
    private let hysteresisDuration: TimeInterval = 3.0 // 3s de estabilidad de rol
    
    private init() {}
    
    // MARK: - Publicación y Actualización
    
    /// Publica o actualiza una actividad según las reglas de prioridad y actualización en sitio
    public func publish(_ activity: LiveActivity) {
        AppState.shared.isHoldingBareNotch = false
        
        if dismissingActivityId == activity.id {
            dismissingActivityId = nil
        }
        
        // Actualización en sitio si ya existe
        if let index = activeActivities.firstIndex(where: { $0.id == activity.id }) {
            activeActivities[index] = activity
            if currentActivity?.id == activity.id {
                currentActivity = activity
            }
            if expandedActivity?.id == activity.id {
                expandedActivity = activity
            }
            rescheduleTimer(for: activity)
            recalculateRoles()
            return
        }
        
        // Nueva actividad
        activeActivities.append(activity)
        rescheduleTimer(for: activity)
        recalculateRoles()
    }
    
    /// Alias para compatibilidad
    public func show(_ activity: LiveActivity) {
        publish(activity)
    }
    
    /// Quita una actividad por su ID de forma inmediata
    public func remove(id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        if dismissingActivityId == id {
            dismissingActivityId = nil
        }
        
        if expandedActivity?.id == id {
            expandedActivity = nil
            fusingActivityId = nil
            isFusing = false
            fusionProgress = 0.0
        }
        
        NotificationActivityProvider.shared.handleActivityRemoved(id: id)
        AgentActivityProvider.shared.handleActivityRemoved(id: id)
        
        let wasCurrent = currentActivity?.id == id
        activeActivities.removeAll(where: { $0.id == id })
        if wasCurrent || activeActivities.isEmpty {
            customCardWidth = nil
            customCardHeight = nil
            customTopRadius = nil
            customBottomRadius = nil
        }
        recalculateRoles()
        if currentActivity == nil {
            AppState.shared.isHoldingBareNotch = false
            AppState.shared.reconcileCompactMode()
        }
    }
    
    public func pauseDismissTimer(for id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
    }
    
    /// Cierre animado coordinado hacia el notch
    public func dismissWithAnimation(id: String) {
        guard let current = currentActivity, current.id == id else {
            remove(id: id)
            return
        }
        
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        dismissingActivityId = id
        lastDismissedActivity = current
        
        NotificationActivityProvider.shared.handleActivityRemoved(id: id)
        AgentActivityProvider.shared.handleActivityRemoved(id: id)
        
        let isCard = current.style == .card
        let duration = isCard ? ExitAnimationMetrics.cardDismissDuration : ExitAnimationMetrics.sliderDismissDuration
        
        if isCard && AppState.shared.mode == .compact && MusicService.shared.hasActiveMusic {
            AppState.shared.isHoldingBareNotch = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.activeActivities.removeAll(where: { $0.id == id })
            self.customCardWidth = nil
            self.customCardHeight = nil
            self.customTopRadius = nil
            self.customBottomRadius = nil
            self.recalculateRoles()
            self.dismissingActivityId = nil
            
            if isCard && (AppState.shared.mode == .compact || AppState.shared.shouldShowCompact) && MusicService.shared.hasActiveMusic {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard self.currentActivity == nil else {
                        AppState.shared.isHoldingBareNotch = false
                        return
                    }
                    withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                        AppState.shared.isHoldingBareNotch = false
                        AppState.shared.reconcileCompactMode()
                    }
                }
            } else {
                AppState.shared.isHoldingBareNotch = false
                if self.currentActivity == nil {
                    AppState.shared.reconcileCompactMode()
                }
            }
        }
    }
    
    // MARK: - Motor de Prioridad y Selección con Histéresis
    
    public func recalculateRoles() {
        guard !activeActivities.isEmpty else {
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.35, dampingFraction: 0.82)) {
                self.currentActivity = nil
                self.secondaryActivities = []
                self.overflowActivities = []
                self.overflowCount = 0
            }
            if expandedActivity != nil {
                collapseExpandedActivity()
            }
            return
        }
        
        // Ordenamiento determinista:
        // 1. Urgencia (isUrgent)
        // 2. Prioridad numérica
        // 3. Momento de última actualización
        let sorted = activeActivities.sorted { (a, b) -> Bool in
            if a.isUrgent != b.isUrgent {
                return a.isUrgent && !b.isUrgent
            }
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            return a.lastUpdatedAt > b.lastUpdatedAt
        }
        
        let now = Date()
        let mode = AppState.shared.multiActivityMode
        let maxSatellites = max(1, AppState.shared.maxSatelliteBolitas)
        
        // Candidatos a actividad principal en el notch físico:
        // Las actividades de progreso de IA en segundo plano (agentAI no modal) NUNCA deben ocupar
        // el notch físico en reposo como píldora vacía; deben vivir exclusivamente como bolitas satélite.
        let primaryCandidates = sorted.filter { activity in
            if activity.kind == .claude {
                // Claude vive siempre como bolita satélite; se integra al notch sólo cuando el usuario la toca
                return false
            }
            if activity.kind == .agentAI {
                // Solo puede ser principal si es una interacción modal activa (pregunta o solicitud de permiso)
                return AgentActivityProvider.shared.isActive && activity.id.hasPrefix("agent_") && activity.id != "agent_live_progress"
            }
            return true
        }
        
        // Histéresis de rol (3s) para evitar intercambios constantes ante micro-actualizaciones
        var chosenPrimary: LiveActivity? = primaryCandidates.first
        if let current = currentActivity,
           let isCurrentStillValid = primaryCandidates.first(where: { $0.id == current.id }) {
            let timeSinceChange = now.timeIntervalSince(lastRoleChangeTime)
            if let top = primaryCandidates.first, top.id != current.id {
                if top.isUrgent {
                    chosenPrimary = top
                    lastRoleChangeTime = now
                } else if timeSinceChange < hysteresisDuration {
                    chosenPrimary = isCurrentStillValid
                } else {
                    chosenPrimary = top
                    lastRoleChangeTime = now
                }
            } else {
                chosenPrimary = isCurrentStillValid
            }
        } else {
            chosenPrimary = primaryCandidates.first
            lastRoleChangeTime = now
        }
        
        let primaryId = chosenPrimary?.id
        let remaining = sorted.filter { $0.id != primaryId }
        
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.35, dampingFraction: 0.82)) {
            self.currentActivity = chosenPrimary
            switch mode {
            case .modeA:
                self.secondaryActivities = Array(remaining.prefix(maxSatellites))
                self.overflowActivities = Array(remaining.dropFirst(maxSatellites))
                self.overflowCount = self.overflowActivities.count
                
            case .modeB:
                self.secondaryActivities = Array(remaining.prefix(1))
                self.overflowActivities = Array(remaining.dropFirst(1))
                self.overflowCount = self.overflowActivities.count
            }
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    private func rescheduleTimer(for activity: LiveActivity) {
        dismissTimers[activity.id]?.invalidate()
        dismissTimers.removeValue(forKey: activity.id)
        
        if let duration = activity.duration, duration > 0 {
            let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if NotificationActivityProvider.shared.currentNotificationId == activity.id &&
                        NotificationActivityProvider.shared.isQuickReplyExpanded {
                        return
                    }
                    self?.dismissWithAnimation(id: activity.id)
                }
            }
            dismissTimers[activity.id] = timer
        }
    }
    
    // MARK: - Coordinador de Morfeo Líquido y Fusión (Bolita -> Notch -> Expansión)
    
    /// Inicia la animación de fusión orgánica en 2 fases con soporte para interrupción y reversibilidad:
    /// Fase 1: Bolita (micro-compresión 0.94x + haptic/audio) -> elongación direccional en el eje de movimiento -> fusión continua con el notch
    /// Fase 2: Cápsula se expande progresivamente hacia abajo (anclada arriba en y=0) revelando el contenido
    public func initiateFusion(for activity: LiveActivity, fromSide: SatelliteSide = .right) {
        // Interrupción interactiva: si ya está expandida esta misma actividad, colapsar suavemente
        if expandedActivity?.id == activity.id {
            collapseExpandedActivity()
            return
        }
        
        // Interrupción interactiva: si ya se está fusionando esta misma actividad, revertir suavemente hacia la bolita
        if isFusing && fusingActivityId == activity.id {
            reverseFusion(for: activity.id)
            return
        }
        
        // Interrupción interactiva: si hay otra actividad expandida, redirigir suavemente sin reiniciar bruscamente
        if let currentExp = expandedActivity, currentExp.id != activity.id {
            switchExpandedActivity(to: activity, fromSide: fromSide)
            return
        }
        
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        fusingActivityId = activity.id
        fusionSide = fromSide
        isFusing = true
        fusionProgress = 0.0
        
        // 1. Respuesta háptica y sonora inmediata
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        // Sin rebote: la bolita viaja con desaceleración natural y se funde (ver LiquidSatelliteModifier)
        let spring = AnimationSpeedManager.shared.spring(response: 0.34, dampingFraction: 0.92)
        let travelDuration = AnimationSpeedManager.shared.adjustedDuration(0.24)
        
        // 2. Fase 1: Desplazamiento orgánico y elongación sutil hacia la silueta del notch
        withAnimation(spring) {
            self.fusionProgress = 1.0
        }
        
        // 3. Fase 2: Expansión continua de la cápsula hacia abajo (anclada arriba en y=0)
        let timer = Timer(timeInterval: travelDuration, repeats: false) { [weak self] _ in
            guard let self = self, self.fusingActivityId == activity.id else { return }
            
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.40, dampingFraction: 0.82)) {
                self.expandedActivity = activity
                self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : 420)
                self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : 160)
                self.customTopRadius = 24
                self.customBottomRadius = 28
                self.recalculateRoles()
            }
            
            if activity.kind == .agentAI {
                AgentActivityProvider.shared.isProgressHUDExpanded = true
            }
            
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fusionExpansionTimer = timer
    }
    
    /// Revierte suavemente la transición en curso hacia la posición satélite compacta sin saltos visuales
    public func reverseFusion(for id: String) {
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playActionDismissed()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        
        let spring = AnimationSpeedManager.shared.spring(response: 0.34, dampingFraction: 0.82)
        let travelDuration = AnimationSpeedManager.shared.adjustedDuration(0.20)
        
        withAnimation(spring) {
            self.fusionProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + travelDuration) { [weak self] in
            guard let self = self else { return }
            if self.expandedActivity == nil {
                self.fusingActivityId = nil
                self.isFusing = false
            }
            self.recalculateRoles()
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    /// Redirige la transición hacia una nueva actividad desde el estado visual actual
    public func switchExpandedActivity(to newActivity: LiveActivity, fromSide: SatelliteSide = .right) {
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        fusingActivityId = newActivity.id
        fusionSide = fromSide
        
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.38, dampingFraction: 0.82)) {
            self.expandedActivity = newActivity
            self.customCardWidth = newActivity.customExpandedWidth ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudWidth : 420)
            self.customCardHeight = newActivity.customExpandedHeight ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudHeight : 160)
            self.customTopRadius = 24
            self.customBottomRadius = 28
            self.fusionProgress = 1.0
            self.recalculateRoles()
        }
        
        if newActivity.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = true
        } else {
            AgentActivityProvider.shared.isProgressHUDExpanded = false
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Contrae la actividad expandida de vuelta al notch y expulsa suavemente la bolita a su slot satélite
    public func collapseExpandedActivity() {
        guard expandedActivity != nil || isFusing else { return }
        

        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playActionDismissed()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        
        if expandedActivity?.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = false
        }
        
        let contractDuration = AnimationSpeedManager.shared.adjustedDuration(0.22)
        
        // Fase 2 reverso: Contracción vertical de la cápsula hacia el notch (top anclado en y=0)
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.36, dampingFraction: 0.85)) {
            self.expandedActivity = nil
            self.customCardWidth = nil
            self.customCardHeight = nil
            self.customTopRadius = nil
            self.customBottomRadius = nil
            self.recalculateRoles()
        }
        
        // Fase 1 reverso: Desprendimiento y regreso elástico de la bolita a su slot satélite
        DispatchQueue.main.asyncAfter(deadline: .now() + (contractDuration * 0.35)) { [weak self] in
            guard let self = self else { return }
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.40, dampingFraction: 0.90)) {
                self.fusionProgress = 0.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + contractDuration) {
                if self.expandedActivity == nil {
                    self.fusingActivityId = nil
                    self.isFusing = false
                }
                NotchWindowManager.shared.updateHitAreaForCurrentState()
            }
        }
    }
    
    /// Descarta una bolita secundaria o actividad
    public func dismissBolita(id: String) {
        dismissWithAnimation(id: id)
    }
    
    /// Promueve una actividad a principal de forma inmediata
    public func makePrimary(id: String) {
        guard let idx = activeActivities.firstIndex(where: { $0.id == id }) else { return }
        var act = activeActivities[idx]
        act.priority = (activeActivities.map { $0.priority }.max() ?? 900) + 20
        act.lastUpdatedAt = Date()
        activeActivities[idx] = act
        recalculateRoles()
        SoundFeedbackService.shared.playBubblePop()
    }
    
    /// Expande directamente una actividad hacia su tarjeta rica
    public func expandActivity(_ activity: LiveActivity) {
        if expandedActivity?.id == activity.id {
            collapseExpandedActivity()
            return
        }
        
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.38, dampingFraction: 0.82)) {
            self.expandedActivity = activity
            self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : 420)
            self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : 160)
            self.customTopRadius = 24
            self.customBottomRadius = 28
            self.recalculateRoles()
        }
        
        if activity.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = true
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Maneja el click sobre la actividad principal
    public func handleTap() {
        guard let activity = currentActivity else { return }
        if let onTap = activity.onTap {
            onTap()
        } else if activity.expandedView != nil {
            expandActivity(activity)
        } else {
            AppState.shared.expand()
        }
    }
}
