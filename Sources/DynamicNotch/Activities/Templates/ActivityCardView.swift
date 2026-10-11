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
        .frame(minWidth: 380, maxWidth: 410, minHeight: 112, maxHeight: 112)
        .background(DesignTokens.background)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .shadow(color: Color.black.opacity(0.40), radius: 20, x: 0, y: 8)
    }
}
