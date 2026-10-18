import SwiftUI
import AppKit

// MARK: - GlassClearManager (Gestor Reactivo de Capas y Bisección para Liquid Glass)
public final class GlassClearManager: ObservableObject {
    public static let shared = GlassClearManager()
    
    // MARK: - Toggles de Bisección (Paso 1: Identificación de Capas)
    /// a) Franja negra del notch físico (~34pt) y degradado superior (~10pt)
    @Published public var showNotchFusionStrip: Bool = true
    
    /// b) Tinte del cristal (false = Glass.clear puro sin tinte; true = tinte blanco sutil <= 4%)
    @Published public var showGlassTint: Bool = false
    
    /// c) Sombra exterior (false = sin sombra detrás del cristal para eliminar manchas; true = sombra exterior con máscara inversa)
    @Published public var showCardShadow: Bool = false
    
    /// d) Forma negra de base o NSVisualEffectView debajo del cristal (¡EL CULPABLE LECHOSO!)
    @Published public var showBaseFill: Bool = false
    
    /// e) Borde especular diagonal de 1 pt
    @Published public var showSpecularBorder: Bool = true
    
    /// f) Fondo transparente de ventana (NSPanel y NSHostingView con fondo .clear)
    @Published public var enableTransparentWindowBackground: Bool = true
    
    /// g) Scrim local tras bloques de texto para máxima legibilidad
    @Published public var showLocalTextScrim: Bool = true
    
    // MARK: - Parámetros Numéricos Calibrados (Paso 2)
    /// Atenuación en modo Cristal Claro (Glass.clear): rango 0% (0.0, cristal puro sin velo) a 45% (0.45)
    @Published public var uniformScrimOpacity: Double = {
        let val = UserDefaults.standard.object(forKey: "glassClearScrimOpacityV2") != nil
            ? UserDefaults.standard.double(forKey: "glassClearScrimOpacityV2")
            : 0.0
        return max(0.0, min(0.45, val))
    }() {
        didSet {
            let clamped = max(0.0, min(0.45, uniformScrimOpacity))
            if clamped != uniformScrimOpacity {
                uniformScrimOpacity = clamped
            }
            UserDefaults.standard.set(clamped, forKey: "glassClearScrimOpacityV2")
            UserDefaults.standard.set(clamped, forKey: "glassClearScrimOpacity")
        }
    }
    
    /// Patrón de prueba de refracción detrás del notch para diagnóstico
    @Published public var showRefractionTestPattern: Bool = false
    
    /// Tinte blanco sutil (0% a 4%, default 0%)
    @Published public var glassTintOpacity: Double = 0.00
    
    /// Franja de acople con el notch físico (~34pt de alto + ~10pt de degradado)
    @Published public var notchStripHeight: CGFloat = 34.0
    @Published public var notchFadeHeight: CGFloat = 10.0
    
    // Borde especular 1 pt
    public let specularBorderWidth: CGFloat = 1.0
    public let specularTopOpacity: Double = 0.40
    public let specularMidOpacity: Double = 0.05
    public let specularBottomOpacity: Double = 0.18
    
    // Legibilidad de textos
    public let textShadowRadius: CGFloat = 2.0
    public let textShadowOpacity: Double = 0.25
    public let textShadowY: CGFloat = 1.0
    public let localTextScrimOpacity: Double = 0.18
    
    // Modo Auto luminosidad del fondo de pantalla
    @Published public var enableAutoWallpaperLuminance: Bool = false
    @Published public var detectedWallpaperLuminance: Double = 0.50
    
    // Detección del Sistema (macOS Accessibility y Liquid Glass Tint)
    public var isReduceTransparencyActive: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    
    public var isSystemLiquidGlassTinted: Bool {
        // macOS 26+: Verifica si el sistema tiene activado tinte en Liquid Glass o acento del sistema
        if let accent = UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int, accent != -1 {
            return true
        }
        if let tint = UserDefaults.standard.string(forKey: "AppleAquaColorVariant"), tint != "1" && tint != "6" {
            return true
        }
        return false
    }
    
    private init() {
        checkWallpaperLuminance()
    }
    
    public func checkWallpaperLuminance() {
        DispatchQueue.global(qos: .utility).async {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  let img = NSImage(contentsOf: url),
                  let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            
            let w = cgImg.width
            let h = cgImg.height
            let sampleRect = CGRect(x: max(0, w / 2 - w / 10), y: 0, width: w / 5, height: max(10, h / 10))
            guard let cropped = cgImg.cropping(to: sampleRect) else { return }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rawData = [UInt8](repeating: 0, count: 16 * 16 * 4)
            guard let ctx = CGContext(
                data: &rawData,
                width: 16,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 16 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            
            var totalLum: Double = 0
            let pixels = 16 * 16
            for p in 0..<pixels {
                let r = Double(rawData[p * 4]) / 255.0
                let g = Double(rawData[p * 4 + 1]) / 255.0
                let b = Double(rawData[p * 4 + 2]) / 255.0
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                totalLum += lum
            }
            let avg = totalLum / Double(pixels)
            DispatchQueue.main.async {
                self.detectedWallpaperLuminance = avg
                if self.enableAutoWallpaperLuminance {
                    // Solo sube la atenuación proporcionalmente en fondos muy claros (> 0.65), sin piso artificial de 18%
                    let autoVal = max(0.0, min(0.35, max(0.0, avg - 0.65) * 0.60))
                    if autoVal > self.uniformScrimOpacity {
                        self.uniformScrimOpacity = autoVal
                    }
                }
            }
        }
    }
}

// MARK: - GlassClearMetrics (Constantes para el Modo Cristal Claro "Glass.clear")
public struct GlassClearMetrics {
    public static var uniformScrimOpacity: Double {
        get { GlassClearManager.shared.uniformScrimOpacity }
        set { GlassClearManager.shared.uniformScrimOpacity = newValue }
    }
    public static var glassTintOpacity: Double {
        get { GlassClearManager.shared.glassTintOpacity }
        set { GlassClearManager.shared.glassTintOpacity = newValue }
    }
    public static var specularBorderWidth: CGFloat { GlassClearManager.shared.specularBorderWidth }
    public static var specularTopOpacity: Double { GlassClearManager.shared.specularTopOpacity }
    public static var specularMidOpacity: Double { GlassClearManager.shared.specularMidOpacity }
    public static var specularBottomOpacity: Double { GlassClearManager.shared.specularBottomOpacity }
    public static var textShadowRadius: CGFloat { GlassClearManager.shared.textShadowRadius }
    public static var textShadowOpacity: Double { GlassClearManager.shared.textShadowOpacity }
    public static var textShadowY: CGFloat { GlassClearManager.shared.textShadowY }
    public static var textScrimOpacity: Double { GlassClearManager.shared.localTextScrimOpacity }
    
    // Sombras exteriores
    public static var cardShadowRadius: CGFloat = 24.0
    public static var cardShadowY: CGFloat = 10.0
    public static var cardShadowOpacity: Double = 0.28
}
