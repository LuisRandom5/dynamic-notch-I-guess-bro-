import SwiftUI

public struct ActivityCardView: View {
    public let activity: LiveActivity
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            // Visual / Icono grande (44-52 pt) a la izquierda
            if let leading = activity.leading {
                leading
                    .frame(width: 48, height: 48)
            }
            
            // Título (bold ~20 pt) y Subtítulo (~15 pt, blanco 60%)
            VStack(alignment: .leading, spacing: 3) {
                if let center = activity.center {
                    center
                }
            }
            
            Spacer(minLength: 12)
            
            // Elemento trailing a la derecha
            if let trailing = activity.trailing {
                trailing
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 36) // Despeja completamente el notch físico de la MacBook
        .padding(.bottom, 16)
        .frame(width: 390, height: 112)
    }
}
