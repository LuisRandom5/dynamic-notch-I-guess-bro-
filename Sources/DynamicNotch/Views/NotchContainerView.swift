import SwiftUI
import UniformTypeIdentifiers

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
    @ObservedObject var backdropMonitor = BackdropBrightnessMonitor.shared
    @Namespace var notchNamespace
    
    @State var interactionState: NotchInteractionState = .collapsed
    @State var animStage1: Bool = false
    @State var animStage2: Bool = false
    @State var animStage3: Bool = false
    @State var isFileDragTargeted: Bool = false
    @State var isTransitioningFromActivity: Bool = false
    
    // Estados de salida escalonada (Exit Animation con Springs)
    @State var isCollapsing: Bool = false
    @State var controlsExiting: Bool = false
    @State var progressExiting: Bool = false
    @State var topRowExiting: Bool = false
    @State var hoverExitTimer: Timer? = nil
    
    // Gesto de arrastre hacia abajo con desenfoque (blur) estilo iPhone Dynamic Island
    @State var dragOffsetY: CGFloat = 0
    @State var dragBlur: CGFloat = 0
    @State var dragScaleY: CGFloat = 1.0
    @State var horizontalDragOffset: CGFloat = 0
    @State var lastCardCollapseDetailTime: Date = Date.distantPast
    @State var detailDragCount: Int = 0
    @State var lastDetailDragTime: Date = Date.distantPast
    @State var hasTriggeredHapticInSwipe: Bool = false
    @State var hasSwitchedPageInCurrentDrag: Bool = false
    @State var isMouseInsideWidget: Bool = false
    
    enum DragLockAxis {
        case none
        case horizontal
        case vertical
    }
    @State var dragLockAxis: DragLockAxis = .none
    
    public var body: some View {
        // Sin GlassEffectContainer alrededor: el contenedor dibuja todo el vidrio en una pasada por ENCIMA de
        // los hermanos, y el reproductor quedaba borroso debajo de la superficie (probado en macOS 27)
        notchContainerContent
            .environment(\.notchGlassSurfaceVisible, isGlassSurfaceVisible)
            .onPreferenceChange(NotchHitRegionsKey.self) { regions in
                NotchWindowManager.shared.updateDynamicHitRegions(regions)
            }
    }
    
    @ViewBuilder
    var topNotchCloseZone: some View {
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
    func expandedActivityContentView(_ expandedAct: LiveActivity) -> some View {
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
    var idleContentView: some View {
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
    var mainModeContentView: some View {
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
    var notchContainerContent: some View {
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
                        // Sin cámara detrás: toda la isla es del material (sin franja negra) y se ve en reposo
                        isFloatingSurface: isFloatingIsland,
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
            .opacity(isHiddenAtRest ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isHiddenAtRest)
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
                    // Con el retroceso de la isla incluido: si no, el extremo de la gota quedaba corrido 1.4 pt
                    // del de la isla y asomaba un arco fino al soltarse
                    notchEndX: isLeft
                        ? leftEdge + activityCenter.islandRecoil + notchRadius
                        : rightEdge + activityCenter.islandRecoil + (slotIndex == 0 ? activityCenter.pillImpulse : 0) - notchRadius,
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
    
}
