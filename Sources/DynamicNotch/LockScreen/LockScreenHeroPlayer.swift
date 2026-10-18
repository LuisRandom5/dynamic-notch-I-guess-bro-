import SwiftUI
import AppKit

// MARK: - Reproductor compacto de la pantalla bloqueada (composición vertical estilo iPhone)
//
// Carátula protagonista arriba y una tarjeta de controles debajo que comparte su proporción (la tarjeta es
// apenas más ancha que la carátula). Orden: título/artista → progreso con tiempos → transporte.
// Sin efectos decorativos: el cambio de canción es un fundido, reproducir/pausa un cambio de símbolo, y el
// paso a pantalla completa es una transformación continua (carátula y superficie compartidas).

public enum LockScreenHeroMetrics {
    public static let artworkMaxSize: CGFloat = 268
    public static let artworkMinSize: CGFloat = 188
    /// La tarjeta sobresale 18 pt por lado de la carátula: relación visual clara sin duplicar el ancho
    public static let cardExtraWidth: CGFloat = 36
    public static let spacing: CGFloat = 14
    public static let cardCornerRadius: CGFloat = 28
    public static let artworkCornerRadiusRatio: CGFloat = 0.075
    public static let cardHeight: CGFloat = 160
    public static let cardHeightWithVolume: CGFloat = 188

    public static func cardHeight(showsVolume: Bool) -> CGFloat {
        showsVolume ? cardHeightWithVolume : cardHeight
    }

    /// Tamaño de carátula que cabe en el alto disponible (nil: no cabe a un tamaño legible → usar la
    /// variante horizontal)
    public static func artworkSize(availableHeight: CGFloat, showsVolume: Bool) -> CGFloat? {
        let size = min(artworkMaxSize, availableHeight - spacing - cardHeight(showsVolume: showsVolume))
        return size >= artworkMinSize ? size : nil
    }
}

struct LockScreenHeroPlayer: View {
    let artworkSize: CGFloat
    let namespace: Namespace.ID?
    let onExpand: () -> Void
    @Binding var isShowingRoutePicker: Bool

    @ObservedObject private var musicService = MusicService.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var audioService = AudioDeviceService.shared

    @State private var previousTick = 0
    @State private var nextTick = 0

    private var track: MusicTrack { musicService.currentTrack }
    private var isPrivacyMode: Bool { appState.lockScreenHideMediaDetails }
    private var trackKey: String { track.title + "|" + track.artist }
    private var cardWidth: CGFloat { artworkSize + LockScreenHeroMetrics.cardExtraWidth }

    var body: some View {
        VStack(spacing: LockScreenHeroMetrics.spacing) {
            artwork
            card
        }
    }

    // MARK: Carátula

    private var artwork: some View {
        let radius = artworkSize * LockScreenHeroMetrics.artworkCornerRadiusRatio
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if !isPrivacyMode, let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Cambio de canción: la carátula nueva aparece con un fundido, sin girar ni rebotar
                    .id(trackKey)
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: artworkSize * 0.24, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                )
            }
        }
        .animation(.easeInOut(duration: 0.35), value: trackKey)
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .lockMatched("lock.artwork", namespace)
        .shadow(color: .black.opacity(0.30), radius: 22, y: 10)
        // Como en Apple Music: en pausa la carátula se recoge un poco
        .scaleEffect(track.isPlaying ? 1.0 : 0.92)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: track.isPlaying)
        .contentShape(shape)
        .onTapGesture(perform: onExpand)
        .help("Toca para ver en pantalla completa")
    }

    // MARK: Tarjeta

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: LockScreenHeroMetrics.cardCornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            trackInfo
                .padding(.bottom, 13)
            LockScreenProgressScrubber()
                .padding(.bottom, 6)
            transport
            if appState.lockScreenShowVolumeSlider {
                LockScreenVolumeRow()
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(width: cardWidth, height: LockScreenHeroMetrics.cardHeight(showsVolume: appState.lockScreenShowVolumeSlider), alignment: .top)
        .background(
            LockScreenSurface(cornerRadius: LockScreenHeroMetrics.cardCornerRadius)
                .lockMatched("lock.surface", namespace)
        )
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    isPrivacyMode ? "Reproduciendo" : (track.title.isEmpty ? "Sin reproducción" : track.title),
                    fontSize: 15.5,
                    fontWeight: .semibold,
                    color: .white
                )
                .frame(height: 19)
                MarqueeText(
                    isPrivacyMode ? "Detalles ocultos" : track.artist,
                    fontSize: 14,
                    fontWeight: .regular,
                    color: .white.opacity(0.62)
                )
                .frame(height: 17)
            }
            // Título y artista cambian con un fundido; la tarjeta no se mueve
            .id(trackKey)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: trackKey)

            Spacer(minLength: 6)

            // Visualizador pequeño sólo mientras suena (aporta información: está sonando)
            if track.isPlaying && !isPrivacyMode {
                AudioVisualizer(isPlaying: true, colorMode: .fromArtwork(track.artwork))
                    .frame(width: 24, height: 12)
                    .transition(.opacity)
            }
            if !isPrivacyMode {
                LockScreenSourceIcon(appSource: track.appSource)
            }
        }
        .animation(.easeOut(duration: 0.25), value: track.isPlaying)
    }

    private var transport: some View {
        ZStack {
            HStack(spacing: 30) {
                Button {
                    previousTick += 1
                    musicService.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 21, weight: .regular))
                        .symbolEffect(.bounce.down, value: previousTick)
                }
                .buttonStyle(TransportButtonStyle(diameter: 42))

                Button {
                    musicService.togglePlayPause()
                } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 29, weight: .regular))
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(TransportButtonStyle(diameter: 50))

                Button {
                    nextTick += 1
                    musicService.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 21, weight: .regular))
                        .symbolEffect(.bounce.down, value: nextTick)
                }
                .buttonStyle(TransportButtonStyle(diameter: 42))
            }
            .foregroundStyle(.white)

            // Salida de audio: disponible pero discreta, sin competir con el transporte
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        isShowingRoutePicker.toggle()
                    }
                } label: {
                    Image(systemName: audioService.isAirPodsActive ? audioService.currentDeviceIcon : "airplayaudio")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(audioService.isAirPodsActive ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.white.opacity(0.55)))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Salida de audio: \(audioService.currentDeviceName)")
            }
        }
        .frame(height: 50)
    }
}

// MARK: - Superficie (material según el modo de apariencia)

/// Fondo de la tarjeta en la pantalla bloqueada. Sigue el modo de la app: negro OLED, o Liquid Glass
/// (clear, como el notch) con una capa de atenuación para que el texto se lea sobre cualquier fondo de
/// pantalla. Reducir transparencia / Aumentar contraste → OLED.
struct LockScreenSurface: View {
    let cornerRadius: CGFloat
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let mode = appState.effectiveAppearanceMode
        let isOLED = mode == .pureOLED || appState.lockScreenRenderMode == .pureOLED
        ZStack {
            if isOLED {
                shape.fill(Color.black)
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            } else if appState.lockScreenRenderMode == .solidDark {
                shape.fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.94))
            } else if appState.lockScreenRenderMode == .visualEffect {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .clipShape(shape)
            } else if #available(macOS 26.0, *) {
                // Atenuación: la que elija el usuario, con un piso mayor en "Cristal Oscuro"
                let dim = mode == .darkGlass
                    ? max(0.30, appState.lockScreenDimmingOpacity + 0.12)
                    : max(0.16, appState.lockScreenDimmingOpacity)
                ZStack {
                    Color.clear.glassEffect(Glass.clear, in: shape)
                    Color.black.opacity(dim).clipShape(shape)
                }
            } else {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .clipShape(shape)
                Color.black.opacity(appState.lockScreenDimmingOpacity).clipShape(shape)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Barra de progreso

/// Progreso fino con tiempos en cifras tabulares. Avanza de forma continua entre los reportes de posición,
/// sigue al dedo al arrastrar y, al soltar, se queda en el destino hasta que la reproducción lo alcanza
/// (no regresa a la posición vieja por una actualización atrasada).
struct LockScreenProgressScrubber: View {
    @ObservedObject private var musicService = MusicService.shared

    @State private var anchorPosition: Double = 0
    @State private var anchorDate: Date = Date()
    @State private var dragFraction: Double?
    @State private var pendingSeek: (target: Double, at: Date)?
    @State private var isHovering = false

    private var track: MusicTrack { musicService.currentTrack }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !track.isPlaying || dragFraction != nil)) { context in
            let duration = max(track.duration, 0.001)
            let live = min(duration, anchorPosition + (track.isPlaying ? context.date.timeIntervalSince(anchorDate) : 0))
            let position: Double = {
                if let drag = dragFraction { return drag * duration }
                if let pending = pendingSeek { return pending.target }
                return live
            }()
            let fraction = min(1, max(0, position / duration))
            let active = isHovering || dragFraction != nil
            let barHeight: CGFloat = active ? 7 : 5

            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.20))
                        Capsule()
                            .fill(Color.white.opacity(active ? 1 : 0.82))
                            .frame(width: max(barHeight, geo.size.width * fraction))
                    }
                    .frame(height: barHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(1, max(0, Double(value.location.x / geo.size.width)))
                            }
                            .onEnded { value in
                                let target = min(1, max(0, Double(value.location.x / geo.size.width))) * duration
                                musicService.seek(to: target)
                                pendingSeek = (target, Date())
                                anchorPosition = target
                                anchorDate = Date()
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) { isHovering = hovering }
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: dragFraction != nil)

                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, duration - position)))
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .onAppear { reanchor(track.playbackPosition) }
        .onChange(of: track.playbackPosition) { _, newValue in reanchor(newValue) }
        .onChange(of: track.isPlaying) { _, _ in reanchor(track.playbackPosition) }
    }

    private func reanchor(_ reported: Double) {
        if let pending = pendingSeek {
            // Ignorar reportes viejos hasta que la reproducción alcance el destino (o pasen 2 s)
            guard abs(reported - pending.target) < 1.5 || Date().timeIntervalSince(pending.at) > 2 else { return }
            pendingSeek = nil
        }
        anchorPosition = reported
        anchorDate = Date()
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Volumen (opcional)

struct LockScreenVolumeRow: View {
    @ObservedObject private var audioService = AudioDeviceService.shared
    @State private var dragVolume: Float?

    var body: some View {
        let volume = dragVolume ?? audioService.currentVolume
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9.5, weight: .medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.20))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(0, geo.size.width * CGFloat(volume)))
                }
                .frame(height: dragVolume != nil ? 6 : 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let v = Float(max(0, min(1, value.location.x / geo.size.width)))
                            dragVolume = v
                            audioService.setVolume(v)
                        }
                        .onEnded { _ in dragVolume = nil }
                )
            }
            .frame(height: 12)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Icono de la app de origen (secundario y discreto)

struct LockScreenSourceIcon: View {
    let appSource: String

    var body: some View {
        if let icon = Self.resolveIcon(appSource) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .opacity(0.75)
        }
    }

    static func resolveIcon(_ sourceName: String) -> NSImage? {
        let lower = (sourceName.isEmpty ? "Apple Music" : sourceName).lowercased()
        let bundleId: String?
        if lower.contains("spotify") { bundleId = "com.spotify.client" }
        else if lower.contains("music") || lower.contains("música") { bundleId = "com.apple.Music" }
        else if lower.contains("safari") { bundleId = "com.apple.Safari" }
        else if lower.contains("chrome") || lower.contains("youtube") { bundleId = "com.google.Chrome" }
        else if lower.contains("brave") { bundleId = "com.brave.Browser" }
        else if lower.contains("arc") { bundleId = "company.thebrowser.Browser" }
        else { bundleId = nil }
        guard let id = bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
