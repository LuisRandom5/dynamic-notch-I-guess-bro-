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

public enum ArtworkGradientCache {
    private static var cache: [ObjectIdentifier: [Color]] = [:]
    private static var pendingKeys = Set<ObjectIdentifier>()
    private static let lock = NSLock()
    
    public static func colors(for nsImage: NSImage) -> (top: Color, bottom: Color) {
        let key = ObjectIdentifier(nsImage)
        lock.lock()
        if let cached = cache[key], cached.count >= 2 {
            lock.unlock()
            return (cached[0], cached[1])
        }
        
        let isPending = pendingKeys.contains(key)
        if !isPending {
            pendingKeys.insert(key)
            lock.unlock()
            
            // Extraer en cola de fondo para JAMÁS bloquear el hilo principal ni competir con ImageIO de SwiftUI
            DispatchQueue.global(qos: .utility).async {
                let extracted = extract(from: nsImage)
                lock.lock()
                pendingKeys.remove(key)
                if let extracted = extracted {
                    if cache.count > 32 {
                        cache.removeAll(keepingCapacity: true)
                    }
                    cache[key] = extracted
                }
                lock.unlock()
            }
        } else {
            lock.unlock()
        }
        
        return (PlayerMetrics.visualizerTopGradient, PlayerMetrics.visualizerBottomGradient)
    }
    
    public static func extract(from nsImage: NSImage) -> [Color]? {
        let key = ObjectIdentifier(nsImage)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
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
        
        // Renderizar un thumbnail pequeño de 16x16 de forma segura y aislada
        var drawn = false
        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            drawn = true
        } else if let tiff = nsImage.tiffRepresentation,
                  let source = CGImageSourceCreateWithData(tiff as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 32,
                      kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) {
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
            drawn = true
        }
        
        guard drawn else { return nil }
        
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
        
        let result = [color1, color2]
        lock.lock()
        if cache.count > 32 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = result
        lock.unlock()
        return result
    }
}


public struct AudioVisualizer: View {
    public var isPlaying: Bool
    public var colorMode: VisualizerColorMode = .fixedGradient
    public var customGradient: LinearGradient? = nil
    
    @ObservedObject private var appState = AppState.shared
    
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
                let h = max(PlayerMetrics.visualizerPausedDotSize, barHeights[safe: index] ?? PlayerMetrics.visualizerPausedDotSize)
                let normH = Double((h - PlayerMetrics.visualizerMinHeight) / (PlayerMetrics.visualizerMaxHeight - PlayerMetrics.visualizerMinHeight))
                let glowAlpha = min(0.42, max(0.0, normH * 0.42))
                
                Capsule(style: .continuous)
                    .fill(resolvedGradient)
                    .frame(
                        width: PlayerMetrics.visualizerBarWidth,
                        height: h
                    )
                    .shadow(
                        color: (gradientColors.first ?? Color.white).opacity(glowAlpha),
                        radius: 1.6,
                        x: 0,
                        y: 0
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
        .onChange(of: appState.visualizerColorStyle) { _, _ in
            updateColors()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    @State private var animPhase: Double = 0.0
    
    // Renderizado reactivo a 60 fps sincronizado al espectro real por banda (Sub-Bass a Brilliance)
    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        
        let restingDot = PlayerMetrics.visualizerPausedDotSize
        let maxH = PlayerMetrics.visualizerMaxHeight
        let bandMultipliers: [CGFloat] = [1.05, 1.02, 1.04, 1.00, 0.98, 0.95]
        
        if isPlaying {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
                let engine = AudioSpectrumEngine.shared
                let levels = engine.getMagnitudes()
                
                var newHeights: [CGFloat] = []
                newHeights.reserveCapacity(PlayerMetrics.visualizerBarCount)
                
                for i in 0..<PlayerMetrics.visualizerBarCount {
                    let rawLvl = CGFloat(levels[safe: i] ?? 0.0)
                    let targetH: CGFloat
                    if rawLvl <= 0.015 {
                        // Banda en silencio real -> punto de reposo exacto (sin elevar bandas vacías)
                        targetH = restingDot
                    } else {
                        let scaled = min(1.0, rawLvl * (bandMultipliers[safe: i] ?? 1.0))
                        targetH = restingDot + scaled * (maxH - restingDot)
                    }
                    newHeights.append(max(restingDot, min(maxH, targetH)))
                }
                
                withAnimation(.linear(duration: 0.022)) {
                    self.barHeights = newHeights
                }
            }
            t.tolerance = 0.003
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            // EN PAUSA: Transición suave a reposo circular
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                self.barHeights = Array(repeating: restingDot, count: PlayerMetrics.visualizerBarCount)
            }
        }
    }
    
    private func updateColors() {
        switch appState.visualizerColorStyle {
        case .pureWhite:
            gradientColors = [
                Color.white.opacity(0.95),
                Color.white.opacity(0.65)
            ]
            return
        case .vibrant:
            gradientColors = [
                PlayerMetrics.visualizerTopGradient,
                PlayerMetrics.visualizerBottomGradient
            ]
            return
        case .adaptive:
            break
        }
        
        switch colorMode {
        case .fixedGradient:
            gradientColors = [
                PlayerMetrics.visualizerTopGradient,
                PlayerMetrics.visualizerBottomGradient
            ]
        case .fromArtwork(let image):
            if let image = image {
                let pair = ArtworkGradientCache.colors(for: image)
                gradientColors = [pair.top, pair.bottom]
            } else {
                gradientColors = [
                    PlayerMetrics.visualizerTopGradient,
                    PlayerMetrics.visualizerBottomGradient
                ]
            }
        }
    }
}

// Extensión segura para arrays
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
