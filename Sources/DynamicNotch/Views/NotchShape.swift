import SwiftUI

public struct NotchShape: Shape {
    public var cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }
    
    public var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        
        // Start top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Down to bottom-left before curve
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        
        // Bottom-left rounded corner
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY),
            radius: radius
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        
        // Bottom-right rounded corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            radius: radius
        )
        
        // Up to top-right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        
        path.closeSubpath()
        return path
    }
}
