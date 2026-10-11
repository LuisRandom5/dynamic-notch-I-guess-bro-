import SwiftUI

// MARK: - PlayerControlButton (Respuesta Visual Garantizada para Clics de Trackpad)
/// Proporciona retroalimentación visual inmediata e inconfundible en CUALQUIER clic:
/// - No depende de mantener presionado el trackpad.
/// - Dispara una animación garantizada con rebote elástico.
/// - Muestra un destello circular translúcido (ripple/flash) que confirma visualmente la pulsación.
/// - Aplica desplazamiento direccional físico (izquierda en anterior, derecha en siguiente).
public struct PlayerControlButton<Content: View>: View {
    public let action: () -> Void
    public var xOffset: CGFloat = 0.0
    public var scaleAmount: CGFloat = 0.80
    public var haloSize: CGFloat = 34.0
    public let content: Content
    
    @State private var isBouncing: Bool = false
    @State private var flashOpacity: Double = 0.0
    
    public init(
        xOffset: CGFloat = 0.0,
        scaleAmount: CGFloat = 0.80,
        haloSize: CGFloat = 34.0,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.action = action
        self.xOffset = xOffset
        self.scaleAmount = scaleAmount
        self.haloSize = haloSize
        self.content = content()
    }
    
    public var body: some View {
        Button(action: {
            triggerFeedback()
            action()
        }) {
            ZStack {
                // Destello/halo de confirmación visual brillante
                Circle()
                    .fill(Color.white.opacity(flashOpacity))
                    .frame(width: haloSize, height: haloSize)
                    .blur(radius: 3.5)
                
                content
            }
            .scaleEffect(isBouncing ? scaleAmount : 1.0)
            .offset(x: isBouncing ? xOffset : 0.0)
        }
        .buttonStyle(.plain)
    }
    
    private func triggerFeedback() {
        // Fase 1: Compresión inmediata + destello visual brillante
        withAnimation(.spring(response: 0.12, dampingFraction: 0.50)) {
            isBouncing = true
            flashOpacity = 0.38
        }
        
        // Fase 2: Retorno elástico con rebote suave asegurado (~0.14 s después)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                self.isBouncing = false
                self.flashOpacity = 0.0
            }
        }
    }
}
