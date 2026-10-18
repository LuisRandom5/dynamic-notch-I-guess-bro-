import SwiftUI
import AppKit

public struct NotchPlayerView: View {
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioService = AudioDeviceService.shared
    @ObservedObject var debugOverlay = DebugOverlayManager.shared
    
    public var namespace: Namespace.ID? = nil
    
    // Fases de entrada
    public var animStage1: Bool
    public var animStage2: Bool
    public var animStage3: Bool
    
    // Fases de salida (staggered exit de abajo hacia arriba)
    public var controlsExiting: Bool = false
    public var progressExiting: Bool = false
    public var topRowExiting: Bool = false
    
    @State private var isSeeking: Bool = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isHoveringBar: Bool = false
    @State private var isShowingAirPlayPicker: Bool = false
    @State private var isHoveringVolume: Bool = false
    @State private var isDraggingVolume: Bool = false
    @State private var dragVolumeLevel: Float? = nil
    @State private var artworkTilt: Double = 0.0
    @State private var skipDirection: Double = 1.0
    
    public init(
        namespace: Namespace.ID? = nil,
        animStage1: Bool = true,
        animStage2: Bool = true,
        animStage3: Bool = true,
        controlsExiting: Bool = false,
        progressExiting: Bool = false,
        topRowExiting: Bool = false
    ) {
        self.namespace = namespace
        self.animStage1 = animStage1
        self.animStage2 = animStage2
        self.animStage3 = animStage3
        self.controlsExiting = controlsExiting
        self.progressExiting = progressExiting
        self.topRowExiting = topRowExiting
    }
    
    private var track: MusicTrack {
        musicService.currentTrack
    }
    
    private var stretch: CGFloat {
        appState.overscrollOffset
    }
    
    private var verticalStretch: CGFloat {
        appState.verticalOverscrollOffset
    }
    
    private var shouldFadeMediaAnchors: Bool {
        let isGoingToCompact = musicService.hasActiveMusic && appState.showCompactWhenPlaying
        return !isGoingToCompact && topRowExiting
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Contenido interno con padding exacto de 18 pt
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Barra Superior: Manija e Indicador de Páginas (Home ●  ○ Bandeja con indicador exactamente centrado)
                ZStack {
                    // Centro Absoluto: Indicador de Pestañas (Home ●  ○ Bandeja)
                    HStack(spacing: 5) {
                        Capsule()
                            .fill(Color.white.opacity(0.90))
                            .frame(
                                width: 14 + (stretch > 0 ? min(OverscrollMetrics.pageIndicatorStretch, stretch * 0.15) : 0),
                                height: 5.5
                            )
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                                appState.mode = .shelf
                                appState.activeTab = .shelf
                            }
                            appState.hapticService.triggerSnap()
                        }) {
                            Circle()
                                .fill(Color.white.opacity(0.35))
                                .frame(width: 5.5, height: 5.5)
                        }
                        .buttonStyle(.plain)
                        .help("Ir a la bandeja de archivos")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Extremos izquierdo y derecho
                    HStack(spacing: 4) {
                        if appState.isPlayerDetailExpanded && appState.activeMiniAppOverlay == nil && !isShowingAirPlayPicker {
                            Button(action: {
                                withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                                    appState.isPlayerDetailExpanded = false
                                }
                                appState.hapticService.triggerSnap()
                            }) {
                                Image(systemName: "chevron.compact.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 16)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 28, height: 16)
                        }
                        
                        Spacer()
                        
                        // Botones de acceso rápido al Banco de Mini-Apps (configurables en Ajustes)
                        HStack(spacing: 5) {
                            if appState.pinTimerMiniAppInNotch {
                                let isTimerOpen = appState.activeMiniAppOverlay == .timer
                                let hasActiveTimer = TimerActivityProvider.shared.hasActiveSession
                                Button(action: {
                                    appState.hapticService.triggerSnap()
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                        isShowingAirPlayPicker = false
                                        appState.activeMiniAppOverlay = isTimerOpen ? nil : .timer
                                    }
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: TimerActivityProvider.shared.mode.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor((isTimerOpen || hasActiveTimer) ? DesignTokens.orange : Color.white.opacity(0.55))
                                            .frame(width: 22, height: 16)
                                            .background(
                                                Capsule()
                                                    .fill((isTimerOpen || hasActiveTimer) ? DesignTokens.orange.opacity(0.18) : Color.white.opacity(0.07))
                                            )
                                        
                                        if hasActiveTimer && !isTimerOpen {
                                            Circle()
                                                .fill(DesignTokens.orange)
                                                .frame(width: 4.5, height: 4.5)
                                                .offset(x: -1, y: 1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Cronómetro y Temporizador")
                            }
                            
                            if appState.pinAudioMonitorMiniAppInNotch {
                                let isMonitorOpen = appState.activeMiniAppOverlay == .audioMonitor
                                Button(action: {
                                    appState.hapticService.triggerSnap()
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                        isShowingAirPlayPicker = false
                                        appState.activeMiniAppOverlay = isMonitorOpen ? nil : .audioMonitor
                                    }
                                }) {
                                    Image(systemName: "waveform.badge.magnifyingglass")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isMonitorOpen ? Color.cyan : Color.white.opacity(0.55))
                                        .frame(width: 22, height: 16)
                                        .background(
                                            Capsule()
                                                .fill(isMonitorOpen ? Color.cyan.opacity(0.18) : Color.white.opacity(0.07))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Monitor de Espectro FFT en Tiempo Real")
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, appState.isPlayerDetailExpanded ? 8 : 4)
                
                if let miniApp = appState.activeMiniAppOverlay {
                    // MARK: - Mini-App Integrada (Cronómetro/Temporizador o Monitor FFT)
                    Group {
                        switch miniApp {
                        case .timer:
                            TimerMiniAppOverlayView {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    appState.activeMiniAppOverlay = nil
                                }
                                appState.hapticService.triggerSnap()
                            }
                        case .audioMonitor:
                            AudioMonitorMiniAppOverlayView {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    appState.activeMiniAppOverlay = nil
                                }
                                appState.hapticService.triggerSnap()
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                } else if isShowingAirPlayPicker {
                    // MARK: - Selector de Audio Integrado en la Píldora
                    airPlayPickerContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                } else if appState.isPlayerDetailExpanded {
                    // MARK: - Vista Detallada de Mini Reproductor (Apple Music Style)
                    detailPlayerContent
                } else {
                    // MARK: - Vista Estándar (3 Filas Clásicas)
                    standardPlayerContent
                }
            }
            .padding(.horizontal, PlayerMetrics.paddingInternal)
            .padding(.top, PlayerMetrics.topContentPadding - 12)
            .padding(.bottom, PlayerMetrics.bottomPadding)
            .offset(x: appState.contentOverscrollOffset * 0.45, y: appState.contentVerticalOverscrollOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            
            // MARK: - MODO DEBUG DE COMPARACIÓN (OVERLAY)
            if debugOverlay.isOverlayActive {
                if let overlayImg = debugOverlay.overlayImage {
                    Image(nsImage: overlayImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous))
                        .opacity(debugOverlay.opacity)
                        .allowsHitTesting(false)
                } else {
                    PixelPerfectGuideView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(debugOverlay.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: track.title) { oldTitle, newTitle in
            guard !newTitle.isEmpty, newTitle != oldTitle else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                artworkTilt = skipDirection * 24.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                    artworkTilt = 0.0
                }
            }
        }
    }
    
    // MARK: - Vista Estándar (Reproductor Clásico Compacto)
    @ViewBuilder
    private var standardPlayerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FILA 1: Carátula, Textos y Visualizador (Centrado vertical armónico)
            HStack(alignment: .center, spacing: PlayerMetrics.artworkToTextSpacing) {
                // Carátula a la izquierda
                Button(action: {
                    if NSEvent.modifierFlags.contains(.option) {
                        AmbientCanvasWindowManager.shared.toggleCanvas()
                    } else {
                        appState.hapticService.triggerExpand()
                        musicService.openMusicApp()
                        appState.collapse()
                    }
                }) {
                    ZStack {
                        if let art = track.artwork {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: PlayerMetrics.artworkSize, height: PlayerMetrics.artworkSize)
                                .clipShape(RoundedRectangle(cornerRadius: PlayerMetrics.artworkCornerRadius, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: PlayerMetrics.artworkCornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.95, green: 0.35, blue: 0.20),
                                            Color(red: 0.85, green: 0.15, blue: 0.35)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: PlayerMetrics.artworkSize, height: PlayerMetrics.artworkSize)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .rotation3DEffect(.degrees(artworkTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(BouncyButtonStyle(scaleAmount: PlayerMetrics.buttonPressScale))
                .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
                .notchContentExit(isExiting: shouldFadeMediaAnchors)
                .scaleEffect(animStage1 ? 1.0 : 0.90)
                .opacity(animStage1 ? 1.0 : 0.0)
                
                // Título y Artista
                VStack(alignment: .leading, spacing: PlayerMetrics.titleToArtistSpacing) {
                    MarqueeText(
                        track.title.isEmpty ? "No Playing" : track.title,
                        fontSize: PlayerMetrics.titleFontSize,
                        fontWeight: .bold,
                        color: .white
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    MarqueeText(
                        track.artist.isEmpty ? "Apple Music" : track.artist,
                        fontSize: PlayerMetrics.artistFontSize,
                        fontWeight: .medium,
                        color: Color.white.opacity(PlayerMetrics.artistOpacity)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .shadow(
                    color: Color.black.opacity(GlassClearMetrics.textShadowOpacity),
                    radius: GlassClearMetrics.textShadowRadius,
                    y: GlassClearMetrics.textShadowY
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PlayerMetrics.artworkSize)
                .notchContentExit(isExiting: topRowExiting)
                .scaleEffect(animStage1 ? 1.0 : 0.94)
                .opacity(animStage1 ? 1.0 : 0.0)
                
                // Visualizador de Audio (Perfectamente centrado en la fila)
                AudioVisualizer(
                    isPlaying: track.isPlaying,
                    colorMode: .fromArtwork(track.artwork)
                )
                .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
                .notchContentExit(isExiting: shouldFadeMediaAnchors)
                .scaleEffect(animStage1 ? 1.0 : 0.90)
                .opacity(animStage1 ? 1.0 : 0.0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
                .frame(height: PlayerMetrics.row1ToRow2Spacing)
            
            // FILA 2: Progreso y Tiempos
            HStack(spacing: PlayerMetrics.timeToBarSpacing) {
                Text(formatTime(isSeeking ? seekPosition : track.playbackPosition))
                    .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary) // vibrante sobre el vidrio
                    .shadow(
                        color: Color.black.opacity(GlassClearMetrics.textShadowOpacity),
                        radius: GlassClearMetrics.textShadowRadius,
                        y: GlassClearMetrics.textShadowY
                    )
                    .frame(width: PlayerMetrics.timeWidth, alignment: .leading)
                
                GeometryReader { geo in
                    let currentProgress = track.duration > 0
                        ? (isSeeking ? seekPosition : track.playbackPosition) / track.duration
                        : 0.0
                    let barHeight = isHoveringBar ? PlayerMetrics.progressBarHoverHeight : PlayerMetrics.progressBarHeight
                    
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(PlayerMetrics.progressBarTrackColor)
                            .frame(height: barHeight)
                        
                        Capsule(style: .continuous)
                            .fill(PlayerMetrics.progressBarFillColor)
                            .frame(
                                width: max(barHeight, geo.size.width * CGFloat(min(1.0, max(0.0, currentProgress)))),
                                height: barHeight
                            )
                    }
                    .frame(height: PlayerMetrics.progressBarHoverHeight, alignment: .center)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isHoveringBar = hovering
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if abs(value.translation.height) > abs(value.translation.width) && abs(value.translation.height) > 4 {
                                    if isSeeking { isSeeking = false }
                                    return
                                }
                                isSeeking = true
                                let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                seekPosition = track.duration * Double(ratio)
                            }
                            .onEnded { value in
                                if isSeeking {
                                    let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                    let newPos = track.duration * Double(ratio)
                                    musicService.seek(to: newPos)
                                    isSeeking = false
                                }
                            }
                    )
                }
                .frame(height: PlayerMetrics.progressBarHoverHeight)
                
                Text("-" + formatTime(max(0, track.duration - (isSeeking ? seekPosition : track.playbackPosition))))
                    .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
                    .shadow(
                        color: Color.black.opacity(GlassClearMetrics.textShadowOpacity),
                        radius: GlassClearMetrics.textShadowRadius,
                        y: GlassClearMetrics.textShadowY
                    )
                    .frame(width: PlayerMetrics.timeWidth, alignment: .trailing)
            }
            .notchContentExit(isExiting: progressExiting)
            .scaleEffect(animStage2 ? 1.0 : 0.94)
            .opacity(animStage2 ? 1.0 : 0.0)
            
            Spacer()
                .frame(height: PlayerMetrics.row2ToRow3Spacing)
            
            // FILA 3: Controles
            controlsRow
                .notchContentExit(isExiting: controlsExiting)
                .scaleEffect(animStage3 ? 1.0 : 0.94)
                .opacity(animStage3 ? 1.0 : 0.0)
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Vista Detallada (Apple Music Mini Player Expandido)
    @ViewBuilder
    private var detailPlayerContent: some View {
        VStack(spacing: 10) {
            // Hero Artwork + Textos + Visualizador
            HStack(spacing: 14) {
                ZStack {
                    if let art = track.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.black.opacity(0.40), radius: 8, x: 0, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink.opacity(0.85), Color.orange.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundColor(.white))
                    }
                }
                .rotation3DEffect(.degrees(artworkTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
                
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(
                        track.title.isEmpty ? "No Playing" : track.title,
                        fontSize: 16,
                        fontWeight: .bold,
                        color: .white
                    )
                    
                    MarqueeText(
                        track.artist.isEmpty ? "Apple Music" : track.artist,
                        fontSize: 13,
                        fontWeight: .medium,
                        color: Color.white.opacity(0.70)
                    )
                    
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 2)
                    
                    AudioVisualizer(
                        isPlaying: track.isPlaying,
                        colorMode: .fromArtwork(track.artwork)
                    )
                    .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
                }
                .frame(height: 72)
            }
            
            // Barra de progreso y tiempos
            HStack(spacing: PlayerMetrics.timeToBarSpacing) {
                Text(formatTime(isSeeking ? seekPosition : track.playbackPosition))
                    .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: PlayerMetrics.timeWidth, alignment: .leading)
                
                GeometryReader { geo in
                    let currentProgress = track.duration > 0
                        ? (isSeeking ? seekPosition : track.playbackPosition) / track.duration
                        : 0.0
                    
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(PlayerMetrics.progressBarTrackColor)
                            .frame(height: 5.5)
                        
                        Capsule(style: .continuous)
                            .fill(PlayerMetrics.progressBarFillColor)
                            .frame(
                                width: max(5.5, geo.size.width * CGFloat(min(1.0, max(0.0, currentProgress)))),
                                height: 5.5
                            )
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if abs(value.translation.height) > abs(value.translation.width) && abs(value.translation.height) > 4 {
                                    if isSeeking { isSeeking = false }
                                    return
                                }
                                isSeeking = true
                                let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                seekPosition = track.duration * Double(ratio)
                            }
                            .onEnded { value in
                                if isSeeking {
                                    let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                    let newPos = track.duration * Double(ratio)
                                    musicService.seek(to: newPos)
                                    isSeeking = false
                                }
                            }
                    )
                }
                .frame(height: 14)
                
                Text("-" + formatTime(max(0, track.duration - (isSeeking ? seekPosition : track.playbackPosition))))
                    .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: PlayerMetrics.timeWidth, alignment: .trailing)
            }
            
            // Controles centrales
            controlsRow
            
            // MARK: - Slider de volumen integrado y ultra-smooth
            let displayVolume = dragVolumeLevel ?? audioService.currentVolume
            let isVolumeActive = isHoveringVolume || isDraggingVolume
            let barHeight: CGFloat = isVolumeActive ? 7.5 : 4.5
            
            HStack(spacing: 8) {
                // Icono dinámico izquierdo (mute / restaurar)
                Button(action: {
                    let newVol: Float = audioService.currentVolume > 0.05 ? 0.0 : 0.35
                    audioService.setVolume(newVol)
                    appState.hapticService.triggerSnap()
                }) {
                    Image(systemName: displayVolume <= 0.01 ? "speaker.slash.fill" : (displayVolume < 0.33 ? "speaker.fill" : "speaker.wave.1.fill"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(displayVolume <= 0.01 ? 0.40 : 0.65))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                
                GeometryReader { geo in
                    let volClamped = max(0.0, min(1.0, CGFloat(displayVolume)))
                    let fillWidth = max(barHeight, geo.size.width * volClamped)
                    
                    ZStack(alignment: .leading) {
                        // Canal de fondo
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isVolumeActive ? 0.22 : 0.16))
                            .frame(height: barHeight)
                        
                        // Barra de llenado con brillo sutil
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(white: 0.92)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: barHeight)
                            .shadow(color: Color.white.opacity(isDraggingVolume ? 0.35 : 0.12), radius: isDraggingVolume ? 4 : 2, x: 0, y: 0)
                    }
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            isHoveringVolume = hovering
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                isDraggingVolume = true
                                let ratio = max(0.0, min(1.0, Float(val.location.x / geo.size.width)))
                                dragVolumeLevel = ratio
                                audioService.setVolume(ratio)
                            }
                            .onEnded { val in
                                let ratio = max(0.0, min(1.0, Float(val.location.x / geo.size.width)))
                                audioService.setVolume(ratio)
                                dragVolumeLevel = nil
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    isDraggingVolume = false
                                }
                                appState.hapticService.triggerSnap()
                            }
                    )
                }
                .frame(height: 16)
                .animation(.spring(response: 0.22, dampingFraction: 0.84), value: displayVolume)
                .animation(.spring(response: 0.28, dampingFraction: 0.80), value: isVolumeActive)
                
                // Icono dinámico derecho (volumen al máximo)
                Button(action: {
                    audioService.setVolume(1.0)
                    appState.hapticService.triggerSnap()
                }) {
                    Image(systemName: displayVolume >= 0.66 ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(displayVolume >= 0.66 ? 0.85 : 0.65))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
    }
    
    // Fila de controles compartida
    private var controlsRow: some View {
        ZStack {
            // Controles Laterales: Shuffle + Repeat (izquierda) y AirPlay (derecha)
            HStack {
                HStack(spacing: 4) {
                    PlayerControlButton(
                        scaleAmount: 0.85,
                        haloSize: 26,
                        isActive: musicService.isShuffle,
                        activeTint: .orange
                    ) {
                        musicService.toggleShuffle()
                        appState.hapticService.triggerSnap()
                    } content: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(musicService.isShuffle ? Color.orange : PlayerMetrics.sideButtonColor)
                            .frame(width: PlayerMetrics.sideButtonWidth, height: PlayerMetrics.sideButtonWidth)
                    }
                    .help(musicService.isShuffle ? "Aleatorio activado" : "Activar modo aleatorio")
                    
                    let isRepeatActive = musicService.repeatMode != .off
                    PlayerControlButton(
                        scaleAmount: 0.85,
                        haloSize: 26,
                        isActive: isRepeatActive,
                        activeTint: .orange
                    ) {
                        musicService.toggleRepeat()
                        appState.hapticService.triggerSnap()
                    } content: {
                        Image(systemName: musicService.repeatMode.icon)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(isRepeatActive ? Color.orange : PlayerMetrics.sideButtonColor)
                            .frame(width: PlayerMetrics.sideButtonWidth, height: PlayerMetrics.sideButtonWidth)
                    }
                    .help("Modo de repetición: \(musicService.repeatMode.label)")
                }
                
                Spacer()
                
                // Selector de salida de audio / AirPlay integrado en la píldora
                PlayerControlButton(
                    scaleAmount: 0.85,
                    haloSize: 26,
                    isActive: isShowingAirPlayPicker || audioService.isAirPodsActive || audioService.isAirPlayActive,
                    activeTint: .blue
                ) {
                    appState.hapticService.triggerSnap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isShowingAirPlayPicker.toggle()
                    }
                } content: {
                    let iconName: String = {
                        if audioService.isAirPodsActive {
                            return audioService.currentDeviceIcon
                        } else {
                            return "airplayaudio"
                        }
                    }()
                    Image(systemName: iconName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor((isShowingAirPlayPicker || audioService.isAirPodsActive || audioService.isAirPlayActive) ? Color.blue : PlayerMetrics.sideButtonColor)
                        .frame(width: PlayerMetrics.sideButtonWidth, height: PlayerMetrics.sideButtonWidth)
                }
                .help("Seleccionar salida de audio (AirPlay / AirPods)")
            }
            .padding(.horizontal, 10)
            
            // Tres controles centrales
            HStack(spacing: PlayerMetrics.controlsCenterSpacing - PlayerMetrics.playPauseWidth) {
                PlayerControlButton(xOffset: -4.5, scaleAmount: 0.82, haloSize: 32) {
                    appState.hapticService.triggerSnap()
                    skipDirection = -1.0
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                        artworkTilt = -24.0
                    }
                    musicService.previousTrack()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                            artworkTilt = 0.0
                        }
                    }
                } content: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: PlayerMetrics.skipButtonWidth, height: PlayerMetrics.skipButtonHeight)
                }
                
                PlayerControlButton(scaleAmount: 0.82, haloSize: 38) {
                    appState.hapticService.triggerExpand()
                    musicService.togglePlayPause()
                } content: {
                    ZStack {
                        if track.isPlaying {
                            HStack(spacing: PlayerMetrics.pauseBarSpacing) {
                                RoundedRectangle(cornerRadius: PlayerMetrics.pauseBarRadius, style: .continuous)
                                    .fill(Color.white)
                                    .frame(width: PlayerMetrics.pauseBarWidth, height: PlayerMetrics.pauseBarHeight)
                                RoundedRectangle(cornerRadius: PlayerMetrics.pauseBarRadius, style: .continuous)
                                    .fill(Color.white)
                                    .frame(width: PlayerMetrics.pauseBarWidth, height: PlayerMetrics.pauseBarHeight)
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: PlayerMetrics.playIconSize, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 1.5)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .frame(width: PlayerMetrics.playPauseWidth, height: PlayerMetrics.playPauseHeight)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: track.isPlaying)
                
                PlayerControlButton(xOffset: 4.5, scaleAmount: 0.82, haloSize: 32) {
                    appState.hapticService.triggerSnap()
                    skipDirection = 1.0
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                        artworkTilt = 24.0
                    }
                    musicService.nextTrack()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                            artworkTilt = 0.0
                        }
                    }
                } content: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: PlayerMetrics.skipButtonWidth, height: PlayerMetrics.skipButtonHeight)
                }
            }
        }
    }
    
    // MARK: - Selector de Audio / AirPlay Integrado dentro de la Píldora
    @ViewBuilder
    private var airPlayPickerContent: some View {
        VStack(spacing: 8) {
            // Cabecera del selector
            HStack {
                HStack(spacing: 6) {
                    let headerIcon = audioService.isAirPodsActive ? audioService.currentDeviceIcon : "airplayaudio"
                    Image(systemName: headerIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.blue)
                    Text("Salida de audio")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isShowingAirPlayPicker = false
                    }
                    appState.hapticService.triggerSnap()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // Lista de dispositivos con scroll suave si hay varios
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(audioService.getOutputDevices()) { dev in
                        Button(action: {
                            audioService.setDefaultOutputDevice(id: dev.id)
                            appState.hapticService.triggerSnap()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                isShowingAirPlayPicker = false
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: dev.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(dev.isDefault ? Color.blue : Color.white.opacity(0.65))
                                    .frame(width: 20)
                                
                                Text(dev.name)
                                    .font(.system(size: 12, weight: dev.isDefault ? .semibold : .regular, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if dev.isDefault {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color.blue)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(dev.isDefault ? Color.blue.opacity(0.18) : Color.white.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 90)
            
            // Acceso rápido a ajustes del sistema
            Button(action: {
                AudioDeviceService.shared.openSoundSettings()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                    Text("Ajustes de sonido...")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func showAirPlayMenu() {
        let menu = NSMenu(title: "AirPlay")
        let titleItem = NSMenuItem(title: "Salida de audio (AirPlay)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let devices = audioService.getOutputDevices()
        for dev in devices {
            let item = NSMenuItem(
                title: dev.name,
                action: #selector(AudioDeviceService.shared.selectDeviceMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = AudioDeviceService.shared
            item.representedObject = dev.id
            item.state = dev.isDefault ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "Ajustes de sonido...",
            action: #selector(AudioDeviceService.shared.openSoundSettings),
            keyEquivalent: ""
        )
        settingsItem.target = AudioDeviceService.shared
        menu.addItem(settingsItem)
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// Guía visual Pixel-Perfect y Monitor de Simetría para el modo Overlay
private struct PixelPerfectGuideView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let pad = PlayerMetrics.paddingInternal
        let offset = appState.overscrollOffset
        let contentOffset = appState.contentOverscrollOffset
        
        let leftMargin = pad + (offset < 0 ? abs(offset) : 0) + contentOffset
        let rightMargin = pad + (offset > 0 ? offset : 0) - contentOffset
        let delta = abs(leftMargin - rightMargin)
        let isAsymmetric = delta > 1.0
        
        ZStack {
            // Contorno de la forma de la píldora visible (Verde 65%)
            RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous)
                .stroke(Color.green.opacity(0.65), lineWidth: 1.5)
            
            // Contorno del contenido interno con padding (Naranja 60%)
            RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius - pad/2, style: .continuous)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                .padding(.horizontal, pad)
                .padding(.top, PlayerMetrics.topContentPadding - 12)
                .padding(.bottom, PlayerMetrics.bottomPadding)
            
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("📐 DEBUG SIMETRÍA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundColor(.green)
                    
                    Text("Izq: \(String(format: "%.1f", leftMargin)) pt | Der: \(String(format: "%.1f", rightMargin)) pt | Offset: \(String(format: "%.1f", offset)) pt")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    
                    if isAsymmetric && abs(offset) < 0.5 {
                        Text("⚠️ ASIMETRÍA > 1pt")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .foregroundColor(.white)
                    } else if abs(offset) < 0.5 {
                        Text("✅ SIMÉTRICO")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.8)))
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}
