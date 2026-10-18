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
    
    @State private var gradientColors: [Color] = [
        PlayerMetrics.visualizerTopGradient,
        PlayerMetrics.visualizerBottomGradient
    ]
    // Fundido entre reproducir y pausa: momento del último cambio y si el reloj de pantalla debe correr
    @State private var playStateChangedAt: Date = .distantPast
    @State private var isAnimating: Bool = false
    @State private var stopToken: Int = 0
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
        // Sincronizado al refresco de pantalla: cada cuadro lee el motor una vez, sin timers ni animaciones encadenadas
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { context in
            let heights = barHeights(at: context.date)
            // HStack centrado verticalmente: las barras crecen simétricamente hacia arriba y hacia abajo
            HStack(alignment: .center, spacing: PlayerMetrics.visualizerBarSpacing) {
                ForEach(0..<PlayerMetrics.visualizerBarCount, id: \.self) { index in
                    let h = heights[index]
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
        }
        .frame(height: PlayerMetrics.visualizerMaxHeight, alignment: .center)
        .onAppear {
            updateColors()
            // Al aparecer (p. ej. al expandir el reproductor) no hay fundido: entra ya en movimiento
            isAnimating = isPlaying
        }
        .onChange(of: isPlaying) { _, playing in
            handlePlayingChange(playing)
        }
        .onChange(of: colorMode) { _, _ in
            updateColors()
        }
        .onChange(of: appState.visualizerColorStyle) { _, _ in
            updateColors()
        }
    }
    
    // MARK: - Movimiento
    
    private static let fadeIn: TimeInterval = 0.22
    private static let fadeOut: TimeInterval = 0.30
    
    /// Alturas de las barras en este cuadro: niveles del motor × fundido de reproducción/pausa.
    private func barHeights(at date: Date) -> [CGFloat] {
        let rest = PlayerMetrics.visualizerPausedDotSize
        let maxH = PlayerMetrics.visualizerMaxHeight
        let count = PlayerMetrics.visualizerBarCount
        
        let sinceChange = date.timeIntervalSince(playStateChangedAt)
        let gain: Double = isPlaying
            ? Self.smoothstep(sinceChange / Self.fadeIn)
            : 1 - Self.smoothstep(sinceChange / Self.fadeOut)
        guard gain > 0.001 else { return Array(repeating: rest, count: count) }
        
        // Reducir movimiento: perfil fijo y tranquilo en lugar de ritmo
        let levels: [Float] = reduceMotion
            ? [0.45, 0.70, 0.55, 0.80, 0.60, 0.50]
            : AudioSpectrumEngine.shared.getMagnitudes()
        
        return (0..<count).map { i in
            let level = CGFloat(levels.indices.contains(i) ? levels[i] : 0) * CGFloat(gain)
            return max(rest, min(maxH, rest + level * (maxH - rest)))
        }
    }
    
    private func handlePlayingChange(_ playing: Bool) {
        playStateChangedAt = Date()
        isAnimating = true
        stopToken += 1
        guard !playing else { return }
        // Tras el fundido a pausa, detener el reloj de pantalla (cero CPU mientras está pausado)
        let token = stopToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut + 0.1) {
            if token == stopToken && !isPlaying {
                isAnimating = false
            }
        }
    }
    
    private static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
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
