import SwiftUI
import AppKit

public struct MarqueeText: View {
    public var text: String
    public var fontSize: CGFloat
    public var fontWeight: Font.Weight
    public var color: Color
    
    @State private var offset: CGFloat = 0
    
    public init(
        _ text: String,
        fontSize: CGFloat = 14.5,
        fontWeight: Font.Weight = .bold,
        color: Color = .white
    ) {
        self.text = text
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
    }
    
    private var font: Font {
        .system(size: fontSize, weight: fontWeight)
    }
    
    // Medición síncrona y exacta de ancho de texto en AppKit
    private var measuredTextWidth: CGFloat {
        let nsWeight: NSFont.Weight
        switch fontWeight {
        case .ultraLight: nsWeight = .ultraLight
        case .thin: nsWeight = .thin
        case .light: nsWeight = .light
        case .regular: nsWeight = .regular
        case .medium: nsWeight = .medium
        case .semibold: nsWeight = .semibold
        case .bold: nsWeight = .bold
        case .heavy: nsWeight = .heavy
        case .black: nsWeight = .black
        default: nsWeight = .regular
        }
        let font = NSFont.systemFont(ofSize: fontSize, weight: nsWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    
    public var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let textWidth = measuredTextWidth
            let isOverflowing = availableWidth > 0 && textWidth > availableWidth
            let overflow = isOverflowing ? (textWidth - availableWidth + 14) : 0
            
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
            }
            .frame(width: availableWidth, alignment: .leading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: (isOverflowing && offset < -2) ? .clear : .white, location: 0.0),
                        .init(color: .white, location: (isOverflowing && offset < -2) ? 0.03 : 0.0),
                        .init(color: .white, location: (isOverflowing && offset > -(overflow - 2)) ? 0.97 : 1.0),
                        .init(color: (isOverflowing && offset > -(overflow - 2)) ? .clear : .white, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            // Tarea vinculada EXCLUSIVAMENTE al texto: NUNCA se cancela por actualizaciones de tiempo o visualizador
            .task(id: text) {
                self.offset = 0
                
                var currentWidth = availableWidth
                if currentWidth <= 0 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    currentWidth = geo.size.width
                }
                
                guard currentWidth > 0 && textWidth > currentWidth else { return }
                
                let actualOverflow = textWidth - currentWidth + 14
                let scrollDuration = max(2.6, Double(actualOverflow) / 28.0)
                
                while !Task.isCancelled {
                    // 1. Pausa al inicio (1.8 seg)
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard !Task.isCancelled else { break }
                    
                    // 2. Recorrido hacia la izquierda hasta revelar el final
                    withAnimation(.easeInOut(duration: scrollDuration)) {
                        self.offset = -actualOverflow
                    }
                    
                    // Esperar el recorrido + pausa de lectura al final
                    let waitTime = UInt64((scrollDuration + 1.8) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: waitTime)
                    guard !Task.isCancelled else { break }
                    
                    // 3. Regreso suave al inicio (1.2 seg)
                    withAnimation(.easeInOut(duration: 1.2)) {
                        self.offset = 0
                    }
                    
                    // Pausa antes del siguiente ciclo
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                }
            }
        }
        .frame(height: fontSize + 6)
    }
}
