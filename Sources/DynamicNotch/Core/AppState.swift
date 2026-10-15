import AppKit
import SwiftUI
import Combine

public enum NotchAppearanceMode: String, CaseIterable, Identifiable {
    case pureOLED = "oled"
    case darkGlass = "darkGlass"
    case clearGlass = "clearGlass"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pureOLED: return "Negro Puro OLED"
        case .darkGlass: return "Cristal Oscuro"
        case .clearGlass: return "Cristal Claro"
        }
    }
}

public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Notch State
    @Published public var mode: NotchMode = .idle
    @Published public var activeTab: NotchTab = .music
    @Published public var activeAlert: NotchAlert?
    @Published public var isHovered: Bool = false
    @Published public var shelfItems: [ShelfItem] = []
    @Published public var isShelfDragTargeted: Bool = false
    @Published public var isDropInvitationActive: Bool = false
    @Published public var isDropSuccessAnimating: Bool = false
    @Published public var trackpadDragOffset: CGFloat = 0
    @Published public var trackpadDragOffsetY: CGFloat = 0
    @Published public var isHoldingBareNotch: Bool = false
    
    // Elastic Overscroll State (Forma vs Contenido)
    @Published public var overscrollOffset: CGFloat = 0           // Estiramiento asimétrico de la cápsula negra (pt)
    @Published public var contentOverscrollOffset: CGFloat = 0    // Desplazamiento orgánico con desfase del contenido (pt)
    @Published public var verticalOverscrollOffset: CGFloat = 0   // Estiramiento elástico hacia abajo (anclado arriba al notch)
    @Published public var contentVerticalOverscrollOffset: CGFloat = 0 // Desplazamiento vertical orgánico del contenido
    @Published public var isOverscrolling: Bool = false
    
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
    @Published public var enableSoundFeedback: Bool = true
    @Published public var showCompactWhenPlaying: Bool = true
    @Published public var autoCollapseOnHoverExit: Bool = true
    @Published public var isPlayerDetailExpanded: Bool = false
    
    // MARK: - Modos de Apariencia & Liquid Glass Nativo (macOS 26+)
    @Published public var appearanceMode: NotchAppearanceMode = {
        let suite = UserDefaults(suiteName: "com.luisrandom.DynamicNotch")
        if let saved = suite?.string(forKey: "notchAppearanceMode") ?? UserDefaults.standard.string(forKey: "notchAppearanceMode"),
           let mode = NotchAppearanceMode(rawValue: saved) {
            return mode
        }
        return .clearGlass // Por defecto: Cristal Claro ("Glass.clear")
    }() {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "notchAppearanceMode")
            UserDefaults(suiteName: "com.luisrandom.DynamicNotch")?.set(appearanceMode.rawValue, forKey: "notchAppearanceMode")
            isLiquidGlassEnabled = (appearanceMode != .pureOLED)
        }
    }
    
    /// Modo efectivo considerando preferencias de accesibilidad del sistema
    public var effectiveAppearanceMode: NotchAppearanceMode {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ||
           NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return .pureOLED
        }
        return appearanceMode
    }
    
    @Published public var isLiquidGlassEnabled: Bool = UserDefaults.standard.object(forKey: "isLiquidGlassEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "isLiquidGlassEnabled")
        : true {
        didSet { UserDefaults.standard.set(isLiquidGlassEnabled, forKey: "isLiquidGlassEnabled") }
    }
    
    // Opacidad de tinte: rango 30%-90%, DEFAULT 55% (0.55)
    @Published public var glassDarknessOpacity: Double = UserDefaults.standard.object(forKey: "glassDarknessOpacity") != nil
        ? UserDefaults.standard.double(forKey: "glassDarknessOpacity")
        : 0.55 {
        didSet { UserDefaults.standard.set(glassDarknessOpacity, forKey: "glassDarknessOpacity") }
    }
    @Published public var enableTrackpadSwipe: Bool = UserDefaults.standard.object(forKey: "enableTrackpadSwipe") != nil ? UserDefaults.standard.bool(forKey: "enableTrackpadSwipe") : true {
        didSet { UserDefaults.standard.set(enableTrackpadSwipe, forKey: "enableTrackpadSwipe") }
    }
    @Published public var enableAirPodsAnimation: Bool = UserDefaults.standard.object(forKey: "enableAirPodsAnimation") != nil ? UserDefaults.standard.bool(forKey: "enableAirPodsAnimation") : true {
        didSet { UserDefaults.standard.set(enableAirPodsAnimation, forKey: "enableAirPodsAnimation") }
    }
    // Drag & Drop / Shelf Settings
    @Published public var moveFilesToShelf: Bool = UserDefaults.standard.object(forKey: "moveFilesToShelf") != nil
        ? UserDefaults.standard.bool(forKey: "moveFilesToShelf")
        : true {
        didSet { UserDefaults.standard.set(moveFilesToShelf, forKey: "moveFilesToShelf") }
    }
    @Published public var isDropErrorAnimating: Bool = false
    @Published public var dropErrorMessage: String = ""
    @Published public var lastDroppedCount: Int = 0
    @Published public var enableDropInvitation: Bool = UserDefaults.standard.object(forKey: "enableDropInvitation") != nil
        ? UserDefaults.standard.bool(forKey: "enableDropInvitation")
        : true {
        didSet { UserDefaults.standard.set(enableDropInvitation, forKey: "enableDropInvitation") }
    }
    @Published public var dropInvitationDistance: Double = UserDefaults.standard.object(forKey: "dropInvitationDistance") != nil
        ? UserDefaults.standard.double(forKey: "dropInvitationDistance")
        : 175.0 {
        didSet { UserDefaults.standard.set(dropInvitationDistance, forKey: "dropInvitationDistance") }
    }
    @Published public var autoOpenShelfOnDrop: Bool = UserDefaults.standard.object(forKey: "autoOpenShelfOnDrop") != nil
        ? UserDefaults.standard.bool(forKey: "autoOpenShelfOnDrop")
        : true {
        didSet { UserDefaults.standard.set(autoOpenShelfOnDrop, forKey: "autoOpenShelfOnDrop") }
    }
    @Published public var enableShelfHaptics: Bool = UserDefaults.standard.object(forKey: "enableShelfHaptics") != nil
        ? UserDefaults.standard.bool(forKey: "enableShelfHaptics")
        : true {
        didSet { UserDefaults.standard.set(enableShelfHaptics, forKey: "enableShelfHaptics") }
    }
    @Published public var showShelfBadgeInNotch: Bool = UserDefaults.standard.object(forKey: "showShelfBadgeInNotch") != nil
        ? UserDefaults.standard.bool(forKey: "showShelfBadgeInNotch")
        : true {
        didSet { UserDefaults.standard.set(showShelfBadgeInNotch, forKey: "showShelfBadgeInNotch") }
    }
    
    /// Archivo de la repisa actualmente en proceso de ser arrastrado hacia afuera (Drag-Out)
    @Published public var activeDragOutItem: ShelfItem? = nil
    
    // Services
    public let screenService = ScreenService.shared
    public let musicService = MusicService.shared
    public let batteryService = BatteryService.shared
    public let hapticService = HapticService.shared
    public let audioService = AudioDeviceService.shared
    
    public var requestCollapse: (() -> Void)?
    private var musicPauseDismissTimer: Timer?
    private var alertDismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSubscriptions()
        self.shelfItems = ShelfStorageService.shared.loadExistingStashedItems()
    }
    
    private func setupSubscriptions() {
        // Battery MagSafe connection listener -> Publicar actividad de carga dedicada (sin forzar reproductor de música)
        batteryService.onPowerConnected = { percentage in
            ChargingActivityProvider.shared.publishChargingActivity(
                percentage: percentage,
                isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isPluggedIn: true
            )
        }
        
        // Alerta de Batería Baja automática estilo Apple Card / Dynamic Island
        batteryService.onLowBattery = { percentage in
            ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: percentage)
        }
        
        // Volume change listener
        audioService.onVolumeChanged = { [weak self] volume, isMuted in
            self?.handleVolumeChanged(volume: volume, isMuted: isMuted)
        }
        
        // Music changes con retención de 30 segundos al pausar
        musicService.$hasActiveMusic
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                print("[AppState] hasActiveMusic: \(isPlaying), current mode: \(self.mode)")
                if isPlaying {
                    // Cancela cualquier timer de colapso pendiente
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = nil
                    if self.mode == .idle && self.showCompactWhenPlaying {
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                            self.mode = .compact
                        }
                    }
                } else {
                    // Al pausar: retener el minirreproductor durante 30 segundos antes de colapsar
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self = self, !self.musicService.hasActiveMusic else { return }
                            if self.mode == .compact {
                                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                                    self.mode = .idle
                                }
                            } else if self.mode == .expanded {
                                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                                    self.mode = .idle
                                }
                            }
                            self.musicPauseDismissTimer = nil
                        }
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
    
    // Latido reactivo e inmersivo ("Notch Vivo" - respiración orgánica con física elástica)
    public func triggerHeartbeat() {
        guard mode != .expanded && mode != .shelf else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastHeartbeatTime) > 0.40 else { return }
        lastHeartbeatTime = now
        
        // Pulso reactivo orgánico (expansión elástica con presencia táctil viva)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            heartbeatScaleX = 1.035
            heartbeatScaleY = 1.022
            heartbeatShadowOpacity = 0.40
        }
        
        // Retorno suave y fluido al reposo con inercia elástica
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self = self, self.mode != .expanded && self.mode != .shelf else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
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
        guard !isHovered else { return }
        self.isHovered = true
        if expandOnHover {
            if mode == .idle || mode == .compact {
                withAnimation(.spring(response: 0.68, dampingFraction: 0.76)) {
                    if !self.shelfItems.isEmpty {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    } else {
                        self.mode = .expanded
                    }
                }
                hapticService.triggerExpand()
            }
        } else {
            // Latido al pasar el cursor (solo una vez por entrada)
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
        overscrollOffset = 0
        contentOverscrollOffset = 0
        verticalOverscrollOffset = 0
        contentVerticalOverscrollOffset = 0
        
        if let requestCollapse = requestCollapse {
            requestCollapse()
        } else {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeCloseResponse,
                dampingFraction: ExitAnimationMetrics.shapeCloseDamping
            )
            withAnimation(springAnim) {
                if (musicService.hasActiveMusic || musicPauseDismissTimer != nil) && showCompactWhenPlaying {
                    mode = .compact
                } else if !shelfItems.isEmpty {
                    mode = .compact
                } else {
                    mode = .idle
                }
                hapticService.triggerSnap()
            }
        }
    }
    
    public func expand() {
        guard mode != .expanded && mode != .shelf else { return }
        overscrollOffset = 0
        contentOverscrollOffset = 0
        verticalOverscrollOffset = 0
        contentVerticalOverscrollOffset = 0
        isPlayerDetailExpanded = false
        
        let springAnim = AnimationSpeedManager.shared.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        withAnimation(springAnim) {
            mode = (activeTab == .shelf) ? .shelf : .expanded
            hapticService.triggerExpand()
        }
    }
    
    public func toggleExpand() {
        if mode == .expanded || mode == .shelf {
            collapse()
        } else {
            expand()
        }
    }
    
    public func addShelfFile(url: URL) {
        guard !shelfItems.contains(where: { $0.url.path == url.path || $0.originalURL?.path == url.path }) else {
            mode = .shelf
            activeTab = .shelf
            return
        }
        let item = ShelfStorageService.shared.stashFile(from: url, shouldMove: moveFilesToShelf)
        shelfItems.append(item)
        mode = .shelf
        activeTab = .shelf
        hapticService.triggerDrop()
    }
    
    public var onDropSuccess: (() -> Void)?
    public var onDropError: ((String) -> Void)?
    
    public func triggerDropError(message: String) {
        isDropErrorAnimating = true
        dropErrorMessage = message
        hapticService.triggerSnap()
        onDropError?(message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
                self.isDropErrorAnimating = false
            }
        }
    }
    
    public func triggerDropSuccess(urls: [URL]) {
        DNDLogger.log("AppState.triggerDropSuccess called with \(urls.count) urls")
        isDropSuccessAnimating = true
        isDropErrorAnimating = false
        var addedAny = false
        var newBatch: [ShelfItem] = []
        
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("File already exists in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("Stashed item: \(item.name), destination: \(item.url.path), isStashed: \(item.isStashed)")
        }
        
        self.lastDroppedCount = newBatch.isEmpty ? urls.count : newBatch.count
        
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        
        if addedAny && enableShelfHaptics {
            hapticService.triggerDrop()
        }
        onDropSuccess?()
        
        // Retención de confirmación de 0.65 s para disfrutar la animación de éxito antes de retraerse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self = self else { return }
            let needsHold = self.mode == .compact && self.musicService.hasActiveMusic
            if needsHold {
                self.isHoldingBareNotch = true
            }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isDropSuccessAnimating = false
                if addedAny || self.autoOpenShelfOnDrop || !self.shelfItems.isEmpty {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    }
                    if self.enableShelfHaptics {
                        self.hapticService.triggerSnap()
                    }
                } else if needsHold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard !self.isDropInvitationActive && ActivityCenter.shared.currentActivity == nil else {
                            self.isHoldingBareNotch = false
                            return
                        }
                        withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                            self.isHoldingBareNotch = false
                        }
                    }
                }
            }
        }
    }
    
    public func addShelfFiles(urls: [URL]) {
        DNDLogger.log("AppState.addShelfFiles called with \(urls.count) urls")
        var addedAny = false
        var newBatch: [ShelfItem] = []
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("addShelfFiles: file already in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("addShelfFiles stashed: \(item.name) at \(item.url.path)")
        }
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        if addedAny {
            if enableShelfHaptics {
                hapticService.triggerDrop()
            }
            if mode != .shelf {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                    mode = .shelf
                    activeTab = .shelf
                }
            }
        } else if !shelfItems.isEmpty && mode != .shelf {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                mode = .shelf
                activeTab = .shelf
            }
        }
    }
    
    public func removeShelfItem(_ item: ShelfItem, moveToTrash: Bool = true) {
        if moveToTrash && item.isStashed {
            ShelfStorageService.shared.moveToTrash(item: item)
        }
        shelfItems.removeAll(where: { $0.id == item.id || $0.url.path == item.url.path })
    }
    
    public func restoreShelfItemToOrigin(_ item: ShelfItem) {
        if ShelfStorageService.shared.restoreToOrigin(item: item) {
            shelfItems.removeAll(where: { $0.id == item.id })
            hapticService.triggerSnap()
        }
    }
    
    public func restoreAllShelfItemsToOrigin() {
        var toRemove: [UUID] = []
        for item in shelfItems {
            if ShelfStorageService.shared.restoreToOrigin(item: item) {
                toRemove.append(item.id)
            }
        }
        shelfItems.removeAll(where: { toRemove.contains($0.id) })
        hapticService.triggerSnap()
    }
    
    public func emptyShelfToTrash() {
        for item in shelfItems {
            if item.isStashed {
                ShelfStorageService.shared.moveToTrash(item: item)
            }
        }
        shelfItems.removeAll()
        hapticService.triggerSnap()
    }
    
    public func undoLastDrop() {
        let restored = ShelfStorageService.shared.undoLastBatch(from: &shelfItems)
        if !restored.isEmpty {
            hapticService.triggerSnap()
        }
    }
}
