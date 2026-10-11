import SwiftUI

public struct NotchCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var screenService: ScreenService
    
    public var namespace: Namespace.ID?
    private let wingWidth: CGFloat = 52
    
    public init(namespace: Namespace.ID? = nil) {
        self.namespace = namespace
    }
    
    private var trackColor: Color {
        if musicService.currentTrack.appSource == "Spotify" {
            return Color(red: 0.11, green: 0.84, blue: 0.38)
        } else {
            return Color(red: 0.99, green: 0.18, blue: 0.42)
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Ala izquierda compacta (Leading): Carátula
            ZStack {
                if let art = musicService.currentTrack.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 19, height: 19)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
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
                            Image(systemName: "music.note")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
            }
            .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
            .frame(width: wingWidth, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
            
            // Área central que coincide con el sensor de la cámara
            Color.clear
                .frame(
                    width: screenService.currentGeometry.width,
                    height: screenService.currentGeometry.height
                )
            
            // Ala derecha compacta (Trailing): Visualizador + Badge de archivos en bandeja si existen
            HStack(spacing: 5) {
                if !appState.shelfItems.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DesignTokens.blue)
                        Text("\(appState.shelfItems.count)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            appState.mode = .shelf
                        }
                    }
                }
                
                AudioVisualizer(
                    isPlaying: musicService.currentTrack.isPlaying,
                    colorMode: .fromArtwork(musicService.currentTrack.artwork)
                )
            }
            .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
            .frame(width: wingWidth + (!appState.shelfItems.isEmpty ? 18 : 0), height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
        }
        .frame(
            width: screenService.currentGeometry.width + (wingWidth * 2) + (!appState.shelfItems.isEmpty ? 18 : 0),
            height: screenService.currentGeometry.height
        )
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
