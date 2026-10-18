import SwiftUI

// MARK: - Liquid Glass del notch (guía "Adopting Liquid Glass" de Apple)
//
// - El notch desplegado es la capa funcional que flota sobre el contenido (como los módulos del Centro de
//   Control): es la única superficie grande de vidrio. Nada de vidrio sobre vidrio: lo que va encima del
//   notch (botones, carátula, textos) es contenido, sin materiales propios.
// - Todas las superficies de vidrio (notch + bolitas) viven en un único `GlassEffectContainer`: se dibujan
//   juntas (mejor rendimiento) y, al acercarse, se funden y separan como líquido de forma nativa.
// - Variante `clear` (el aspecto elegido del Centro de Control) con una capa de atenuación oscura; Apple
//   recomienda clear sólo sobre fondos ricos y atenuar si el fondo es claro.
// - Sin tinte decorativo: el color se reserva para estados (anillos, indicadores), no para el vidrio.
// - Reducir transparencia / Aumentar contraste → negro OLED (AppState.effectiveAppearanceMode).

public enum NotchGlassMetrics {
    /// Distancia a la que dos superficies de vidrio empiezan a fundirse. Menor que el hueco entre el notch y
    /// las bolitas (6 pt) para que en reposo se vean separadas y sólo se unan al acercarse.
    public static let containerSpacing: CGFloat = 4

    /// Atenuación sobre el vidrio clear según el modo y los ajustes del usuario
    public static func veilOpacity(for mode: NotchAppearanceMode) -> Double {
        if mode == .clearGlass {
            return max(0.0, min(0.45, GlassClearManager.shared.uniformScrimOpacity)) * 0.5
        }
        return max(0.0, min(0.85, AppState.shared.glassDarknessOpacity)) * 0.30
    }
}

// MARK: - Entorno

private struct NotchGlassSurfaceVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// true mientras el notch se muestra como vidrio (desplegado en un modo de cristal): las bolitas que lo
    /// acompañan pasan a ser del mismo vidrio para no ser discos negros junto a una superficie translúcida.
    var notchGlassSurfaceVisible: Bool {
        get { self[NotchGlassSurfaceVisibleKey.self] }
        set { self[NotchGlassSurfaceVisibleKey.self] = newValue }
    }
}

// MARK: - Contenedor

/// Agrupa todas las superficies de vidrio del notch en un `GlassEffectContainer` (macOS 26+).
public struct NotchGlassContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: NotchGlassMetrics.containerSpacing) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Fondo de bolita

/// Fondo circular de una bolita satélite: negro OLED junto al notch negro, o el mismo vidrio que el notch
/// cuando éste está desplegado en cristal (interactivo: responde al puntero como un control nativo).
public struct NotchBubbleBackground: View {
    public let size: CGFloat

    @Environment(\.notchGlassSurfaceVisible) private var glassVisible
    @ObservedObject private var appState = AppState.shared

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let mode = appState.effectiveAppearanceMode
        ZStack {
            if #available(macOS 26.0, *), glassVisible, mode != .pureOLED {
                Color.black.opacity(NotchGlassMetrics.veilOpacity(for: mode))
                    .clipShape(Circle())
                    .glassEffect(Glass.clear.interactive(), in: Circle())
                    .glassEffectTransition(.materialize)
                    .environment(\.colorScheme, mode == .clearGlass ? .light : .dark)
            } else {
                Circle()
                    .fill(Color.black)
                    .overlay(
                        // Borde exterior fino y sutil que define la silueta sin estridencias
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.40), radius: 3, x: 0, y: 1)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.24), value: glassVisible)
    }
}
