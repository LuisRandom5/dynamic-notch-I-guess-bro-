import SwiftUI

// MARK: - NotchDropInvitationView (Tarjeta Pop-Up Expandida de Drag & Drop - Estilo MagSafe / Batería)
/// Diseñada con dimensiones generosas (460 x 144 pt) para una zona de suelta amplia, cómoda y reactiva:
/// - Extremo izquierdo: Hero Icon circular de 56x56 pt con halo reactivo y onda expansiva.
/// - Centro: Título y subtítulo con tipografía nativa amplia y legible de Live Activity.
/// - Extremo derecho: Badge de cápsula translúcida con recuento dinámico de archivos o confirmación.
/// - Zona de soltado interactiva con borde pulsante cuando el cursor se aproxima al notch.
public struct NotchDropInvitationView: View {
    @ObservedObject var probe = DragDetectionProbe.shared
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenService: ScreenService
    
    // Estados de animación pop-up escalonada (idéntica a ActivityCardView)
    @State private var isRevealed: Bool = false
    @State private var isDismissing: Bool = false
    @State private var isDroppedSuccess: Bool = false
    @State private var isDropError: Bool = false
    @State private var successRippleScale: CGFloat = 1.0
    @State private var successRippleOpacity: Double = 0.0
    
    public init() {}
    
    private var isVeryClose: Bool {
        probe.distanceToNotch <= 85.0
    }
    
    private var tintColor: Color {
        if isDropError || appState.isDropErrorAnimating {
            return DesignTokens.red
        } else if isDroppedSuccess || appState.isDropSuccessAnimating || isVeryClose {
            return DesignTokens.green
        } else {
            return DesignTokens.blue
        }
    }
    
    private var heroIconName: String {
        if isDropError || appState.isDropErrorAnimating {
            return "xmark.circle.fill"
        } else if isDroppedSuccess || appState.isDropSuccessAnimating {
            return "checkmark.circle.fill"
        } else if isVeryClose {
            return "tray.and.arrow.down.fill"
        } else {
            return "arrow.down.doc.fill"
        }
    }
    
    private var titleText: String {
        if isDropError || appState.isDropErrorAnimating {
            return appState.dropErrorMessage.isEmpty ? "Formato no compatible" : appState.dropErrorMessage
        } else if isDroppedSuccess || appState.isDropSuccessAnimating {
            let count = max(1, appState.lastDroppedCount)
            return count > 1 ? "¡\(count) archivos guardados!" : "¡Archivo guardado en la repisa!"
        } else if isVeryClose {
            return "¡Suelta para guardar!"
        } else {
            return "Añadir a la bandeja"
        }
    }
    
    private var subtitleText: String {
        if isDropError || appState.isDropErrorAnimating {
            return "Solo se admiten archivos y carpetas válidos"
        } else if isDroppedSuccess || appState.isDropSuccessAnimating {
            return "Archivos listos en el Notch cuando los necesites"
        } else if isVeryClose {
            return "Soltar para guardar y mover a la bandeja"
        } else {
            return "Bandeja temporal de Dynamic Notch"
        }
    }
    
    private var badgeIconName: String {
        if isDropError || appState.isDropErrorAnimating {
            return "exclamationmark.triangle.fill"
        } else if isDroppedSuccess || appState.isDropSuccessAnimating {
            return "checkmark"
        } else {
            return "doc.on.doc.fill"
        }
    }
    
    private var badgeText: String {
        if isDropError || appState.isDropErrorAnimating {
            return "Error"
        } else if isDroppedSuccess || appState.isDropSuccessAnimating {
            return "Guardado"
        } else {
            let count = max(1, probe.itemCount)
            return "\(count) \(count == 1 ? "archivo" : "archivos")"
        }
    }
    
    public var body: some View {
        ZStack {
            // Guía visual suave de zona de suelta activa
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(
                    tintColor.opacity(isVeryClose ? 0.45 : 0.15),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .padding(6)
                .opacity(isRevealed && !isDismissing ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.25), value: isVeryClose)
            
            HStack(spacing: 18) {
                // MARK: - Extremo Izquierdo: Hero Icon Pop con halo reactivo (56x56 pt)
                ZStack {
                    // Onda de éxito expansiva al recibir el archivo
                    Circle()
                        .stroke(DesignTokens.green, lineWidth: 2.5)
                        .frame(width: 56, height: 56)
                        .scaleEffect(successRippleScale)
                        .opacity(successRippleOpacity)
                    
                    // Halo de fondo suave
                    Circle()
                        .fill(tintColor.opacity(isVeryClose ? 0.24 : 0.16))
                        .frame(width: 56, height: 56)
                        .scaleEffect(isVeryClose ? 1.06 : 1.0)
                    
                    // Borde fino de 1px físico real
                    Circle()
                        .stroke(tintColor.opacity(0.40), lineWidth: MotionTokens.physicalPixel)
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: heroIconName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(tintColor)
                        .scaleEffect(isDroppedSuccess ? 1.15 : 1.0)
                        .contentTransition(.symbolEffect(.replace))
                }
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
                
                // MARK: - Centro: Título y Subtítulo estilo Apple Card (MagSafe / Batería)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    
                    Text(subtitleText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
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
                
                // MARK: - Extremo Derecho: Badge de Cápsula Translúcida
                HStack(spacing: 6) {
                    Image(systemName: badgeIconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(tintColor)
                    
                    Text(badgeText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Capsule().stroke(tintColor.opacity(0.38), lineWidth: MotionTokens.physicalPixel)
                        )
                )
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
            .padding(.horizontal, 28)
            .padding(.top, 40) // Despeja la cámara física del notch con holgura
            .padding(.bottom, 20)
        }
        .frame(width: 460, height: 144)
        .scaleEffect(isDismissing ? 0.94 : 1.0, anchor: .top)
        .animation(
            isDismissing
                ? .spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)
                : .default,
            value: isDismissing
        )
        .onAppear {
            // Revelación suave sincronizada estilo Dynamic Island
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    isRevealed = true
                }
            }
            
            // Suscripción a éxito de soltado
            appState.onDropSuccess = {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                    self.isDroppedSuccess = true
                }
                // Onda expansiva de confirmación
                successRippleScale = 1.0
                successRippleOpacity = 0.85
                withAnimation(.easeOut(duration: 0.55)) {
                    successRippleScale = 1.65
                    successRippleOpacity = 0.0
                }
                
                // Desvanecimiento suave e integración
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                    self.isDismissing = true
                }
            }
            
            // Suscripción a error de soltado
            appState.onDropError = { _ in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                    self.isDropError = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
                    self.isDismissing = true
                }
            }
        }
        .onDisappear {
            isDroppedSuccess = false
            isDropError = false
            isDismissing = false
            isRevealed = false
            successRippleScale = 1.0
            successRippleOpacity = 0.0
        }
    }
}
