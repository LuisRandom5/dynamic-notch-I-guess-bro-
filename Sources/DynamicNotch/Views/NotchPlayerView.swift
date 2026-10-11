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
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Fondo con degradado vertical sutil: #000000 arriba -> #0B0B0B abajo desde 65%
            RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: PlayerMetrics.backgroundTopColor, location: 0.0),
                            .init(color: PlayerMetrics.backgroundTopColor, location: PlayerMetrics.backgroundShiftLocation),
                            .init(color: PlayerMetrics.backgroundBottomColor, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Borde de 1 pt: blanco 0% arriba -> blanco 10% abajo
                .overlay(
                    RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(PlayerMetrics.borderTopOpacity), location: 0.0),
                                    .init(color: Color.white.opacity(PlayerMetrics.borderMidOpacity), location: 0.50),
                                    .init(color: Color.white.opacity(PlayerMetrics.borderBottomOpacity), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: PlayerMetrics.borderWidth
                        )
                )
                // Sombra suave debajo
                .shadow(
                    color: Color.black.opacity(PlayerMetrics.shadowOpacity),
                    radius: PlayerMetrics.shadowRadius,
                    x: 0,
                    y: PlayerMetrics.shadowY
                )
            
            // Contenido interno con padding exacto de 18 pt
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - FILA 1: Carátula, Textos y Visualizador
                HStack(alignment: .top, spacing: PlayerMetrics.artworkToTextSpacing) {
                    // Carátula a la izquierda (click abre Apple Music / Spotify)
                    Button(action: {
                        appState.hapticService.triggerExpand()
                        musicService.openMusicApp()
                        appState.collapse()
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
                        .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(BouncyButtonStyle(scaleAmount: PlayerMetrics.buttonPressScale))
                    .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
                    // Si no hay música o no se contrae a compact, se desvanece
                    .notchContentExit(isExiting: (!musicService.hasActiveMusic) && topRowExiting)
                    .scaleEffect(animStage1 ? 1.0 : 0.90)
                    .opacity(animStage1 ? 1.0 : 0.0)
                    
                    // VStack de Título y Artista centrados verticalmente con la carátula
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
                    .frame(height: PlayerMetrics.artworkSize) // Centrado con la carátula
                    .notchContentExit(isExiting: topRowExiting)
                    .scaleEffect(animStage1 ? 1.0 : 0.94)
                    .opacity(animStage1 ? 1.0 : 0.0)
                    
                    // Visualizador alineado verticalmente con la línea del título (arriba a la derecha)
                    AudioVisualizer(
                        isPlaying: track.isPlaying,
                        colorMode: .fromArtwork(track.artwork)
                    )
                    .padding(.top, 3) // Alineación visual exacta con la línea del título
                    .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
                    .notchContentExit(isExiting: (!musicService.hasActiveMusic) && topRowExiting)
                    .scaleEffect(animStage1 ? 1.0 : 0.90)
                    .opacity(animStage1 ? 1.0 : 0.0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Espaciado exacto a la fila 2
                Spacer()
                    .frame(height: PlayerMetrics.row1ToRow2Spacing)
                
                // MARK: - FILA 2: Progreso y Tiempos
                HStack(spacing: PlayerMetrics.timeToBarSpacing) {
                    // Tiempo transcurrido
                    Text(formatTime(isSeeking ? seekPosition : track.playbackPosition))
                        .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(Color.white.opacity(PlayerMetrics.timeOpacity))
                        .frame(width: PlayerMetrics.timeWidth, alignment: .leading)
                    
                    // Barra continua sin perilla
                    GeometryReader { geo in
                        let currentProgress = track.duration > 0
                            ? (isSeeking ? seekPosition : track.playbackPosition) / track.duration
                            : 0.0
                        let barHeight = isHoveringBar ? PlayerMetrics.progressBarHoverHeight : PlayerMetrics.progressBarHeight
                        
                        ZStack(alignment: .leading) {
                            // Pista
                            Capsule(style: .continuous)
                                .fill(PlayerMetrics.progressBarTrackColor)
                                .frame(height: barHeight)
                            
                            // Relleno
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
                                    isSeeking = true
                                    let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                    seekPosition = track.duration * Double(ratio)
                                }
                                .onEnded { value in
                                    let ratio = max(0.0, min(1.0, value.location.x / geo.size.width))
                                    let newPos = track.duration * Double(ratio)
                                    musicService.seek(to: newPos)
                                    isSeeking = false
                                }
                        )
                    }
                    .frame(height: PlayerMetrics.progressBarHoverHeight)
                    
                    // Tiempo restante con signo menos (sin truncamiento con ...)
                    Text("-" + formatTime(max(0, track.duration - (isSeeking ? seekPosition : track.playbackPosition))))
                        .font(.system(size: PlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(Color.white.opacity(PlayerMetrics.timeOpacity))
                        .frame(width: PlayerMetrics.timeWidth, alignment: .trailing)
                }
                .notchContentExit(isExiting: progressExiting)
                .scaleEffect(animStage2 ? 1.0 : 0.94)
                .opacity(animStage2 ? 1.0 : 0.0)
                
                // Espaciado exacto a la fila 3
                Spacer()
                    .frame(height: PlayerMetrics.row2ToRow3Spacing)
                
                // MARK: - FILA 3: Controles
                // Controles centrados + Shuffle (izq) + AirPlay (der)
                ZStack {
                    // Controles Laterales: Shuffle a la izquierda y AirPlay a la derecha
                    HStack {
                        // Shuffle a la izquierda
                        PlayerControlButton(scaleAmount: 0.85, haloSize: 26) {
                            musicService.toggleShuffle()
                            appState.hapticService.triggerSnap()
                        } content: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(musicService.isShuffle ? Color.orange : PlayerMetrics.sideButtonColor)
                                .frame(width: PlayerMetrics.sideButtonWidth, height: PlayerMetrics.sideButtonWidth)
                        }
                        
                        Spacer()
                        
                        // Botón de AirPlay a la derecha (visible y funcional como botón robusto)
                        PlayerControlButton(scaleAmount: 0.85, haloSize: 26) {
                            appState.hapticService.triggerSnap()
                            showAirPlayMenu()
                        } content: {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(audioService.isAirPlayActive ? Color.blue : PlayerMetrics.sideButtonColor)
                                .frame(width: PlayerMetrics.sideButtonWidth, height: PlayerMetrics.sideButtonWidth)
                        }
                    }
                    
                    // Tres controles centrales centrados horizontalmente
                    HStack(spacing: PlayerMetrics.controlsCenterSpacing - PlayerMetrics.playPauseWidth) {
                        // Retroceso (~28 x 18 pt, blanco con micro-animación hacia la izquierda y confirmación visual)
                        PlayerControlButton(xOffset: -4.5, scaleAmount: 0.80, haloSize: 32) {
                            appState.hapticService.triggerSnap()
                            musicService.previousTrack()
                        } content: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: PlayerMetrics.skipButtonWidth, height: PlayerMetrics.skipButtonHeight)
                        }
                        
                        // Play / Pausa en el centro con halo de confirmación
                        PlayerControlButton(scaleAmount: 0.82, haloSize: 38) {
                            appState.hapticService.triggerExpand()
                            musicService.togglePlayPause()
                        } content: {
                            ZStack {
                                if track.isPlaying {
                                    // Pausa: dos barras redondeadas personalizadas
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
                                    // Play: triángulo redondeado
                                    Image(systemName: "play.fill")
                                        .font(.system(size: PlayerMetrics.playIconSize, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 1.5) // compensación óptica
                                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                                }
                            }
                            .frame(width: PlayerMetrics.playPauseWidth, height: PlayerMetrics.playPauseHeight)
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: track.isPlaying)
                        
                        // Avance (~28 x 18 pt, blanco con micro-animación hacia la derecha y confirmación visual)
                        PlayerControlButton(xOffset: 4.5, scaleAmount: 0.80, haloSize: 32) {
                            appState.hapticService.triggerSnap()
                            musicService.nextTrack()
                        } content: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: PlayerMetrics.skipButtonWidth, height: PlayerMetrics.skipButtonHeight)
                        }
                    }
                }
                .notchContentExit(isExiting: controlsExiting)
                .scaleEffect(animStage3 ? 1.0 : 0.94)
                .opacity(animStage3 ? 1.0 : 0.0)
            }
            .padding(.horizontal, PlayerMetrics.paddingInternal)
            .padding(.top, PlayerMetrics.topContentPadding)
            .padding(.bottom, PlayerMetrics.bottomPadding)
            
            // MARK: - MODO DEBUG DE COMPARACIÓN (OVERLAY)
            if debugOverlay.isOverlayActive {
                if let overlayImg = debugOverlay.overlayImage {
                    Image(nsImage: overlayImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: PlayerMetrics.cardWidth, height: PlayerMetrics.cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous))
                        .opacity(debugOverlay.opacity)
                        .allowsHitTesting(false)
                } else {
                    PixelPerfectGuideView()
                        .frame(width: PlayerMetrics.cardWidth, height: PlayerMetrics.cardHeight)
                        .opacity(debugOverlay.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: PlayerMetrics.cardWidth, height: PlayerMetrics.cardHeight)
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

// Guía visual Pixel-Perfect para el modo Overlay
private struct PixelPerfectGuideView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlayerMetrics.cornerRadius, style: .continuous)
                .stroke(Color.cyan.opacity(0.6), lineWidth: 1)
            
            VStack {
                HStack {
                    Text("📐 MODO OVERLAY (\(Int(PlayerMetrics.cardWidth))x\(Int(PlayerMetrics.cardHeight)))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                }
                .padding(PlayerMetrics.paddingInternal)
                Spacer()
            }
        }
    }
}
