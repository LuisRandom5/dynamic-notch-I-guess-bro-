import SwiftUI
import UniformTypeIdentifiers

// Gestos sobre el notch: presionar la píldora y deslizar la tarjeta (páginas, detalle y cierre)
extension NotchContainerView {
    var pillPressGesture: some Gesture {
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
    var cardSwipeGesture: some Gesture {
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
}

// Modificador condicional para aplicar el gesto solo cuando no está expandido
struct PillGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G
    
    // Sin `if`/`else`: cambiar de rama recreaba TODA la píldora (fondo y contenido) cada vez que se abría el
    // reproductor o llegaba una actividad, y SwiftUI fundía la copia vieja con la nueva: a media animación la isla
    // se veía doble y translúcida y la forma nueva aparecía de golpe con su tamaño final. Así la vista conserva su
    // identidad y sólo se apaga el gesto (los de adentro siguen funcionando).
    func body(content: Content) -> some View {
        content.gesture(gesture, including: isEnabled ? .all : .subviews)
    }
}
