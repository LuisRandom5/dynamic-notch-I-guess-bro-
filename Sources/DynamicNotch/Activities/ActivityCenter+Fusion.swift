import SwiftUI
import Combine
import AppKit

// Fusión bolita → notch → tarjeta expandida, y su reversa
extension ActivityCenter {
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
                // Sin medidas propias: la plantilla expandida de Apple (ancho 408, alto según su contenido)
                self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
                self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
                self.customTopRadius = 24
                self.customBottomRadius = IslandExpandedTemplateMetrics.defaultOuterRadius
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
            self.customCardWidth = newActivity.customExpandedWidth ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
            self.customCardHeight = newActivity.customExpandedHeight ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
            self.customTopRadius = 24
            self.customBottomRadius = IslandExpandedTemplateMetrics.defaultOuterRadius
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
        alertingActivityId = nil
        

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
            self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
            self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
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
