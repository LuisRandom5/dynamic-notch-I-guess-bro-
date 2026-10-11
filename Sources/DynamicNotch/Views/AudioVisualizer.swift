import SwiftUI
import AppKit

public enum VisualizerColorMode: Equatable {
    case fixedGradient
    case fromArtwork(NSImage?)
    
    public static func == (lhs: VisualizerColorMode, rhs: VisualizerColorMode) -> Bool {
        switch (lhs, rhs) {
        case (.fixedGradient, .fixedGradient):
            return true
        case (.fromArtwork(let img1), .fromArtwork(let img2)):
            return img1 == img2
        default:
            return false
        }
    }
}

public struct AudioVisualizer: View {
    public var isPlaying: Bool
    public var colorMode: VisualizerColorMode = .fixedGradient
    public var customGradient: LinearGradient? = nil
    
    // Altura de las 6 barras (animadas independientemente)
    @State private var barHeights: [CGFloat] = [9.0, 13.0, 8.0, 14.0, 10.0, 12.0]
    @State private var timer: Timer?
    @State private var gradientColors: [Color] = [
        PlayerMetrics.visualizerTopGradient,
        PlayerMetrics.visualizerBottomGradient
    ]
    
    public init(
        isPlaying: Bool,
        colorMode: VisualizerColorMode = .fixedGradient,
        customGradient: LinearGradient? = nil
    ) {
        self.isPlaying = isPlaying
        self.colorMode = colorMode
        self.customGradient = customGradient
    }
    
    private var resolvedGradient: LinearGradient {
        if let custom = customGradient {
            return custom
        }
        return LinearGradient(
            colors: gradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    public var body: some View {
        // HStack centrado verticalmente: las barras crecen simétricamente hacia arriba y hacia abajo
        HStack(alignment: .center, spacing: PlayerMetrics.visualizerBarSpacing) {
            ForEach(0..<PlayerMetrics.visualizerBarCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(resolvedGradient)
                    .frame(
                        width: PlayerMetrics.visualizerBarWidth,
                        height: isPlaying ? max(PlayerMetrics.visualizerMinHeight, barHeights[safe: index] ?? 8.0)
                                          : PlayerMetrics.visualizerPausedDotSize
                    )
            }
        }
        .frame(height: PlayerMetrics.visualizerMaxHeight, alignment: .center)
        .onAppear {
            updateColors()
            updateAnimation()
        }
        .onChange(of: isPlaying) { _, _ in
            updateAnimation()
        }
        .onChange(of: colorMode) { _, _ in
            updateColors()
        }
    }
    
    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        
        if isPlaying {
            // Animación continua, desfasada y orgánica
            timer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { _ in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                    barHeights = [
                        CGFloat.random(in: PlayerMetrics.visualizerMinHeight...PlayerMetrics.visualizerMaxHeight),
                        CGFloat.random(in: 8.5...PlayerMetrics.visualizerMaxHeight),
                        CGFloat.random(in: PlayerMetrics.visualizerMinHeight...12.5),
                        CGFloat.random(in: 9.0...PlayerMetrics.visualizerMaxHeight),
                        CGFloat.random(in: PlayerMetrics.visualizerMinHeight...13.0),
                        CGFloat.random(in: 8.0...PlayerMetrics.visualizerMaxHeight)
                    ]
                }
            }
        } else {
            // En pausa: colapsa suavemente a puntos circulares de 3.5 pt
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                barHeights = Array(repeating: PlayerMetrics.visualizerPausedDotSize, count: PlayerMetrics.visualizerBarCount)
            }
        }
    }
    
    private func updateColors() {
        switch colorMode {
        case .fixedGradient:
            gradientColors = [
                PlayerMetrics.visualizerTopGradient,
                PlayerMetrics.visualizerBottomGradient
            ]
        case .fromArtwork(let image):
            if let image = image, let extracted = extractArtworkGradient(from: image) {
                gradientColors = extracted
            } else {
                gradientColors = [
                    PlayerMetrics.visualizerTopGradient,
                    PlayerMetrics.visualizerBottomGradient
                ]
            }
        }
    }
    
    private func extractArtworkGradient(from nsImage: NSImage) -> [Color]? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 16
        let height = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let a = CGFloat(rawData[i + 3]) / 255.0
            if a > 0.5 {
                totalR += CGFloat(rawData[i]) / 255.0
                totalG += CGFloat(rawData[i + 1]) / 255.0
                totalB += CGFloat(rawData[i + 2]) / 255.0
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        
        let avgR = totalR / count
        let avgG = totalG / count
        let avgB = totalB / count
        
        let nsColor = NSColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        let sat = max(0.65, min(0.95, s))
        let bri = max(0.70, min(1.0, b))
        
        let color1 = Color(hue: Double(h), saturation: Double(sat), brightness: Double(bri))
        let h2 = (Double(h) + (40.0 / 360.0)).truncatingRemainder(dividingBy: 1.0)
        let color2 = Color(hue: h2, saturation: Double(sat), brightness: Double(bri))
        
        return [color1, color2]
    }
}

// Extensión segura para arrays
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
