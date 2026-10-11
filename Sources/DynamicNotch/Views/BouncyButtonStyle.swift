import SwiftUI

public struct BouncyButtonStyle: ButtonStyle {
    public var scaleAmount: CGFloat = 0.88
    
    public init(scaleAmount: CGFloat = 0.88) {
        self.scaleAmount = scaleAmount
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
