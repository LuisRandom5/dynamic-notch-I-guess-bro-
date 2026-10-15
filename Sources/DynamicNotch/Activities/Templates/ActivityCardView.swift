import SwiftUI

public struct ActivityCardView: View {
    public let activity: LiveActivity
    @ObservedObject var center = ActivityCenter.shared
    
    @State private var isRevealed: Bool = false
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var isDismissing: Bool {
        center.dismissingActivityId == activity.id
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Fondo interactivo: al tocar cualquier parte libre de la tarjeta o del notch, colapsa
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    activity.onTap?()
                }
            
            HStack(spacing: 16) {
                // MARK: - Extremo Izquierdo: Visual / Icono (MagSafe, Batería, AirDrop, etc.)
                // Acompaña la contracción del borde izquierdo desplazándose hacia el centro
                if let leading = activity.leading {
                    leading
                        .frame(width: 48, height: 48)
                        .scaleEffect(isDismissing ? 0.82 : (isRevealed ? 1.0 : 0.84))
                        .opacity(isDismissing ? 0.0 : (isRevealed ? 1.0 : 0.0))
                        .offset(x: isDismissing ? 18 : 0)
                        .animation(
                            isDismissing
                                ? .easeOut(duration: ExitAnimationMetrics.cardDismissLeadingDuration)
                                : .spring(response: 0.36, dampingFraction: 0.76),
                            value: isDismissing
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.76), value: isRevealed)
                }
                
                // MARK: - Centro: Título y Subtítulo
                // Se desvanece primero (180 ms) elevándose sutilmente hacia la cámara para no deformarse
                VStack(alignment: .leading, spacing: 3) {
                    if let centerView = activity.center {
                        centerView
                    }
                }
                .offset(y: isDismissing ? -6 : (isRevealed ? 0 : 6))
                .scaleEffect(isDismissing ? 0.94 : 1.0)
                .opacity(isDismissing ? 0.0 : (isRevealed ? 1.0 : 0.0))
                .animation(
                    isDismissing
                        ? .easeOut(duration: ExitAnimationMetrics.cardDismissTextDuration)
                        : .spring(response: 0.40, dampingFraction: 0.82),
                    value: isDismissing
                )
                .animation(.spring(response: 0.40, dampingFraction: 0.82), value: isRevealed)
                
                Spacer(minLength: 12)
                
                // MARK: - Extremo Derecho: Trailing (Porcentaje + Batería / Estado)
                // Acompaña la contracción del borde derecho desplazándose hacia adentro
                if let trailing = activity.trailing {
                    trailing
                        .scaleEffect(isDismissing ? 0.86 : (isRevealed ? 1.0 : 0.88))
                        .opacity(isDismissing ? 0.0 : (isRevealed ? 1.0 : 0.0))
                        .offset(x: isDismissing ? -18 : 0)
                        .animation(
                            isDismissing
                                ? .easeOut(duration: ExitAnimationMetrics.cardDismissTrailingDuration)
                                : .spring(response: 0.38, dampingFraction: 0.78),
                            value: isDismissing
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isRevealed)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 36) // Despeja completamente el notch físico de la MacBook
            .padding(.bottom, 16)
        }
        .frame(width: 390, height: 112)
        .scaleEffect(isDismissing ? 0.94 : 1.0, anchor: .top)
        .animation(
            isDismissing
                ? .spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)
                : .default,
            value: isDismissing
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    isRevealed = true
                }
            }
        }
    }
}
