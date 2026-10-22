import AppKit
import SwiftUI

/// Traduce los gestos decididos por `TrackpadGestureRecognizer` en acciones del notch.
///
/// El contexto se resuelve UNA vez al inicio de cada gesto con una jerarquía estricta:
/// HUD/actividad expandida > Notificación (WhatsApp) > Llamada > Interacción del agente >
/// Tarjeta modal > Reproductor (idle/compact) > Expandido > Bandeja.
/// Los indicadores secundarios (p. ej. la bolita de progreso del agente) nunca bloquean el reproductor.
public final class NotchGestureDispatcher: TrackpadGestureDelegate {
    enum Context: Equatable {
        case expandedActivity
        case notification(quickReplyExpanded: Bool)
        case call(expandedCard: Bool)
        case agentInteraction(expanded: Bool)
        case modalCard
        case collapsed
        case expanded(detail: Bool)
        case shelf
    }

    private var context: Context = .collapsed
    private var hasTriggeredStretchHaptic = false
    
    // MARK: Cierre interactivo
    /// Recorrido de dedos (pt) para cerrar por completo; al soltar se cierra si se pasó del 30 % o con un flick
    private static let interactiveCloseDistance: CGFloat = 72
    private static let interactiveCloseCommit: CGFloat = 0.30
    private static let interactiveCloseFlickDelta: CGFloat = -3.0
    private var pendingInteractiveClose: (() -> Void)?
    private var lastCloseDelta: CGFloat = 0
    /// El cierre ya se completó solo al llegar al final: el desenfoque no se mantiene hasta soltar
    private var didAutoCommitClose = false
    
    /// Sigue los dedos hacia arriba: devuelve false para seguir recibiendo movimientos (la decisión es al soltar)
    private func trackInteractiveClose(translation t: CGFloat, delta: CGFloat, onCommit: @escaping () -> Void) -> Bool {
        // Ajuste apagado: cierre inmediato al deslizar hacia arriba (como antes)
        guard AppState.shared.interactiveCloseEnabled else {
            guard t <= -2.0 else { return false }
            onCommit()
            AppState.shared.hapticService.triggerSnap()
            return true
        }
        let progress = min(1, max(0, -t / Self.interactiveCloseDistance))
        AppState.shared.interactiveCollapseProgress = progress
        lastCloseDelta = delta
        pendingInteractiveClose = progress > 0 ? onCommit : nil
        // Llegó al final del recorrido: se cierra YA, sin esperar a que se levanten los dedos (antes se quedaba
        // "compactada" en pantalla hasta soltar). El resto del gesto se absorbe.
        if progress >= 0.92 {
            finishInteractiveClose()
            didAutoCommitClose = true
            return true
        }
        return false
    }
    
    /// Al soltar: completa el cierre (más allá del umbral o con un flick) o regresa con un resorte
    private func finishInteractiveClose() {
        let app = AppState.shared
        let progress = app.interactiveCollapseProgress
        // Sin cierre pendiente (p. ej. ya se completó solo al llegar al final) no hay nada que decidir
        guard pendingInteractiveClose != nil else { return }
        let commit = pendingInteractiveClose
        pendingInteractiveClose = nil
        if let commit = commit, progress >= CGFloat(app.interactiveCloseThreshold) || lastCloseDelta <= Self.interactiveCloseFlickDelta {
            DNDLogger.log("Gestos: cierre interactivo completado (\(Int(progress * 100))%)")
            commit()
            // La escala del gesto regresa con EXACTAMENTE el resorte de la contracción y en el mismo instante
            // (la forma empieza a cerrarse a los 40 ms): así nunca crece mientras se cierra
            DispatchQueue.main.asyncAfter(deadline: .now() + AnimationSpeedManager.shared.adjustedDuration(0.04)) {
                withAnimation(AnimationSpeedManager.shared.spring(
                    response: ExitAnimationMetrics.compactMorphResponse,
                    dampingFraction: ExitAnimationMetrics.compactMorphDamping
                )) {
                    app.interactiveCollapseProgress = 0
                }
            }
            app.hapticService.triggerSnap()
        } else {
            // No llegó: regresa a su tamaño
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                app.interactiveCollapseProgress = 0
            }
        }
    }

    public init() {}

    // MARK: - Contexto y zona activa

    private func resolveContext() -> Context {
        let app = AppState.shared
        let agent = AgentActivityProvider.shared
        let notification = NotificationActivityProvider.shared
        let call = CallActivityProvider.shared

        if ActivityCenter.shared.expandedActivity != nil || agent.isProgressHUDExpanded {
            return .expandedActivity
        }
        if notification.isNotificationActive {
            return .notification(quickReplyExpanded: notification.isQuickReplyExpanded)
        }
        if call.isCallActive || call.isIncomingCall {
            return .call(expandedCard: call.isExpandedCard)
        }
        if agent.isInteractionActive {
            return .agentInteraction(expanded: agent.isExpanded)
        }
        switch app.mode {
        case .expanded:
            return .expanded(detail: app.isPlayerDetailExpanded)
        case .shelf:
            return .shelf
        case .idle, .compact:
            if ActivityCenter.shared.currentActivity?.style == .card { return .modalCard }
            return .collapsed
        }
    }

    /// Medidas de la zona sensible: distancia horizontal máxima desde el centro y vertical desde el borde superior.
    private func zone(for context: Context) -> (halfWidth: CGFloat, depth: CGFloat) {
        switch context {
        case .expandedActivity:
            return (max(300, AgentLiveProgressView.hudWidth / 2 + 40), 280)
        case .notification, .agentInteraction:
            return (280, 240)
        case .call, .modalCard:
            return (260, 200)
        case .collapsed:
            return (260, 120)
        // Reproductor y bandeja: sólo la tarjeta visible + 16 pt. Con la zona holgada (70 pt de más hacia abajo),
        // desplazarse en la ventana de debajo con el cursor cerca del notch contaba como "deslizar arriba" y
        // cerraba la bandeja sola.
        case .expanded(let detail):
            return (PlayerMetrics.cardWidth / 2 + 16, (detail ? PlayerMetrics.detailCardHeight : PlayerMetrics.cardHeight) + 16)
        case .shelf:
            return (PlayerMetrics.cardWidth / 2 + 16, 204 + 16)
        }
    }

    public func gestureShouldBegin(at screenLocation: NSPoint) -> Bool {
        guard AppState.shared.enableTrackpadSwipe, !NotchWindowManager.shared.isHiddenForFullScreen else { return false }
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        let dxFromCenter = abs(screenLocation.x - frame.midX)
        let dyFromTop = frame.maxY - screenLocation.y

        context = resolveContext()
        hasTriggeredStretchHaptic = false
        // Recorrer actividades sólo si el gesto empieza sobre la franja de la isla y sus bolitas (no al
        // desplazarse de lado en la ventana de abajo)
        let geometry = ScreenService.shared.currentGeometry
        let bubbleReach = 2 * (AppState.shared.effectiveBolitaDiameter + AppState.shared.bolitaGap) + NotchTuning.compactWingWidth
        beganOnIslandRow = dyFromTop <= geometry.height + 10 && dxFromCenter <= geometry.width / 2 + bubbleReach
        let zone = zone(for: context)
        return dxFromCenter <= zone.halfWidth && dyFromTop >= 0 && dyFromTop <= zone.depth
    }

    public func gestureAllowsHorizontal() -> Bool {
        switch context {
        case .expanded, .shelf: return true
        // Notch cerrado con música (o minimizado): deslizar de lado la esconde / la regresa
        // Con varias actividades, deslizar de lado las recorre (como la Isla Dinámica)
        case .collapsed:
            return swipeCyclesActivities
                || (AppState.shared.swipeToMinimizeMusic && (AppState.shared.mode == .compact || AppState.shared.isCompactMinimized))
        default: return false
        }
    }

    /// El gesto empezó sobre la isla o sus bolitas (ver gestureShouldBegin)
    private var beganOnIslandRow = false

    /// El swipe a lo ancho recorre las actividades en vez de esconder la música
    private var swipeCyclesActivities: Bool {
        beganOnIslandRow && AppState.shared.swipeCyclesActivities && ActivityCenter.shared.canCycleActivities
    }

    // MARK: - Acciones

    public func gestureMoved(axis: GestureAxis, translation t: CGFloat, delta: CGFloat) -> Bool {
        // Si los dedos regresan hacia abajo, el cierre interactivo se deshace con ellos
        if axis == .vertical && t >= 0 && AppState.shared.interactiveCollapseProgress > 0 {
            AppState.shared.interactiveCollapseProgress = 0
            pendingInteractiveClose = nil
        }
        didAutoCommitClose = false
        let triggered = route(axis: axis, translation: t, delta: delta)
        if didAutoCommitClose {
            withAnimation(.easeOut(duration: 0.30)) { AppState.shared.gestureBlurHold = 0 }
            return true
        }
        // Desenfoque interactivo SÓLO cuando hay transformación: el cierre que sigue a los dedos crece con el
        // recorrido y, si el gesto ya disparó un cambio, se queda completo hasta levantar los dedos.
        // El estiramiento de resorte (topar con pared: no hay más páginas) no se desenfoca.
        let closing = AppState.shared.interactiveCollapseProgress
        // Cambiar de página (reproductor ⇄ repisa, gesto horizontal) tampoco se desenfoca
        let raw: CGFloat = (triggered && axis == .vertical) ? 1 : (closing > 0 ? min(1, closing * 4) : 0)
        // En escalones de 1/8: cada cambio de radio obliga a recalcular el desenfoque de todo el contenido, y con
        // ocho pasos el ojo no nota la diferencia (antes cambiaba con cada evento del trackpad)
        let hold = (raw * 8).rounded() / 8
        if AppState.shared.gestureBlurHold != hold {
            AppState.shared.gestureBlurHold = hold
        }
        return triggered
    }

    private func route(axis: GestureAxis, translation t: CGFloat, delta: CGFloat) -> Bool {
        let app = AppState.shared

        switch (context, axis) {
        case (.expandedActivity, .vertical):
            if t < 0 {
                // Cierre interactivo: la tarjeta se encoge con los dedos y se decide al soltar
                return trackInteractiveClose(translation: t, delta: delta) {
                    DNDLogger.log("Gestos: swipe up en actividad expandida -> contrayendo")
                    ActivityCenter.shared.collapseExpandedActivity()
                    AgentActivityProvider.shared.collapseProgressHUD()
                }
            }

        case (.notification(let quickReplyExpanded), .vertical):
            let provider = NotificationActivityProvider.shared
            if !quickReplyExpanded {
                if t >= 2.0 {
                    DNDLogger.log("Gestos: swipe down en notificación -> expandQuickReply")
                    provider.expandQuickReply()
                    return true
                }
                if t <= -8.0 {
                    DNDLogger.log("Gestos: swipe up en notificación -> dismissNotification")
                    provider.dismissNotification()
                    return true
                }
            } else if t <= -16.0 {
                // Umbral alto: un roce al llevar las manos al teclado no debe cerrar la respuesta
                DNDLogger.log("Gestos: swipe up en Quick Reply -> collapseQuickReply")
                provider.collapseQuickReply()
                return true
            }

        case (.call(let expandedCard), .vertical):
            let call = CallActivityProvider.shared
            if !expandedCard {
                if t >= 1.2 {
                    DNDLogger.log("Gestos: swipe down en llamada -> expandToCard")
                    call.expandToCard()
                    return true
                }
            } else if t <= -6.0 {
                DNDLogger.log("Gestos: swipe up en llamada -> collapseToPill")
                call.collapseToPill()
                return true
            } else if t >= 16.0 {
                // Con la tarjeta de llamada abierta, seguir bajando muestra el reproductor normal
                DNDLogger.log("Gestos: swipe down en tarjeta de llamada -> reproductor")
                call.collapseToPill()
                app.isPlayerDetailExpanded = false
                app.expand()
                return true
            }

        case (.agentInteraction(let expanded), .vertical):
            let agent = AgentActivityProvider.shared
            if !expanded {
                if t >= 2.0 {
                    agent.expandInteraction()
                    return true
                }
                if t <= -8.0 {
                    agent.dismissActivity()
                    return true
                }
            } else if t <= -16.0 {
                agent.collapseInteraction()
                return true
            }

        case (.collapsed, .horizontal):
            if abs(t) >= 10 && swipeCyclesActivities {
                // Dedos hacia la izquierda = siguiente, como pasar páginas
                DNDLogger.log("Gestos: swipe lateral en notch cerrado -> recorrer actividades (\(t < 0 ? "siguiente" : "anterior"))")
                ActivityCenter.shared.cycleActivities(forward: t < 0)
                return true
            }
            if abs(t) >= 10 {
                let minimize = !app.isCompactMinimized
                DNDLogger.log("Gestos: swipe lateral en notch cerrado -> \(minimize ? "minimizar" : "restaurar") música")
                withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.84)) {
                    app.isCompactMinimized = minimize
                }
                app.hapticService.triggerSnap()
                return true
            }

        case (.collapsed, .vertical):
            if t >= 1.5 {
                DNDLogger.log("Gestos: swipe down -> expandiendo notch")
                app.expand()
                app.hapticService.triggerExpand()
                return true
            }

        case (.expanded(let detail), .vertical):
            if t > 0 {
                applyVerticalStretch(t)
                let isFastFlick = delta > 2.2 && t > 8.0
                if !detail && (t >= 14.0 || isFastFlick) {
                    DNDLogger.log("Gestos: swipe down en reproductor -> detalle de volumen")
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        app.isPlayerDetailExpanded = true
                        app.verticalOverscrollOffset = 0
                        app.contentVerticalOverscrollOffset = 0
                    }
                    app.hapticService.triggerExpand()
                    return true
                }
            } else if t < 0 {
                if detail {
                    guard t <= -2.0 else { return false }
                    DNDLogger.log("Gestos: swipe up -> cerrando detalle de volumen")
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                        app.isPlayerDetailExpanded = false
                        app.verticalOverscrollOffset = 0
                        app.contentVerticalOverscrollOffset = 0
                    }
                    app.hapticService.triggerSnap()
                    return true
                }
                // Cierre interactivo del reproductor: se encoge con los dedos y se decide al soltar
                return trackInteractiveClose(translation: t, delta: delta) {
                    DNDLogger.log("Gestos: swipe up -> colapsando reproductor")
                    app.collapse()
                }
            } else {
                applyVerticalStretch(0)
            }

        case (.expanded, .horizontal):
            if t > 0 {
                // A la derecha de Música no hay más páginas: rebote elástico
                applyHorizontalStretch(t)
            } else if t <= -4.0 {
                switchPage(to: .shelf)
                return true
            }

        case (.shelf, .vertical):
            if t > 0 {
                applyVerticalStretch(t)
            } else if t < 0 {
                // Cierre interactivo de la bandeja
                return trackInteractiveClose(translation: t, delta: delta) {
                    DNDLogger.log("Gestos: swipe up en bandeja -> colapsando")
                    app.collapse()
                }
            }

        case (.shelf, .horizontal):
            if t < 0 {
                // A la izquierda de la Bandeja no hay más páginas: rebote elástico
                applyHorizontalStretch(t)
            } else if t >= 4.0 {
                switchPage(to: .expanded)
                return true
            }

        default:
            break
        }
        return false
    }

    public func gestureDiscreteStep(axis: GestureAxis, direction: CGFloat) -> Bool {
        context = resolveContext()
        // Un paso de rueda equivale a un swipe completo; sin estiramiento visual
        // Rueda clásica: sin fase de "levantar los dedos", así que no mantiene el desenfoque (basta el automático)
        let triggered = route(axis: axis, translation: direction * 20, delta: direction * 20)
        resetOverscroll()
        return triggered
    }

    public func gestureEnded(triggered: Bool) {
        finishInteractiveClose()
        resetOverscroll()
        // Dedos fuera del trackpad: el contenido vuelve a enfocarse mientras la forma termina de asentarse
        withAnimation(.easeOut(duration: 0.32)) {
            AppState.shared.gestureBlurHold = 0
        }
    }

    // MARK: - Overscroll elástico

    private func applyVerticalStretch(_ translation: CGFloat) {
        let app = AppState.shared
        let stretch = OverscrollMetrics.calculateStretch(for: max(0, translation))
        app.verticalOverscrollOffset = stretch
        app.contentVerticalOverscrollOffset = stretch * OverscrollMetrics.contentFollow
    }

    private func applyHorizontalStretch(_ translation: CGFloat) {
        let app = AppState.shared
        let stretch = OverscrollMetrics.calculateStretch(for: translation)
        app.overscrollOffset = stretch
        app.contentOverscrollOffset = stretch * OverscrollMetrics.contentFollow
        if abs(stretch) > 2.0 && !hasTriggeredStretchHaptic {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            hasTriggeredStretchHaptic = true
        }
    }

    private func switchPage(to mode: NotchMode) {
        let app = AppState.shared
        DNDLogger.log("Gestos: swipe horizontal -> \(mode == .shelf ? "bandeja" : "música")")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            app.mode = mode
            app.activeTab = mode == .shelf ? .shelf : .music
            app.overscrollOffset = 0
            app.contentOverscrollOffset = 0
        }
        app.hapticService.triggerSnap()
    }

    /// Regresa la forma y el contenido a su sitio: la forma con un resorte rápido y el contenido con uno más suave.
    private func resetOverscroll() {
        let app = AppState.shared
        let shapeSpring = AnimationSpeedManager.shared.spring(
            response: OverscrollMetrics.shapeSpringResponse,
            dampingFraction: OverscrollMetrics.shapeSpringDamping
        )
        let contentSpring = AnimationSpeedManager.shared.spring(
            response: OverscrollMetrics.contentSpringResponse,
            dampingFraction: OverscrollMetrics.contentSpringDamping
        )
        if app.overscrollOffset != 0 || app.verticalOverscrollOffset != 0 {
            withAnimation(shapeSpring) {
                app.overscrollOffset = 0
                app.verticalOverscrollOffset = 0
            }
        }
        if app.contentOverscrollOffset != 0 || app.contentVerticalOverscrollOffset != 0 {
            withAnimation(contentSpring) {
                app.contentOverscrollOffset = 0
                app.contentVerticalOverscrollOffset = 0
            }
        }
        if app.trackpadDragOffsetY != 0 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                app.trackpadDragOffsetY = 0
            }
        }
    }
}
