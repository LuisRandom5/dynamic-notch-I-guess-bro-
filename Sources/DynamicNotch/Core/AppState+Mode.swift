import AppKit
import SwiftUI
import Combine

// Modo del notch: compacto/reposo, hover, abrir, cerrar, alertas
extension AppState {
    public var shouldShowCompact: Bool {
        // La repisa ya no abre las alas: se muestra como bolita (ShelfActivityProvider)
        return (musicService.hasActiveMusic || musicPauseDismissTimer != nil) && showCompactWhenPlaying
    }
    
    /// Reconcilia de forma segura el modo compacto cuando cambia la música, la bandeja o se cierra una actividad
    public func reconcileCompactMode() {
        guard mode != .expanded && mode != .shelf else { return }
        if shouldShowCompact {
            if mode == .idle {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    mode = .compact
                }
            }
        } else {
            if mode == .compact {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    mode = .idle
                }
            }
        }
    }
    

    public func handleVolumeChanged(volume: Float, isMuted: Bool) {
        self.currentVolume = volume
        self.isVolumeMuted = isMuted
        self.isVolumeHUDActive = false
    }
    
    /// Expansión suave y continua tipo Dynamic Island real con sombra fija mientras el cursor permanece sobre el Notch
    public func setHoverState(_ hovering: Bool) {
        if hovering && enableHoverExpansion && mode != .expanded && mode != .shelf {
            let targetX = CGFloat(max(1.01, min(1.09, hoverScaleAmount)))
            let targetY = CGFloat(1.0 + (hoverScaleAmount - 1.0) * 0.72)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                heartbeatScaleX = targetX
                heartbeatScaleY = targetY
                heartbeatShadowOpacity = hoverShadowIntensity
            }
        } else {
            // Ya en reposo: no publicar nada (evita reevaluar todas las vistas sin motivo)
            guard heartbeatScaleX != 1.0 || heartbeatScaleY != 1.0 || heartbeatShadowOpacity != 0.0 else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                heartbeatScaleX = 1.0
                heartbeatScaleY = 1.0
                heartbeatShadowOpacity = 0.0
            }
        }
    }
    
    public func triggerHeartbeat() {
        setHoverState(true)
    }
    
    public func triggerAlert(_ type: AlertType, duration: TimeInterval = 4.0) {
        let alert = NotchAlert(type: type)
        self.activeAlert = alert
        self.activeTab = .alerts
        
        if mode != .expanded {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                self.mode = .expanded
            }
            hapticService.triggerExpand()
        }
        
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.collapse()
            self.activeAlert = nil
        }
    }
    
    public func handleMouseEnter() {
        guard !isHovered else { return }
        self.isHovered = true
        if expandOnHover {
            if mode == .idle || mode == .compact {
                withAnimation(.spring(response: 0.68, dampingFraction: 0.76)) {
                    if !self.shelfItems.isEmpty && !self.musicService.hasActiveMusic {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    } else {
                        self.mode = .expanded
                        self.activeTab = .music
                    }
                }
                hapticService.triggerExpand()
            }
        } else {
            setHoverState(true)
        }
    }
    
    public func handleMouseLeave() {
        self.isHovered = false
        setHoverState(false)
        if expandOnHover {
            if mode == .expanded && activeAlert == nil {
                collapse()
            }
        }
    }
    
    public func collapse() {
        // Asignar sólo si cambia: cada asignación a un @Published (aunque sea el mismo valor) hace que TODAS
        // las vistas que observan AppState se reevalúen, y eso en el primer cuadro del cierre lo congelaba
        if overscrollOffset != 0 { overscrollOffset = 0 }
        if contentOverscrollOffset != 0 { contentOverscrollOffset = 0 }
        if verticalOverscrollOffset != 0 { verticalOverscrollOffset = 0 }
        if contentVerticalOverscrollOffset != 0 { contentVerticalOverscrollOffset = 0 }
        if activeMiniAppOverlay != nil { activeMiniAppOverlay = nil }
        setHoverState(false)
        if (shelfItems.isEmpty || musicService.hasActiveMusic) && activeTab != .music {
            activeTab = .music
        }
        
        if let requestCollapse = requestCollapse {
            requestCollapse()
        } else {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeCloseResponse,
                dampingFraction: ExitAnimationMetrics.shapeCloseDamping
            )
            withAnimation(springAnim) {
                mode = shouldShowCompact ? .compact : .idle
                hapticService.triggerSnap()
            }
        }
    }
    
    public func expand() {
        guard mode != .expanded && mode != .shelf else { return }
        overscrollOffset = 0
        contentOverscrollOffset = 0
        verticalOverscrollOffset = 0
        contentVerticalOverscrollOffset = 0
        isPlayerDetailExpanded = false
        setHoverState(false)
        if shelfItems.isEmpty {
            activeTab = .music
        }
        
        let springAnim = AnimationSpeedManager.shared.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        withAnimation(springAnim) {
            mode = (activeTab == .shelf && !shelfItems.isEmpty) ? .shelf : .expanded
            hapticService.triggerExpand()
        }
    }
    
    public func openWithMiniApp(_ miniApp: MiniAppKind) {
        activeMiniAppOverlay = miniApp
        activeTab = .music
        if mode != .expanded {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeOpenResponse,
                dampingFraction: ExitAnimationMetrics.shapeOpenDamping
            )
            withAnimation(springAnim) {
                mode = .expanded
            }
            hapticService.triggerExpand()
        }
    }
    
    public func toggleExpand() {
        if mode == .expanded || mode == .shelf {
            collapse()
        } else {
            expand()
        }
    }
}
