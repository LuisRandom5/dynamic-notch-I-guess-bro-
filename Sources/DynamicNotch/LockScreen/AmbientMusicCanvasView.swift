import SwiftUI
import AppKit
import Combine

/// Vista completa de Canvas Dinámico Ambiental con Letras Sincronizadas (Estilo Imagen 1).
/// Incluye:
/// - Fondo fluido dinámico generado a partir de los colores dominantes de la carátula con iluminación volumétrica.
/// - Encabezado superior con Reloj Hero y Fecha ("21:08  Tue, 29 Sep").
/// - Columna izquierda: Carátula Hero 1:1 cuadrada de alta fidelidad con resplandor ambiental difuminado.
/// - Columna derecha: Letras sincronizadas en tiempo real (Karaoke Synced Lyrics) con auto-scroll y resaltado blanco.
/// - Cápsula flotante inferior de Vidrio Líquido con ecualizador de 6 barras reactivas, scrubber y controles de reproducción.
public struct AmbientMusicCanvasView: View {
    @ObservedObject var musicService = MusicService.shared
    @ObservedObject var lyricsService = LyricsService.shared
    @ObservedObject var audioService = AudioDeviceService.shared
    @ObservedObject var appState = AppState.shared
    
    public var onDismiss: (() -> Void)?
    
    // Estados interactivos
    @State private var isSeeking: Bool = false
    @State private var seekProgress: Double = 0.0
    @State private var isHoveringProgress: Bool = false
    @State private var hoveredLineId: UUID? = nil
    @State private var currentDate: Date = Date()
    @State private var ambientBreathing: Bool = false
    
    // Timer para el reloj hero
    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    private var track: MusicTrack {
        musicService.currentTrack
    }
    
    private var progress: Double {
        if isSeeking { return seekProgress }
        guard track.duration > 0 else { return 0 }
        return min(max(track.playbackPosition / track.duration, 0.0), 1.0)
    }
    
    // Colores ambientales extraídos de la carátula
    private var primaryAmbientColor: Color {
        if let art = track.artwork {
            return ArtworkGradientCache.colors(for: art).top
        }
        return Color(red: 0.15, green: 0.28, blue: 0.65)
    }
    
    private var secondaryAmbientColor: Color {
        if let art = track.artwork {
            return ArtworkGradientCache.colors(for: art).bottom
        }
        return Color(red: 0.40, green: 0.18, blue: 0.60)
    }
    
    public var body: some View {
        ZStack {
            // MARK: - 1. Fondo Dinámico Ambiental Multicromático con Respiración
            ambientDynamicBackground
            
            // MARK: - 2. Capa Principal: Reloj, Contenido y Cápsula
            VStack(spacing: 0) {
                // Encabezado con Reloj y Fecha Hero ("21:08  Tue, 29 Sep")
                heroHeaderClockSection
                    .padding(.top, 64)
                    .padding(.bottom, 20)
                
                // Zona Central: Carátula 1:1 a la izquierda + Letras Sincronizadas a la derecha
                HStack(alignment: .center, spacing: 56) {
                    // Columna Izquierda: Carátula Hero 1:1
                    heroArtworkSection
                        .frame(width: 360)
                    
                    // Columna Derecha: Letras Sincronizadas
                    syncedLyricsSection
                        .frame(width: 540)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 48)
                
                // Cápsula Flotante Inferior de Vidrio Líquido
                floatingLiquidGlassCapsule
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Botón de cierre sutil en esquina superior derecha
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        SoundFeedbackService.shared.playActionDismissed()
                        if let dismiss = onDismiss {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                appState.lockScreenStyle = .heroWidget
                                appState.isAmbientCanvasOpen = false
                            }
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.40))
                            .padding(20)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .onReceive(clockTimer) { date in
            self.currentDate = date
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                ambientBreathing = true
            }
        }
    }
    
    // MARK: - 1. Fondo Ambiental con Resplandor Difuminado
    
    private var ambientDynamicBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Base oscura profunda
                Color(red: 0.05, green: 0.06, blue: 0.09)
                    .ignoresSafeArea()
                
                // Orbe 1: Color primario (superior izquierda)
                Circle()
                    .fill(primaryAmbientColor.opacity(0.48))
                    .frame(width: geo.size.width * 0.75, height: geo.size.width * 0.75)
                    .blur(radius: 95)
                    .offset(x: -geo.size.width * 0.20, y: -geo.size.height * 0.20)
                    .scaleEffect(ambientBreathing ? 1.08 : 0.94)
                
                // Orbe 2: Color secundario (inferior derecha)
                Circle()
                    .fill(secondaryAmbientColor.opacity(0.42))
                    .frame(width: geo.size.width * 0.70, height: geo.size.width * 0.70)
                    .blur(radius: 110)
                    .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.25)
                    .scaleEffect(ambientBreathing ? 0.95 : 1.08)
                
                // Atenuación uniforme para contraste perfecto del texto blanco
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - 2. Encabezado Hero: Reloj y Fecha
    
    private var heroHeaderClockSection: some View {
        VStack(spacing: 4) {
            Text(formattedClockTime)
                .font(.system(size: 74, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 4)
            
            Text(formattedHeroDate)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
    }
    
    private var formattedClockTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: currentDate)
    }
    
    private var formattedHeroDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: currentDate)
    }
    
    // MARK: - 3. Columna Izquierda: Carátula Hero 1:1
    
    private var heroArtworkSection: some View {
        let size: CGFloat = 340
        let cornerRadius: CGFloat = 26
        
        return ZStack {
            // Resplandor ambiental suave detrás de la carátula
            RadialGradient(
                colors: [
                    primaryAmbientColor.opacity(0.55),
                    primaryAmbientColor.opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: size * 0.85
            )
            .frame(width: size + 100, height: size + 100)
            .blur(radius: 36)
            
            // Imagen de la carátula
            Group {
                if let art = track.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [primaryAmbientColor, secondaryAmbientColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "music.note")
                            .font(.system(size: 72, weight: .light))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
            .scaleEffect(track.isPlaying ? 1.0 : 0.94)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: track.isPlaying)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    appState.lockScreenStyle = .heroWidget
                }
            }
            .help("Toca para volver a la tarjeta de música")
        }
    }
    
    // MARK: - 4. Columna Derecha: Letras Sincronizadas en Tiempo Real (Karaoke)
    
    private var syncedLyricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lyricsService.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Cargando letras...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lyricsService.lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 38))
                        .foregroundColor(.white.opacity(0.35))
                    Text("Letra no disponible")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            // Espaciador superior para que la primera línea comience centrada
                            Spacer(minLength: 120)
                            
                            ForEach(Array(lyricsService.lines.enumerated()), id: \.element.id) { index, line in
                                let isCurrent = (index == lyricsService.currentLineIndex)
                                let distance = abs(index - lyricsService.currentLineIndex)
                                
                                Button(action: {
                                    lyricsService.seekToLine(line)
                                }) {
                                    HStack(spacing: 8) {
                                        if isCurrent {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(Color.white)
                                                .opacity(0.90)
                                                .transition(.opacity.combined(with: .scale))
                                        }
                                        
                                        Text(line.text)
                                            .font(
                                                .system(
                                                    size: isCurrent ? 26 : (distance == 1 ? 21 : 19),
                                                    weight: isCurrent ? .bold : (distance <= 2 ? .semibold : .medium),
                                                    design: .rounded
                                                )
                                            )
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .foregroundColor(
                                                isCurrent
                                                    ? Color.white
                                                    : (distance <= 1 ? Color.white.opacity(0.55) : Color.white.opacity(0.28))
                                            )
                                            .blur(radius: isCurrent ? 0 : (distance <= 1 ? 0.3 : 1.1))
                                            .scaleEffect(isCurrent ? 1.03 : 1.0, anchor: .leading)
                                            .shadow(
                                                color: isCurrent ? Color.white.opacity(0.35) : Color.clear,
                                                radius: 8,
                                                x: 0,
                                                y: 2
                                            )
                                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)
                                    }
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                            
                            // Espaciador inferior para scroll holgado
                            Spacer(minLength: 160)
                        }
                        .padding(.vertical, 20)
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.88),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: lyricsService.currentLineIndex) { _, newIndex in
                        if newIndex < lyricsService.lines.count {
                            let targetId = lyricsService.lines[newIndex].id
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 5. Cápsula Flotante de Vidrio Líquido (Liquid Glass Floating Player)
    
    private var floatingLiquidGlassCapsule: some View {
        let width: CGFloat = 520
        let height: CGFloat = 136
        let cornerRadius: CGFloat = 36
        
        return VStack(spacing: 8) {
            // Fila Superior: Título • Artista a la izquierda + Ecualizador reactivo a la derecha
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text(track.title.isEmpty ? "Sin Reproducción" : track.title)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if !track.artist.isEmpty {
                        Text("•")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.50))
                        
                        Text(track.artist)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Ecualizador de 6 barras reactivo al audio real
                AudioVisualizer(
                    isPlaying: track.isPlaying,
                    colorMode: .fromArtwork(track.artwork)
                )
                .frame(width: 38, height: 16)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            
            // Fila Central: Scrubber de Progreso con Timestamps Monoespaciados
            HStack(spacing: 10) {
                Text(formatTime(isSeeking ? seekProgress * track.duration : track.playbackPosition))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.60))
                    .frame(width: 38, alignment: .leading)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                            .frame(height: isHoveringProgress ? 6 : 4)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(4, geo.size.width * CGFloat(progress)), height: isHoveringProgress ? 6 : 4)
                        
                        // Círculo interactivo (Scrubber Thumb)
                        if isHoveringProgress || isSeeking {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: Color.black.opacity(0.4), radius: 4)
                                .offset(x: max(0, min(geo.size.width - 12, geo.size.width * CGFloat(progress) - 6)))
                        }
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                isSeeking = true
                                let clamped = max(0.0, min(1.0, Double(val.location.x / geo.size.width)))
                                seekProgress = clamped
                            }
                            .onEnded { val in
                                let clamped = max(0.0, min(1.0, Double(val.location.x / geo.size.width)))
                                let targetTime = clamped * track.duration
                                musicService.seek(to: targetTime)
                                isSeeking = false
                            }
                    )
                    .onHover { h in
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                            isHoveringProgress = h
                        }
                    }
                }
                .frame(height: 14)
                
                let remaining = max(0, track.duration - (isSeeking ? seekProgress * track.duration : track.playbackPosition))
                Text("-\(formatTime(remaining))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.60))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            
            // Fila Inferior: Botones de Transporte Estilo Apple Control Center
            HStack(spacing: 34) {
                // Salto anterior (⏮)
                Button(action: {
                    musicService.previousTrack()
                    appState.hapticService.triggerSnap()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                
                // Play / Pause (⏯)
                Button(action: {
                    musicService.togglePlayPause()
                    appState.hapticService.triggerExpand()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.white.opacity(0.30), radius: 6)
                        
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color.black)
                            .offset(x: track.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                
                // Salto siguiente (⏭)
                Button(action: {
                    musicService.nextTrack()
                    appState.hapticService.triggerSnap()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.50), radius: 26, x: 0, y: 12)
        )
    }
    
    // MARK: - Helper de Formato de Tiempo
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
