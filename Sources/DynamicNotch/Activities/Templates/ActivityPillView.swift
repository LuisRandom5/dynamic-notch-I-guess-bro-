import SwiftUI

// MARK: - ActivityPillView (Alas del Notch para Actividades Compactas como AirDrop - Imagen 2)
/// Extiende el notch físico a los lados con alas simétricas y márgenes amplios:
/// - Ala izquierda: Icono de AirDrop en azul con generoso espacio interior.
/// - Centro: Espacio libre protegido bajo la cámara física del notch.
/// - Ala derecha: Anillo circular azul de progreso con suficiente distancia del borde curvo.
public struct ActivityPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    @ObservedObject var center = ActivityCenter.shared
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    private var isDismissing: Bool {
        center.dismissingActivityId == activity.id
    }
    
    public var body: some View {
        let wingWidth: CGFloat = 85.0
        
        HStack(spacing: 0) {
            // Ala izquierda: Icono Leading (AirDrop azul) con margen holgado
            HStack {
                if let leading = activity.leading {
                    leading
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .frame(width: wingWidth, height: geometry.height, alignment: .center)
            .opacity(isDismissing ? 0.0 : 1.0)
            .scaleEffect(isDismissing ? 0.90 : 1.0)
            .offset(x: isDismissing ? 14 : 0)
            .animation(.spring(response: ExitAnimationMetrics.sliderDismissResponse, dampingFraction: ExitAnimationMetrics.sliderDismissDamping), value: isDismissing)
            
            // Centro: Espacio libre bajo la cámara física del notch
            Spacer(minLength: 0)
                .frame(width: geometry.width)
            
            // Ala derecha: Anillo circular azul de progreso con margen holgado
            HStack {
                Spacer(minLength: 0)
                if let trailing = activity.trailing {
                    trailing
                }
            }
            .padding(.trailing, 18)
            .frame(width: wingWidth, height: geometry.height, alignment: .center)
            .opacity(isDismissing ? 0.0 : 1.0)
            .scaleEffect(isDismissing ? 0.90 : 1.0)
            .offset(x: isDismissing ? -14 : 0)
            .animation(.spring(response: ExitAnimationMetrics.sliderDismissResponse, dampingFraction: ExitAnimationMetrics.sliderDismissDamping), value: isDismissing)
        }
        .frame(width: geometry.width + (wingWidth * 2), height: geometry.height, alignment: .center)
    }
}
