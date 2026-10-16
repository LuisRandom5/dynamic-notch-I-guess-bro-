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
    @State private var isBouncing: Bool = false
    @State private var flashOpacity: Double = 0.0
    @State private var rippleScale: CGFloat = 0.85
    
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
        Button(action: {
            triggerFeedback()
            action()
        }) {
            ZStack {
                // Fondo translúcido en Hover / Estado activo
                Circle()
                    .fill(
                        Color.white.opacity(
                            isBouncing ? 0.22 : (isHovering ? 0.12 : (isActive ? 0.10 : 0.0))
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white.opacity(isHovering || isBouncing ? 0.16 : (isActive ? 0.12 : 0.0)),
                                lineWidth: 0.6
                            )
                    )
                    .frame(width: haloSize, height: haloSize)
                    .scaleEffect(isBouncing ? 0.94 : (isHovering ? 1.03 : 0.92))
                
                // Onda de confirmación (ripple) al hacer clic
                Circle()
                    .fill(Color.white.opacity(flashOpacity))
                    .frame(width: haloSize * 1.08, height: haloSize * 1.08)
                    .scaleEffect(rippleScale)
                    .blur(radius: 2.0)
                
                content
                    .scaleEffect(isBouncing ? scaleAmount : (isHovering ? 1.06 : 1.0))
                    .offset(x: isBouncing ? xOffset : 0.0)
                
                // Punto luminoso inferior cuando un modo (Shuffle / Repeat) está activo
                if isActive {
                    Circle()
                        .fill(activeTint)
                        .frame(width: 3.5, height: 3.5)
                        .shadow(color: activeTint.opacity(0.8), radius: 3, x: 0, y: 0)
                        .offset(y: (haloSize * 0.5) - 3.5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: haloSize, height: haloSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.76)) {
                isHovering = hovering
            }
        }
    }
    
    private func triggerFeedback() {
        rippleScale = 0.85
        withAnimation(.spring(response: 0.14, dampingFraction: 0.58)) {
            isBouncing = true
            flashOpacity = 0.30
            rippleScale = 1.12
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.64)) {
                self.isBouncing = false
                self.flashOpacity = 0.0
                self.rippleScale = 1.0
            }
        }
    }
}
