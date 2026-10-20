import SwiftUI
import AppKit

// MARK: - AirDropIconView (Icono Oficial de AirDrop para macOS)
/// Carga directamente el recurso gráfico oficial de AirDrop del sistema macOS (/System/Library/PrivateFrameworks/SharingUI.framework)
/// configurado en modo plantilla para renderizado nativo idéntico al de Apple en cualquier color y tamaño.
public struct AirDropIconView: View {
    public var size: CGFloat
    public var color: Color
    
    // Caché estática del gráfico oficial de AirDrop de Apple o personalizado
    private static let systemAirDropImage: NSImage? = {
        if let bundlePath = Bundle.main.path(forResource: "airdrop", ofType: "png"),
           let img = NSImage(contentsOfFile: bundlePath) {
            img.isTemplate = true
            return img
        }
        let path = "/System/Library/PrivateFrameworks/SharingUI.framework/Resources/AirDrop-large.png"
        if let img = NSImage(contentsOfFile: path) {
            img.isTemplate = true
            return img
        }
        return nil
    }()
    
    public init(
        size: CGFloat = 18,
        color: Color = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
    ) {
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        Group {
            if let nsImg = Self.systemAirDropImage {
                Image(nsImage: nsImg)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(color)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Renderizado vectorial fiel con anillos concéntricos abiertos en la base
                AirDropVectorFallback(size: size, color: color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Vector Fallback de Alta Precisión
private struct AirDropVectorFallback: View {
    let size: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            // Anillos concéntricos de AirDrop con apertura inferior de ~100°
            ForEach(0..<3) { i in
                let factor: CGFloat = 0.42 + (CGFloat(i) * 0.28)
                Circle()
                    .trim(from: 0.14, to: 0.86)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: max(1.6, size * 0.105), lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size * factor, height: size * factor)
            }
            
            // Cuña / punto emisor central inferior
            Circle()
                .fill(color)
                .frame(width: max(2.5, size * 0.18), height: max(2.5, size * 0.18))
                .offset(y: size * 0.12)
        }
        .frame(width: size, height: size)
    }
}
