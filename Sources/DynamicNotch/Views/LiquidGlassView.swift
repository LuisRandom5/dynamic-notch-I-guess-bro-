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
    @ObservedObject var backdrop = BackdropBrightnessMonitor.shared
    
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    public var isLiquidGlass: Bool
    public var darknessOpacity: Double
    public var stretch: CGFloat
    public var verticalStretch: CGFloat
    public var isExpanded: Bool
    public var topBleed: CGFloat
    /// Ver ElasticPillShape.trailingImpulse (física de desprendimiento/absorción de las bolitas)
    public var trailingImpulse: CGFloat = 0

    public init(
        topRadius: CGFloat,
        bottomRadius: CGFloat,
        isLiquidGlass: Bool = true,
        darknessOpacity: Double = 0.55,
        stretch: CGFloat = 0,
        verticalStretch: CGFloat = 0,
        isExpanded: Bool = true,
        topBleed: CGFloat = 0,
        trailingImpulse: CGFloat = 0
    ) {
        self.trailingImpulse = trailingImpulse
        self.topBleed = topBleed
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.isLiquidGlass = isLiquidGlass
        self.darknessOpacity = darknessOpacity
        self.stretch = stretch
        self.verticalStretch = verticalStretch
        self.isExpanded = isExpanded
    }

    /// Antes de macOS 26 no hay Liquid Glass: las alas del notch cerrado siguen negras
    private var isLegacyGlass: Bool {
        if #available(macOS 26.0, *) { return false }
        return true
    }
    
    public var body: some View {
        let pillShape: ElasticPillShape = {
            var shape = ElasticPillShape(
                topRadius: topRadius,
                bottomRadius: bottomRadius,
                stretch: stretch,
                verticalStretch: verticalStretch,
                topBleed: topBleed
            )
            shape.trailingImpulse = trailingImpulse
            return shape
        }()
        
        // Accesibilidad: Si el usuario activó "Reducir transparencia" o "Aumentar contraste", usar Negro Puro OLED
        let mode = appState.effectiveAppearanceMode
        
        GeometryReader { geo in
            let notchHeight = ScreenService.shared.currentGeometry.height
            let notchWidth = ScreenService.shared.currentGeometry.width
            // Notch cerrado con actividad (música, temporizador…): la píldora es más ancha que la cámara y sus
            // lados ("alas") son de cristal; el centro sigue negro detrás de la cámara física
            let hasGlassWings = appState.glassWingsEnabled && !isExpanded && geo.size.width > notchWidth + 12
            let showsGlass = isExpanded || hasGlassWings
            
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
                        // cmux #5860; y no detrás: el vidrio refractaría negro).
                        // Las alas pasan sobre la barra de menús: piso de 30% (Apple sugiere ~35% sobre fondos claros)
                        // Piso de 2 % (imperceptible): el vidrio lo compone macOS DETRÁS de la ventana, así que con
                        // velo 0 los píxeles de la tarjeta quedaban 100 % transparentes y macOS dejaba pasar los
                        // archivos arrastrados (y clics) a la ventana de abajo, salvo donde había texto o iconos
                        let veilOpacity = hasGlassWings
                            ? max(0.30, NotchGlassMetrics.veilOpacity(for: mode))
                            : max(0.02, NotchGlassMetrics.veilOpacity(for: mode))
                        
                        // El vidrio aparece/desaparece con la transición nativa `materialize` (la lente se forma y
                        // se disuelve) en vez de un simple fundido de opacidad
                        if showsGlass {
                            ZStack(alignment: .top) {
                                // Clear sobre el fondo de pantalla (lo más transparente); regular cuando detrás hay una
                                // ventana clara o un fondo claro: desenfoca lo de atrás y ajusta la luminosidad para que
                                // el texto blanco se lea (guía de Apple: clear sólo sobre contenido visual)
                                Color.clear
                                    .glassEffect(backdrop.isBackdropBright ? Glass.regular : Glass.clear, in: pillShape)
                                    .glassEffectTransition(.materialize)
                                
                                Color.black.opacity(veilOpacity)
                                    .clipShape(pillShape)
                                
                                // Negro detrás del notch físico con bordes suaves: desplegado, sólo la franja a la
                                // altura de la cámara (el resto del borde superior refracta como vidrio); cerrado con
                                // alas, todo el alto, para que la cámara quede dentro de una isla negra que se funde
                                // con el cristal de los lados
                                let bandWidth = notchWidth + (hasGlassWings ? 28 : 36)
                                let fade = (hasGlassWings ? 14 : 18) / bandWidth
                                LinearGradient(
                                    stops: hasGlassWings
                                        ? [.init(color: .black, location: 0.0), .init(color: .black, location: 1.0)]
                                        : [.init(color: .black.opacity(0.85), location: 0.0), .init(color: .black.opacity(0.0), location: 1.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(width: bandWidth, height: hasGlassWings ? geo.size.height : notchHeight + 12)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .black, location: fade),
                                            .init(color: .black, location: 1 - fade),
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
                    
                    // En reposo absoluto (notch cerrado sin actividad): negro puro para fundirse con la cámara física
                    pillShape
                        .fill(Color.black)
                        .opacity(showsGlass && !isLegacyGlass ? 0.0 : (isExpanded ? 0.0 : 1.0))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: showsGlass)
            .animation(.easeInOut(duration: 0.35), value: backdrop.isBackdropBright)
        }
        .animation(.easeInOut(duration: 0.24), value: isExpanded)
        .environment(\.controlActiveState, .key)
        .allowsHitTesting(false)
    }
}
