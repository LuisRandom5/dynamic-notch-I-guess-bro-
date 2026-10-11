import SwiftUI

// MARK: - NotchExitContentModifier (Efecto de salida: Blur + Scale + Opacity anclado arriba)
public struct NotchExitContentModifier: ViewModifier {
    public var isExiting: Bool
    public var blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur
    public var scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale
    
    public init(
        isExiting: Bool,
        blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur,
        scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale
    ) {
        self.isExiting = isExiting
        self.blurAmount = blurAmount
        self.scaleAmount = scaleAmount
    }
    
    public func body(content: Content) -> some View {
        content
            .opacity(isExiting ? 0.0 : 1.0)
            .blur(radius: isExiting ? blurAmount : 0.0)
            .scaleEffect(isExiting ? scaleAmount : 1.0, anchor: .top)
    }
}

public extension View {
    func notchContentExit(
        isExiting: Bool,
        blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur,
        scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale
    ) -> some View {
        self.modifier(NotchExitContentModifier(
            isExiting: isExiting,
            blurAmount: blurAmount,
            scaleAmount: scaleAmount
        ))
    }
}
