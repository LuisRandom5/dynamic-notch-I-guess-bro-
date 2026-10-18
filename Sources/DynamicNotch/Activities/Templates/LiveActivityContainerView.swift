import SwiftUI

public struct LiveActivityContainerView: View {
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var notificationProvider = NotificationActivityProvider.shared
    @ObservedObject var agentProvider = AgentActivityProvider.shared
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
                    if activity.id.hasPrefix("notification_"),
                       let payload = notificationProvider.currentPayload,
                       payload.id == activity.id {
                        QuickReplyNotificationView(
                            id: payload.id,
                            title: payload.title,
                            message: payload.message,
                            handle: payload.handle,
                            avatar: payload.avatar,
                            appName: payload.appName,
                            appIcon: payload.appIcon,
                            tintColor: payload.tintColor
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        ))
                    } else if (activity.id == "agent_live_progress" || activity.id.hasPrefix("agent_progress")) {
                        if center.expandedActivity?.id == activity.id || agentProvider.isProgressHUDExpanded {
                            AgentLiveProgressView()
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                    removal: .opacity.animation(.easeOut(duration: 0.10))
                                ))
                        } else {
                            EmptyView()
                        }
                    } else if activity.id.hasPrefix("agent_"),
                              let payload = agentProvider.currentPayload,
                              payload.id == activity.id {
                        AgentInteractionView(payload: payload)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                removal: .opacity.animation(.easeOut(duration: 0.10))
                            ))
                    } else if let custom = activity.customView {
                        custom
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                removal: .opacity.animation(.easeOut(duration: 0.10))
                            ))
                    } else if activity.id == "live_timer" {
                        TimerCardView()
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.18)),
                                removal: .opacity.animation(.easeOut(duration: 0.10))
                            ))
                    } else {
                        ActivityCardView(activity: activity)
                            // Toda la tarjeta responde al toque (p. ej. "AirDrop recibido" abre el archivo)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activity.onTap?()
                            }
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
