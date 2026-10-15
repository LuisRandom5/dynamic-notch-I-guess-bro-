import SwiftUI

// MARK: - NotchExitContentModifier (Efecto de salida: Blur + Scale + Opacity anclado arriba)
public struct NotchExitContentModifier: ViewModifier {
    public var isExiting: Bool
    public var blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur
    public var scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale
    
    public var offsetY: CGFloat = ExitAnimationMetrics.contentExitOffsetY
    
    public init(
        isExiting: Bool,
        blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur,
        scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale,
        offsetY: CGFloat = ExitAnimationMetrics.contentExitOffsetY
    ) {
        self.isExiting = isExiting
        self.blurAmount = blurAmount
        self.scaleAmount = scaleAmount
        self.offsetY = offsetY
    }
    
    public func body(content: Content) -> some View {
        content
            .opacity(isExiting ? 0.0 : 1.0)
            .scaleEffect(isExiting ? scaleAmount : 1.0, anchor: .top)
            .offset(y: isExiting ? offsetY : 0.0)
    }
}

public extension View {
    func notchContentExit(
        isExiting: Bool,
        blurAmount: CGFloat = ExitAnimationMetrics.contentExitBlur,
        scaleAmount: CGFloat = ExitAnimationMetrics.contentExitScale,
        offsetY: CGFloat = ExitAnimationMetrics.contentExitOffsetY
    ) -> some View {
        self.modifier(NotchExitContentModifier(
            isExiting: isExiting,
            blurAmount: blurAmount,
            scaleAmount: scaleAmount,
            offsetY: offsetY
        ))
    }
}
