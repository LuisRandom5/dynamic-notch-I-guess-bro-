import SwiftUI

public struct BouncyButtonStyle: ButtonStyle {
    public var scaleAmount: CGFloat = 0.88
    public var xOffset: CGFloat = 0.0
    
    public init(scaleAmount: CGFloat = 0.88, xOffset: CGFloat = 0.0) {
        self.scaleAmount = scaleAmount
        self.xOffset = xOffset
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .offset(x: configuration.isPressed ? xOffset : 0.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.60), value: configuration.isPressed)
    }
}
