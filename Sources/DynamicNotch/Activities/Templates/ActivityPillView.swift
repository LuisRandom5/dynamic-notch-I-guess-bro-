import SwiftUI

// MARK: - ActivityPillView (Diseño Minimalista de Alas del Notch para Actividades Compactas - Imagen 2)
/// Extiende el notch físico a los lados con alas simétricas:
/// - Ala izquierda: Icono Leading (ej. AirDrop azul).
/// - Centro: Espacio libre bajo la cámara física del notch.
/// - Ala derecha: Elemento Trailing (ej. Anillo circular de progreso).
public struct ActivityPillView: View {
    public let activity: LiveActivity
    @EnvironmentObject var screenService: ScreenService
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    public var body: some View {
        let wingWidth: CGFloat = 60.0
        
        HStack(spacing: 0) {
            // Ala izquierda: Icono Leading (ej. AirDrop azul)
            HStack {
                if let leading = activity.leading {
                    leading
                }
                Spacer(minLength: 0)
            }
            .frame(width: wingWidth)
            .padding(.leading, 14)
            
            // Centro: Espacio libre bajo la cámara física del notch
            Spacer(minLength: 0)
                .frame(width: geometry.width)
            
            // Ala derecha: Trailing (ej. Anillo circular azul de progreso)
            HStack {
                Spacer(minLength: 0)
                if let trailing = activity.trailing {
                    trailing
                }
            }
            .frame(width: wingWidth)
            .padding(.trailing, 14)
        }
        .frame(width: geometry.width + (wingWidth * 2), height: geometry.height)
    }
}
