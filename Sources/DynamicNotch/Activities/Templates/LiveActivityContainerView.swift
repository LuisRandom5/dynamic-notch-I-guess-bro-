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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if center.dismissingActivityId == nil {
                                center.handleTap()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.16)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        ))
                case .sliderPill:
                    ActivitySliderPillView(activity: activity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if center.dismissingActivityId == nil {
                                center.handleTap()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.16)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        ))
                case .airpodsPill:
                    ActivityAirPodsPillView(activity: activity)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        ))
                case .card:
                    if activity.id == "live_timer" {
                        TimerCardView()
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                removal: .opacity.animation(.easeOut(duration: 0.10))
                            ))
                    } else {
                        ActivityCardView(activity: activity)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                removal: .opacity.animation(.easeOut(duration: 0.10))
                            ))
                    }
                }
            }
            .id("\(activity.id)_\(activity.style.rawValue)")
        }
    }
}
