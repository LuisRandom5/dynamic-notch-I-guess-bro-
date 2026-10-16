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
    @ObservedObject var activityCenter = ActivityCenter.shared
    @ObservedObject var notificationProvider = NotificationActivityProvider.shared
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
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    private var baseRestingWidth: CGFloat {
        if appState.isHoldingBareNotch {
            return geometry.width
        }
        switch appState.mode {
        case .idle:
            return !appState.shelfItems.isEmpty ? geometry.width + 96 : geometry.width
        case .compact:
            let wingExtra: CGFloat = (!appState.shelfItems.isEmpty && appState.showShelfBadgeInNotch) ? 24 : 0
            return geometry.width + 104 + (wingExtra * 2)
        case .expanded, .shelf:
            return NotchTuning.expandedWidth
        }
    }
    
    // Ancho: notch físico en idle, alas en compact, HUD de volumen, Live Activity o ancho fijo en expanded
    private var currentWidth: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedWidth
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
                return geometry.width + 170
            case .sliderPill:
                return geometry.width + 292
            case .airpodsPill:
                return geometry.width + 132
            case .card:
                if notificationProvider.isNotificationActive && activity.id.hasPrefix("notification_") {
                    return notificationProvider.isQuickReplyExpanded
                        ? NotificationActivityProvider.expandedWidth
                        : NotificationActivityProvider.compactWidth
                }
                return activityCenter.customCardWidth ?? 390
            }
        } else {
            return baseRestingWidth
        }
    }
    
    // Alto: altura del notch en reposo, 36pt en SliderPill, altura del notch en alas de AirPods, 144pt en Drop Invitation, 204pt en repisa, 196pt en reproductor
    private var currentHeight: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return (appState.isPlayerDetailExpanded && appState.mode == .expanded)
                ? PlayerMetrics.detailCardHeight
                : (appState.mode == .shelf ? 204 : NotchTuning.expandedHeight)
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
                        ? NotificationActivityProvider.expandedHeight
                        : NotificationActivityProvider.compactHeight
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
        } else if appState.isDropInvitationActive {
            return 0
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill, .sliderPill, .airpodsPill:
                return 0
            case .card:
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
        return currentHeight + appState.verticalOverscrollOffset + notifPull
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
        if interactionState == .pressed && appState.mode != .expanded && appState.mode != .shelf {
            return NotchTuning.pressScaleX
        } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil {
            return appState.heartbeatScaleX
        }
        return 1.0
    }
    
    private var scaleY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded && appState.mode != .shelf {
            return NotchTuning.pressScaleY
        } else if appState.mode != .expanded && appState.mode != .shelf && activityCenter.currentActivity == nil {
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
    
    public var body: some View {
        notchContainerContent
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
        snapStretch / 2.0
    }
    
    private var cardExpandedHeight: CGFloat {
        let absS = abs(snapStretch)
        let maxS = max(1.0, OverscrollMetrics.maxStretch)
        let heightFactor = 1.0 - (min(absS, maxS) / maxS) * OverscrollMetrics.heightShortenPercent
        return activeExpandedHeight * heightFactor
    }
    
    @ViewBuilder
    private var notchContainerContent: some View {
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
                    isExpanded: appState.mode == .expanded || appState.mode == .shelf || appState.isDropInvitationActive
                )
                .frame(width: cardExpandedWidth, height: cardExpandedHeight, alignment: .top)
                
                // Contenido según el modo, Live Activity o HUD de volumen
                Group {
                    if appState.mode == .expanded {
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
                            .clipShape(ElasticPillShape(
                                topRadius: topRadius,
                                bottomRadius: bottomRadius,
                                stretch: 0,
                                verticalStretch: 0
                            ))
                            .clipped()
                            .transition(.opacity)
                    } else if appState.isDropInvitationActive {
                        NotchDropInvitationView()
                            .frame(width: currentWidth, height: currentHeight, alignment: .top)
                            .transition(.opacity)
                    } else {
                        switch appState.mode {
                        case .idle:
                            if !appState.shelfItems.isEmpty {
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
                            
                        case .compact:
                            if appState.isHoldingBareNotch {
                                Color.clear
                                    .frame(width: currentWidth, height: currentHeight)
                            } else {
                                NotchCompactView(namespace: notchNamespace)
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
                .clipShape(ElasticPillShape(
                    topRadius: topRadius,
                    bottomRadius: bottomRadius,
                    stretch: 0,
                    verticalStretch: 0
                ))
                
                // Zona táctil superior en el notch para cerrar al hacer click en el notch
                if appState.mode == .expanded || appState.mode == .shelf {
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
            // MARCO PRIMARIO: Se fija el ancho y alto del contenedor simétricamente antes de aplicar sombra
            .frame(
                width: cardExpandedWidth,
                height: cardExpandedHeight,
                alignment: .top
            )
            .offset(x: cardOffsetX)
            // Sombra Multicapa (Ambient + Key): profundidad hiperrealista tipo isla dinámica
            // En modo Cristal Claro EXPANDIDO, se anula la sombra interior directa para evitar manchas oscuras bajo la tarjeta translúcida;
            // cuando está colapsado (idle/compact), la píldora es negro puro y sí proyecta su sombra fija de Dynamic Island.
            .shadow(
                color: Color.black.opacity(
                    (appState.effectiveAppearanceMode == .clearGlass && (appState.mode == .expanded || appState.mode == .shelf || appState.isDropInvitationActive))
                        ? 0.0
                        : ((shadowOpacity * 0.42) + (hasDownPull ? 0.14 : 0.0))
                ),
                radius: (shadowRadius * 0.38) + (hasDownPull ? 4 : 0),
                x: 0,
                y: (shadowY * 0.45) + totalOffsetY * 0.2
            )
            .shadow(
                color: Color.black.opacity(
                    (appState.effectiveAppearanceMode == .clearGlass && (appState.mode == .expanded || appState.mode == .shelf || appState.isDropInvitationActive))
                        ? 0.0
                        : (shadowOpacity + (hasDownPull ? 0.22 : 0.0))
                ),
                radius: shadowRadius + (hasDownPull ? 10 : 0),
                x: 0,
                y: shadowY + totalOffsetY * 0.4
            )
            // Sombra exterior con máscara inversa para Cristal Claro expandido (la sombra existe fuera y es nula dentro)
            .background(
                Group {
                    if appState.effectiveAppearanceMode == .clearGlass && glassManager.showCardShadow && (appState.mode == .expanded || appState.mode == .shelf || appState.isDropInvitationActive) {
                        let pill = ElasticPillShape(
                            topRadius: topRadius,
                            bottomRadius: bottomRadius,
                            stretch: 0,
                            verticalStretch: 0
                        )
                        pill
                            .fill(Color.black.opacity(GlassClearMetrics.cardShadowOpacity))
                            .shadow(
                                color: Color.black.opacity(GlassClearMetrics.cardShadowOpacity),
                                radius: GlassClearMetrics.cardShadowRadius,
                                x: 0,
                                y: GlassClearMetrics.cardShadowY
                            )
                            .mask(
                                Rectangle()
                                    .overlay(
                                        pill
                                            .blendMode(.destinationOut)
                                    )
                                    .compositingGroup()
                            )
                    }
                }
            )
            .offset(y: containerOffsetY)
            .scaleEffect(x: scaleX, y: scaleY * dragScaleY, anchor: .top)
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
                isEnabled: (appState.mode == .expanded || appState.mode == .shelf) && activityCenter.currentActivity == nil,
                gesture: cardSwipeGesture
            ))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            // Click fuera del widget para cerrar cuando está expandido o en la bandeja
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if appState.mode == .expanded || appState.mode == .shelf {
                        performCollapse()
                    }
                }
        )

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
        .onAppear {
            appState.requestCollapse = {
                performCollapse()
            }
            if appState.mode == .expanded {
                interactionState = .expanded
                triggerStaggeredIn()
            }
        }
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
                let pulledDown = value.translation.height >= 18 || value.predictedEndTranslation.height >= 30
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
                
                // Si el gesto es predominantemente horizontal
                if abs(tx) > abs(ty) {
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
                } else {
                    // Gesto predominantemente vertical: estirar elásticamente hacia abajo anclado arriba al notch
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
                hasTriggeredHapticInSwipe = false
                hasSwitchedPageInCurrentDrag = false
                
                let tx = value.translation.width
                let ty = value.translation.height
                
                if abs(tx) > abs(ty) {
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
                            withAnimation(.spring(
                                response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                                dampingFraction: OverscrollMetrics.shapeSpringDamping
                            )) {
                                appState.overscrollOffset = 0
                            }
                            withAnimation(.spring(
                                response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                                dampingFraction: OverscrollMetrics.contentSpringDamping
                            )) {
                                appState.contentOverscrollOffset = 0
                            }
                        }
                    } else if appState.mode == .shelf {
                        if tx > 44 {
                            // Superó el umbral hacia la derecha -> transición limpia a Música
                            hasSwitchedPageInCurrentDrag = true
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                appState.mode = .expanded
                                appState.activeTab = .music
                                appState.overscrollOffset = 0
                                appState.contentOverscrollOffset = 0
                            }
                            appState.hapticService.triggerSnap()
                        } else if appState.overscrollOffset != 0 {
                            // Soltó durante overscroll: regreso con desfase Forma vs Contenido
                            withAnimation(.spring(
                                response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                                dampingFraction: OverscrollMetrics.shapeSpringDamping
                            )) {
                                appState.overscrollOffset = 0
                            }
                            withAnimation(.spring(
                                response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                                dampingFraction: OverscrollMetrics.contentSpringDamping
                            )) {
                                appState.contentOverscrollOffset = 0
                            }
                        }
                    }
                } else {
                    // Gesto vertical en reproductor (expandir a modo detallado / rebote elástico / colapsar)
                    if appState.mode == .expanded {
                        if !appState.isPlayerDetailExpanded {
                            if ty > 22 {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                    appState.isPlayerDetailExpanded = true
                                    appState.verticalOverscrollOffset = 0
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                appState.hapticService.triggerExpand()
                            } else {
                                withAnimation(.spring(
                                    response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                                    dampingFraction: OverscrollMetrics.shapeSpringDamping
                                )) {
                                    appState.verticalOverscrollOffset = 0
                                }
                                withAnimation(.spring(
                                    response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                                    dampingFraction: OverscrollMetrics.contentSpringDamping
                                )) {
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                if ty < -24 && Date().timeIntervalSince(lastCardCollapseDetailTime) > 0.75 {
                                    performCollapse()
                                    appState.hapticService.triggerSnap()
                                }
                            }
                        } else {
                            if ty < -24 {
                                detailDragCount = 0
                                withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                                    appState.isPlayerDetailExpanded = false
                                    appState.verticalOverscrollOffset = 0
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                                lastCardCollapseDetailTime = Date()
                                appState.hapticService.triggerSnap()
                            } else {
                                withAnimation(.spring(
                                    response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                                    dampingFraction: OverscrollMetrics.shapeSpringDamping
                                )) {
                                    appState.verticalOverscrollOffset = 0
                                }
                                withAnimation(.spring(
                                    response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                                    dampingFraction: OverscrollMetrics.contentSpringDamping
                                )) {
                                    appState.contentVerticalOverscrollOffset = 0
                                }
                            }
                        }
                    } else if appState.mode == .shelf {
                        // Bandeja temporal (Drag & Drop): rebote elástico a su forma original ya que no hay menú extendido
                        withAnimation(.spring(
                            response: OverscrollMetrics.shapeSpringResponse * OverscrollMetrics.speedMultiplier,
                            dampingFraction: OverscrollMetrics.shapeSpringDamping
                        )) {
                            appState.verticalOverscrollOffset = 0
                        }
                        withAnimation(.spring(
                            response: OverscrollMetrics.contentSpringResponse * OverscrollMetrics.speedMultiplier,
                            dampingFraction: OverscrollMetrics.contentSpringDamping
                        )) {
                            appState.contentVerticalOverscrollOffset = 0
                        }
                        
                        if ty < -22 {
                            performCollapse()
                            appState.hapticService.triggerSnap()
                        }
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
            isCollapsing = false
            isTransitioningFromActivity = false
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
                self.appState.isHoldingBareNotch = false
                self.appState.isPlayerDetailExpanded = false
                self.appState.verticalOverscrollOffset = 0
                self.appState.contentVerticalOverscrollOffset = 0
                self.appState.overscrollOffset = 0
                self.appState.contentOverscrollOffset = 0
                if self.appState.shelfItems.isEmpty || self.musicService.hasActiveMusic {
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
        
        // Reseteo limpio al asentarse la animación (~0.48 s)
        let totalTime = speedManager.adjustedDuration(0.48)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            guard self.isCollapsing else { return }
            self.isCollapsing = false
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
