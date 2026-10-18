import AppKit
import AVKit
import SwiftUI

/// Representable para usar NSVisualEffectView nativo como fallback en versiones anteriores a macOS 26
public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Selector nativo de salida de audio del sistema (AirPlay / Salida de Audio)
public struct NativeAudioRoutePicker: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(NSColor.white.withAlphaComponent(0.85), for: .normal)
        picker.setRoutePickerButtonColor(NSColor.systemBlue, for: .active)
        return picker
    }
    
    public func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

/// Patrón de prueba para diagnosticar refracción de borde y curvatura en Liquid Glass
public struct StripedTestPatternView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Canvas { context, size in
                let stripeWidth: CGFloat = 18.0
                var x: CGFloat = 0
                var isBlack = true
                while x < size.width + size.height * 2 {
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x - size.height, y: size.height))
                        p.addLine(to: CGPoint(x: x - size.height + stripeWidth, y: size.height))
                        p.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
                        p.closeSubpath()
                    }
                    context.fill(path, with: .color(isBlack ? .black : .white))
                    x += stripeWidth
                    isBlack.toggle()
                }
            }
            
            VStack(spacing: 4) {
                Text("PATRÓN DE PRUEBA: REFRACCIÓN")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.blue)
                Text("1 2 3 4 5 6 7 8 9 0")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.red)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Fondo reactivo del Notch (Liquid Glass macOS 26+ Tahoe HIG Compliant):
/// - Variante base: `Glass.regular` sin tinte decorativo ni imitaciones.
/// - Eliminados todos los blurs simulados, ultraThinMaterial, degradados y bordes manuales.
/// - Dejadas únicamente las 3 capas permitidas:
///   (a) La atenuación uniforme como capa propia separada.
///   (b) La sombra exterior fuera de la silueta.
///   (c) El resplandor reactivo al cursor como capa de primer plano (.blendMode(.plusLighter)).
/// - Estado compacto = Negro puro OLED (#000000) para fundirse con el hardware de la cámara.
public struct DynamicNotchBackgroundView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var glassManager = GlassClearManager.shared
    
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    public var isLiquidGlass: Bool
    public var darknessOpacity: Double
    public var stretch: CGFloat
    public var verticalStretch: CGFloat
    public var isExpanded: Bool
    public var topBleed: CGFloat

    public init(
        topRadius: CGFloat,
        bottomRadius: CGFloat,
        isLiquidGlass: Bool = true,
        darknessOpacity: Double = 0.55,
        stretch: CGFloat = 0,
        verticalStretch: CGFloat = 0,
        isExpanded: Bool = true,
        topBleed: CGFloat = 0
    ) {
        self.topBleed = topBleed
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.isLiquidGlass = isLiquidGlass
        self.darknessOpacity = darknessOpacity
        self.stretch = stretch
        self.verticalStretch = verticalStretch
        self.isExpanded = isExpanded
    }

    public var body: some View {
        let pillShape = ElasticPillShape(
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            stretch: stretch,
            verticalStretch: verticalStretch,
            topBleed: topBleed
        )
        
        // Accesibilidad: Si el usuario activó "Reducir transparencia" o "Aumentar contraste", usar Negro Puro OLED
        let mode = appState.effectiveAppearanceMode
        
        ZStack {
            if mode == .pureOLED {
                // MODO 1: Negro Puro OLED (#000000 sólido continuo, 100% opaco, 0% GPU)
                pillShape
                    .fill(Color.black)
            } else {
                // MODO 2 (Cristal Oscuro) y MODO 3 (Cristal Claro): Liquid Glass Nativo de Apple (macOS 26+)
                if #available(macOS 26.0, *) {
                    // Probado con capturas en el laboratorio (GlassLabWindow): el aspecto objetivo es el de los
                    // módulos del Centro de Control: vidrio clear + velo oscuro ligero para que el texto se lea.
                    // Velo SOBRE el vidrio (no tinte: en macOS 27 el tinte oscuro se dibuja como relleno sólido,
                    // cmux #5860; y no detrás: el vidrio refractaría negro). Con el slider por defecto (38%) ≈ 11%.
                    let veilOpacity = NotchGlassMetrics.veilOpacity(for: mode)
                    let notchHeight = ScreenService.shared.currentGeometry.height
                    let notchWidth = ScreenService.shared.currentGeometry.width
                    
                    // El vidrio aparece/desaparece con la transición nativa `materialize` (la lente se forma y
                    // se disuelve) en vez de un simple fundido de opacidad
                    if isExpanded {
                        ZStack(alignment: .top) {
                            Color.clear
                                .glassEffect(Glass.clear, in: pillShape)
                                .glassEffectTransition(.materialize)
                            
                            Color.black.opacity(veilOpacity)
                                .clipShape(pillShape)
                            
                            // Franja a la altura de la cámara SÓLO detrás del notch físico (con bordes suaves): funde
                            // el vidrio con la cámara sin apagar el resto del borde superior, que así refracta como
                            // vidrio de verdad
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.85), location: 0.0),
                                    .init(color: .black.opacity(0.0), location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: notchWidth + 36, height: notchHeight + 12)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .black, location: 18 / (notchWidth + 36)),
                                        .init(color: .black, location: 1 - 18 / (notchWidth + 36)),
                                        .init(color: .clear, location: 1.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipShape(pillShape)
                        }
                        .allowsHitTesting(false)
                        // El vidrio se dibuja siempre con apariencia oscura: es la variante "Clear puro" elegida en
                        // el laboratorio; en apariencia clara macOS lo vuelve blanquecino y esmerilado
                        .environment(\.colorScheme, .dark)
                        .environment(\.controlActiveState, .key)
                        .transition(.opacity)
                    }
                } else {
                    // Fallback para versiones anteriores a macOS 26
                    let activeScrim = (mode == .darkGlass)
                        ? max(0.0, min(0.85, appState.glassDarknessOpacity))
                        : max(0.0, min(0.45, glassManager.uniformScrimOpacity))
                    ZStack {
                        VisualEffectBackground(
                            material: (mode == .darkGlass) ? .hudWindow : .popover,
                            blendingMode: .behindWindow,
                            state: .active
                        )
                        if activeScrim > 0.001 {
                            Color.black.opacity(activeScrim)
                        }
                    }
                    .clipShape(pillShape)
                    .opacity(isExpanded ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }
                
                // En reposo absoluto (sin contenido desplegado): Negro puro para fundirse con la cámara física
                pillShape
                    .fill(Color.black)
                    .opacity(isExpanded ? 0.0 : 1.0)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: isExpanded)
        .environment(\.controlActiveState, .key)
        .allowsHitTesting(false)
    }
}
