import SwiftUI

public struct NotchExpandedMusicView: View {
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var appState: AppState
    
    @State private var isSeeking: Bool = false
    @State private var seekPosition: TimeInterval = 0
    
    private var track: MusicTrack {
        musicService.currentTrack
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Upper row: Artwork + Title + Source badge + Waveform
            HStack(spacing: 14) {
                // Album Artwork
                ZStack {
                    if let art = track.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.pink.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                // Track Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    // Source badge (Spotify / Apple Music / YouTube / Safari)
                    HStack(spacing: 4) {
                        Image(systemName: track.appSource.lowercased().contains("spotify") ? "waveform" : (track.appSource.lowercased().contains("youtube") ? "play.rectangle.fill" : (track.appSource.lowercased().contains("safari") ? "safari" : "applelogo")))
                            .font(.system(size: 9))
                            .foregroundColor(track.appSource.lowercased().contains("spotify") ? .green : (track.appSource.lowercased().contains("youtube") ? Color(red: 1.0, green: 0.25, blue: 0.25) : .white.opacity(0.8)))
                        
                        Text(track.appSource)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(track.appSource.lowercased().contains("spotify") ? .green : (track.appSource.lowercased().contains("youtube") ? Color(red: 1.0, green: 0.25, blue: 0.25) : .white.opacity(0.8)))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Waveform equalizer
                AnimatedEqualizerView(
                    isPlaying: track.isPlaying,
                    color: track.appSource.lowercased().contains("spotify") ? .green : (track.appSource.lowercased().contains("youtube") ? Color(red: 1.0, green: 0.25, blue: 0.25) : .pink)
                )
                .padding(.trailing, 4)
            }
            
            // Progress Bar / Scrubber
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let progress = track.duration > 0 ? (isSeeking ? seekPosition : track.playbackPosition) / track.duration : 0.0
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, progress)))), height: 4)
                    }
                    .contentShape(Rectangle())
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
                .frame(height: 6)
                
                // Time stamps
                HStack {
                    Text(formatTime(isSeeking ? seekPosition : track.playbackPosition))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("-" + formatTime(max(0, track.duration - (isSeeking ? seekPosition : track.playbackPosition))))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Controls row: Previous, Play/Pause, Next, AirPlay
            HStack(spacing: 24) {
                Spacer()
                
                // Previous
                Button(action: {
                    appState.hapticService.triggerSnap()
                    musicService.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                
                // Play / Pause Circle Button
                Button(action: {
                    appState.hapticService.triggerExpand()
                    musicService.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: track.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                
                // Next
                Button(action: {
                    appState.hapticService.triggerSnap()
                    musicService.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
