import SwiftUI

public struct LiveActivityContainerView: View {
    @ObservedObject var center = ActivityCenter.shared
    @EnvironmentObject var appState: AppState
    
    @State private var contentVisible: Bool = false
    
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
            .scaleEffect(contentVisible ? 1.0 : 0.85)
            .opacity(contentVisible ? 1.0 : 0.0)
            .contentShape(Rectangle())
            .onTapGesture {
                center.handleTap()
            }
            .onAppear {
                contentVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + DesignTokens.activityContentDelay) {
                    withAnimation(DesignTokens.activityEntrySpring) {
                        contentVisible = true
                    }
                }
            }
            .onDisappear {
                contentVisible = false
            }
            .id(activity.id)
        }
    }
}
