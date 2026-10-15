import SwiftUI

public struct NotchCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var screenService: ScreenService
    
    public var namespace: Namespace.ID?
    private let wingWidth: CGFloat = 52
    private var wingExtra: CGFloat {
        (!appState.shelfItems.isEmpty && appState.showShelfBadgeInNotch) ? 24 : 0
    }
    @State private var compactTilt: Double = 0.0
    
    public init(namespace: Namespace.ID? = nil) {
        self.namespace = namespace
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
            
            // Ala izquierda compacta (Leading): Carátula
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
                }
            }
            .frame(width: 19, height: 19)
            .modifier(OptionalMatchedGeometry(id: "albumArtwork", namespace: namespace))
            .rotation3DEffect(.degrees(compactTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .onChange(of: musicService.currentTrack.title) { oldTitle, newTitle in
                guard !newTitle.isEmpty, newTitle != oldTitle else { return }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
                    compactTilt = 18.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                        compactTilt = 0.0
                    }
                }
            }
            .frame(width: wingWidth + wingExtra, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
            
            // Área central que coincide con el sensor de la cámara
            Color.clear
                .frame(
                    width: screenService.currentGeometry.width,
                    height: screenService.currentGeometry.height
                )
            
            // Ala derecha compacta (Trailing): Visualizador + Badge activo con pulso de radar si hay archivos
            HStack(spacing: 5) {
                if !appState.shelfItems.isEmpty && appState.showShelfBadgeInNotch {
                    ActiveFileBadgeView()
                }
                
                AudioVisualizer(
                    isPlaying: musicService.currentTrack.isPlaying || !AudioSpectrumEngine.shared.isSilent,
                    colorMode: .fromArtwork(musicService.currentTrack.artwork)
                )
                .modifier(OptionalMatchedGeometry(id: "audioVisualizer", namespace: namespace))
            }
            .frame(width: wingWidth + wingExtra, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
        }
        .frame(
            width: screenService.currentGeometry.width + ((wingWidth + wingExtra) * 2),
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
