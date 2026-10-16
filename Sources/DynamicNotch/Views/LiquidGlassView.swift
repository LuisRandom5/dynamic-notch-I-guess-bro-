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

    // Resplandor reactivo al cursor
    @State private var hoverLocation: CGPoint = .zero
    @State private var isCursorInside: Bool = false

    public init(
        topRadius: CGFloat,
        bottomRadius: CGFloat,
        isLiquidGlass: Bool = true,
        darknessOpacity: Double = 0.55,
        stretch: CGFloat = 0,
        verticalStretch: CGFloat = 0,
        isExpanded: Bool = true
    ) {
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
            verticalStretch: verticalStretch
        )
        
        // Accesibilidad: Si el usuario activó "Reducir transparencia", forzar Negro Puro OLED
        let isReduceTransparencyActive = MotionTokens.isReduceTransparencyActive
        let mode = isReduceTransparencyActive ? .pureOLED : appState.effectiveAppearanceMode
        
        ZStack {
            if mode == .pureOLED {
                // MODO A: Negro Puro OLED (#000000 sólido continuo, 0% GPU)
                Color.black
            } else {
                // MODO B: Cristal Líquido (Liquid Glass) Real del Sistema
                if #available(macOS 26.0, *) {
                    ZStack {
                        // Material real del sistema macOS Tahoe (sin imitaciones)
                        Color.clear
                            .glassEffect(Glass.regular, in: pillShape)
                        
                        // (a) Capa de atenuación negra uniforme calibrada
                        let activeScrim = (mode == .darkGlass)
                            ? appState.glassDarknessOpacity
                            : min(0.35, max(0.0, glassManager.uniformScrimOpacity))
                        Color.black.opacity(activeScrim)
                        
                        // (c) Resplandor reactivo al cursor
                        if isCursorInside && !MotionTokens.isReduceMotionActive {
                            GeometryReader { proxy in
                                let size = proxy.size
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.0)
                                    ],
                                    center: UnitPoint(
                                        x: size.width > 0 ? hoverLocation.x / size.width : 0.5,
                                        y: size.height > 0 ? hoverLocation.y / size.height : 0.5
                                    ),
                                    startRadius: 0,
                                    endRadius: 95
                                )
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .opacity(isExpanded ? 1.0 : 0.0)
                } else {
                    // Fallback para versiones anteriores
                    ZStack {
                        VisualEffectBackground(
                            material: (mode == .darkGlass) ? .hudWindow : .popover,
                            blendingMode: .behindWindow,
                            state: .active
                        )
                        let activeScrim = (mode == .darkGlass)
                            ? appState.glassDarknessOpacity
                            : min(0.35, max(0.0, glassManager.uniformScrimOpacity))
                        Color.black.opacity(activeScrim)
                        
                        if isCursorInside && !MotionTokens.isReduceMotionActive {
                            GeometryReader { proxy in
                                let size = proxy.size
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.0)
                                    ],
                                    center: UnitPoint(
                                        x: size.width > 0 ? hoverLocation.x / size.width : 0.5,
                                        y: size.height > 0 ? hoverLocation.y / size.height : 0.5
                                    ),
                                    startRadius: 0,
                                    endRadius: 95
                                )
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .opacity(isExpanded ? 1.0 : 0.0)
                }
                
                // En reposo (o transición): Negro puro para fundirse con la cámara del notch físico
                Color.black
                    .opacity(isExpanded ? 0.0 : 1.0)
            }
        }
        .clipShape(pillShape)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
                if !isCursorInside {
                    withAnimation(.easeIn(duration: 0.15)) {
                        isCursorInside = true
                    }
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.25)) {
                    isCursorInside = false
                }
            }
        }
    }
}
