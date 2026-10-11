import SwiftUI

public struct LiveActivityContainerView: View {
    @ObservedObject var center = ActivityCenter.shared
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        if let activity = center.currentActivity {
            Group {
                switch activity.style {
                case .pill:
                    ActivityPillView(activity: activity)
                case .sliderPill:
                    ActivitySliderPillView(activity: activity)
                case .card:
                    ActivityCardView(activity: activity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                center.handleTap()
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity
            ))
            .id(activity.id)
        }
    }
}
