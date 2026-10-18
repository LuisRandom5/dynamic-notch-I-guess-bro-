import SwiftUI

public struct AnimatedEqualizerView: View {
    public var isPlaying: Bool
    public var color: Color = .green
    
    @State private var barHeights: [CGFloat] = [0.25, 0.65, 0.40, 0.85]
    @State private var timer: Timer?
    
    public init(isPlaying: Bool, color: Color = .green) {
        self.isPlaying = isPlaying
        self.color = color
    }
    
    public var body: some View {
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
                        height: isPlaying ? max(PlayerMetrics.visualizerMinHeight, barHeights[index] * 14) : PlayerMetrics.visualizerMinHeight
                    )
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onAppear {
            updateAnimationState()
        }
        .onChange(of: isPlaying) { _, _ in
            updateAnimationState()
        }
    }
    
    private func updateAnimationState() {
        timer?.invalidate()
        timer = nil
        
        if isPlaying {
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
                let mags = ProceduralMotionEngine.shared.getMagnitudes(barCount: 4)
                guard mags.count >= 4 else { return }
                withAnimation(.interactiveSpring(response: 0.06, dampingFraction: 0.85)) {
                    barHeights = [
                        CGFloat(mags[0]),
                        CGFloat(mags[1]),
                        CGFloat(mags[2]),
                        CGFloat(mags[3])
                    ]
                }
            }
            t.tolerance = 0.004
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                barHeights = [0.0, 0.0, 0.0, 0.0]
            }
        }
    }
}
