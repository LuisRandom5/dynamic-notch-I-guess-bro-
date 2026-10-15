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
        HStack(alignment: .bottom, spacing: 2.2) {
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
                        width: 2.8,
                        height: isPlaying ? max(3.5, barHeights[index] * 13) : 3.5
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
            timer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { _ in
                withAnimation(.spring(response: 0.12, dampingFraction: 0.60)) {
                    barHeights = [
                        CGFloat.random(in: 0.20...1.0),
                        CGFloat.random(in: 0.35...1.0),
                        CGFloat.random(in: 0.15...0.95),
                        CGFloat.random(in: 0.30...1.0)
                    ]
                }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                barHeights = [0.2, 0.2, 0.2, 0.2]
            }
        }
    }
}
