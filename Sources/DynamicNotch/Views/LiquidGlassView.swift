import AppKit
import SwiftUI

/// Representable para usar NSVisualEffectView nativo de macOS como respaldo de refracción detrás de la ventana
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

/// Fondo reactivo del Notch (Liquid Glass macOS 26/27 Tahoe HIG Compliant):
/// - Variante base: `Glass.regular` sin tinte decorativo.
/// - Atenuación negra uniforme como capa propia (0-35%, default 10%).
/// - Estado compacto = Negro puro OLED (0% shaders Metal). El cristal se activa al iniciar la expansión.
/// - Resplandor reactivo al cursor con `onContinuousHover` y `blendMode(.plusLighter)`.
/// - Destello diagonal de apertura (~350 ms, blanco ~12%).
/// - Trazos de 1 píxel físico real (`MotionTokens.physicalPixel`).
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

    // Estados para efectos de luz (Cursor Glow & Expansion Shimmer)
    @State private var hoverLocation: CGPoint = .zero
    @State private var isCursorInside: Bool = false
    @State private var shimmerPhase: CGFloat = -1.0

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
        
        GeometryReader { proxy in
            let size = proxy.size
            
            ZStack {
                if mode == .pureOLED {
                    // MODO A: Negro Puro OLED (#000000 sólido continuo, 0% GPU)
                    Color.black
                } else {
                    // MODO B: Cristal Líquido (Liquid Glass) Continuo
                    // Mantiene el árbol de vistas idéntico a OLED para que SwiftUI interpole suavemente los springs a 120 fps
                    ZStack {
                        if isExpanded {
                            // Capa 1: Respaldo nativo de refracción NSVisualEffectView que difumina el fondo del escritorio
                            VisualEffectBackground(
                                material: (mode == .darkGlass) ? .hudWindow : .popover,
                                blendingMode: .behindWindow,
                                state: .active
                            )
                            
                            // Capa 1b: Película ultraThinMaterial para micro-grano y textura de cristal
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            
                            // Capa 2: Atenuación oscura calibrada (Clear Glass: 0-35%, Dark Glass: 30-90%)
                            let activeScrim = (mode == .darkGlass)
                                ? appState.glassDarknessOpacity
                                : min(0.35, max(0.0, glassManager.uniformScrimOpacity))
                            Color.black.opacity(activeScrim)
                        } else {
                            // En reposo: Negro puro para fundirse con la cámara del notch físico
                            Color.black
                        }
                        
                        // Capa 4: Franja superior de fusión con el notch
                        if glassManager.showNotchFusionStrip && isExpanded {
                            VStack(spacing: 0) {
                                Color.black
                                    .frame(height: glassManager.notchStripHeight)
                                LinearGradient(
                                    colors: [Color.black, Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: glassManager.notchFadeHeight)
                                Spacer()
                            }
                        }
                        
                        // Capa 5: Borde especular sutil
                        if glassManager.showSpecularBorder && isExpanded {
                            pillShape.stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.24), location: 0.0),
                                        .init(color: Color.white.opacity(0.04), location: 0.45),
                                        .init(color: Color.white.opacity(0.10), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: MotionTokens.physicalPixel
                            )
                        }
                        
                        // Capa 6: Destello lumínico al abrir
                        if shimmerPhase > -0.9 && shimmerPhase < 1.9 {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.12), location: 0.5),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: max(40, size.width * 0.40))
                            .offset(x: (shimmerPhase - 0.5) * (size.width * 1.5))
                            .rotationEffect(.degrees(20))
                            .allowsHitTesting(false)
                        }
                        
                        // Capa 7: Resplandor reactivo al cursor
                        if isCursorInside && isExpanded && !MotionTokens.isReduceMotionActive {
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
            .onChange(of: isExpanded) { _, newValue in
                if newValue && !MotionTokens.isReduceMotionActive {
                    // Disparar destello lumínico diagonal al abrir
                    shimmerPhase = -0.5
                    withAnimation(.linear(duration: MotionTokens.shimmerDuration)) {
                        shimmerPhase = 1.5
                    }
                } else {
                    shimmerPhase = -1.0
                }
            }
        }
    }
}
