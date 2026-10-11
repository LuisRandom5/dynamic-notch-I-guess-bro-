import SwiftUI

public struct NotchCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var screenService: ScreenService
    
    private let wingWidth: CGFloat = 52
    
    private var trackColor: Color {
        if musicService.currentTrack.appSource == "Spotify" {
            return Color(red: 0.11, green: 0.84, blue: 0.38)
        } else {
            return Color(red: 0.99, green: 0.18, blue: 0.42)
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left compact wing (Leading)
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
            .frame(width: wingWidth, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
            
            // Center area matching the physical MacBook notch cutout
            Color.clear
                .frame(
                    width: screenService.currentGeometry.width,
                    height: screenService.currentGeometry.height
                )
            
            // Right compact wing (Trailing)
            ZStack {
                AnimatedEqualizerView(
                    isPlaying: musicService.currentTrack.isPlaying,
                    color: trackColor
                )
            }
            .frame(width: wingWidth, height: screenService.currentGeometry.height)
            .contentShape(Rectangle())
        }
        .frame(
            width: screenService.currentGeometry.width + (wingWidth * 2),
            height: screenService.currentGeometry.height
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.toggleExpand()
        }
    }
}
