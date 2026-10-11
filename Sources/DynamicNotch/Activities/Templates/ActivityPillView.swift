import SwiftUI

public struct ActivityPillView: View {
    public let activity: LiveActivity
    
    public init(activity: LiveActivity) {
        self.activity = activity
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            if let leading = activity.leading {
                leading
            }
            
            if let center = activity.center {
                center
            }
            
            Spacer(minLength: 12)
            
            if let trailing = activity.trailing {
                trailing
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .frame(minWidth: 220)
        .background(DesignTokens.background)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
    }
}
