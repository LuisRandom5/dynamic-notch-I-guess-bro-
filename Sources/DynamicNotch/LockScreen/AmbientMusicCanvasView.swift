import SwiftUI
import AppKit
import Combine

/// Reproductor de pantalla completa en la pantalla bloqueada, con el lenguaje visual de Apple Music:
/// - Tipografía SF Pro (la del sistema, la misma de Apple Music), sin la variante redondeada.
/// - Fondo de degradado animado con los colores de la carátula.
/// - Columna izquierda: carátula, título/artista, barra de progreso y controles de transporte con
///   animaciones de símbolo (pausa ↔ reproducir, rebote en anterior/siguiente) y estado de presión.
/// - Columna derecha: letras sincronizadas grandes y en negritas; la línea actual en blanco y el resto
///   atenuado, con desplazamiento suave y puntos "•••" en las partes instrumentales.
public struct AmbientMusicCanvasView: View {
    @ObservedObject var musicService = MusicService.shared
    @ObservedObject var lyricsService = LyricsService.shared
    @ObservedObject var appState = AppState.shared

    public var onDismiss: (() -> Void)?
    /// En la pantalla bloqueada: espacio de nombres compartido con el reproductor compacto, para que la
    /// carátula y la superficie se transformen de una presentación a la otra (matchedGeometryEffect)
    public var namespace: Namespace.ID?

    @State private var isSeeking: Bool = false
    @State private var seekProgress: Double = 0.0
    @State private var isHoveringProgress: Bool = false
    @State private var currentDate: Date = Date()
    @State private var previousTick: Int = 0
    @State private var nextTick: Int = 0
    /// El reloj y las letras aparecen cuando la carátula y el fondo ya van llegando a su lugar
    @State private var contentRevealed: Bool = false

    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(namespace: Namespace.ID? = nil, onDismiss: (() -> Void)? = nil) {
        self.namespace = namespace
        self.onDismiss = onDismiss
    }
    
    /// Negro OLED: fondo negro puro (los colores sólo vienen de la carátula y las letras)
    private var isOLED: Bool {
        appState.lockScreenRenderMode == .pureOLED || appState.effectiveAppearanceMode == .pureOLED
    }

    private var track: MusicTrack { musicService.currentTrack }
    
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var primaryColor: Color {
        track.artwork.map { ArtworkGradientCache.colors(for: $0).top } ?? Color(red: 0.20, green: 0.30, blue: 0.62)
    }

    private var secondaryColor: Color {
        track.artwork.map { ArtworkGradientCache.colors(for: $0).bottom } ?? Color(red: 0.42, green: 0.20, blue: 0.58)
    }

    public var body: some View {
        ZStack {
            AmbientArtworkBackground(primary: primaryColor, secondary: secondaryColor, isOLED: isOLED)
                // La superficie del reproductor compacto crece hasta ser este fondo
                .lockMatched("lock.surface", namespace)

            VStack(spacing: 0) {
                clockHeader
                    .padding(.top, 58)
                    .opacity(contentRevealed ? 1 : 0)

                HStack(alignment: .center, spacing: 72) {
                    playerColumn
                        .frame(width: 380)
                    lyricsColumn
                        .frame(width: 560)
                        .opacity(contentRevealed ? 1 : 0)
                        .offset(y: contentRevealed ? 0 : 18)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            closeButton
        }
        .environment(\.colorScheme, .dark)
        .onReceive(clockTimer) { currentDate = $0 }
        .onAppear {
            guard namespace != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                contentRevealed = true
                return
            }
            withAnimation(.easeOut(duration: 0.38).delay(0.18)) { contentRevealed = true }
        }
    }

    // MARK: - Reloj

    private var clockHeader: some View {
        VStack(spacing: 2) {
            Text(Self.clockFormatter.string(from: currentDate))
                .font(.system(size: 76, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(currentDate, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 3)
    }

    // MARK: - Columna del reproductor

    private var playerColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            artwork

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title.isEmpty ? "Sin reproducción" : track.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AudioVisualizer(isPlaying: track.isPlaying, colorMode: .fromArtwork(track.artwork))
                    .frame(width: 38, height: 16)
            }

            scrubber
            transportControls
                .frame(maxWidth: .infinity)
        }
    }

    private var artwork: some View {
        let size: CGFloat = 380
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Group {
            if let art = track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .lockMatched("lock.artwork", namespace)
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        // Como en Apple Music: la carátula se encoge un poco en pausa
        .scaleEffect(track.isPlaying ? 1.0 : 0.88)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: track.isPlaying)
        .contentShape(shape)
        .onTapGesture {
            onDismiss?()
        }
        .help("Toca para volver a la tarjeta de música")
    }

    private var scrubber: some View {
        TimelineView(.animation(paused: !track.isPlaying || isSeeking)) { _ in
            let duration = max(track.duration, 0.001)
            let position = isSeeking ? seekProgress * duration : min(duration, lyricsService.estimatedPosition)
            let fraction = min(1, max(0, position / duration))
            let barHeight: CGFloat = (isHoveringProgress || isSeeking) ? 10 : 6

            VStack(spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Color.white.opacity((isHoveringProgress || isSeeking) ? 1 : 0.85))
                            .frame(width: max(barHeight, geo.size.width * fraction))
                    }
                    .frame(height: barHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isSeeking = true
                                seekProgress = min(1, max(0, Double(value.location.x / geo.size.width)))
                            }
                            .onEnded { value in
                                let target = min(1, max(0, Double(value.location.x / geo.size.width))) * duration
                                musicService.seek(to: target)
                                isSeeking = false
                            }
                    )
                }
                .frame(height: 16)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isHoveringProgress = hovering }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSeeking)

                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text("-" + formatTime(max(0, duration - position)))
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 46) {
            Button {
                previousTick += 1
                musicService.previousTrack()
                appState.hapticService.triggerSnap()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28, weight: .regular))
                    .symbolEffect(.bounce.down, value: previousTick)
            }
            .buttonStyle(TransportButtonStyle(diameter: 60))

            Button {
                musicService.togglePlayPause()
                appState.hapticService.triggerExpand()
            } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38, weight: .regular))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(TransportButtonStyle(diameter: 72))

            Button {
                nextTick += 1
                musicService.nextTrack()
                appState.hapticService.triggerSnap()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28, weight: .regular))
                    .symbolEffect(.bounce.down, value: nextTick)
            }
            .buttonStyle(TransportButtonStyle(diameter: 60))
        }
        .foregroundStyle(.white)
    }

    // MARK: - Columna de letras

    @ViewBuilder
    private var lyricsColumn: some View {
        if lyricsService.isLoading {
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lyricsService.lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(lyricsService.isInstrumental ? "Instrumental" : "Letra no disponible")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if lyricsService.hasSyncedLyrics {
            SyncedLyricsView(lyrics: lyricsService)
        } else {
            unsyncedLyrics
        }
    }

    /// Letra sin tiempos: se muestra completa y fija, sin fingir sincronía
    private var unsyncedLyrics: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Letra sin sincronizar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 60)
                ForEach(lyricsService.lines) { line in
                    Text(line.text)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mask(LyricsFadeMask())
    }

    // MARK: - Cerrar

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    SoundFeedbackService.shared.playActionDismissed()
                    if let dismiss = onDismiss {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                            appState.lockScreenStyle = .heroWidget
                            appState.isAmbientCanvasOpen = false
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(22)
            }
            Spacer()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Letras sincronizadas

private struct SyncedLyricsView: View {
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Lazy: sólo se dibujan las líneas visibles (antes se componían todas, con desenfoque, en cada cuadro)
                LazyVStack(alignment: .leading, spacing: 26) {
                    Spacer(minLength: 150)

                    // Antes de la primera línea: puntos de introducción
                    if lyrics.currentLineIndex < 0, let first = lyrics.lines.first, first.timestamp > 3 {
                        InstrumentalDots(start: 0, end: first.timestamp, lyrics: lyrics)
                            .id("intro-dots")
                    }

                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let current = lyrics.currentLineIndex
                        let distance = abs(index - current)
                        let isCurrent = index == current

                        Button {
                            lyrics.seekToLine(line)
                        } label: {
                            Text(line.text)
                                .font(.system(size: 30, weight: .bold))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.white.opacity(isCurrent ? 1.0 : (index < current ? 0.30 : 0.36)))
                                // Desenfoque sólo en las líneas vecinas (las lejanas ya están atenuadas)
                                .blur(radius: (isCurrent || distance > 3) ? 0 : Double(distance) * 0.55)
                                .animation(.easeOut(duration: 0.35), value: isCurrent)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)

                        // Parte instrumental larga después de esta línea: "•••" que se van llenando
                        if isCurrent, index + 1 < lyrics.lines.count,
                           lyrics.lines[index + 1].timestamp - line.timestamp > 9 {
                            InstrumentalDots(start: line.timestamp + 3.5, end: lyrics.lines[index + 1].timestamp, lyrics: lyrics)
                        }
                    }

                    Spacer(minLength: 220)
                }
            }
            .mask(LyricsFadeMask())
            .onChange(of: lyrics.currentLineIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < lyrics.lines.count else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                    proxy.scrollTo(lyrics.lines[newIndex].id, anchor: UnitPoint(x: 0, y: 0.32))
                }
            }
            .onAppear {
                let index = lyrics.currentLineIndex
                if index >= 0, index < lyrics.lines.count {
                    proxy.scrollTo(lyrics.lines[index].id, anchor: UnitPoint(x: 0, y: 0.32))
                }
            }
        }
    }
}

/// Tres puntos que se van llenando durante una parte instrumental (como Apple Music).
private struct InstrumentalDots: View {
    let start: Double
    let end: Double
    @ObservedObject var lyrics: LyricsService
    @State private var breathe = false

    var body: some View {
        TimelineView(.animation) { _ in
            let span = max(0.1, end - start)
            let progress = min(1, max(0, (lyrics.estimatedPosition - start) / span))
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    let fill = min(1, max(0, progress * 3 - Double(i)))
                    Circle()
                        .fill(Color.white.opacity(0.25 + 0.75 * fill))
                        .frame(width: 12, height: 12)
                }
            }
            .scaleEffect(breathe ? 1.06 : 0.94, anchor: .leading)
            .opacity(progress > 0 ? 1 : 0.6)
        }
        .frame(height: 30)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

private struct LyricsFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Botones de transporte

/// Estado de presión al estilo iOS: el símbolo se encoge y aparece un círculo de resalte detrás.
struct TransportButtonStyle: ButtonStyle {
    let diameter: CGFloat
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : (isHovering ? 0.07 : 0)))
                    .scaleEffect(configuration.isPressed ? 1 : 0.82)
            )
            .contentShape(Circle())
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - Fondo

/// Degradado de los colores de la carátula que se mueve lentamente, oscurecido para que el texto se lea.
private struct AmbientArtworkBackground: View {
    let primary: Color
    let secondary: Color
    var isOLED: Bool = false
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
            if isOLED {
                // Negro puro: respeta el modo OLED también en pantalla completa
                Color.black
            } else if #available(macOS 15.0, *) {
                // Rendimiento: la malla se dibuja UNA vez y lo que se mueve es la capa (escala, giro y desplazamiento
                // con animaciones de Core Animation a la frecuencia de la pantalla). Antes se recalculaba la malla
                // a pantalla completa 30 veces por segundo y todo se veía a ≤30 fps.
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.55], [0.42, 0.48], [1, 0.45],
                        [0, 1], [0.6, 1], [1, 1]
                    ],
                    colors: [
                        primary, primary.opacity(0.85), secondary,
                        secondary.opacity(0.9), primary.opacity(0.75), secondary.opacity(0.8),
                        primary.opacity(0.7), secondary, primary.opacity(0.9)
                    ]
                )
                .scaleEffect(drift ? 1.45 : 1.30)
                .rotationEffect(.degrees(drift ? 14 : -10))
                .offset(x: drift ? 60 : -50, y: drift ? -36 : 30)
                .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: drift)
                .opacity(0.85)
                .onAppear { drift = true }
            } else {
                LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.8)
            }
            if !isOLED {
                Color.black.opacity(0.38)
            }
        }
        // La malla escalada no debe salirse del marco (durante la transformación desde la tarjeta)
        .clipped()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: primary)
    }
}

// MARK: - Transformación compartida con el reproductor compacto

extension View {
    /// `matchedGeometryEffect` sólo cuando hay espacio de nombres (en la ventana de escritorio no lo hay)
    @ViewBuilder
    func lockMatched(_ id: String, _ namespace: Namespace.ID?) -> some View {
        if let namespace = namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
