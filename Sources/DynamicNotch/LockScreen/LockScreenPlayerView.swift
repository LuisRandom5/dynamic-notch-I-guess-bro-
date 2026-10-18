import SwiftUI
import AppKit
import AVKit

/// Vista nativa Liquid Glass y OLED para el Reproductor en Pantalla de Bloqueo de macOS (Apple HIG / macOS Tahoe).
/// Cumple estrictamente con las especificaciones y feedback del usuario:
/// 1. Formato dual adaptativo:
///    - Vertical Hero (iPhone Lockscreen): Carátula 1:1 cuadrada prominente (220 x 220 pt) con sutil ambient glow + cápsula de controles (410 pt).
///    - Horizontal Compacto (macOS): Carátula 1:1 cuadrada (108 x 108 pt), metadatos, barra interactiva y controles en una composición unificada.
/// 2. Barras reactivas al sonido en tiempo real (AudioVisualizer) integradas en ambas presentaciones, respondiendo al audio real del sistema.
/// 3. Modo OLED 100% Negro Puro (#000000 opaco absoluto, cero transparencias no deseadas) y Liquid Glass nativo (.hudWindow / .glassEffect).
/// 4. Scrubber interactivo con cifras tabulares monoespaciadas ("1:24", "-2:36"), hover suave y búsqueda fluida.
/// 5. Controles multimedia estilo Apple Control Center con respuesta de resorte y transiciones de símbolo.
/// 6. Seguridad y privacidad: ventana no-key para jamás bloquear Touch ID o contraseña; modo privacidad configurable.
public struct LockScreenPlayerView: View {
    @ObservedObject var musicService = MusicService.shared
    @ObservedObject var appState = AppState.shared
    @ObservedObject var audioService = AudioDeviceService.shared
    
    // Estados interactivos locales
    @State private var isSeeking: Bool = false
    @State private var seekProgress: Double = 0.0
    @State private var isHoveringProgressBar: Bool = false
    @State private var isDraggingVolume: Bool = false
    @State private var dragVolume: Float = 0.5
    @State private var isShowingRoutePicker: Bool = false
    
    // Triggers para efectos SF Symbols
    @State private var previousButtonTrigger: Int = 0
    @State private var nextButtonTrigger: Int = 0
    
    public init() {}
    
    private var isDemoPreview: Bool {
        (LockScreenManager.shared.isPreviewMode || AppState.shared.isLockScreenTestArmed) && musicService.currentTrack.title.isEmpty
    }
    
    private var track: MusicTrack {
        if isDemoPreview {
            return MusicTrack(
                title: "Starboy",
                artist: "The Weeknd ft. Daft Punk",
                album: "Starboy",
                artwork: NSImage(named: NSImage.applicationIconName),
                isPlaying: true,
                playbackPosition: 84,
                duration: 230,
                appSource: "Apple Music"
            )
        }
        return musicService.currentTrack
    }
    
    private var isPrivacyMode: Bool {
        appState.lockScreenHideMediaDetails
    }
    
    private var isReduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    
    private var isIncreaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    
    private var isReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    private var isOLED: Bool {
        appState.lockScreenRenderMode == .pureOLED || appState.effectiveAppearanceMode == .pureOLED
    }
    
    private var progress: Double {
        if isSeeking { return seekProgress }
        guard track.duration > 0 else { return 0 }
        return min(max(track.playbackPosition / track.duration, 0), 1)
    }
    
    private var currentVolume: Float {
        isDraggingVolume ? dragVolume : audioService.currentVolume
    }
    
    // Color dominante extraído de la carátula para el resplandor ambiental (clamped y sutil)
    private var ambientGlowColor: Color {
        if let art = track.artwork {
            return ArtworkGradientCache.colors(for: art).top
        }
        return Color(red: 0.18, green: 0.35, blue: 0.85)
    }
    
    @Namespace private var stageNamespace
    
    /// Transformación compacto ⇄ pantalla completa: resorte sin rebote; con Reducir movimiento, fundido
    private var stageAnimation: Animation {
        isReduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.58, dampingFraction: 0.88)
    }
    
    private func setFullscreen(_ value: Bool) {
        if value { SoundFeedbackService.shared.playBubblePop() }
        withAnimation(stageAnimation) {
            appState.isLockScreenFullscreen = value
        }
    }
    
    /// La ventana cubre toda la pantalla bloqueada: el reproductor compacto se coloca en el hueco entre el
    /// reloj y el bloque de usuario/Touch ID, y la pantalla completa ocupa todo. Así el paso de uno a otro es
    /// una sola transformación continua (carátula y superficie compartidas) sin redimensionar ventanas.
    /// Las zonas vacías son transparentes y los clics las atraviesan hacia la pantalla de inicio de sesión.
    public var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            // Hueco disponible: debajo del reloj (~28%) y encima del usuario/Touch ID (~79%)
            let regionTop = height * 0.28 - appState.lockScreenVerticalOffset
            let regionBottom = height * 0.79 - appState.lockScreenVerticalOffset
            let available = regionBottom - regionTop
            // El reproductor se apoya abajo del hueco, justo arriba de la foto de perfil (no centrado)
            let playerBottom = height * 0.755 - appState.lockScreenVerticalOffset
            let heroHeight = LockScreenHeroMetrics.cardHeight(showsVolume: appState.lockScreenShowVolumeSlider)
            let compactHeight = appState.lockScreenShowVolumeSlider
                ? LockScreenPlayerMetrics.compactCardHeightWithVolume
                : (isPrivacyMode ? 120 : LockScreenPlayerMetrics.compactCardHeight)
            let heroFits = available >= LockScreenHeroMetrics.cardHeight(showsVolume: appState.lockScreenShowVolumeSlider)
            let namespace = isReduceMotion ? nil : stageNamespace
            
            ZStack {
                if appState.isLockScreenFullscreen {
                    AmbientMusicCanvasView(namespace: namespace) {
                        setFullscreen(false)
                    }
                    .transition(.opacity)
                } else if appState.lockScreenStyle != .compactCard && heroFits {
                    LockScreenHeroPlayer(
                        namespace: namespace,
                        onExpand: { setFullscreen(true) },
                        isShowingRoutePicker: $isShowingRoutePicker
                    )
                    .position(x: geo.size.width / 2, y: playerBottom - heroHeight / 2)
                    .transition(.opacity)
                } else {
                    // Variante horizontal: estilo elegido o pantallas donde la vertical no cabe legible
                    compactCardView
                        .position(x: geo.size.width / 2, y: playerBottom - compactHeight / 2)
                        .transition(.opacity)
                }
                
                // Selector interactivo de ruta de audio (AirPods / Altavoces / AirPlay)
                if isShowingRoutePicker {
                    lockScreenRoutePickerOverlay
                }
                
                // Modo debug con contornos y selector de renderizado
                if appState.lockScreenDebugOutlines {
                    debugOutlinesAndHUD
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    // MARK: - 2. Estilo Tarjeta Horizontal Compacta (macOS Nativo)
    
    private var compactCardView: some View {
        let cardWidth = LockScreenPlayerMetrics.compactCardWidth // 460 pt
        let cardHeight = appState.lockScreenShowVolumeSlider
            ? LockScreenPlayerMetrics.compactCardHeightWithVolume
            : (isPrivacyMode ? 120 : LockScreenPlayerMetrics.compactCardHeight)
        let cornerRadius = LockScreenPlayerMetrics.compactCardCornerRadius // 24 pt
        
        return ZStack {
            // Sombra externa continua
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(
                    color: Color.black.opacity(LockScreenPlayerMetrics.cardShadowOpacity),
                    radius: LockScreenPlayerMetrics.cardShadowRadius,
                    x: 0,
                    y: LockScreenPlayerMetrics.cardShadowY
                )
            
            // Fondo: negro OLED o Liquid Glass según el modo de la app (misma superficie que la vertical)
            LockScreenSurface(cornerRadius: cornerRadius)
                .lockMatched("lock.surface", isReduceMotion ? nil : stageNamespace)
            
            // Contenido en 2 columnas equilibradas
            HStack(spacing: 16) {
                // Carátula cuadrada 1:1 a la izquierda
                compactArtworkSection
                
                // Columna derecha con metadatos, barras reactivas, scrubber y controles
                VStack(alignment: .leading, spacing: 0) {
                    compactTrackInfoSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 6)
                    
                    timelineScrubberSection
                    
                    Spacer(minLength: 6)
                    
                    compactMediaControlsSection
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    if appState.lockScreenShowVolumeSlider {
                        Spacer(minLength: 6)
                        volumeSliderRow
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(LockScreenPlayerMetrics.compactPadding)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    // MARK: - Mini Ecualizador Reactivo al Sonido Real
    
    private var heroEqualizerView: some View {
        AudioVisualizer(
            isPlaying: track.isPlaying,
            colorMode: .fromArtwork(track.artwork)
        )
    }
    
    // MARK: - Scrubber Timeline con Cifras Tabulares
    
    private var timelineScrubberSection: some View {
        HStack(spacing: 8) {
            // Tiempo transcurrido con cifras monoespaciadas para estabilidad visual
            Text(formatTime(isSeeking ? seekProgress * track.duration : track.playbackPosition))
                .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
                .frame(width: 36, alignment: .leading)
            
            // Barra interactiva de búsqueda
            GeometryReader { geo in
                let w = geo.size.width
                let curProgress = progress
                let barHeight: CGFloat = (isHoveringProgressBar || isSeeking)
                    ? LockScreenPlayerMetrics.progressBarHeightHovered
                    : LockScreenPlayerMetrics.progressBarHeightResting
                
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(LockScreenPlayerMetrics.progressTrackOpacity))
                        .frame(height: barHeight)
                    
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(LockScreenPlayerMetrics.progressFillOpacity))
                        .frame(width: max(4, w * CGFloat(curProgress)), height: barHeight)
                }
                .frame(height: barHeight)
                .animation(LockScreenPlayerMetrics.progressHoverSpring, value: curProgress)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let ratio = max(0.0, min(1.0, value.location.x / w))
                            seekProgress = Double(ratio)
                        }
                        .onEnded { value in
                            let ratio = max(0.0, min(1.0, value.location.x / w))
                            let targetSec = Double(ratio) * track.duration
                            musicService.seek(to: targetSec)
                            isSeeking = false
                        }
                )
            }
            .frame(height: 10)
            .onHover { isHoveringProgressBar = $0 }
            
            // Tiempo restante con signo negativo
            let remaining = track.duration - (isSeeking ? seekProgress * track.duration : track.playbackPosition)
            Text("-" + formatTime(max(remaining, 0)))
                .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    // MARK: - Controles Multimedia
    
    private var mediaControlsCenter: some View {
        HStack(spacing: LockScreenPlayerMetrics.controlsSpacing) {
            // Anterior
            Button(action: {
                previousButtonTrigger += 1
                musicService.previousTrack()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: previousButtonTrigger)
            }
            .buttonStyle(PressedScaleButtonStyle())
            
            // Play / Pause con morfismo de icono
            Button(action: {
                musicService.togglePlayPause()
            }) {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressedScaleButtonStyle())
            
            // Siguiente
            Button(action: {
                nextButtonTrigger += 1
                musicService.nextTrack()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: nextButtonTrigger)
            }
            .buttonStyle(PressedScaleButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var compactMediaControlsSection: some View {
        ZStack(alignment: .trailing) {
            mediaControlsCenter
            
            audioRouteButton
                .padding(.trailing, 2)
        }
    }
    
    // MARK: - Botón dinámico de ruta de audio (AirPods 4 / Altavoces)
    
    private var audioRouteButton: some View {
        Button(action: {
            appState.hapticService.triggerSnap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isShowingRoutePicker.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(audioService.isAirPodsActive ? Color.blue.opacity(0.24) : Color.white.opacity(0.12))
                    .frame(width: 26, height: 26)
                
                Image(systemName: audioService.isAirPodsActive ? audioService.currentDeviceIcon : "airplayaudio")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(audioService.isAirPodsActive ? Color(red: 0.35, green: 0.75, blue: 1.0) : Color.white.opacity(0.85))
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help("Ruta de audio: \(audioService.currentDeviceName)")
    }
    
    // MARK: - Menú flotante interactivo de salidas de audio para Lock Screen
    
    private var lockScreenRoutePickerOverlay: some View {
        ZStack {
            // Fondo atenuado táctil para cerrar al tocar fuera
            Color.black.opacity(0.40)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isShowingRoutePicker = false
                    }
                }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: audioService.currentDeviceIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                    
                    Text("Salida de audio")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isShowingRoutePicker = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 2)
                
                VStack(spacing: 5) {
                    ForEach(audioService.getOutputDevices()) { dev in
                        Button(action: {
                            audioService.setDefaultOutputDevice(id: dev.id)
                            appState.hapticService.triggerSnap()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isShowingRoutePicker = false
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: dev.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(dev.isDefault ? Color.blue : Color.white.opacity(0.70))
                                    .frame(width: 20)
                                
                                Text(dev.name)
                                    .font(.system(size: 12, weight: dev.isDefault ? .semibold : .regular, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if dev.isDefault {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.blue)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(dev.isDefault ? Color.blue.opacity(0.20) : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 290)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.96))
                    .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
    
    // MARK: - Fila de Volumen Opcional
    
    private var volumeSliderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: currentVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 14)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: isDraggingVolume ? 5 : 3.5)
                    
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: max(geo.size.width * CGFloat(currentVolume), 0), height: isDraggingVolume ? 5 : 3.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingVolume = true
                            let newVol = Float(max(0, min(1, value.location.x / geo.size.width)))
                            dragVolume = newVol
                            audioService.setVolume(newVol)
                        }
                        .onEnded { value in
                            let newVol = Float(max(0, min(1, value.location.x / geo.size.width)))
                            audioService.setVolume(newVol)
                            isDraggingVolume = false
                        }
                )
            }
            .frame(height: 8)
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 16)
        }
    }
    
    // MARK: - Secciones del Estilo Compacto
    
    private var compactArtworkSection: some View {
        let size = isPrivacyMode ? 86 : LockScreenPlayerMetrics.compactArtworkSize // 108 pt
        let cornerRadius = LockScreenPlayerMetrics.compactArtworkCornerRadius // 16 pt
        
        return ZStack {
            if isPrivacyMode {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(.white.opacity(0.60))
                    )
            } else {
                if let art = track.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.28, blue: 0.85), Color(red: 0.05, green: 0.10, blue: 0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 38, weight: .light))
                                .foregroundColor(.white.opacity(0.45))
                        )
                }
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
            }
        }
        .frame(width: size, height: size)
        .lockMatched("lock.artwork", isReduceMotion ? nil : stageNamespace)
        .scaleEffect(track.isPlaying ? 1.0 : LockScreenPlayerMetrics.pausedScale)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            setFullscreen(true)
        }
        .help("Toca para abrir el Canvas a pantalla completa")
    }
    
    private var compactTrackInfoSection: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    isPrivacyMode ? "Reproduciendo" : (track.title.isEmpty ? "Sin reproducción" : track.title),
                    fontSize: LockScreenPlayerMetrics.titleFontSize,
                    fontWeight: LockScreenPlayerMetrics.titleFontWeight,
                    color: .white
                )
                .frame(height: 18)
                
                MarqueeText(
                    isPrivacyMode ? "Detalles ocultos" : (track.artist.isEmpty ? "Dynamic Notch" : track.artist),
                    fontSize: LockScreenPlayerMetrics.artistFontSize,
                    fontWeight: LockScreenPlayerMetrics.artistFontWeight,
                    color: Color.white.opacity(LockScreenPlayerMetrics.artistOpacity)
                )
                .frame(height: 15)
            }
            
            Spacer(minLength: 4)
            
            // Barras reactivas al sonido en tiempo real en la pantalla de bloqueo
            heroEqualizerView
                .padding(.trailing, 2)
            
            if !isPrivacyMode {
                appIconBadge(size: LockScreenPlayerMetrics.appIconSize, radius: LockScreenPlayerMetrics.appIconCornerRadius)
            }
        }
    }
    
    // MARK: - Insignia de Icono Nativo
    
    @ViewBuilder
    private func appIconBadge(size: CGFloat, radius: CGFloat) -> some View {
        let appSource = track.appSource.isEmpty ? "Apple Music" : track.appSource
        if let icon = resolveAppIcon(for: appSource) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .opacity(0.90)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
        } else {
            Image(systemName: appSource.lowercased().contains("spotify") ? "waveform" : "music.note")
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
        }
    }
    
    // MARK: - Selector de Renderizado y HUD de Debug
    
    private var debugOutlinesAndHUD: some View {
        VStack {
            HStack {
                Button(action: {
                    cycleRenderMode()
                }) {
                    Text("🎨 Render: \(appState.lockScreenRenderMode.displayName)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(appState.lockScreenStyle == .heroWidget ? "Hero Widget" : "Compact Card")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(5)
            }
            .padding(6)
            
            Spacer()
        }
        .allowsHitTesting(true)
    }
    
    private func cycleRenderMode() {
        let modes = AppState.LockScreenRenderMode.allCases
        if let idx = modes.firstIndex(of: appState.lockScreenRenderMode) {
            let nextIdx = (idx + 1) % modes.count
            appState.lockScreenRenderMode = modes[nextIdx]
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = max(0, Int(seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func resolveAppIcon(for sourceName: String) -> NSImage? {
        let lower = sourceName.lowercased()
        var bundleId: String? = nil
        if lower.contains("spotify") {
            bundleId = "com.spotify.client"
        } else if lower.contains("music") || lower.contains("música") {
            bundleId = "com.apple.Music"
        } else if lower.contains("safari") {
            bundleId = "com.apple.Safari"
        } else if lower.contains("chrome") {
            bundleId = "com.google.Chrome"
        } else if lower.contains("brave") {
            bundleId = "com.brave.Browser"
        } else if lower.contains("arc") {
            bundleId = "company.thebrowser.Browser"
        } else if lower.contains("youtube") {
            bundleId = "com.google.Chrome"
        }
        
        if let bid = bundleId, let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: appUrl.path)
        }
        return nil
    }
}

public struct PressedScaleButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LockScreenPlayerMetrics.buttonPressedScale : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

