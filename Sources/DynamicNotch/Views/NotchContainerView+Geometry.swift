import SwiftUI
import UniformTypeIdentifiers

// Tamaño, radios, escala, sombras y resortes de la superficie del notch (sin vistas ni gestos)
extension NotchContainerView {
    var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    var baseRestingWidth: CGFloat {
        if appState.isHoldingBareNotch || appState.isCompactMinimized {
            return geometry.width
        }
        switch appState.mode {
        case .idle:
            return geometry.width
        case .compact:
            return geometry.width + NotchTuning.compactWingsExtraWidth
        case .expanded, .shelf:
            return NotchTuning.expandedWidth
        }
    }
    
    // Ancho: notch físico en idle, alas en compact, HUD de volumen, Live Activity o ancho fijo en expanded
    var currentWidth: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedWidth
        } else if agentProvider.isProgressHUDExpanded {
            return AgentLiveProgressView.hudWidth
        } else if let expandedAct = activityCenter.expandedActivity {
            return activityCenter.customCardWidth ?? (expandedAct.customExpandedWidth ?? 430)
        } else if appState.isDropInvitationActive {
            return 460
        } else if let activity = activityCenter.currentActivity {
            if activityCenter.dismissingActivityId == activity.id {
                switch activity.style {
                case .card:
                    return geometry.width
                case .sliderPill, .pill:
                    return baseRestingWidth
                case .airpodsPill:
                    return baseRestingWidth
                }
            }
            switch activity.style {
            case .pill:
                // Una píldora puede pedir su propio ancho (p. ej. AirDrop ensancha las alas al confirmar)
                return activity.customExpandedWidth ?? (geometry.width + 170)
            case .sliderPill:
                return geometry.width + 292
            case .airpodsPill:
                return geometry.width + 104
            case .card:
                if notificationProvider.isNotificationActive && activity.id.hasPrefix("notification_") {
                    return notificationProvider.isQuickReplyExpanded
                        ? NotificationActivityProvider.expandedWidth
                        : NotificationActivityProvider.compactWidth
                }
                if activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress") || (agentProvider.isActive && activity.id.hasPrefix("agent_")) {
                    if activityCenter.expandedActivity?.id == activity.id || agentProvider.isProgressHUDExpanded {
                        return AgentLiveProgressView.hudWidth
                    }
                    return agentProvider.isExpanded
                        ? AgentActivityProvider.expandedWidth
                        : baseRestingWidth
                }
                return activityCenter.customCardWidth ?? 390
            }
        } else {
            switch appState.mode {
            case .idle:
                return geometry.width
            case .compact:
                // Pausa tras el HUD de volumen/brillo: el notch se recoge por completo (sin alas negras vacías)
                // y al terminar vuelve a abrirse hacia los lados con la carátula y las barras
                if appState.isHoldingBareNotch || appState.isCompactMinimized {
                    return geometry.width
                }
                if isMinimalAttached {
                    return geometry.width + minimalWingWidth
                }
                return geometry.width + NotchTuning.compactWingsExtraWidth
            case .expanded, .shelf:
                return NotchTuning.expandedWidth
            }
        }
    }
    
    /// Mínima pegada, como la Isla Dinámica con varias actividades: la música queda sólo con su carátula a la
    /// izquierda de la cámara y la isla se angosta; las demás actividades son bolitas separadas
    var isMinimalAttached: Bool {
        appState.minimalAttachedEnabled
            && appState.mode == .compact && !appState.isHoldingBareNotch && !appState.isCompactMinimized
            && activityCenter.currentActivity == nil && activityCenter.expandedActivity == nil
            && !activityCenter.secondaryActivities.isEmpty
            && !appState.isDropInvitationActive && !agentProvider.isProgressHUDExpanded
    }
    
    var minimalWingWidth: CGFloat {
        activityCenter.isLimitedWidth ? NotchTuning.minimalWingLimitedWidth : NotchTuning.minimalWingWidth
    }
    
    /// Bolita en su lugar. La identidad incluye el lado: si cambia de lado (swipe a lo ancho) se reabsorbe en
    /// el notch de un lado y brota del otro en vez de cruzar por encima de la isla (guía de Apple: mejor salir
    /// y volver a entrar que encimarse)
    struct SatelliteSlot {
        let activity: LiveActivity
        let index: Int
        let isLeft: Bool
        var key: String { "\(activity.id)|\(isLeft ? "L" : "R")" }
    }
    
    func satelliteSlots(bothSides: Bool) -> [SatelliteSlot] {
        activityCenter.secondaryActivities.enumerated().map { index, activity in
            // El lado lo guarda ActivityCenter (estable); por si aún no está, el orden
            let placement = activityCenter.satelliteLayout[activity.id]
                ?? SatellitePlacement(isLeft: bothSides && index == 1, slotIndex: bothSides ? 0 : index)
            return SatelliteSlot(activity: activity, index: placement.slotIndex, isLeft: placement.isLeft)
        }
    }
    
    /// La mínima pegada sólo crece hacia la izquierda: la forma se corre para que la cámara quede en su lugar
    var attachedOffsetX: CGFloat {
        isMinimalAttached ? -minimalWingWidth / 2 : 0
    }
    
    // Alto: altura del notch en reposo, 36pt en SliderPill, altura del notch en alas de AirPods, 144pt en Drop Invitation, 204pt en repisa, 196pt en reproductor
    var currentHeight: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return (appState.isPlayerDetailExpanded && appState.mode == .expanded)
                ? PlayerMetrics.detailCardHeight
                : (appState.mode == .shelf ? 204 : NotchTuning.expandedHeight)
        } else if agentProvider.isProgressHUDExpanded {
            return AgentLiveProgressView.hudHeight
        } else if let expandedAct = activityCenter.expandedActivity {
            return activityCenter.customCardHeight ?? (expandedAct.customExpandedHeight ?? 160)
        } else if appState.isDropInvitationActive {
            return 144
        } else if let activity = activityCenter.currentActivity {
            if activityCenter.dismissingActivityId == activity.id {
                return geometry.height
            }
            switch activity.style {
            case .pill, .sliderPill, .airpodsPill:
                return geometry.height
            case .card:
                if notificationProvider.isNotificationActive && activity.id.hasPrefix("notification_") {
                    return notificationProvider.isQuickReplyExpanded
                        ? notificationProvider.dynamicReplyHeight
                        : NotificationActivityProvider.compactHeight
                }
                if activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress") || (agentProvider.isActive && activity.id.hasPrefix("agent_")) {
                    if activityCenter.expandedActivity?.id == activity.id || agentProvider.isProgressHUDExpanded {
                        return AgentLiveProgressView.hudHeight
                    }
                    return agentProvider.isExpanded
                        ? AgentActivityProvider.expandedHeight
                        : geometry.height
                }
                return activityCenter.customCardHeight ?? 112
            }
        } else {
            return geometry.height
        }
    }
    
    // Curvatura de esquinas: se redondea dinámicamente al arrastrar para convertirse en PÍLDORA completa
    /// Isla flotante (pantalla sin notch): cápsula completa separada del borde, como la del iPhone
    var isFloatingIsland: Bool {
        geometry.kind == .floatingIsland
    }
    
    /// Esquinas de arriba: colgando del borde (notch) casi rectas; flotando, iguales a las de abajo
    var topRadius: CGFloat {
        isFloatingIsland ? bottomRadius : hangingTopRadius
    }
    
    var hangingTopRadius: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedTopRadius
        } else if agentProvider.isProgressHUDExpanded {
            return 0
        } else if activityCenter.expandedActivity?.kind == .claude {
            // Radios propios: los radios compartidos (customTopRadius) los sobrescriben otras actividades
            return ClaudeActivityProvider.cardCornerRadius
        } else if activityCenter.expandedActivity != nil {
            return activityCenter.customTopRadius ?? 24
        } else if appState.isDropInvitationActive {
            return 0
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill, .sliderPill, .airpodsPill:
                return 0
            case .card:
                if activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress") {
                    return 0
                }
                if agentProvider.isActive && activity.id.hasPrefix("agent_") {
                    return AgentActivityProvider.topRadius
                }
                return activityCenter.customTopRadius ?? 28
            }
        } else if dragOffsetY > 0 {
            // ¡Al arrastrar hacia abajo se redondea progresivamente a PÍLDORA flotante continua!
            return min(dragOffsetY * 0.9, 18.0)
        } else {
            return 0
        }
    }
    
    var bottomRadius: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedBottomRadius
        } else if agentProvider.isProgressHUDExpanded {
            return 28
        } else if activityCenter.expandedActivity?.kind == .claude {
            return ClaudeActivityProvider.cardCornerRadius
        } else if activityCenter.expandedActivity != nil {
            return activityCenter.customBottomRadius ?? 32
        } else if appState.isDropInvitationActive {
            return 42
        } else if let activity = activityCenter.currentActivity {
            if activityCenter.dismissingActivityId == activity.id {
                return 17
            }
            switch activity.style {
            case .pill, .sliderPill, .airpodsPill:
                return 17
            case .card:
                if notificationProvider.isNotificationActive && activity.id.hasPrefix("notification_") {
                    return notificationProvider.isQuickReplyExpanded
                        ? NotificationActivityProvider.expandedBottomRadius
                        : NotificationActivityProvider.compactBottomRadius
                }
                if activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress") || (agentProvider.isActive && activity.id.hasPrefix("agent_")) {
                    if activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress") || agentProvider.currentProgressPayload != nil {
                        return 28
                    }
                    return agentProvider.isExpanded
                        ? AgentActivityProvider.expandedBottomRadius
                        : AgentActivityProvider.compactBottomRadius
                }
                return activityCenter.customBottomRadius ?? 32
            }
        } else if dragOffsetY > 0 {
            return 17.0 + min(dragOffsetY * 0.15, 3.0)
        } else {
            return 17
        }
    }
    
    var totalOffsetY: CGFloat {
        dragOffsetY + appState.trackpadDragOffsetY
    }
    
    var hasDownPull: Bool {
        totalOffsetY > 0
    }

    var activeExpandedHeight: CGFloat {
        let notifPull = notificationProvider.isNotificationActive ? notificationProvider.dragPullOffset : 0
        return currentHeight + notifPull
    }
    
    /// Sangrado superior de la silueta mientras está pegada al bisel (ver ElasticPillShape.topBleed).
    /// Si la isla se despega hacia abajo, se anula para no asomar por encima.
    var shapeTopBleed: CGFloat {
        // Flotando no hay borde contra el que sangrar
        !isFloatingIsland && containerOffsetY <= 0.5 ? 2.0 : 0.0
    }
    
    /// Isla flotante sin nada que mostrar y el usuario la quiere oculta en reposo
    var isHiddenAtRest: Bool {
        isFloatingIsland && !appState.islandVisibleAtRest && appState.mode == .idle
            && activityCenter.currentActivity == nil && activityCenter.secondaryActivities.isEmpty
            && activityCenter.expandedActivity == nil && !appState.isHovered && !appState.isDropInvitationActive
    }
    
    var containerOffsetY: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return 0 // Anclado arriba contra el notch físico: solo se estira hacia abajo sin separarse
        } else {
            return totalOffsetY
        }
    }
    
    // Escala reactiva: si presiona (squash & stretch), si mantiene cursor encima (expansión continua tipo Dynamic Island), si no 1.0
    var scaleX: CGFloat {
        baseScaleX * activityCenter.islandJiggle
    }
    
    var baseScaleX: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded && appState.mode != .shelf {
            return NotchTuning.pressScaleX
        } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil && !isCollapsing {
            // Mientras se cierra no aplica la expansión de hover: si el cursor sigue encima, el notch crecía a
            // media contracción (el "espasmo")
            return appState.heartbeatScaleX
        }
        return 1.0
    }
    
    /// La isla reacciona a la gota que se suelta o llega: se estira a lo ancho y se aplana un poco (volumen
    /// constante), y rebota casi imperceptible
    var scaleY: CGFloat {
        baseScaleY * (1 - (activityCenter.islandJiggle - 1) * 0.6)
    }
    
    var baseScaleY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded && appState.mode != .shelf {
            return NotchTuning.pressScaleY
        } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil && !isCollapsing {
            return appState.heartbeatScaleY
        }
        return 1.0
    }
    
    // Sombra suave en anticipación, fija y profunda en hover de Dynamic Island, Live Activities o fija en expandido/bandeja
    var shadowRadius: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowRadius
        } else if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedShadowRadius
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .card:
                return 32
            case .sliderPill, .airpodsPill, .pill:
                return 22
            }
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return 22
        } else if appState.mode == .compact {
            return 14
        }
        return 8
    }
    
    var shadowOpacity: Double {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowOpacity
        } else if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedShadowOpacity
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .card:
                return 0.55
            case .sliderPill, .airpodsPill, .pill:
                return 0.48
            }
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return appState.heartbeatShadowOpacity
        } else if appState.mode == .compact {
            return 0.35
        }
        return 0.20
    }
    
    var shadowY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowY
        } else if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedShadowY
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .card:
                return 12
            case .sliderPill, .airpodsPill, .pill:
                return 7
            }
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return 8
        } else if appState.mode == .compact {
            return 5
        }
        return 3
    }
    
    
    /// Color de la keyline (nil = sin keyline): actividad principal, tarjeta abierta o la carátula de la música
    var keylineColor: Color? {
        guard appState.keylineEnabled, backdropMonitor.isSystemDarkMode, appState.effectiveAppearanceMode == .pureOLED else { return nil }
        if let activity = activityCenter.expandedActivity ?? activityCenter.currentActivity {
            return activity.tint
        }
        let showsMusic = (appState.mode == .compact && !appState.isHoldingBareNotch && !appState.isCompactMinimized)
            || appState.mode == .expanded
        if showsMusic, let artwork = musicService.currentTrack.artwork {
            return ArtworkGradientCache.colors(for: artwork).top
        }
        return nil
    }
    
    /// Cambia cada vez que el notch se transforma (abre/cierra, cambia de página, de tarjeta o de actividad)
    var morphKey: String {
        // Reproductor y repisa cuentan como la misma "página abierta": cambiar entre ellas no desenfoca
        let page = (appState.mode == .expanded || appState.mode == .shelf) ? "open" : "\(appState.mode)"
        return "\(page)|\(appState.isPlayerDetailExpanded)|\(activityCenter.expandedActivity?.id ?? "-")|\(activityCenter.currentActivity?.id ?? "-")|\(agentProvider.isProgressHUDExpanded)"
    }
    
    /// El notch muestra su superficie desplegada (vidrio en los modos de cristal, negro en OLED)
    var isSurfaceExpanded: Bool {
        appState.mode == .expanded || appState.mode == .shelf || isCollapsing || appState.isDropInvitationActive || (activityCenter.currentActivity?.style == .card) || agentProvider.isProgressHUDExpanded || activityCenter.expandedActivity != nil
    }
    
    /// Modo de cristal activo: las bolitas son siempre gotas de Liquid Glass. El notch cerrado sigue negro
    /// porque tiene que fundirse con la cámara física; desplegado, es del mismo vidrio que las bolitas.
    var isGlassSurfaceVisible: Bool {
        appState.effectiveAppearanceMode != .pureOLED
    }
    
    var snapStretch: CGFloat {
        (appState.mode == .expanded || appState.mode == .shelf)
            ? OverscrollMetrics.snapToZeroIfMinimal(appState.overscrollOffset)
            : 0
    }
    
    var cardExpandedWidth: CGFloat {
        currentWidth + abs(snapStretch)
    }
    
    var cardOffsetX: CGFloat {
        snapStretch / 2.0 + attachedOffsetX
    }
    
    var cardExpandedHeight: CGFloat {
        let absS = abs(snapStretch)
        let maxS = max(1.0, OverscrollMetrics.maxStretch)
        let heightFactor = 1.0 - (min(absS, maxS) / maxS) * OverscrollMetrics.heightShortenPercent
        return (activeExpandedHeight + appState.verticalOverscrollOffset) * heightFactor
    }
    
    var containerPillShape: ElasticPillShape {
        var shape = ElasticPillShape(
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            stretch: 0,
            verticalStretch: 0
        )
        // El tamaño viaja en la forma (animable): fondo, borde y recorte del contenido siguen la misma curva
        shape.surfaceSize = CGSize(width: cardExpandedWidth, height: cardExpandedHeight)
        return shape
    }
    
    var morphSpring: Animation {
        speedManager.spring(
            response: ExitAnimationMetrics.sliderDismissResponse,
            dampingFraction: ExitAnimationMetrics.sliderDismissDamping
        )
    }
    
    var currentShapeSpring: Animation {
        if appState.isDropInvitationActive {
            return speedManager.spring(
                response: ExitAnimationMetrics.cardOpenResponse,
                dampingFraction: ExitAnimationMetrics.cardOpenDamping
            )
        } else if appState.mode == .expanded || appState.mode == .shelf {
            return speedManager.spring(
                response: ExitAnimationMetrics.shapeOpenResponse,
                dampingFraction: ExitAnimationMetrics.shapeOpenDamping
            )
        } else if isCollapsing {
            return speedManager.spring(
                response: ExitAnimationMetrics.compactMorphResponse,
                dampingFraction: ExitAnimationMetrics.compactMorphDamping
            )
        } else if let activity = activityCenter.currentActivity ?? activityCenter.lastDismissedActivity, activity.style == .card {
            let isDismissing = activityCenter.dismissingActivityId != nil
            return speedManager.spring(
                response: isDismissing ? ExitAnimationMetrics.cardDismissResponse : ExitAnimationMetrics.cardOpenResponse,
                dampingFraction: isDismissing ? ExitAnimationMetrics.cardDismissDamping : ExitAnimationMetrics.cardOpenDamping
            )
        } else if let activity = activityCenter.currentActivity, activityCenter.dismissingActivityId == nil,
                  activity.style == .airpodsPill || (activity.style == .pill && activity.customView != nil) {
            // Como la Isla del iPhone al conectar los AirPods o el cargador: se abre a los lados con un rebote
            // elástico (el volumen y el brillo siguen sin rebote)
            return speedManager.spring(response: 0.46, dampingFraction: 0.7)
        } else if activityCenter.currentActivity != nil || activityCenter.dismissingActivityId != nil {
            return speedManager.spring(
                response: ExitAnimationMetrics.sliderDismissResponse,
                dampingFraction: ExitAnimationMetrics.sliderDismissDamping
            )
        } else {
            return speedManager.spring(
                response: ExitAnimationMetrics.sliderDismissResponse,
                dampingFraction: ExitAnimationMetrics.sliderDismissDamping
            )
        }
    }
    
    // Gesto de presión y arrastre hacia abajo con desenfoque (blur) tipo iPhone Dynamic Island
}
