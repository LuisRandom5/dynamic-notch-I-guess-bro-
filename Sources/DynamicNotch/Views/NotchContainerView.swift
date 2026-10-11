import SwiftUI

// MARK: - Notch Physics & Animation Tuning
public struct NotchTuning {
    // 1) FASE PRESIONAR (Mouse Down) - Anticipación elástica física sutil
    public static let pressScaleX: CGFloat = 1.040              // Más sutil para no generar saltos bruscos
    public static let pressScaleY: CGFloat = 0.975              // Compresión vertical suave
    public static let pressShadowRadius: CGFloat = 12           // Sombra difusa debajo
    public static let pressShadowOpacity: Double = 0.28         // Opacidad suave
    public static let pressShadowY: CGFloat = 4                 // Desplazamiento vertical de la sombra
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
    @ObservedObject var speedManager = AnimationSpeedManager.shared
    @Namespace private var notchNamespace
    
    @State private var interactionState: NotchInteractionState = .collapsed
    @State private var animStage1: Bool = false
    @State private var animStage2: Bool = false
    @State private var animStage3: Bool = false
    @State private var pillsRevealed: Bool = false
    @State private var selectedBottomTab: BottomTab = .music
    
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
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    // Ancho: notch físico en idle, alas en compact, HUD de volumen, Live Activity o ancho fijo en expanded
    private var currentWidth: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedWidth
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill:
                return max(250, geometry.width + 60)
            case .sliderPill:
                return 320
            case .card:
                return 390
            }
        } else {
            switch appState.mode {
            case .idle:
                return geometry.width
            case .compact:
                return geometry.width + 104
            case .expanded, .shelf:
                return NotchTuning.expandedWidth
            }
        }
    }
    
    // Alto: altura del notch en reposo, 36pt en SliderPill, 105pt en Card, 158pt en expandido
    private var currentHeight: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedHeight
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill:
                return max(38, geometry.height)
            case .sliderPill:
                return 36
            case .card:
                return 112
            }
        } else {
            switch appState.mode {
            case .idle, .compact:
                return geometry.height
            case .expanded, .shelf:
                return NotchTuning.expandedHeight
            }
        }
    }
    
    // Curvatura de esquinas: arriba plano en reposo, 18pt en SliderPill, 40pt en Card, radio en expandido
    private var topRadius: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedTopRadius
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill:
                return 19
            case .sliderPill:
                return 18
            case .card:
                return 40
            }
        } else {
            switch appState.mode {
            case .idle, .compact:
                return 0
            case .expanded, .shelf:
                return NotchTuning.expandedTopRadius
            }
        }
    }
    
    private var bottomRadius: CGFloat {
        if appState.mode == .expanded || appState.mode == .shelf {
            return NotchTuning.expandedBottomRadius
        } else if let activity = activityCenter.currentActivity {
            switch activity.style {
            case .pill:
                return 19
            case .sliderPill:
                return 18
            case .card:
                return 40
            }
        } else {
            switch appState.mode {
            case .idle, .compact:
                return 17
            case .expanded, .shelf:
                return NotchTuning.expandedBottomRadius
            }
        }
    }
    
    // Escala temporal: si presiona (squash & stretch), si pasa cursor (latido), si no 1.0
    private var scaleX: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressScaleX
        } else if appState.mode != .expanded {
            return appState.heartbeatScaleX
        }
        return 1.0
    }
    
    private var scaleY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressScaleY
        } else if appState.mode != .expanded {
            return appState.heartbeatScaleY
        }
        return 1.0
    }
    
    // Sombra suave en anticipación, latido de hover o fija en expandido
    private var shadowRadius: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowRadius
        } else if appState.mode == .expanded {
            return NotchTuning.expandedShadowRadius
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return 12
        }
        return 0
    }
    
    private var shadowOpacity: Double {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowOpacity
        } else if appState.mode == .expanded {
            return NotchTuning.expandedShadowOpacity
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return appState.heartbeatShadowOpacity
        }
        return 0.0
    }
    
    private var shadowY: CGFloat {
        if interactionState == .pressed && appState.mode != .expanded {
            return NotchTuning.pressShadowY
        } else if appState.mode == .expanded {
            return NotchTuning.expandedShadowY
        } else if appState.heartbeatShadowOpacity > 0 && appState.mode != .expanded {
            return 4
        }
        return 0
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Píldora Principal (#000 puro, anclada arriba contra la cámara)
            ZStack(alignment: .top) {
                // Fondo negro puro con esquinas suaves redondeadas
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(Color.black)
                
                // Contenido según el modo, Live Activity o HUD de volumen
                Group {
                    if appState.mode == .expanded || appState.mode == .shelf {
                        // Reproductor minimalista estilo iPhone
                        NotchPlayerView(
                            namespace: notchNamespace,
                            animStage1: animStage1,
                            animStage2: animStage2,
                            animStage3: animStage3,
                            controlsExiting: controlsExiting,
                            progressExiting: progressExiting,
                            topRowExiting: topRowExiting
                        )
                        .frame(width: currentWidth, height: currentHeight, alignment: .top)
                    } else if activityCenter.currentActivity != nil {
                        // Live Activity activa (Pill / SliderPill / Card)
                        LiveActivityContainerView()
                            .frame(width: currentWidth, height: currentHeight, alignment: .top)
                            .transition(.opacity)
                    } else {
                        switch appState.mode {
                        case .idle:
                            Color.clear
                                .frame(width: currentWidth, height: currentHeight)
                            
                        case .compact:
                            NotchCompactView(namespace: notchNamespace)
                                .frame(width: currentWidth, height: currentHeight)
                                .blur(radius: dragBlur)
                                .transition(.opacity)
                            
                        default:
                            EmptyView()
                        }
                    }
                }
                
                // Zona táctil superior en el notch para cerrar al hacer click en el notch
                if appState.mode == .expanded {
                    Color.clear
                        .frame(width: geometry.width, height: geometry.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            performCollapse()
                        }
                }
            }
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowY + dragOffsetY * 0.4
            )
            .offset(y: dragOffsetY)
            .scaleEffect(x: scaleX, y: scaleY * dragScaleY, anchor: .top)
            .frame(width: currentWidth, height: currentHeight + dragOffsetY, alignment: .top)
            // Gesto de presión con anticipación en 3 fases cuando está colapsado y no hay actividad activa
            .modifier(PillGestureModifier(
                isEnabled: appState.mode != .expanded && activityCenter.currentActivity == nil,
                gesture: pillPressGesture
            ))
            .onHover { isHovering in
                if appState.mode == .expanded && appState.autoCollapseOnHoverExit {
                    if !isHovering {
                        // Inicia timer de ~0.6 s al salir del widget
                        hoverExitTimer?.invalidate()
                        let delay = speedManager.adjustedDuration(ExitAnimationMetrics.hoverExitDelay)
                        hoverExitTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                            DispatchQueue.main.async {
                                if appState.mode == .expanded {
                                    performCollapse()
                                }
                            }
                        }
                    } else {
                        // El cursor regresó al widget: cancela el timer
                        hoverExitTimer?.invalidate()
                        hoverExitTimer = nil
                    }
                } else if isHovering && appState.mode != .expanded && activityCenter.currentActivity == nil {
                    appState.triggerHeartbeat()
                }
            }
            .animation(NotchTuning.pressSpring, value: interactionState)
            .animation(currentShapeSpring, value: appState.mode)
            .animation(DesignTokens.activityEntrySpring, value: activityCenter.currentActivity?.id)
            .animation(currentShapeSpring, value: currentWidth)
            .animation(currentShapeSpring, value: currentHeight)
            .animation(currentShapeSpring, value: topRadius)
            .animation(currentShapeSpring, value: bottomRadius)
            
            // Cápsulas de pestañas flotantes inferiores (separadas con 8pt)
            if appState.mode == .expanded || pillsRevealed {
                NotchBottomPillsView(selectedTab: $selectedBottomTab)
                    .offset(y: pillsRevealed ? 0 : -14)
                    .opacity(pillsRevealed ? 1.0 : 0.0)
                    .animation(currentShapeSpring, value: pillsRevealed)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            // Click fuera del widget para cerrar cuando está expandido
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if appState.mode == .expanded {
                        performCollapse()
                    }
                }
        )
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
    
    private var currentShapeSpring: Animation {
        if appState.mode == .expanded {
            return speedManager.spring(
                response: ExitAnimationMetrics.shapeOpenResponse,
                dampingFraction: ExitAnimationMetrics.shapeOpenDamping
            )
        } else {
            return speedManager.spring(
                response: ExitAnimationMetrics.shapeCloseResponse,
                dampingFraction: ExitAnimationMetrics.shapeCloseDamping
            )
        }
    }
    
    // Gesto de presión y arrastre hacia abajo con desenfoque (blur) tipo iPhone Dynamic Island
    private var pillPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard appState.mode != .expanded else { return }
                
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
                    // ARRASTRE HACIA ABAJO CON BLUR TIPO IPHONE
                    let rawY = value.translation.height
                    let offset = min(rawY * 0.38, 28.0)
                    let blur = min(6.0, (rawY / 30.0) * 4.5)
                    let stretch = 1.0 + min(rawY * 0.0016, 0.06)
                    
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
                guard appState.mode != .expanded else { return }
                
                let cancelX = abs(value.translation.width) > NotchTuning.dragCancelThresholdX
                let cancelUp = value.translation.height < -25
                let pulledDown = value.translation.height >= 20 || value.predictedEndTranslation.height >= 32
                let isTap = abs(value.translation.width) < 12 && abs(value.translation.height) < 12
                
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    dragOffsetY = 0
                    dragBlur = 0
                    dragScaleY = 1.0
                }
                
                if !cancelX && !cancelUp && (pulledDown || isTap) && interactionState == .pressed {
                    // FASE 2: SOLTAR / ARRASTRE COMPLETADO -> Expansión suave y orgánica
                    performExpand()
                } else {
                    withAnimation(NotchTuning.cancelSpring) {
                        interactionState = .collapsed
                    }
                }
            }
    }
    
    private func handleModeChange(_ mode: NotchMode) {
        if mode == .expanded {
            performExpand()
        } else {
            performCollapse()
        }
    }
    
    // Expansión con resorte físico reversible
    private func performExpand() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
        
        isCollapsing = false
        controlsExiting = false
        progressExiting = false
        topRowExiting = false
        
        let shapeSpring = speedManager.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        withAnimation(shapeSpring) {
            interactionState = .expanded
            appState.mode = .expanded
        }
        appState.hapticService.triggerExpand()
        triggerStaggeredIn()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(NotchTuning.stage4Delay)) {
            guard self.appState.mode == .expanded else { return }
            withAnimation(self.currentShapeSpring) {
                self.pillsRevealed = true
            }
        }
    }
    
    // ANIMACIÓN DE SALIDA (CIERRE) DEL NOTCH BASADA EN ESTADO Y RESORTES INTERRUMPIBLES
    private func performCollapse() {
        guard appState.mode == .expanded && !isCollapsing else { return }
        
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
        isCollapsing = true
        
        let exitAnim = speedManager.easeIn(duration: ExitAnimationMetrics.contentExitDuration)
        let shapeSpring = speedManager.spring(
            response: ExitAnimationMetrics.shapeCloseResponse,
            dampingFraction: ExitAnimationMetrics.shapeCloseDamping
        )
        
        // t = 0 ms: la fila de controles sale primero de abajo hacia arriba
        withAnimation(exitAnim) {
            controlsExiting = true
            pillsRevealed = false
        }
        
        // t = 20 ms: la barra de progreso sale
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(ExitAnimationMetrics.progressExitDelay)) {
            guard self.isCollapsing else { return }
            withAnimation(exitAnim) {
                self.progressExiting = true
            }
        }
        
        // t = 40 ms: la fila superior sale
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(ExitAnimationMetrics.topRowExitDelay)) {
            guard self.isCollapsing else { return }
            withAnimation(exitAnim) {
                self.topRowExiting = true
            }
        }
        
        // t = 40 ms (solapado, NO espera a que termine el contenido): la forma se contrae
        DispatchQueue.main.asyncAfter(deadline: .now() + speedManager.adjustedDuration(ExitAnimationMetrics.shapeContractionDelay)) {
            guard self.isCollapsing else { return }
            withAnimation(shapeSpring) {
                self.interactionState = .collapsed
                if self.musicService.hasActiveMusic && self.appState.showCompactWhenPlaying {
                    self.appState.mode = .compact
                } else {
                    self.appState.mode = .idle
                }
            }
            self.appState.hapticService.triggerSnap()
        }
        
        // Reseteo limpio al asentarse la animación
        let totalTime = speedManager.adjustedDuration(0.38)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            guard self.isCollapsing else { return }
            self.isCollapsing = false
            self.controlsExiting = false
            self.progressExiting = false
            self.topRowExiting = false
            self.animStage1 = false
            self.animStage2 = false
            self.animStage3 = false
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
