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
    
    // Volume HUD State
    @Published public var isVolumeHUDActive: Bool = false
    @Published public var currentVolume: Float = 0.5
    @Published public var isVolumeMuted: Bool = false
    private var volumeDismissTimer: Timer?
    
    // Hover Heartbeat ("Latido") State
    @Published public var heartbeatScaleX: CGFloat = 1.0
    @Published public var heartbeatScaleY: CGFloat = 1.0
    @Published public var heartbeatShadowOpacity: Double = 0.0
    private var lastHeartbeatTime: Date = Date.distantPast
    
    // Settings
    @Published public var expandOnHover: Bool = false
    @Published public var enableHaptics: Bool = true
    @Published public var showCompactWhenPlaying: Bool = true
    @Published public var autoCollapseOnHoverExit: Bool = true
    
    // Services
    public let screenService = ScreenService.shared
    public let musicService = MusicService.shared
    public let batteryService = BatteryService.shared
    public let hapticService = HapticService.shared
    public let audioService = AudioDeviceService.shared
    
    public var requestCollapse: (() -> Void)?
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
        
        // Volume change listener
        audioService.onVolumeChanged = { [weak self] volume, isMuted in
            self?.handleVolumeChanged(volume: volume, isMuted: isMuted)
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
    
    public func handleVolumeChanged(volume: Float, isMuted: Bool) {
        self.currentVolume = volume
        self.isVolumeMuted = isMuted
        self.isVolumeHUDActive = false
    }
    
    // Latido suave al pasar el cursor (respiro sutil, sin rebote brusco)
    public func triggerHeartbeat() {
        guard mode != .expanded else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastHeartbeatTime) > 0.8 else { return }
        lastHeartbeatTime = now
        
        // Pulso suave y fluido (dampingFraction alto para evitar rebote)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            heartbeatScaleX = 1.018
            heartbeatScaleY = 1.010
            heartbeatShadowOpacity = 0.20
        }
        
        // Regreso suave y progresivo al reposo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self = self, self.mode != .expanded else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                self.heartbeatScaleX = 1.0
                self.heartbeatScaleY = 1.0
                self.heartbeatShadowOpacity = 0.0
            }
        }
    }
    
    public func triggerAlert(_ type: AlertType, duration: TimeInterval = 4.0) {
        let alert = NotchAlert(type: type)
        self.activeAlert = alert
        self.activeTab = .alerts
        
        if mode != .expanded {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                self.mode = .expanded
            }
            hapticService.triggerExpand()
        }
        
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.collapse()
            self.activeAlert = nil
        }
    }
    
    public func handleMouseEnter() {
        self.isHovered = true
        if expandOnHover {
            if mode == .idle || mode == .compact {
                withAnimation(.spring(response: 0.68, dampingFraction: 0.76)) {
                    self.mode = .expanded
                }
                hapticService.triggerExpand()
            }
        } else {
            // Latido al pasar el cursor
            triggerHeartbeat()
        }
    }
    
    public func handleMouseLeave() {
        self.isHovered = false
        if expandOnHover {
            if mode == .expanded && activeAlert == nil {
                collapse()
            }
        }
    }
    
    public func collapse() {
        if let requestCollapse = requestCollapse {
            requestCollapse()
        } else {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeCloseResponse,
                dampingFraction: ExitAnimationMetrics.shapeCloseDamping
            )
            withAnimation(springAnim) {
                if musicService.hasActiveMusic && showCompactWhenPlaying {
                    mode = .compact
                } else {
                    mode = .idle
                }
                hapticService.triggerSnap()
            }
        }
    }
    
    public func expand() {
        guard mode != .expanded else { return }
        let springAnim = AnimationSpeedManager.shared.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        withAnimation(springAnim) {
            mode = .expanded
            hapticService.triggerExpand()
        }
    }
    
    public func toggleExpand() {
        if mode == .expanded {
            collapse()
        } else {
            expand()
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
