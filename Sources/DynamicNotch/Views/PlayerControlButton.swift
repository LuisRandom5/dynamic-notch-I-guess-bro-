import SwiftUI

// MARK: - PlayerControlButton (Botón de Control Multimedia Estilo iOS 18 / Apple Music)
/// Proporciona retroalimentación visual táctil tanto al pasar el cursor (hover) como al hacer clic:
/// - Estado hover con cápsula/círculo de cristal translúcido y micro-escala suave (1.06x).
/// - Compresión elástica con onda luminosa nítida al hacer clic y desplazamiento direccional opcional.
/// - Indicador luminoso inferior opcional para estados activos (Shuffle / Repeat).
public struct PlayerControlButton<Content: View>: View {
    public let action: () -> Void
    public var xOffset: CGFloat = 0.0
    public var scaleAmount: CGFloat = 0.84
    public var haloSize: CGFloat = 34.0
    public var isActive: Bool = false
    public var activeTint: Color = .white
    public let content: Content
    
    @State private var isHovering: Bool = false
    
    public init(
        xOffset: CGFloat = 0.0,
        scaleAmount: CGFloat = 0.84,
        haloSize: CGFloat = 34.0,
        isActive: Bool = false,
        activeTint: Color = .white,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.action = action
        self.xOffset = xOffset
        self.scaleAmount = scaleAmount
        self.haloSize = haloSize
        self.isActive = isActive
        self.activeTint = activeTint
        self.content = content()
    }
    
    public var body: some View {
        // Como Apple Music: la respuesta llega al presionar (MusicTransportButtonStyle), no al soltar
        Button(action: action) {
            content
                .scaleEffect(isHovering ? 1.04 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isHovering)
        }
        .buttonStyle(MusicTransportButtonStyle(haloSize: haloSize, pressedScale: scaleAmount, isHovering: isHovering, isActive: isActive))
        .overlay(alignment: .bottom) {
            // Punto luminoso inferior cuando un modo (Shuffle / Repeat) está activo
            if isActive {
                Circle()
                    .fill(activeTint)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: activeTint.opacity(0.8), radius: 3, x: 0, y: 0)
                    .offset(y: -1.5)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
