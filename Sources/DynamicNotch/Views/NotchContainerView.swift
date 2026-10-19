import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notch Physics & Animation Tuning
public struct NotchTuning {
    // 1) FASE PRESIONAR (Mouse Down) - Anticipación elástica física sutil
    public static let pressScaleX: CGFloat = 1.040              // Más sutil para no generar saltos bruscos
    public static let pressScaleY: CGFloat = 0.975              // Compresión vertical suave
    public static let pressShadowRadius: CGFloat = 18           // Sombra difusa debajo
    public static let pressShadowOpacity: Double = 0.42         // Opacidad suave
    public static let pressShadowY: CGFloat = 6                 // Desplazamiento vertical de la sombra
    public static let pressSpring = Animation.spring(response: 0.26, dampingFraction: 0.74)
    
    // 2) FASE SOLTAR (Mouse Up) - Expansión completa (MUCHO MÁS SMOOTH, sin golpe ni rebote brusco)
    public static let expandSpring = Animation.spring(response: 0.52, dampingFraction: 0.90)
    public static let expandedWidth: CGFloat = PlayerMetrics.cardWidth              // Ancho de la píldora expandida (420 pt)
    public static let expandedHeight: CGFloat = PlayerMetrics.cardHeight            // Alto de la píldora expandida (190 pt)
    public static let expandedTopRadius: CGFloat = PlayerMetrics.cornerRadius       // Curvatura superior (56 pt continuo)
    public static let expandedBottomRadius: CGFloat = PlayerMetrics.cornerRadius    // Curvatura inferior (56 pt continuo)
    public static let expandedShadowRadius: CGFloat = PlayerMetrics.shadowRadius    // Sombra de la isla abierta (30 pt)
    public static let expandedShadowOpacity: Double = PlayerMetrics.shadowOpacity   // Opacidad sombra abierta (0.50)
    public static let expandedShadowY: CGFloat = PlayerMetrics.shadowY              // Desplazamiento Y sombra abierta (12 pt)
    
    // Delays escalonados progresivos y suaves
    public static let stage1Delay: Double = 0.16               // Carátula, título, artista, ecualizador
    public static let stage2Delay: Double = 0.26               // Barra de progreso y tiempos
    public static let stage3Delay: Double = 0.36               // Controles de reproducción
    public static let stage4Delay: Double = 0.46               // Cápsulas inferiores flotantes
    public static let contentInSpring = Animation.spring(response: 0.52, dampingFraction: 0.88)
    
    // 3) FASE CERRAR / Contracción inversa
    public static let contentFadeOutDuration: Double = 0.12    // El contenido se desvanece primero
    public static let collapseSpring = Animation.spring(response: 0.62, dampingFraction: 0.86)
    
    // 4) FASE CANCELAR (arrastrar mouse fuera del notch)
    public static let dragCancelThresholdX: CGFloat = 45       // Umbral horizontal para cancelar
    public static let dragCancelThresholdY: CGFloat = 45       // Umbral vertical para cancelar
    public static let cancelSpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    
    // 5) ALAS COMPACTAS (música): ancho ajustado al contenido. La carátula (19 pt) y las barras (~21 pt) quedan
    //    con ~11 pt de margen a cada lado; el resto del ancho es la cámara, que no se puede reducir
    public static let compactWingWidth: CGFloat = 42
    public static let compactWingsExtraWidth: CGFloat = compactWingWidth * 2
    /// Mínima pegada (varias actividades): sólo el ala izquierda, más angosta; en ancho limitado (3 a la vista)
    /// todavía más, como el círculo de 28 pt de la Isla Dinámica
    public static let minimalWingWidth: CGFloat = 34
    public static let minimalWingLimitedWidth: CGFloat = 30
}

public enum NotchInteractionState: Equatable {
    case collapsed
    case pressed
    case expanded
}

public struct NotchContainerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenService: ScreenService
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var batteryService: BatteryService
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var activityCenter = ActivityCenter.shared
    @ObservedObject var notificationProvider = NotificationActivityProvider.shared
    @ObservedObject var agentProvider = AgentActivityProvider.shared
    @ObservedObject var speedManager = AnimationSpeedManager.shared
    @ObservedObject var glassManager = GlassClearManager.shared
    @Namespace private var notchNamespace
    
    @State private var interactionState: NotchInteractionState = .collapsed
    @State private var animStage1: Bool = false
    @State private var animStage2: Bool = false
    @State private var animStage3: Bool = false
    @State private var isFileDragTargeted: Bool = false
    @State private var isTransitioningFromActivity: Bool = false
    
    // Estados de salida escalonada (Exit Animation con Springs)
    @State private var isCollapsing: Bool = false
    @State private var controlsExiting: Bool = false
    @State private var progressExiting: Bool = false
    @State private var topRowExiting: Bool = false
    @State private var hoverExitTimer: Timer? = nil
    
    // Gesto de arrastre hacia abajo con desenfoque (blur) estilo iPhone Dynamic Island
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragBlur: CGFloat = 0
    @State private var dragScaleY: CGFloat = 1.0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var lastCardCollapseDetailTime: Date = Date.distantPast
    @State private var detailDragCount: Int = 0
    @State private var lastDetailDragTime: Date = Date.distantPast
    @State private var hasTriggeredHapticInSwipe: Bool = false
    @State private var hasSwitchedPageInCurrentDrag: Bool = false
    @State private var isMouseInsideWidget: Bool = false
    
    private enum DragLockAxis {
        case none
        case horizontal
        case vertical
    }
    @State private var dragLockAxis: DragLockAxis = .none
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    private var baseRestingWidth: CGFloat {
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
    private var currentWidth: CGFloat {
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
    private var isMinimalAttached: Bool {
        appState.minimalAttachedEnabled
            && appState.mode == .compact && !appState.isHoldingBareNotch && !appState.isCompactMinimized
            && activityCenter.currentActivity == nil && activityCenter.expandedActivity == nil
            && !activityCenter.secondaryActivities.isEmpty
            && !appState.isDropInvitationActive && !agentProvider.isProgressHUDExpanded
    }
    
    private var minimalWingWidth: CGFloat {
        activityCenter.isLimitedWidth ? NotchTuning.minimalWingLimitedWidth : NotchTuning.minimalWingWidth
    }
    
    /// Bolita en su lugar. La identidad incluye el lado: si cambia de lado (swipe a lo ancho) se reabsorbe en
    /// el notch de un lado y brota del otro en vez de cruzar por encima de la isla (guía de Apple: mejor salir
    /// y volver a entrar que encimarse)
    private struct SatelliteSlot {
        let activity: LiveActivity
        let index: Int
        let isLeft: Bool
        var key: String { "\(activity.id)|\(isLeft ? "L" : "R")" }
    }
    
    private func satelliteSlots(bothSides: Bool) -> [SatelliteSlot] {
        activityCenter.secondaryActivities.enumerated().map { index, activity in
            // El lado lo guarda ActivityCenter (estable); por si aún no está, el orden
            let placement = activityCenter.satelliteLayout[activity.id]
                ?? SatellitePlacement(isLeft: bothSides && index == 1, slotIndex: bothSides ? 0 : index)
            return SatelliteSlot(activity: activity, index: placement.slotIndex, isLeft: placement.isLeft)
        }
    }
    
    /// La mínima pegada sólo crece hacia la izquierda: la forma se corre para que la cámara quede en su lugar
    private var attachedOffsetX: CGFloat {
        isMinimalAttached ? -minimalWingWidth / 2 : 0
    }
    
    // Alto: altura del notch en reposo, 36pt en SliderPill, altura del notch en alas de AirPods, 144pt en Drop Invitation, 204pt en repisa, 196pt en reproductor
    private var currentHeight: CGFloat {
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
    private var topRadius: CGFloat {
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
    
    private var bottomRadius: CGFloat {
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
    
    private var totalOffsetY: CGFloat {
        dragOffsetY + appState.trackpadDragOffsetY
    }
    
    private var hasDownPull: Bool {
        totalOffsetY > 0
    }

    private var activeExpandedHeight: CGFloat {
        let notifPull = notificationProvider.isNotificationActive ? notificationProvider.dragPullOffset : 0
        return currentHeight + notifPull
    }
    
    /// Sangrado superior de la silueta mientras está pegada al bisel (ver ElasticPillShape.topBleed).
    /// Si la isla se despega hacia abajo, se anula para no asomar por encima.
    private var shapeTopBleed: CGFloat {
        containerOffsetY <= 0.5 ? 2.0 : 0.0
    }
    
    private var containerOffsetY: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return 0 // Anclado arriba contra el notch físico: solo se estira hacia abajo sin separarse
        } else {
            return totalOffsetY
        }
    }
    
    // Escala reactiva: si presiona (squash & stretch), si mantiene cursor encima (expansión continua tipo Dynamic Island), si no 1.0
    private var scaleX: CGFloat {
        baseScaleX * activityCenter.islandJiggle
    }
    
    private var baseScaleX: CGFloat {
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
    private var scaleY: CGFloat {
        baseScaleY * (1 - (activityCenter.islandJiggle - 1) * 0.6)
    }
    
    private var baseScaleY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded && appState.mode != .shelf {
            return NotchTuning.pressScaleY
        } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil && !isCollapsing {
            return appState.heartbeatScaleY
        }
        return 1.0
    }
    
    // Sombra suave en anticipación, fija y profunda en hover de Dynamic Island, Live Activities o fija en expandido/bandeja
    private var shadowRadius: CGFloat {
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
    
    private var shadowOpacity: Double {
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
    
    private var shadowY: CGFloat {
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
    
    @ObservedObject private var backdropMonitor = BackdropBrightnessMonitor.shared
    
    /// Color de la keyline (nil = sin keyline): actividad principal, tarjeta abierta o la carátula de la música
    private var keylineColor: Color? {
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
    private var morphKey: String {
        // Reproductor y repisa cuentan como la misma "página abierta": cambiar entre ellas no desenfoca
        let page = (appState.mode == .expanded || appState.mode == .shelf) ? "open" : "\(appState.mode)"
        return "\(page)|\(appState.isPlayerDetailExpanded)|\(activityCenter.expandedActivity?.id ?? "-")|\(activityCenter.currentActivity?.id ?? "-")|\(agentProvider.isProgressHUDExpanded)"
    }
    
    /// El notch muestra su superficie desplegada (vidrio en los modos de cristal, negro en OLED)
    private var isSurfaceExpanded: Bool {
        appState.mode == .expanded || appState.mode == .shelf || isCollapsing || appState.isDropInvitationActive || (activityCenter.currentActivity?.style == .card) || agentProvider.isProgressHUDExpanded || activityCenter.expandedActivity != nil
    }
    
    /// Modo de cristal activo: las bolitas son siempre gotas de Liquid Glass. El notch cerrado sigue negro
    /// porque tiene que fundirse con la cámara física; desplegado, es del mismo vidrio que las bolitas.
    private var isGlassSurfaceVisible: Bool {
        appState.effectiveAppearanceMode != .pureOLED
    }
    
    public var body: some View {
        // Sin GlassEffectContainer alrededor: el contenedor dibuja todo el vidrio en una pasada por ENCIMA de
        // los hermanos, y el reproductor quedaba borroso debajo de la superficie (probado en macOS 27)
        notchContainerContent
            .environment(\.notchGlassSurfaceVisible, isGlassSurfaceVisible)
            .onPreferenceChange(NotchHitRegionsKey.self) { regions in
                NotchWindowManager.shared.updateDynamicHitRegions(regions)
            }
    }
    
    private var snapStretch: CGFloat {
        (appState.mode == .expanded || appState.mode == .shelf)
            ? OverscrollMetrics.snapToZeroIfMinimal(appState.overscrollOffset)
            : 0
    }
    
    private var cardExpandedWidth: CGFloat {
        currentWidth + abs(snapStretch)
    }
    
    private var cardOffsetX: CGFloat {
        snapStretch / 2.0 + attachedOffsetX
    }
    
    private var cardExpandedHeight: CGFloat {
        let absS = abs(snapStretch)
        let maxS = max(1.0, OverscrollMetrics.maxStretch)
        let heightFactor = 1.0 - (min(absS, maxS) / maxS) * OverscrollMetrics.heightShortenPercent
        return (activeExpandedHeight + appState.verticalOverscrollOffset) * heightFactor
    }
    
    private var containerPillShape: ElasticPillShape {
        ElasticPillShape(
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            stretch: 0,
            verticalStretch: 0
        )
    }
    
    @ViewBuilder
    private var topNotchCloseZone: some View {
        if activityCenter.expandedActivity != nil {
            Color.clear
                .frame(width: geometry.width, height: geometry.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    activityCenter.collapseExpandedActivity()
                }
        } else if agentProvider.isProgressHUDExpanded {
            Color.clear
                .frame(width: geometry.width, height: geometry.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    agentProvider.collapseProgressHUD()
                }
        } else if appState.mode == .expanded || appState.mode == .shelf {
            Color.clear
                .frame(width: geometry.width, height: geometry.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    performCollapse()
                }
        } else if let activity = activityCenter.currentActivity, activity.style == .card && activity.customView == nil {
            Color.clear
                .frame(width: max(geometry.width, 180), height: max(geometry.height, 36))
                .contentShape(Rectangle())
                .onTapGesture {
                    activity.onTap?()
                }
        }
    }
    
    @ViewBuilder
    private func expandedActivityContentView(_ expandedAct: LiveActivity) -> some View {
        if let customExpanded = expandedAct.expandedView {
            customExpanded
        } else if expandedAct.kind == .agentAI {
            AgentLiveProgressView()
        } else if let customView = expandedAct.customView {
            customView
        } else {
            // Plantilla de Apple: regiones alrededor de la cámara, márgenes concéntricos y alto según el contenido
            DefaultActivityExpandedView(activity: expandedAct)
        }
    }
    
    @ViewBuilder
    private var idleContentView: some View {
        // La repisa se representa con su bolita: el notch en reposo queda limpio
        if false {
            HStack(spacing: 0) {
                // Ala izquierda simétrica (44 pt): Miniatura o icono del archivo
                ZStack {
                    if let item = appState.shelfItems.first {
                        if item.isImage {
                            Image(nsImage: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 17, height: 17)
                                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                        } else {
                            Image(nsImage: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        .fill(DesignTokens.blue.opacity(0.18))
                                )
                        }
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(DesignTokens.blue)
                    }
                }
                .frame(width: 48, height: currentHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    performExpand()
                }
                
                // Zona central del sensor de cámara (centrado exacto sobre el hardware)
                Color.clear
                    .frame(width: geometry.width, height: currentHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        performExpand()
                    }
                
                // Ala derecha simétrica (48 pt): Bandeja parpadeante con pulso radar
                ActiveFileBadgeView()
                    .frame(width: 48, height: currentHeight)
            }
            .frame(width: currentWidth, height: currentHeight)
        } else {
            Color.clear
                .frame(width: currentWidth, height: currentHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    performExpand()
                }
        }
    }
    
    @ViewBuilder
    private var mainModeContentView: some View {
        if let expandedAct = activityCenter.expandedActivity {
            expandedActivityContentView(expandedAct)
                .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                ))
        } else if agentProvider.isProgressHUDExpanded {
            AgentLiveProgressView()
                .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                ))
        } else if appState.mode == .expanded {
            NotchPlayerView(
                namespace: notchNamespace,
                animStage1: animStage1,
                animStage2: animStage2,
                animStage3: animStage3,
                controlsExiting: controlsExiting,
                progressExiting: progressExiting,
                topRowExiting: topRowExiting
            )
            .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
            .transition(.opacity)
        } else if appState.mode == .shelf {
            NotchShelfView()
                .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                ))
                .id("notchShelfView")
        } else if activityCenter.currentActivity != nil {
            // Live Activity activa (Pill / SliderPill / Card): Máxima prioridad, nunca es desplazada por el reproductor
            LiveActivityContainerView()
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
                .transition(.opacity)
        } else if appState.isDropInvitationActive {
            NotchDropInvitationView()
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
                .transition(.opacity)
        } else {
            switch appState.mode {
            case .idle:
                idleContentView
            case .compact:
                if appState.isHoldingBareNotch || appState.isCompactMinimized {
                    Color.clear
                        .frame(width: currentWidth, height: currentHeight)
                } else {
                    NotchCompactView(namespace: notchNamespace, minimalWingWidth: isMinimalAttached ? minimalWingWidth : nil)
                        .frame(width: currentWidth, height: currentHeight)
                        .blur(radius: dragBlur)
                        .opacity(isTransitioningFromActivity ? 0.0 : 1.0)
                        .transition(.opacity)
                }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var notchContainerContent: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                // Píldora Principal (#000 puro, anclada arriba contra la cámara o Liquid Glass)
                ZStack(alignment: .top) {
                    // Fondo reactivo: Negro Puro OLED o Cristal Líquido (Liquid Glass)
                    DynamicNotchBackgroundView(
                        topRadius: topRadius,
                        bottomRadius: bottomRadius,
                        isLiquidGlass: appState.isLiquidGlassEnabled,
                        darknessOpacity: appState.glassDarknessOpacity,
                        stretch: 0,
                        verticalStretch: 0,
                        isExpanded: isSurfaceExpanded,
                        topBleed: shapeTopBleed,
                        trailingImpulse: activityCenter.pillImpulse,
                        cameraCenterOffset: -attachedOffsetX,
                        // Al cerrar, el vidrio se disuelve mientras la forma se encoge (antes se quedaba gris
                        // alrededor del centro negro y desaparecía de golpe al final)
                        // Si al cerrar quedan alas de cristal (música), el vidrio se queda: la forma se encoge hasta ellas
                        isDissolving: isCollapsing && activityCenter.expandedActivity == nil
                            && !(appState.glassWingsEnabled && appState.shouldShowCompact)
                    )
                    .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                    // Keyline de la Isla Dinámica: en modo oscuro, un borde fino del color de lo que se muestra
                    // la separa del contenido oscuro de detrás (sólo en negro OLED y con algo en el notch)
                    .overlay(alignment: .top) {
                        if let keyline = keylineColor {
                            containerPillShape
                                .stroke(keyline.opacity(0.42), lineWidth: 1)
                                .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: keylineColor != nil)
                    
                    mainModeContentView
                        // Estándar: el contenido se desenfoca un instante mientras la forma se transforma.
                        // Primero el desenfoque y DESPUÉS el recorte: el desenfoque nunca se sale de la forma
                        .morphBlur(on: morphKey, hold: appState.gestureBlurHold)
                        .clipShape(containerPillShape)
                    
                    // Zona táctil superior en el notch para cerrar al hacer click en el notch
                    topNotchCloseZone
                }
                .environment(\.colorScheme, .dark)
                .contentShape(containerPillShape)
            // MARCO PRIMARIO: Se fija el ancho y alto del contenedor simétricamente.
            // CRÍTICO PARA LIQUID GLASS: No aplicar .clipShape ni .shadow(radius > 0) al ZStack padre cuando
            // Liquid Glass está desplegado, pues CoreAnimation crea un grupo de rasterización offscreen que
            // aísla el CABackdropLayer del WindowServer y recorta el borde especular de .glassEffect(_:in:).
            .frame(
                width: cardExpandedWidth,
                height: cardExpandedHeight,
                alignment: .top
            )
            .offset(x: cardOffsetX + activityCenter.islandRecoil)
            // Sombra Multicapa (Ambient + Key): activa únicamente en Negro Puro OLED.
            // En Liquid Glass tanto la opacidad como el radio son 0.0 SIEMPRE para evitar pases offscreen en Metal.
            .shadow(
                color: Color.black.opacity(
                    (appState.effectiveAppearanceMode != .pureOLED)
                        ? 0.0
                        : ((shadowOpacity * 0.42) + (hasDownPull ? 0.14 : 0.0))
                ),
                radius: (appState.effectiveAppearanceMode != .pureOLED)
                    ? 0.0
                    : ((shadowRadius * 0.38) + (hasDownPull ? 4 : 0)),
                x: 0,
                y: (appState.effectiveAppearanceMode != .pureOLED)
                    ? 0.0
                    : ((shadowY * 0.45) + totalOffsetY * 0.2)
            )
            .shadow(
                color: Color.black.opacity(
                    (appState.effectiveAppearanceMode != .pureOLED)
                        ? 0.0
                        : (shadowOpacity + (hasDownPull ? 0.22 : 0.0))
                ),
                radius: (appState.effectiveAppearanceMode != .pureOLED)
                    ? 0.0
                    : (shadowRadius + (hasDownPull ? 10 : 0)),
                x: 0,
                y: (appState.effectiveAppearanceMode != .pureOLED)
                    ? 0.0
                    : (shadowY + totalOffsetY * 0.4)
            )
            // Sombra exterior desacoplada para Cristal Líquido (solo fuera de la silueta sin ralentizar Metal)
            .background(
                Group {
                    if appState.effectiveAppearanceMode != .pureOLED && glassManager.showCardShadow {
                        let isCardOpen = (appState.mode == .expanded || appState.mode == .shelf || isCollapsing || appState.isDropInvitationActive || activityCenter.currentActivity?.style == .card)
                        let pill = ElasticPillShape(
                            topRadius: topRadius,
                            bottomRadius: bottomRadius,
                            stretch: 0,
                            verticalStretch: 0
                        )
                        pill
                            .fill(Color.black.opacity(0.001))
                            .shadow(
                                color: Color.black.opacity(isCardOpen ? (GlassClearMetrics.cardShadowOpacity * 0.45) : (shadowOpacity * 0.35)),
                                radius: isCardOpen ? 18 : (shadowRadius * 0.5),
                                x: 0,
                                y: isCardOpen ? GlassClearMetrics.cardShadowY : (shadowY * 0.5)
                            )
                    }
                    
                    // Patrón de prueba de líneas y texto para diagnosticar refracción de borde (Paso 1)
                    if glassManager.showRefractionTestPattern {
                        StripedTestPatternView()
                            .frame(width: cardExpandedWidth + 60, height: cardExpandedHeight + 40)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .offset(y: -10)
                    }
                }
            )
            .offset(y: containerOffsetY)
            .scaleEffect(x: scaleX, y: scaleY * dragScaleY, anchor: .top)
            // Cierre interactivo: la tarjeta se recoge hacia el notch siguiendo los dedos (más alto que ancho,
            // como si se guardara en la cámara) y su contenido se apaga un poco
            .scaleEffect(
                x: 1 - 0.22 * appState.interactiveCollapseProgress,
                y: 1 - 0.52 * appState.interactiveCollapseProgress,
                anchor: .top
            )
            .contentShape(containerPillShape)
            // Gesto de presión con anticipación en 3 fases cuando está colapsado y no hay actividad activa
            .modifier(PillGestureModifier(
                isEnabled: appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil,
                gesture: pillPressGesture
            ))
            .onTapGesture {
                if appState.mode == .expanded || appState.mode == .shelf {
                    // Ya está expandido: no colapsar al hacer click dentro del contenido de la tarjeta
                    return
                } else if notificationProvider.isNotificationActive {
                    if !notificationProvider.isQuickReplyExpanded {
                        notificationProvider.expandQuickReply()
                    }
                } else if activityCenter.currentActivity != nil {
                    activityCenter.handleTap()
                } else {
                    performExpand()
                }
            }
            // Gesto horizontal con rebote elástico (rubber-band bounce) entre los dos menús
            .modifier(PillGestureModifier(
                isEnabled: (appState.mode == .expanded || appState.mode == .shelf) && activityCenter.expandedActivity == nil,
                gesture: cardSwipeGesture
            ))
            // Gesto de arrastre vertical hacia arriba para guardar / colapsar tarjeta de stats expandida
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if (activityCenter.expandedActivity != nil || agentProvider.isProgressHUDExpanded) && value.translation.height < -12 {
                            DNDLogger.log("NotchContainerView -> Drag UP detectado en tarjeta expandida! Contrayendo...")
                            activityCenter.collapseExpandedActivity()
                            agentProvider.collapseProgressHUD()
                            AppState.shared.hapticService.triggerSnap()
                        }
                    }
            )
            .onHover { isHovering in
                let wasHovered = isMouseInsideWidget
                isMouseInsideWidget = isHovering
                
                if (appState.mode == .expanded || appState.mode == .shelf) && appState.autoCollapseOnHoverExit {
                    if wasHovered && !isHovering {
                        // Inicia timer de ~0.6 s al salir del widget
                        hoverExitTimer?.invalidate()
                        let delay = speedManager.adjustedDuration(ExitAnimationMetrics.hoverExitDelay)
                        hoverExitTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                            DispatchQueue.main.async {
                                if (appState.mode == .expanded || appState.mode == .shelf) && appState.autoCollapseOnHoverExit && !self.isMouseInsideWidget {
                                    performCollapse()
                                }
                            }
                        }
                    } else if isHovering {
                        // El cursor regresó al widget: cancela el timer
                        hoverExitTimer?.invalidate()
                        hoverExitTimer = nil
                    }
                } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil {
                    // Expansión suave sostenida con sombra fija mientras el cursor permanece sobre la Dynamic Island
                    appState.setHoverState(isHovering)
                } else if !isHovering {
                    appState.setHoverState(false)
                }
            }
            .animation(NotchTuning.pressSpring, value: interactionState)
            .animation(currentShapeSpring, value: appState.mode)
            .animation(currentShapeSpring, value: currentWidth)
            .animation(currentShapeSpring, value: currentHeight)
            .animation(currentShapeSpring, value: topRadius)
            .animation(currentShapeSpring, value: bottomRadius)
            .animation(.spring(response: 0.38, dampingFraction: 0.80), value: notificationProvider.isQuickReplyExpanded)
            
            Spacer()
        }
        
        // MARK: - Bolitas Satélite de Live Activities y Coordinador de Fusión
        if activityCenter.expandedActivity == nil {
            let bolitaDiam = appState.effectiveBolitaDiameter
            let gap = appState.bolitaGap
            // Lugares fijos, como la Isla Dinámica: [0] a la derecha, [1] a la izquierda (o segunda a la derecha si
            // el usuario las quiere de un solo lado). El orden lo mantiene estable PresentationEngine.
            let bothSides = appState.bubblesOnBothSides
            
            // Cada bolita se une al notch con un cuello líquido (LiquidSatelliteModifier): brota de él al
            // aparecer, se funde al tocarla (fusionProgress) y se reabsorbe al desaparecer.
            // Bordes VISIBLES del notch: incluyen la expansión al pasar el cursor y el "apretón" al presionar
            // (scaleEffect anclado arriba) y el corrimiento de la mínima pegada, para que las bolitas se aparten
            // y no queden tapadas
            let visibleHalfWidth = cardExpandedWidth * scaleX / 2.0
            let visibleHeight = geometry.height * scaleY
            let notchRadius = visibleHeight / 2.0
            let rightEdge = attachedOffsetX + visibleHalfWidth
            let leftEdge = attachedOffsetX - visibleHalfWidth
            // Al pasar el cursor sólo crece el notch: la bolita se queda donde estaba (independiente) y se hace
            // un poco más pequeña, cediéndole protagonismo. Si el notch creciera mucho, nunca la toca (≥ 3 pt).
            let isNotchHovered = scaleX > 1.001 && interactionState != .pressed && appState.bubbleShrinksOnNotchHover
            let restRight = max(attachedOffsetX + cardExpandedWidth / 2.0, rightEdge + 3 - gap)
            let restLeft = min(attachedOffsetX - cardExpandedWidth / 2.0, leftEdge - 3 + gap)
            let bubbleOffsetY = max(0, (geometry.height - bolitaDiam) / 2.0)
            // En cristal el cuello también existe: se dibuja como parte de la gota de vidrio (LiquidSatelliteModifier)
            let showsBridge = appState.mode != .expanded && appState.mode != .shelf
            // La identidad incluye el lado (ver SatelliteSlot)
            // Colocación de una bolita según su lugar (también para las que se están reabsorbiendo)
            // Lugar en su lado: 0 = pegado al notch (con cuello líquido), 1 = segunda a la derecha
            let placementFor: (Bool, Int, Bool) -> LiquidSatelliteModifier = { isLeft, slotIndex, isFusingThis in
                return LiquidSatelliteModifier(
                    merge: isFusingThis ? activityCenter.fusionProgress : 0,
                    restingX: isLeft
                        ? restLeft - gap - (bolitaDiam / 2.0)
                        : restRight + gap + (bolitaDiam / 2.0) + (CGFloat(slotIndex) * (bolitaDiam + 8)),
                    // El cuello nace del borde real, que del lado derecho se recoge o abulta con la física
                    notchEndX: isLeft
                        ? leftEdge + notchRadius
                        : rightEdge + (slotIndex == 0 ? activityCenter.pillImpulse : 0) - notchRadius,
                    notchRadius: notchRadius,
                    bubbleDiameter: bolitaDiam,
                    offsetY: bubbleOffsetY,
                    showsBridge: showsBridge && slotIndex == 0,
                    isGlass: isGlassSurfaceVisible
                )
            }
            
            // Las que se van: se reabsorben en el notch del lado donde estaban (sin zona de clic)
            ForEach(activityCenter.departingSatellites) { departing in
                LiquidSatelliteHost(placement: placementFor(departing.placement.isLeft, departing.placement.slotIndex, false),
                                    phase: departing.fades ? .fading : .departing, animated: !reduceMotion) {
                    NotchBolitaView(activity: departing.activity, side: departing.placement.isLeft ? .left : .right)
                        .allowsHitTesting(false)
                }
                .zIndex(99)
            }
            
            ForEach(satelliteSlots(bothSides: bothSides), id: \.key) { slot in
                let activity = slot.activity
                let isFusingThis = activityCenter.fusingActivityId == activity.id
                let slotIndex = slot.index
                
                // Brota del notch al aparecer (LiquidSatelliteHost); al irse la dibuja departingSatellites
                // Si otra se está reabsorbiendo en este mismo extremo, espera escondida a que termine de entrar
                let sideIsBusy = activityCenter.departingSatellites.contains { departing in
                    departing.placement.isLeft == slot.isLeft && departing.activity.id != activity.id
                }
                LiquidSatelliteHost(placement: placementFor(slot.isLeft, slot.index, isFusingThis), phase: .appearing, animated: !reduceMotion,
                                    delay: sideIsBusy ? LiquidSatelliteHost<EmptyView>.handoverDelay : 0) {
                    NotchBolitaView(activity: activity, side: slot.isLeft ? .left : .right)
                        .scaleEffect(isNotchHovered && !isFusingThis ? 0.88 : 1)
                        .notchHitRegion("satellite.\(activity.id)") // dentro del .offset de LiquidSatelliteModifier: lo sigue solo
                }
                // Al fundirse pasa POR DEBAJO del notch (se reabsorbe en él) en vez de encimarse a las alas
                .zIndex(isFusingThis ? -1 : 100 - Double(slotIndex))
                .transition(.identity)
            }
            // Como la Isla Dinámica, las que no caben esperan en cola sin indicador (se recorren en A-3)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(
        // Click fuera del widget para cerrar cuando está expandido o en la bandeja
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                if activityCenter.expandedActivity != nil {
                    activityCenter.collapseExpandedActivity()
                } else if agentProvider.isProgressHUDExpanded {
                    agentProvider.collapseProgressHUD()
                } else if appState.mode == .expanded || appState.mode == .shelf {
                    performCollapse()
                }
            }
    )
    .animation(AnimationSpeedManager.shared.spring(response: 0.40, dampingFraction: 0.82), value: activityCenter.expandedActivity?.id)
    .animation(AnimationSpeedManager.shared.spring(response: 0.36, dampingFraction: 0.92), value: activityCenter.fusionProgress)
    // Las bolitas se mueven con el MISMO resorte que el notch cuando éste cambia de ancho (HUD de volumen o
    // brillo, actividades) o se aprieta al presionar: nunca quedan tapadas a mitad de la animación
    .animation(currentShapeSpring, value: cardExpandedWidth)
    .animation(NotchTuning.pressSpring, value: interactionState)
    // Aparecer/desaparecer de bolitas: lo bastante pausado para leer el cuello líquido al separarse
    .animation(AnimationSpeedManager.shared.spring(response: 0.55, dampingFraction: 0.88), value: activityCenter.secondaryActivities.count)
    .animation(.spring(response: 0.40, dampingFraction: 0.82), value: agentProvider.isProgressHUDExpanded)
    .animation(.spring(response: 0.35, dampingFraction: 0.80), value: agentProvider.isSatelliteActive)

        .onChange(of: appState.isHoldingBareNotch) { _, isHolding in
            if isHolding {
                self.isTransitioningFromActivity = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeIn(duration: 0.16)) {
                        self.isTransitioningFromActivity = false
                    }
                }
            }
        }
        .onChange(of: activityCenter.currentActivity?.id) { _, newId in
            if newId != nil {
                self.isTransitioningFromActivity = false
            }
        }
        .onChange(of: appState.isDropInvitationActive) { _, isActive in
            if isActive {
                self.isTransitioningFromActivity = false
            }
        }
        .onChange(of: appState.mode) { _, newMode in
            handleModeChange(newMode)
        }
        .onChange(of: musicService.currentTrack.title) { _, _ in
            NotchWindowManager.shared.resetCursorIfOverNotch()
            // Canción nueva: la actividad minimizada vuelve a mostrarse (como una actualización en la Isla)
            if appState.isCompactMinimized {
                withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.84)) {
                    appState.isCompactMinimized = false
                }
            }
        }
        .onAppear {
            appState.requestCollapse = {
                performCollapse()
            }
            if appState.mode == .expanded {
                interactionState = .expanded
                triggerStaggeredIn()
            }
        }
        .environment(\.controlActiveState, .key)
    }
    
    private var morphSpring: Animation {
        speedManager.spring(
            response: ExitAnimationMetrics.sliderDismissResponse,
            dampingFraction: ExitAnimationMetrics.sliderDismissDamping
        )
    }
    
    private var currentShapeSpring: Animation {
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
    private var pillPressGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard appState.mode != .expanded && appState.mode != .shelf else { return }
                
                let cancelX = abs(value.translation.width) > NotchTuning.dragCancelThresholdX
                let cancelUp = value.translation.height < -25
                
                if cancelX || cancelUp {
                    // CANCELAR arrastre hacia los lados o arriba
                    if interactionState == .pressed {
                        withAnimation(NotchTuning.cancelSpring) {
                            dragOffsetY = 0
                            dragBlur = 0
                            dragScaleY = 1.0
                            interactionState = .collapsed
                        }
                    }
                } else if value.translation.height > 0 {
                    // ARRASTRE HACIA ABAJO CON BLUR TIPO IPHONE Y CRECIMIENTO EN FORMA DE PÍLDORA
                    let rawY = value.translation.height
                    let offset = min(rawY * 0.40, 30.0)
                    let blur = min(6.0, (rawY / 26.0) * 4.5)
                    let stretch = 1.0 + min(rawY * 0.002, 0.07)
                    
                    withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                        dragOffsetY = offset
                        dragBlur = blur
                        dragScaleY = stretch
                        if interactionState != .pressed {
                            interactionState = .pressed
                            appState.hapticService.triggerSnap()
                        }
                    }
                } else {
                    // FASE 1: PRESIONAR (mouse down sin arrastre notable)
                    if interactionState != .pressed {
                        withAnimation(NotchTuning.pressSpring) {
                            interactionState = .pressed
                        }
                        appState.hapticService.triggerSnap()
                    }
                }
            }
            .onEnded { value in
                guard appState.mode != .expanded && appState.mode != .shelf else { return }
                
                let cancelX = abs(value.translation.width) > NotchTuning.dragCancelThresholdX
                let cancelUp = value.translation.height < -25
                let pulledDown = value.translation.height >= 8 || value.predictedEndTranslation.height >= 14
                let isTap = abs(value.translation.width) < 15 && abs(value.translation.height) < 15
                
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    dragOffsetY = 0
                    dragBlur = 0
                    dragScaleY = 1.0
                }
                
                if !cancelX && !cancelUp && (pulledDown || isTap) {
                    // FASE 2: SOLTAR / ARRASTRE COMPLETADO -> Expansión suave y orgánica
                    performExpand()
                } else {
                    withAnimation(NotchTuning.cancelSpring) {
                        interactionState = .collapsed
                    }
                }
            }
    }
    
    // MARK: - Gesto Interactivo Horizontal (Paginación limpia & Overscroll) y Vertical (Estiramiento & Detalle)
    private var cardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard appState.mode == .expanded || appState.mode == .shelf else { return }
                
                let tx = value.translation.width
                let ty = value.translation.height
                let totalDist = hypot(tx, ty)
                
                // Determinar y bloquear el eje del gesto con histéresis estricta para evitar saltos cruzados
                if dragLockAxis == .none && totalDist >= 5 {
                    if abs(tx) > abs(ty) * 1.15 {
                        dragLockAxis = .horizontal
                    } else if abs(ty) >= abs(tx) * 1.05 {
                        dragLockAxis = .vertical
                    }
                }
                
                // Si el eje está bloqueado en HORIZONTAL (o es predominantemente horizontal antes del bloqueo)
                if dragLockAxis == .horizontal || (dragLockAxis == .none && abs(tx) > abs(ty)) {
                    // Garantizar estrictamente que swipes laterales JAMÁS estiren o desplacen verticalmente el reproductor
                    appState.verticalOverscrollOffset = 0
                    appState.contentVerticalOverscrollOffset = 0
                    
                    if hasSwitchedPageInCurrentDrag {
                        appState.overscrollOffset = 0
                        appState.contentOverscrollOffset = 0
                        return
                    }
                    
                    if appState.mode == .expanded {
                        if tx > 0 {
                            // En Menú 1 (Música): arrastre a la derecha (no hay nada más allá) -> overscroll elástico en píldora
                            let stretch = OverscrollMetrics.calculateStretch(for: tx)
                            appState.overscrollOffset = stretch
                            appState.contentOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                            if abs(stretch) > 2.0 && !hasTriggeredHapticInSwipe {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                hasTriggeredHapticInSwipe = true
                            }
                        } else {
                            // Arrastrando a la izquierda hacia la Bandeja (MENÚ QUE SÍ EXISTE):
                            // NUNCA desplazar la tarjeta lateralmente ni estirar los bordes
                            appState.overscrollOffset = 0
                            appState.contentOverscrollOffset = 0
                        }
                    } else if appState.mode == .shelf {
                        if tx < 0 {
                            // En Menú 2 (Bandeja): arrastre a la izquierda (no hay nada más allá) -> overscroll elástico en píldora
                            let stretch = OverscrollMetrics.calculateStretch(for: tx)
                            appState.overscrollOffset = stretch
                            appState.contentOverscrollOffset = stretch * OverscrollMetrics.contentFollow
                            if abs(stretch) > 2.0 && !hasTriggeredHapticInSwipe {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                hasTriggeredHapticInSwipe = true
                            }
                        } else {
                            // Arrastrando a la derecha hacia Música (MENÚ QUE SÍ EXISTE):
                            // NUNCA desplazar la tarjeta lateralmente ni estirar los bordes
                            appState.overscrollOffset = 0
                            appState.contentOverscrollOffset = 0
                        }
                    }
                } else if dragLockAxis == .vertical || (dragLockAxis == .none && abs(ty) >= abs(tx)) {
                    // Gesto vertical: estirar elásticamente hacia abajo anclado arriba al notch
                    appState.overscrollOffset = 0
                    appState.contentOverscrollOffset = 0
                    
                    if appState.mode == .expanded || appState.mode == .shelf {
                        if ty > 0 {
                            let stretchY = OverscrollMetrics.calculateStretch(for: ty)
                            appState.verticalOverscrollOffset = stretchY
                            appState.contentVerticalOverscrollOffset = stretchY * OverscrollMetrics.contentFollow
                        } else {
                            appState.verticalOverscrollOffset = 0
                            appState.contentVerticalOverscrollOffset = 0
                        }
                    }
                }
            }
            .onEnded { value in
                guard appState.mode == .expanded || appState.mode == .shelf else { return }
                let currentAxis = dragLockAxis
                dragLockAxis = .none
                hasTriggeredHapticInSwipe = false
                hasSwitchedPageInCurrentDrag = false
                
                let tx = value.translation.width
                let ty = value.translation.height
                
                // Si el gesto fue horizontal (o predominó horizontal): NUNCA alterar el estado vertical ni bajar el reproductor
                if currentAxis == .horizontal || (currentAxis == .none && abs(tx) > abs(ty)) {
                    appState.verticalOverscrollOffset = 0
                    appState.contentVerticalOverscrollOffset = 0
                    
                    if appState.mode == .expanded {
                        if tx < -44 {
                            // Superó el umbral hacia la izquierda -> transición limpia a Bandeja
                            hasSwitchedPageInCurrentDrag = true
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                appState.mode = .shelf
                                appState.activeTab = .shelf
                                appState.overscrollOffset = 0
                                appState.contentOverscrollOffset = 0
                            }
                            appState.hapticService.triggerSnap()
                        } else if appState.overscrollOffset != 0 {
                            // Soltó durante overscroll: regreso con desfase Forma vs Contenido
                            withAnimation(speedManager.spring(
                                response: OverscrollMetrics.shapeSpringResponse,
                                dampingFraction: OverscrollMetrics.shapeSpringDamping
                            )) {
                                appState.overscrollOffset = 0
                            }
                            withAnimation(speedManager.spring(
                                response: OverscrollMetrics.contentSpringResponse,
                                dampingFraction: OverscrollMetrics.contentSpringDamping
                            )) {
                                appState.contentOverscrollOffset = 0
                            }
                        }
                    } else if appState.mode == .shelf {
                        if tx > 44 {
                            // Superó el umbral hacia la derecha -> transición limpia a Música
                            hasSwitchedPageInCurrentDrag = true
                            withAnimation(speedManager.spring(response: 0.35, dampingFraction: 0.82)) {
                                appState.mode = .expanded
                                appState.activeTab = .music
                                appState.overscrollOffset = 0
                                appState.contentOverscrollOffset = 0
                            }
                            appState.hapticService.triggerSnap()
                        } else if appState.overscrollOffset != 0 {
                            // Soltó durante overscroll: regreso con desfase Forma vs Contenido
                            withAnimation(speedManager.spring(
                                response: OverscrollMetrics.shapeSpringResponse,
                                dampingFraction: OverscrollMetrics.shapeSpringDamping
                            )) {
                                appState.overscrollOffset = 0
                            }
                            withAnimation(speedManager.spring(
                                response: OverscrollMetrics.contentSpringResponse,
                                dampingFraction: OverscrollMetrics.contentSpringDamping
                            )) {
                                appState.contentOverscrollOffset = 0
                            }
                        }
                    }
                } else if currentAxis == .vertical || (currentAxis == .none && abs(ty) >= abs(tx)) {
                    // Gesto estrictamente vertical en reproductor (expandir a modo detallado / rebote elástico / colapsar)
                    if appState.mode == .expanded {
                        if !appState.isPlayerDetailExpanded {
                            // Umbral deliberado hacia abajo (> 20 pt o velocidad hacia abajo) y claramente vertical
                            let isPulledDown = ty > 20 || (ty > 12 && value.predictedEndTranslation.height > 24)
                            if isPulledDown && abs(ty) >= abs(tx) * 1.05 {
                                withAnimation(speedManager.spring(response: 0.42, dampingFraction: 0.82)) {
                                    appState.isPlayerDetailExpanded = true
                                    appState.verticalOverscrollOffset = 0
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                appState.hapticService.triggerExpand()
                            } else {
                                withAnimation(speedManager.spring(
                                    response: OverscrollMetrics.shapeSpringResponse,
                                    dampingFraction: OverscrollMetrics.shapeSpringDamping
                                )) {
                                    appState.verticalOverscrollOffset = 0
                                }
                                withAnimation(speedManager.spring(
                                    response: OverscrollMetrics.contentSpringResponse,
                                    dampingFraction: OverscrollMetrics.contentSpringDamping
                                )) {
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                if ty < -16 && Date().timeIntervalSince(lastCardCollapseDetailTime) > 0.35 {
                                    performCollapse()
                                    appState.hapticService.triggerSnap()
                                }
                            }
                        } else {
                            if ty < -16 {
                                detailDragCount = 0
                                withAnimation(speedManager.spring(response: 0.40, dampingFraction: 0.84)) {
                                    appState.isPlayerDetailExpanded = false
                                    appState.verticalOverscrollOffset = 0
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                lastCardCollapseDetailTime = Date()
                                appState.hapticService.triggerSnap()
                            } else {
                                withAnimation(speedManager.spring(
                                    response: OverscrollMetrics.shapeSpringResponse,
                                    dampingFraction: OverscrollMetrics.shapeSpringDamping
                                )) {
                                    appState.verticalOverscrollOffset = 0
                                }
                                withAnimation(speedManager.spring(
                                    response: OverscrollMetrics.contentSpringResponse,
                                    dampingFraction: OverscrollMetrics.contentSpringDamping
                                )) {
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                            }
                        }
                    } else if appState.mode == .shelf {
                        // Bandeja temporal (Drag & Drop): rebote elástico a su forma original ya que no hay menú extendido
                        withAnimation(speedManager.spring(
                            response: OverscrollMetrics.shapeSpringResponse,
                            dampingFraction: OverscrollMetrics.shapeSpringDamping
                        )) {
                            appState.verticalOverscrollOffset = 0
                        }
                        withAnimation(speedManager.spring(
                            response: OverscrollMetrics.contentSpringResponse,
                            dampingFraction: OverscrollMetrics.contentSpringDamping
                        )) {
                            appState.contentVerticalOverscrollOffset = 0
                        }
                        
                        if ty < -22 {
                            performCollapse()
                            appState.hapticService.triggerSnap()
                        }
                    }
                } else {
                    // Sin eje dominante o movimiento menor a 6 pt: restablecer elásticamente a 0
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        appState.overscrollOffset = 0
                        appState.contentOverscrollOffset = 0
                        appState.verticalOverscrollOffset = 0
                        appState.contentVerticalOverscrollOffset = 0
                    }
                }
            }
    }
    
    private func handleModeChange(_ mode: NotchMode) {
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
    private func performExpand() {
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
    private func triggerStaggeredIn() {
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
    private func performCollapse() {
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

// Modificador condicional para aplicar el gesto solo cuando no está expandido
private struct PillGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G
    
    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(gesture)
        } else {
            content
        }
    }
}
