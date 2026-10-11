import SwiftUI

public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    
    public init(topRadius: CGFloat = 0, bottomRadius: CGFloat = 17) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }
    
    public init(cornerRadius: CGFloat) {
        self.topRadius = 0
        self.bottomRadius = cornerRadius
    }
    
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let topR = min(topRadius, rect.width / 2, rect.height / 2)
        let botR = min(bottomRadius, rect.width / 2, rect.height / 2)
        
        // Start on top edge after top-left corner
        path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
        
        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        
        // Top-right corner
        if topR > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topR),
                radius: topR
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - botR))
        
        // Bottom-right corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - botR, y: rect.maxY),
            radius: botR
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + botR, y: rect.maxY))
        
        // Bottom-left corner
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - botR),
            radius: botR
        )
        
        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        
        // Top-left corner
        if topR > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + topR, y: rect.minY),
                radius: topR
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        
        path.closeSubpath()
        return path
    }
}
