import SwiftUI

public struct NotchContainerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenService: ScreenService
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var batteryService: BatteryService
    
    @State private var isContentRevealed: Bool = false
    
    private var geometry: NotchGeometry {
        screenService.currentGeometry
    }
    
    private var currentWidth: CGFloat {
        switch appState.mode {
        case .idle:
            return geometry.width
        case .compact:
            return geometry.width + 104
        case .expanded:
            return 510
        case .shelf:
            return 460
        }
    }
    
    private var currentHeight: CGFloat {
        switch appState.mode {
        case .idle:
            return geometry.height
        case .compact:
            return geometry.height
        case .expanded:
            return 245
        case .shelf:
            return 210
        }
    }
    
    private var cornerRadius: CGFloat {
        switch appState.mode {
        case .idle:
            return 17
        case .compact:
            return 17
        case .expanded, .shelf:
            return 32
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Main Island Body
            ZStack(alignment: .top) {
                // Background & Hairline Border (only hairline when expanded to eliminate weird borders)
                NotchShape(cornerRadius: cornerRadius)
                    .fill(Color.black)
                    .overlay(
                        NotchShape(cornerRadius: cornerRadius)
                            .stroke(
                                Color.white.opacity(appState.mode == .expanded || appState.mode == .shelf ? 0.12 : 0.0),
                                lineWidth: 0.8
                            )
                    )
                
                // Content depending on mode
                Group {
                    switch appState.mode {
                    case .idle:
                        Color.clear
                            .frame(width: currentWidth, height: currentHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.toggleExpand()
                            }
                        
                    case .compact:
                        NotchCompactView()
                            .frame(width: currentWidth, height: currentHeight)
                        
                    case .expanded:
                        expandedContentView
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .frame(width: currentWidth, height: currentHeight)
                        
                    case .shelf:
                        shelfContentView
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .frame(width: currentWidth, height: currentHeight)
                    }
                }
            }
            .clipShape(NotchShape(cornerRadius: cornerRadius))
            .shadow(
                color: Color.black.opacity(appState.mode == .expanded ? 0.5 : 0.0),
                radius: 16,
                x: 0,
                y: 8
            )
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .animation(.spring(response: 0.54, dampingFraction: 0.82), value: appState.mode)
            .animation(.spring(response: 0.46, dampingFraction: 0.82), value: appState.activeTab)
            .onChange(of: appState.mode) { newMode in
                if newMode == .expanded || newMode == .shelf {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isContentRevealed = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.08)) {
                        isContentRevealed = false
                    }
                }
            }
            .onAppear {
                if appState.mode == .expanded || appState.mode == .shelf {
                    isContentRevealed = true
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var expandedContentView: some View {
        VStack(spacing: 0) {
            // Top tab selector bar (spaced generously below physical notch)
            HStack(spacing: 12) {
                // Tabs
                HStack(spacing: 4) {
                    ForEach(NotchTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                appState.activeTab = tab
                            }
                            appState.hapticService.triggerSnap()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 10, weight: .bold))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(appState.activeTab == tab ? Color.white.opacity(0.18) : Color.white.opacity(0.04))
                            .foregroundColor(appState.activeTab == tab ? .white : .white.opacity(0.55))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // Collapse button
                Button(action: {
                    appState.toggleExpand()
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, geometry.height + 16)
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)
            
            // Tab Content (placed with comfortable vertical offset)
            Group {
                switch appState.activeTab {
                case .music:
                    NotchExpandedMusicView()
                case .alerts:
                    if let alert = appState.activeAlert {
                        NotchAlertView(alert: alert)
                    } else {
                        NotchAlertView(alert: NotchAlert(type: .magsafe(percent: batteryService.status.percentage)))
                    }
                case .shelf:
                    NotchShelfView()
                }
            }
            .padding(.top, 4)
            .transition(.opacity)
        }
    }
    
    private var shelfContentView: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Bandeja de Notch")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { appState.toggleExpand() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, geometry.height + 18)
            .padding(.bottom, 6)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)
            
            NotchShelfView()
                .padding(.top, 4)
        }
    }
}
