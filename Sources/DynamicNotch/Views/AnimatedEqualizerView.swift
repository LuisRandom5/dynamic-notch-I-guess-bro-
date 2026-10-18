import SwiftUI

public struct AnimatedEqualizerView: View {
    public var isPlaying: Bool
    public var color: Color = .green
    
    public init(isPlaying: Bool, color: Color = .green) {
        self.isPlaying = isPlaying
        self.color = color
    }
    
    public var body: some View {
        // Mismo motor y mismo reloj que AudioVisualizer, sincronizado a la pantalla
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { _ in
            let mags = isPlaying ? ProceduralMotionEngine.shared.getMagnitudes(barCount: 4) : [0, 0, 0, 0]
            HStack(alignment: .bottom, spacing: PlayerMetrics.visualizerBarSpacing) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color,
                                    color.opacity(0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width: PlayerMetrics.visualizerBarWidth,
                            height: max(PlayerMetrics.visualizerMinHeight, CGFloat(mags[index]) * 14)
                        )
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPlaying)
    }
}
