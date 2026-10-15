import SwiftUI

// MARK: - Forma de Píldora Elástica con Anclaje Asimétrico (Elastic Overscroll Pill)
public struct ElasticPillShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    public var stretch: CGFloat // Negativo = jala izquierda, Positivo = jala derecha
    public var verticalStretch: CGFloat // Positivo = jala hacia abajo, anclado arriba
    
    public init(
        topRadius: CGFloat = 0,
        bottomRadius: CGFloat = 50,
        stretch: CGFloat = 0,
        verticalStretch: CGFloat = 0
    ) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.stretch = stretch
        self.verticalStretch = verticalStretch
    }
    
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(stretch, verticalStretch) }
        set {
            stretch = newValue.first
            verticalStretch = newValue.second
        }
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let absStretch = abs(stretch)
        let maxS = max(1.0, OverscrollMetrics.maxStretch)
        let heightFactor = 1.0 - (min(absStretch, maxS) / maxS) * OverscrollMetrics.heightShortenPercent
        let activeHeight = rect.height * heightFactor
        
        // Geometría con lado anclado:
        // Si stretch > 0 (derecha): borde izquierdo anclado en rect.minX, derecho avanza a rect.maxX + stretch
        // Si stretch < 0 (izquierda): borde derecho anclado en rect.maxX, izquierdo avanza a rect.minX + stretch
        let minX = stretch < 0 ? (rect.minX + stretch) : rect.minX
        let maxX = stretch > 0 ? (rect.maxX + stretch) : rect.maxX
        let minY = rect.minY
        let maxY = rect.minY + activeHeight
        let width = maxX - minX
        
        guard width > 0, activeHeight > 0 else { return path }
        
        let topR = min(topRadius, width / 2.0, activeHeight / 2.0)
        let botR = min(bottomRadius, width / 2.0, activeHeight / 2.0)
        
        // 1. Inicia en borde superior tras esquina superior izquierda
        path.move(to: CGPoint(x: minX + topR, y: minY))
        
        // 2. Línea superior
        path.addLine(to: CGPoint(x: maxX - topR, y: minY))
        
        // 3. Esquina superior derecha
        if topR > 0 {
            path.addArc(
                tangent1End: CGPoint(x: maxX, y: minY),
                tangent2End: CGPoint(x: maxX, y: minY + topR),
                radius: topR
            )
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }
        
        // 4. Borde derecho
        path.addLine(to: CGPoint(x: maxX, y: maxY - botR))
        
        // 5. Esquina inferior derecha
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: maxY),
            tangent2End: CGPoint(x: maxX - botR, y: maxY),
            radius: botR
        )
        
        // 6. Borde inferior
        path.addLine(to: CGPoint(x: minX + botR, y: maxY))
        
        // 7. Esquina inferior izquierda
        path.addArc(
            tangent1End: CGPoint(x: minX, y: maxY),
            tangent2End: CGPoint(x: minX, y: maxY - botR),
            radius: botR
        )
        
        // 8. Borde izquierdo
        path.addLine(to: CGPoint(x: minX, y: minY + topR))
        
        // 9. Esquina superior izquierda
        if topR > 0 {
            path.addArc(
                tangent1End: CGPoint(x: minX, y: minY),
                tangent2End: CGPoint(x: minX + topR, y: minY),
                radius: topR
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY))
        }
        
        path.closeSubpath()
        return path
    }
}
