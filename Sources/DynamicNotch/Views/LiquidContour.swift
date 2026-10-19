import SwiftUI

// MARK: - Motor de geometría líquida
//
// El extremo del notch y la gota se describen como campos de distancia con signo (SDF): negativo dentro,
// positivo fuera. Se unen con una "unión suave" (smooth min), que es lo que crea la protuberancia y el
// cuello: cuando las dos formas están cerca, la superficie entre ellas se rellena con una curva continua, y
// al alejarse se adelgaza hasta romperse. El borde (nivel 0) se traza con marching squares y se convierte
// en un `Path` real: sirve igual para rellenar de negro o para ponerle Liquid Glass encima.

public enum LiquidContour {
    /// Parámetros de la unión suave: a mayor `blend`, más largo se estira el cuello antes de romperse
    public static var blend: CGFloat { CGFloat(LiquidMotionTuning.v.blend) }
    /// Paso de la rejilla (pt): menor = borde más fino
    public static let gridStep: CGFloat = 0.75

    /// Contorno de (extremo del notch ∪ gota) en el rectángulo `rect`.
    /// - pillRect: cápsula del extremo del notch (redondeada con radio = alto/2)
    /// - drop: elipse de la gota
    public static func path(pillRect: CGRect, drop: CGRect, in rect: CGRect, blend: CGFloat = blend) -> Path {
        let step = gridStep
        let cols = max(2, Int((rect.width / step).rounded(.up)) + 1)
        let rows = max(2, Int((rect.height / step).rounded(.up)) + 1)
        guard cols * rows < 400_000 else { return Path() }

        // Campo en cada vértice de la rejilla
        var field = [CGFloat](repeating: 0, count: cols * rows)
        let pillR = pillRect.height / 2
        let pillCenter = CGPoint(x: pillRect.midX, y: pillRect.midY)
        let pillHalf = CGSize(width: pillRect.width / 2, height: pillRect.height / 2)
        let dropCenter = CGPoint(x: drop.midX, y: drop.midY)
        let a = max(0.5, drop.width / 2), b = max(0.5, drop.height / 2)
        for j in 0..<rows {
            let y = rect.minY + CGFloat(j) * step
            for i in 0..<cols {
                let x = rect.minX + CGFloat(i) * step
                let d1 = roundedBoxSDF(x - pillCenter.x, y - pillCenter.y, pillHalf, pillR)
                let d2 = ellipseSDF(x - dropCenter.x, y - dropCenter.y, a, b)
                field[j * cols + i] = smoothMin(d1, d2, blend)
            }
        }

        // Marching squares → segmentos con extremos identificados por la arista de la rejilla que cruzan
        struct Edge: Hashable { let x: Int; let y: Int; let vertical: Bool }
        var points: [Edge: CGPoint] = [:]
        var neighbors: [Edge: [Edge]] = [:]

        func pointOn(_ e: Edge) -> CGPoint {
            if let p = points[e] { return p }
            let i0 = e.x, j0 = e.y
            let i1 = e.vertical ? i0 : i0 + 1
            let j1 = e.vertical ? j0 + 1 : j0
            let v0 = field[j0 * cols + i0], v1 = field[j1 * cols + i1]
            let t = v0 == v1 ? 0.5 : min(1, max(0, v0 / (v0 - v1)))
            let p = CGPoint(
                x: rect.minX + (CGFloat(i0) + (e.vertical ? 0 : t)) * step,
                y: rect.minY + (CGFloat(j0) + (e.vertical ? t : 0)) * step
            )
            points[e] = p
            return p
        }
        func link(_ e1: Edge, _ e2: Edge) {
            _ = pointOn(e1); _ = pointOn(e2)
            neighbors[e1, default: []].append(e2)
            neighbors[e2, default: []].append(e1)
        }

        for j in 0..<(rows - 1) {
            for i in 0..<(cols - 1) {
                let tl = field[j * cols + i] < 0, tr = field[j * cols + i + 1] < 0
                let br = field[(j + 1) * cols + i + 1] < 0, bl = field[(j + 1) * cols + i] < 0
                let code = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
                if code == 0 || code == 15 { continue }
                let top = Edge(x: i, y: j, vertical: false)
                let bottom = Edge(x: i, y: j + 1, vertical: false)
                let left = Edge(x: i, y: j, vertical: true)
                let right = Edge(x: i + 1, y: j, vertical: true)
                switch code {
                case 1, 14: link(left, bottom)
                case 2, 13: link(bottom, right)
                case 3, 12: link(left, right)
                case 4, 11: link(top, right)
                case 6, 9: link(top, bottom)
                case 7, 8: link(left, top)
                case 5:
                    // Ambigüedad de silla: decidir por el valor del centro de la celda
                    let center = (field[j * cols + i] + field[j * cols + i + 1] + field[(j + 1) * cols + i + 1] + field[(j + 1) * cols + i]) / 4
                    if center < 0 { link(left, top); link(bottom, right) } else { link(left, bottom); link(top, right) }
                case 10:
                    let center = (field[j * cols + i] + field[j * cols + i + 1] + field[(j + 1) * cols + i + 1] + field[(j + 1) * cols + i]) / 4
                    if center < 0 { link(top, right); link(left, bottom) } else { link(left, top); link(bottom, right) }
                default: break
                }
            }
        }

        // Unir los segmentos en lazos cerrados
        var path = Path()
        var visited = Set<Edge>()
        for start in neighbors.keys where !visited.contains(start) {
            var loop: [CGPoint] = []
            var previous: Edge? = nil
            var current = start
            while !visited.contains(current) {
                visited.insert(current)
                loop.append(points[current]!)
                let next = neighbors[current]?.first(where: { $0 != previous && !visited.contains($0) })
                guard let n = next else { break }
                previous = current
                current = n
            }
            guard loop.count > 2 else { continue }
            path.move(to: loop[0])
            for p in loop.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }

    // MARK: Campos de distancia

    private static func roundedBoxSDF(_ px: CGFloat, _ py: CGFloat, _ half: CGSize, _ r: CGFloat) -> CGFloat {
        let qx = abs(px) - (half.width - r)
        let qy = abs(py) - (half.height - r)
        let outside = hypot(max(qx, 0), max(qy, 0))
        let inside = min(max(qx, qy), 0)
        return outside + inside - r
    }

    /// Aproximación de distancia a una elipse (exacta en círculos; suficiente para la gota)
    private static func ellipseSDF(_ px: CGFloat, _ py: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let k = hypot(px / a, py / b)
        return (k - 1) * min(a, b)
    }

    /// Unión suave polinómica: rellena con una curva continua el espacio entre las dos formas
    private static func smoothMin(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
}

/// `Shape` animable que traza el contorno líquido (para rellenar o para `glassEffect(in:)`)
public struct LiquidContourShape: Shape {
    public var pillRect: CGRect
    public var drop: CGRect
    /// En cristal se resta la cápsula del notch (que ya tiene su propio vidrio) para no apilar vidrio
    public var subtractPill: Bool = false

    /// El extremo del notch está a la derecha de su cuerpo (bolita del lado derecho)
    public var notchIsLeading: Bool = true

    public func path(in rect: CGRect) -> Path {
        let bounds = pillRect.union(drop).insetBy(dx: -LiquidContour.blend - 2, dy: -LiquidContour.blend - 2)
            .intersection(rect.insetBy(dx: -1, dy: -1))
        let contour = LiquidContour.path(pillRect: pillRect, drop: drop, in: bounds)
        if subtractPill {
            // Cristal: se quita el notch, alargado hacia su cuerpo. Con la cápsula exacta quedaba una franja finita
            // en su otro extremo (dentro del notch) que el vidrio dibujaba como un contorno sobre el centro negro
            let far: CGFloat = 4000
            let endX = notchIsLeading ? pillRect.maxX : pillRect.minX
            let body = CGRect(x: notchIsLeading ? endX - far : endX, y: pillRect.minY - 0.5,
                              width: far, height: pillRect.height + 1)
            return contour.subtracting(Path(roundedRect: body, cornerRadius: body.height / 2))
        }
        // Negro: se quita el notch (ya lo dibuja el propio notch) salvo un borde de 1 pt que se encima negro
        // sobre negro, para que no quede costura. Antes se quitaba sólo el cuerpo y el extremo redondeado se
        // dibujaba encima del contenido del notch (la carátula quedaba tapada mientras la gota brotaba)
        let inner = pillRect.insetBy(dx: 1, dy: 1)
        return contour.subtracting(Path(roundedRect: inner, cornerRadius: inner.height / 2))
    }
}
