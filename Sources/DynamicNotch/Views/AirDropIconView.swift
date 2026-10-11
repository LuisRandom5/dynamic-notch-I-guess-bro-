import SwiftUI

// MARK: - AirDropIconView (Icono de AirDrop en SwiftUI Puro para macOS)
/// Renderiza las ondas concéntricas oficiales de AirDrop en color azul de Apple.
/// Resuelve la limitación de macOS donde la SF Symbol "airdrop" no existe en el sistema.
public struct AirDropIconView: View {
    public var size: CGFloat
    public var color: Color
    
    public init(
        size: CGFloat = 18,
        color: Color = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
    ) {
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        ZStack {
            // Arcos concéntricos superiores que se expanden hacia arriba
            ForEach(0..<3) { i in
                let scale: CGFloat = 0.44 + CGFloat(i) * 0.28
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.11), lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size * scale, height: size * scale)
            }
            
            // Punto central emisor en la base
            Circle()
                .fill(color)
                .frame(width: max(2.5, size * 0.20), height: max(2.5, size * 0.20))
                .offset(y: size * 0.14)
        }
        .frame(width: size, height: size)
    }
}
