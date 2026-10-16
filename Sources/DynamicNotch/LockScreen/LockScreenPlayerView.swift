import SwiftUI
import AppKit
import AVKit

/// Vista nativa Liquid Glass para el Reproductor en Pantalla de Bloqueo de macOS (macOS 15 Sequoia / macOS 26 Tahoe).
/// Cumple estrictamente con las especificaciones y feedback del usuario:
/// 1. Formato estirado horizontal estilo Apple Music / iOS Lockscreen (410 pt de ancho, ~120 pt de alto).
/// 2. Carátula miniatura (54 x 54 pt) en la tarjeta con esquinas continuas (12 pt), rotación 3D estilo Apple Music al cambiar de canción,
///    y animación fluida (.spring) que se expande a Carátula Hero (240 x 240 pt) con fondo ambiental dinámico (ambient glow).
/// 3. Cadena de renderizado Liquid Glass en 4 niveles (Paso 3):
///    - Tier 1: Liquid Glass nativo (.glassEffect en macOS 26+).
///    - Tier 2: NSVisualEffectView detrás de ventana (macOS 15+).
///    - Tier 3: CoreGraphics Private Window Blur (CGSSetWindowBackgroundBlurRadius de SkyLight).
///    - Tier 4: Sólido oscuro translúcido (Accesibilidad / Reduce Transparency).
/// 4. Selector nativo de salida de audio (NativeAudioRoutePicker / AVRoutePickerView).
/// 5. Ubicación optimizada: justo por encima del cuadro de contraseña, sin tapar el avatar ni el campo de entrada.
/// 6. Cero halo rectangular: ventana transparente, sin hasShadow de ventana, sombra exclusivamente en la silueta continua.
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
    
    // Triggers para efectos SF Symbols
    @State private var previousButtonTrigger: Int = 0
    @State private var nextButtonTrigger: Int = 0
    @State private var isPreviousHovered: Bool = false
    @State private var isPlayPauseHovered: Bool = false
    @State private var isNextHovered: Bool = false
    
    // Animaciones de transición y ecualizador
    @State private var eqPhase: Double = 0
    @State private var artworkRotationY: Double = 0
    @State private var heroArtworkRotationY: Double = 0
    
    public init() {}
    
    private var track: MusicTrack {
        musicService.currentTrack
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
    
    private var progress: Double {
        if isSeeking { return seekProgress }
        guard track.duration > 0 else { return 0 }
        return min(max(track.playbackPosition / track.duration, 0), 1)
    }
    
    private var currentVolume: Float {
        isDraggingVolume ? dragVolume : audioService.currentVolume
    }
    
    // Color dominante extraído de la carátula para el resplandor ambiental
    private var ambientGlowColor: Color {
        if let art = track.artwork {
            return ArtworkGradientCache.colors(for: art).top
        }
        return Color(red: 0.18, green: 0.35, blue: 0.85)
    }
    
    public var body: some View {
        ZStack {
            if appState.lockScreenStyle == .heroWidget {
                heroWidgetView
            } else {
                compactCardView
            }
            
            // Modo debug con contornos y selector de renderizado
            if appState.lockScreenDebugOutlines {
                debugOutlinesAndHUD
            }
        }
        .onChange(of: track.title + track.artist) { _, _ in
            triggerArtworkFlipTransition()
        }
    }
    
    // MARK: - 1. Estilo Hero Widget (iPhone Lockscreen con Carátula Expandible)
    
    private var heroWidgetView: some View {
        let hasVolume = appState.lockScreenShowVolumeSlider
        let panelHeight = hasVolume
            ? LockScreenPlayerMetrics.heroPanelHeightWithVolume
            : LockScreenPlayerMetrics.heroPanelHeight
            
        return VStack(spacing: LockScreenPlayerMetrics.heroSpacing) {
            Spacer(minLength: 0)
            
            // 1. Carátula Hero y Resplandor Ambiental (se muestra si está expandida)
            if appState.isLockScreenArtworkExpanded && !isPrivacyMode {
                heroArtworkWithAmbientGlow
                    .transition(
                        isReduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.88)).combined(with: .offset(y: 16)),
                                removal: .opacity.combined(with: .scale(scale: 0.88)).combined(with: .offset(y: 16))
                            )
                    )
            }
            
            // 2. Tarjeta Frosted Glass Estirada (Controles y miniatura condicional)
            heroFloatingCardView
        }
        .frame(width: LockScreenPlayerMetrics.heroPanelWidth, height: panelHeight)
        .animation(.spring(response: 0.40, dampingFraction: 0.80), value: appState.isLockScreenArtworkExpanded)
    }
    
    // MARK: - 1.1 Carátula Hero con Resplandor Ambiental Dinámico
    
    private var heroArtworkWithAmbientGlow: some View {
        let size = LockScreenPlayerMetrics.heroArtworkSize // 240 pt
        let cornerRadius = LockScreenPlayerMetrics.heroArtworkCornerRadius // 24 pt
        
        return ZStack {
            // Resplandor ambiental difuso detrás de la carátula
            RadialGradient(
                colors: [
                    ambientGlowColor.opacity(0.48),
                    ambientGlowColor.opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 160
            )
            .frame(width: size + 90, height: size + 90)
            .blur(radius: 36)
            .allowsHitTesting(false)
            
            // Sombra suave exterior
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(
                    color: Color.black.opacity(0.40),
                    radius: 24,
                    x: 0,
                    y: 12
                )
            
            // Imagen de carátula hero
            if let artwork = track.artwork {
                Image(nsImage: artwork)
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
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(.white.opacity(0.45))
                    )
            }
            
            // Borde sutil de definición
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isIncreaseContrast
                        ? Color.white.opacity(0.45)
                        : Color.white.opacity(0.16),
                    lineWidth: isIncreaseContrast ? 1.5 : 0.8
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(heroArtworkRotationY), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(track.isPlaying ? 1.0 : 0.94)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                appState.isLockScreenArtworkExpanded = false
            }
        }
        .help("Haz clic para contraer carátula")
    }
    
    // MARK: - 1.2 Tarjeta Flotante Horizontal Frosted Glass
    
    private var heroFloatingCardView: some View {
        let cardWidth = LockScreenPlayerMetrics.heroCardWidth // 410 pt
        let cardHeight = appState.lockScreenShowVolumeSlider
            ? LockScreenPlayerMetrics.heroCardHeightWithVolume
            : LockScreenPlayerMetrics.heroCardHeight
        let cornerRadius = LockScreenPlayerMetrics.heroCardCornerRadius // 26 pt
        
        return ZStack {
            // Sombra exterior suave propia de la silueta continua (cero halo de ventana)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(
                    color: Color.black.opacity(LockScreenPlayerMetrics.cardShadowOpacity),
                    radius: 20,
                    x: 0,
                    y: 8
                )
            
            // Fondo Liquid Glass según la cadena de renderizado Paso 3
            cardGlassBackground(cornerRadius: cornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            
            // Borde sutil de definición especular
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isIncreaseContrast
                        ? Color.white.opacity(0.48)
                        : Color.white.opacity(0.18),
                    lineWidth: isIncreaseContrast ? 1.5 : 0.8
                )
            
            // Contenido en rejilla horizontal
            HStack(spacing: appState.isLockScreenArtworkExpanded ? 0 : 14) {
                // 1. Miniatura interactiva de carátula a la izquierda (54 x 54 pt)
                // Se oculta automáticamente cuando la carátula grande está desplegada
                if !appState.isLockScreenArtworkExpanded {
                    thumbnailArtworkView
                        .transition(
                            isReduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.85)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                )
                        )
                }
                
                // 2. Columna de información, scrubber y controles
                VStack(spacing: 6) {
                    // Fila 1: Título, Artista + Mini Ecualizador y Badge
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1.5) {
                            MarqueeText(
                                isPrivacyMode ? "Reproduciendo audio" : (track.title.isEmpty ? "Sin reproducción" : track.title),
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
                        
                        // Mini ecualizador reactivo
                        heroEqualizerView
                        
                        // Badge con icono de la app nativa (Apple Music, Spotify, etc.)
                        if !isPrivacyMode {
                            appIconBadge(size: 18, radius: 5)
                        }
                    }
                    
                    // Fila 2: Scrubber timeline horizontal
                    HStack(spacing: 8) {
                        Text(formatTime(isSeeking ? seekProgress * track.duration : track.playbackPosition))
                            .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
                            .frame(width: 38, alignment: .leading)
                        
                        // Barra interactiva
                        GeometryReader { geo in
                            let w = geo.size.width
                            let curProgress = progress
                            let barHeight: CGFloat = (isHoveringProgressBar || isSeeking) ? 5.5 : 3.5
                            
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.20))
                                    .frame(height: barHeight)
                                
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: max(4, w * CGFloat(curProgress)), height: barHeight)
                            }
                            .frame(height: barHeight)
                            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: curProgress)
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
                        
                        let remaining = track.duration - (isSeeking ? seekProgress * track.duration : track.playbackPosition)
                        Text("-" + formatTime(max(remaining, 0)))
                            .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
                            .frame(width: 38, alignment: .trailing)
                    }
                    
                    // Fila 3: Controles multimedia + Selector de salida de audio nativo (AVRoutePickerView)
                    ZStack(alignment: .trailing) {
                        // Controles multimedia centrados
                        HStack(spacing: 28) {
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
                            
                            // Play / Pause
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
                        
                        // Selector de ruta de audio nativo (AVRoutePickerView / AirPlay)
                        NativeAudioRoutePicker()
                            .frame(width: 22, height: 22)
                            .padding(.trailing, 2)
                    }
                    
                    // Fila 4 opcional: Deslizador de volumen si está habilitado
                    if appState.lockScreenShowVolumeSlider {
                        volumeSliderRow
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    // MARK: - 1.3 Miniatura de Carátula (54 x 54 pt con rotación 3D y Tap para expandir)
    
    private var thumbnailArtworkView: some View {
        let size = LockScreenPlayerMetrics.heroThumbnailSize // 54 pt
        let cornerRadius = LockScreenPlayerMetrics.heroThumbnailCornerRadius // 12 pt
        
        return ZStack {
            if isPrivacyMode {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .light))
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
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(.white.opacity(0.40))
                        )
                }
                
                // Borde de definición
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(artworkRotationY), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(track.isPlaying ? 1.0 : 0.90)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)
        .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                appState.isLockScreenArtworkExpanded = true
            }
        }
        .help("Toca para expandir la carátula")
    }
    
    // MARK: - 2. Estilo Tarjeta Horizontal Compacta (macOS Tahoe)
    
    private var compactCardView: some View {
        let currentCardHeight = appState.lockScreenShowVolumeSlider
            ? LockScreenPlayerMetrics.cardHeightWithVolume
            : (isPrivacyMode ? 128 : LockScreenPlayerMetrics.cardHeightCompact)
            
        return ZStack {
            // Sombra externa
            RoundedRectangle(cornerRadius: LockScreenPlayerMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(
                    color: Color.black.opacity(LockScreenPlayerMetrics.cardShadowOpacity),
                    radius: LockScreenPlayerMetrics.cardShadowRadius,
                    x: 0,
                    y: LockScreenPlayerMetrics.cardShadowY
                )
            
            // Fondo Liquid Glass Paso 3
            cardGlassBackground(cornerRadius: LockScreenPlayerMetrics.cardCornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: LockScreenPlayerMetrics.cardCornerRadius, style: .continuous))
            
            // Borde sutil
            RoundedRectangle(cornerRadius: LockScreenPlayerMetrics.cardCornerRadius, style: .continuous)
                .stroke(
                    isIncreaseContrast
                        ? Color.white.opacity(0.50)
                        : Color.white.opacity(0.18),
                    lineWidth: isIncreaseContrast ? 1.5 : 0.8
                )
            
            // Contenido en 2 columnas
            HStack(spacing: 20) {
                // Carátula a la izquierda
                compactArtworkSection
                
                // Columna derecha
                VStack(alignment: .leading, spacing: 0) {
                    trackInfoSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 8)
                    
                    progressBarSection
                    
                    Spacer(minLength: 8)
                    
                    mediaControlsSection
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    if appState.lockScreenShowVolumeSlider {
                        Spacer(minLength: 8)
                        volumeSliderRow
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: LockScreenPlayerMetrics.rightColumnWidth)
            }
            .padding(LockScreenPlayerMetrics.cardPadding)
        }
        .frame(width: LockScreenPlayerMetrics.cardWidth, height: currentCardHeight)
    }
    
    // MARK: - 3. Cadena de Renderizado Liquid Glass (Paso 3)
    
    @ViewBuilder
    private func cardGlassBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        ZStack {
            if appState.effectiveAppearanceMode == .pureOLED {
                // Modo 100% Negro Puro OLED (#000000 opaco absoluto)
                Color.black
            } else if isReduceTransparency || appState.lockScreenRenderMode == .solidDark {
                // Tier 4: Sólido Oscuro
                Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.88)
            } else if appState.lockScreenRenderMode == .privateBlur {
                // Tier 3: CoreGraphics Private Window Blur (CGSSetWindowBackgroundBlurRadius)
                Color.black.opacity(0.35)
            } else if appState.lockScreenRenderMode == .visualEffect {
                // Tier 2: NSVisualEffectView Detrás de Ventana
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            } else {
                // Tier 1: Liquid Glass Nativo (.glassEffect en macOS 26+)
                if #available(macOS 26.0, *) {
                    GlassEffectContainer {
                        Color.clear
                            .glassEffect(Glass.regular, in: shape)
                    }
                } else {
                    // Fallback a Tier 2 en sistemas previos
                    VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                }
            }
            
            // Capa de atenuación uniforme independiente (solo en modos translúcidos/vidrio)
            if appState.effectiveAppearanceMode != .pureOLED {
                Color.black.opacity(appState.lockScreenDimmingOpacity)
            }
        }
    }
    
    // MARK: - Mini Ecualizador Reactivo
    
    private var heroEqualizerView: some View {
        HStack(spacing: 1.8) {
            ForEach(0..<4) { idx in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(
                        width: 2.2,
                        height: track.isPlaying ? (CGFloat(4 + ((idx * 3 + Int(eqPhase * 4)) % 8))) : 3
                    )
                    .animation(.easeInOut(duration: 0.22).repeatCount(1, autoreverses: true), value: eqPhase)
            }
        }
        .frame(width: 16, height: 14)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            if track.isPlaying {
                eqPhase = (eqPhase + 1).truncatingRemainder(dividingBy: 10)
            }
        }
    }
    
    // MARK: - Fila de Volumen
    
    private var volumeSliderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: currentVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16)
        }
    }
    
    // MARK: - Secciones del Estilo Compacto
    
    private var compactArtworkSection: some View {
        let size = isPrivacyMode ? 96 : LockScreenPlayerMetrics.artworkSize
        let cornerRadius = LockScreenPlayerMetrics.artworkCornerRadius
        
        return ZStack {
            if isPrivacyMode {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 38, weight: .light))
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
                                colors: [Color.gray.opacity(0.35), Color.black.opacity(0.60)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 42, weight: .light))
                                .foregroundColor(.white.opacity(0.45))
                        )
                }
                
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(artworkRotationY), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(track.isPlaying ? 1.0 : 0.88)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: track.isPlaying)
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
    }
    
    private var trackInfoSection: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    isPrivacyMode ? "Reproduciendo audio" : (track.title.isEmpty ? "Sin reproducción" : track.title),
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
            
            if !isPrivacyMode {
                appIconBadge(size: LockScreenPlayerMetrics.appIconSize, radius: LockScreenPlayerMetrics.appIconCornerRadius)
            }
        }
    }
    
    private var progressBarSection: some View {
        VStack(spacing: 5) {
            let barHeight = (isHoveringProgressBar || isSeeking)
                ? LockScreenPlayerMetrics.progressBarHeightHovered
                : LockScreenPlayerMetrics.progressBarHeightResting
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(LockScreenPlayerMetrics.progressTrackOpacity))
                        .frame(height: barHeight)
                    
                    Capsule()
                        .fill(Color.white.opacity(LockScreenPlayerMetrics.progressFillOpacity))
                        .frame(width: max(geo.size.width * progress, 0), height: barHeight)
                }
                .frame(height: barHeight)
                .animation(LockScreenPlayerMetrics.progressHoverSpring, value: barHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let newProg = max(0, min(1, value.location.x / geo.size.width))
                            seekProgress = newProg
                        }
                        .onEnded { value in
                            let finalProg = max(0, min(1, value.location.x / geo.size.width))
                            let targetTime = finalProg * track.duration
                            musicService.seek(to: targetTime)
                            seekProgress = finalProg
                            isSeeking = false
                        }
                )
                .onHover { hovering in
                    withAnimation(LockScreenPlayerMetrics.progressHoverSpring) {
                        isHoveringProgressBar = hovering
                    }
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(formatTime(isSeeking ? seekProgress * track.duration : track.playbackPosition))
                    .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
                
                Spacer()
                
                let remaining = track.duration - (isSeeking ? seekProgress * track.duration : track.playbackPosition)
                Text("-" + formatTime(max(remaining, 0)))
                    .font(.system(size: LockScreenPlayerMetrics.timeFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color.white.opacity(LockScreenPlayerMetrics.timeOpacity))
            }
        }
    }
    
    private var mediaControlsSection: some View {
        HStack(spacing: LockScreenPlayerMetrics.controlsSpacing) {
            Button(action: {
                previousButtonTrigger += 1
                musicService.previousTrack()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: LockScreenPlayerMetrics.skipButtonWidth, height: 32)
                    .contentShape(Rectangle())
                    .symbolEffect(.bounce, value: previousButtonTrigger)
            }
            .buttonStyle(PressedScaleButtonStyle())
            
            Button(action: {
                musicService.togglePlayPause()
            }) {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: LockScreenPlayerMetrics.playPauseButtonWidth, height: 36)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressedScaleButtonStyle())
            
            Button(action: {
                nextButtonTrigger += 1
                musicService.nextTrack()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: LockScreenPlayerMetrics.skipButtonWidth, height: 32)
                    .contentShape(Rectangle())
                    .symbolEffect(.bounce, value: nextButtonTrigger)
            }
            .buttonStyle(PressedScaleButtonStyle())
            
            // Selector de audio nativo
            NativeAudioRoutePicker()
                .frame(width: 24, height: 24)
        }
    }
    
    // MARK: - Transición 3D de Rotación de Carátula al cambiar canción
    
    private func triggerArtworkFlipTransition() {
        guard !isReduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.20)) {
            artworkRotationY = 90
            heroArtworkRotationY = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                artworkRotationY = 0
                heroArtworkRotationY = 0
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
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
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
    
    private func resolveAppIcon(for sourceName: String) -> NSImage? {
        let name = sourceName.lowercased()
        let bundleID: String
        if name.contains("music") {
            bundleID = "com.apple.Music"
        } else if name.contains("spotify") {
            bundleID = "com.spotify.client"
        } else if name.contains("safari") {
            bundleID = "com.apple.Safari"
        } else if name.contains("chrome") {
            bundleID = "com.google.Chrome"
        } else if name.contains("arc") {
            bundleID = "company.thebrowser.Browser"
        } else if name.contains("podcasts") {
            bundleID = "com.apple.podcasts"
        } else {
            bundleID = "com.apple.Music"
        }
        
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let total = Int(max(seconds, 0))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Estilo de botón que aplica la micro-escala 0.92 al presionar solicitada para los controles
public struct PressedScaleButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LockScreenPlayerMetrics.buttonPressedScale : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: configuration.isPressed)
    }
}
