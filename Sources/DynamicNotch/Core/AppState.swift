import AppKit
import SwiftUI
import Combine

public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Notch State
    @Published public var mode: NotchMode = .idle
    @Published public var activeTab: NotchTab = .music
    @Published public var activeAlert: NotchAlert?
    @Published public var isHovered: Bool = false
    @Published public var shelfItems: [ShelfItem] = []
    
    // Settings
    @Published public var expandOnHover: Bool = true
    @Published public var enableHaptics: Bool = true
    @Published public var showCompactWhenPlaying: Bool = true
    
    // Services
    public let screenService = ScreenService.shared
    public let musicService = MusicService.shared
    public let batteryService = BatteryService.shared
    public let hapticService = HapticService.shared
    
    private var alertDismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Battery MagSafe connection listener
        batteryService.onPowerConnected = { [weak self] percentage in
            self?.triggerAlert(.magsafe(percent: percentage), duration: 4.0)
        }
        
        // Music changes
        musicService.$hasActiveMusic
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                if self.mode == .idle && isPlaying && self.showCompactWhenPlaying {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                        self.mode = .compact
                    }
                } else if self.mode == .compact && !isPlaying {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                        self.mode = .idle
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func triggerAlert(_ type: AlertType, duration: TimeInterval = 4.0) {
        let alert = NotchAlert(type: type)
        self.activeAlert = alert
        self.activeTab = .alerts
        
        if mode != .expanded {
            withAnimation(.spring(response: 0.56, dampingFraction: 0.82)) {
                self.mode = .expanded
            }
            hapticService.triggerExpand()
        }
        
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                if self.musicService.hasActiveMusic && self.showCompactWhenPlaying {
                    self.mode = .compact
                } else {
                    self.mode = .idle
                }
                self.activeAlert = nil
            }
            self.hapticService.triggerSnap()
        }
    }
    
    public func handleMouseEnter() {
        guard expandOnHover else { return }
        if mode == .idle || mode == .compact {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                self.mode = .expanded
            }
            hapticService.triggerExpand()
        }
    }
    
    public func handleMouseLeave() {
        guard expandOnHover else { return }
        if mode == .expanded && activeAlert == nil {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                if musicService.hasActiveMusic && showCompactWhenPlaying {
                    self.mode = .compact
                } else {
                    self.mode = .idle
                }
            }
            hapticService.triggerSnap()
        }
    }
    
    public func toggleExpand() {
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
            if mode == .expanded {
                if musicService.hasActiveMusic && showCompactWhenPlaying {
                    mode = .compact
                } else {
                    mode = .idle
                }
                hapticService.triggerSnap()
            } else {
                mode = .expanded
                hapticService.triggerExpand()
            }
        }
    }
    
    public func addShelfFile(url: URL) {
        let name = url.lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let item = ShelfItem(url: url, name: name, icon: icon)
        shelfItems.append(item)
        activeTab = .shelf
        hapticService.triggerDrop()
    }
    
    public func removeShelfItem(_ item: ShelfItem) {
        shelfItems.removeAll(where: { $0.id == item.id })
    }
}
