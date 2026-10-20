import SwiftUI
import UniformTypeIdentifiers

// Abrir y cerrar el notch: cambio de modo, expansión con entrada escalonada y colapso
extension NotchContainerView {
    func handleModeChange(_ mode: NotchMode) {
        if mode == .expanded {
            performExpand()
        } else if mode == .shelf {
            appState.activeTab = .shelf
            appState.setHoverState(false)
        } else if mode == .compact {
            interactionState = .collapsed
            isTransitioningFromActivity = false
            // `isCollapsing` NO se limpia aquí: el modo pasa a compacto a los 40 ms del cierre, con la forma
            // aún contrayéndose. Limpiarlo a media contracción reactivaba la expansión de hover, cambiaba el
            // fondo/sombra y el resorte (el "espasmo"); performCollapse lo limpia al asentarse.
        } else {
            performCollapse()
        }
    }
    
    // Expansión con resorte físico reversible
    func performExpand() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
        appState.setHoverState(false)
        isTransitioningFromActivity = false
        
        isCollapsing = false
        controlsExiting = false
        progressExiting = false
        topRowExiting = false
        
        let shapeSpring = speedManager.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        
        let targetMode: NotchMode
        if appState.activeMiniAppOverlay != nil || musicService.hasActiveMusic {
            targetMode = .expanded
            appState.activeTab = .music
        } else if !appState.shelfItems.isEmpty {
            targetMode = .shelf
            appState.activeTab = .shelf
        } else if appState.mode == .expanded {
            targetMode = .expanded
            appState.activeTab = .music
        } else {
            targetMode = .expanded
            appState.activeTab = .music
        }
        withAnimation(shapeSpring) {
            interactionState = .expanded
            if appState.mode != targetMode {
                appState.mode = targetMode
            }
        }
        if appState.mode != targetMode {
            appState.hapticService.triggerExpand()
        }
        if targetMode == .expanded {
            triggerStaggeredIn()
        }
    }
    
    // Entrada escalonada con retraso sutil
    func triggerStaggeredIn() {
        let inSpring = NotchTuning.contentInSpring
        
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(NotchTuning.stage1Delay)) {
            guard self.appState.mode == .expanded else { return }
            withAnimation(inSpring) {
                self.animStage1 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(NotchTuning.stage2Delay)) {
            guard self.appState.mode == .expanded else { return }
            withAnimation(inSpring) {
                self.animStage2 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(NotchTuning.stage3Delay)) {
            guard self.appState.mode == .expanded else { return }
            withAnimation(inSpring) {
                self.animStage3 = true
            }
        }
    }
    
    // ANIMACIÓN DE SALIDA (CIERRE) DEL NOTCH BASADA EN ESTADO Y RESORTES INTERRUMPIBLES
    func performCollapse() {
        guard (appState.mode == .expanded || appState.mode == .shelf) && !isCollapsing else { return }
        
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
        appState.setHoverState(false)
        appState.activeMiniAppOverlay = nil
        isCollapsing = true
        
        let exitAnim = speedManager.easeIn(duration: ExitAnimationMetrics.contentExitDuration)
        let shapeSpring = speedManager.spring(
            response: ExitAnimationMetrics.compactMorphResponse,
            dampingFraction: ExitAnimationMetrics.compactMorphDamping
        )
        
        // t = 0 ms: la fila de controles sale primero de abajo hacia arriba
        withAnimation(exitAnim) {
            controlsExiting = true
        }
        
        // t = 20 ms: la barra de progreso sale
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(0.02)) {
            guard self.isCollapsing else { return }
            withAnimation(exitAnim) {
                self.progressExiting = true
            }
        }
        
        // t = 35 ms: la fila superior (textos) sale
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(0.035)) {
            guard self.isCollapsing else { return }
            withAnimation(exitAnim) {
                self.topRowExiting = true
            }
        }
        
        // t = 40 ms: contracción elástica continua hacia el notch / compact con resorte orgánico
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(0.04)) {
            guard self.isCollapsing else { return }
            withAnimation(shapeSpring) {
                self.interactionState = .collapsed
                self.isTransitioningFromActivity = false
                // Sólo lo que cambia (ver AppState.collapse)
                if self.appState.isHoldingBareNotch { self.appState.isHoldingBareNotch = false }
                if self.appState.isPlayerDetailExpanded { self.appState.isPlayerDetailExpanded = false }
                if self.appState.verticalOverscrollOffset != 0 { self.appState.verticalOverscrollOffset = 0 }
                if self.appState.contentVerticalOverscrollOffset != 0 { self.appState.contentVerticalOverscrollOffset = 0 }
                if self.appState.overscrollOffset != 0 { self.appState.overscrollOffset = 0 }
                if self.appState.contentOverscrollOffset != 0 { self.appState.contentOverscrollOffset = 0 }
                if (self.appState.shelfItems.isEmpty || self.musicService.hasActiveMusic) && self.appState.activeTab != .music {
                    self.appState.activeTab = .music
                }
                if self.appState.shouldShowCompact {
                    self.appState.mode = .compact
                } else {
                    self.appState.mode = .idle
                }
            }
            self.appState.hapticService.triggerSnap()
        }
        
        // Reseteo limpio al asentarse la animación (~0.58 s)
        let totalTime = speedManager.adjustedDuration(0.58)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            guard self.isCollapsing else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isCollapsing = false
            }
            self.controlsExiting = false
            self.progressExiting = false
            self.topRowExiting = false
            self.animStage1 = false
            self.animStage2 = false
            self.animStage3 = false
            self.appState.reconcileCompactMode()
        }
    }
}
