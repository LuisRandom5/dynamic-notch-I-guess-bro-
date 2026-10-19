import SwiftUI

public struct NotchCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var screenService: ScreenService
    
    public var namespace: Namespace.ID?
    /// Mínima pegada: sólo el ala izquierda (carátula) con este ancho; nil = compacta con sus dos alas
    public var minimalWingWidth: CGFloat?
    private var wingWidth: CGFloat { minimalWingWidth ?? NotchTuning.compactWingWidth }
    /// La repisa ya no ocupa espacio en las alas (es una bolita)
    private let wingExtra: CGFloat = 0
    
    public init(namespace: Namespace.ID? = nil, minimalWingWidth: CGFloat? = nil) {
        self.namespace = namespace
        self.minimalWingWidth = minimalWingWidth
    }
    
    private var trackColor: Color {
        let src = musicService.currentTrack.appSource.lowercased()
        if src.contains("spotify") {
            return Color(red: 0.11, green: 0.84, blue: 0.38)
        } else if src.contains("youtube") {
            return Color(red: 1.00, green: 0.15, blue: 0.15)
        } else if src.contains("safari") {
            return Color(red: 0.00, green: 0.50, blue: 1.00)
        } else if src.contains("chrome") {
            return Color(red: 0.98, green: 0.73, blue: 0.01)
        } else {
            return Color(red: 0.99, green: 0.18, blue: 0.42)
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            
            // Ala izquierda compacta (Leading): Carátula con 3D Flip estilo Apple Music
            ZStack {
                if !musicService.hasActiveMusic && !appState.shelfItems.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(DesignTokens.blue.opacity(0.22))
                            .frame(width: 19, height: 19)
                        Image(systemName: "tray.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(DesignTokens.blue)
                    }
                } else if let art = musicService.currentTrack.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 19, height: 19)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .id(musicService.currentTrack.title + musicService.currentTrack.artist)
                        .transition(.artworkSwap())
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    trackColor.opacity(0.9),
                                    trackColor.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 19, height: 19)
                        .overlay(
                            Image(systemName: musicService.currentTrack.appSource.lowercased().contains("youtube") ? "play.rectangle.fill" : "music.note")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .id(musicService.currentTrack.title + musicService.currentTrack.artist)
                        .transition(.artworkSwap())
                }
            }
            .frame(width: 19, height: 19)
            // Cambio de canción como Apple Music: la carátula nueva crece con un rebote leve mientras la vieja
            // se encoge y se desvanece (antes daba una vuelta 3D completa)
            .animation(.artworkSwap, value: musicService.currentTrack.title + musicService.currentTrack.artist)
            .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
            .frame(width: wingWidth + wingExtra, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
            
            // Área central que coincide con el sensor de la cámara
            Color.clear
                .frame(
                    width: screenService.currentGeometry.width,
                    height: screenService.currentGeometry.height
                )
            
            // Ala derecha compacta (Trailing): Visualizador + Badge activo con pulso de radar si hay archivos.
            // En la mínima pegada no existe (como el iPhone: el lado derecho se oculta)
            if minimalWingWidth == nil {
                HStack(spacing: 5) {
                    AudioVisualizer(
                        isPlaying: musicService.currentTrack.isPlaying,
                        colorMode: .fromArtwork(musicService.currentTrack.artwork)
                    )
                    .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
                }
                .frame(width: wingWidth + wingExtra, height: screenService.currentGeometry.height)
                .contentShape(Rectangle())
                .transition(.opacity)
            }
        }
        .frame(
            width: screenService.currentGeometry.width + ((wingWidth + wingExtra) * (minimalWingWidth == nil ? 2 : 1)),
            height: screenService.currentGeometry.height
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.toggleExpand()
        }
    }
}

// Modificador condicional para matchedGeometryEffect
public struct OptionalMatchedGeometry: ViewModifier {
    public let id: String
    public let namespace: Namespace.ID?
    
    public init(id: String, namespace: Namespace.ID?) {
        self.id = id
        self.namespace = namespace
    }
    
    public func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
