import AppKit
import SwiftUI
import Combine

/// Estados formales de la Máquina de Estados para la Pantalla de Bloqueo (Paso 1).
public enum LockScreenState: Equatable {
    case unlocked
    case lockedIdle
    case lockedPlaying
    case lockedPaused(remainingSeconds: Int)
    case transitioningOut
}

/// Gestor del Reproductor de Pantalla de Bloqueo de Dynamic Notch.
/// Implementa la máquina de estados reactiva descrita en PLAN_GEMINI_3_8_LOCKSCREEN.md (Paso 1).
public final class LockScreenManager: ObservableObject {
    public static let shared = LockScreenManager()
    
    @Published public private(set) var currentState: LockScreenState = .unlocked
    @Published public private(set) var isPanelVisible: Bool = false
    public var isPreviewMode: Bool = false
    
    // Paneles de la pantalla de bloqueo
    private var lockScreenPanels: [LockScreenPanel] = []
    private var cancellables = Set<AnyCancellable>()
    private var pauseTimer: Timer?
    private var transitionWorkItem: DispatchWorkItem?
    
    private init() {
        setupStatePipeline()
        observeScreenParameters()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Canalización de Estados Reactiva
    private func setupStatePipeline() {
        // Combinar estado de bloqueo de pantalla, reproducción y preferencia del usuario
        Publishers.CombineLatest3(
            LockScreenSkyLightBridge.shared.$isScreenLocked,
            MusicService.shared.$currentTrack,
            AppState.shared.$enableLockScreenPlayer
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] isLocked, track, isEnabled in
            self?.evaluateState(isLocked: isLocked, track: track, isEnabled: isEnabled)
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest3(
            AppState.shared.$lockScreenShowVolumeSlider,
            AppState.shared.$lockScreenVerticalOffset,
            AppState.shared.$lockScreenHideMediaDetails
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self = self, self.isPanelVisible else { return }
            self.showPlayerPanel()
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest(
            AppState.shared.$lockScreenRenderMode,
            AppState.shared.$lockScreenStyle
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            guard let self = self, self.isPanelVisible else { return }
            self.showPlayerPanel()
        }
        .store(in: &cancellables)
    }
    
    private func evaluateState(isLocked: Bool, track: MusicTrack, isEnabled: Bool) {
        if isPreviewMode {
            // En modo de previsualización en el escritorio no evaluar bloqueo de pantalla
            return
        }
        
        guard isEnabled && LockScreenSkyLightBridge.shared.isSupported else {
            if currentState != .unlocked {
                transitionToUnlocked(immediate: true)
            }
            return
        }
        
        // 1. Pantalla Desbloqueada
        if !isLocked {
            if currentState != .unlocked {
                transitionToUnlocked(immediate: true)
            }
            return
        }
        
        // 2. Pantalla Bloqueada
        let hasContent = !track.title.isEmpty
        let isPlaying = track.isPlaying
        
        if isPlaying && hasContent {
            // Reproduciendo activamente
            pauseTimer?.invalidate()
            pauseTimer = nil
            transitionToPlaying()
        } else if hasContent {
            // En pausa con contenido activo
            switch currentState {
            case .lockedPlaying, .lockedPaused:
                if case .lockedPaused = currentState {
                    // Ya está en cuenta atrás
                } else {
                    startPausedCountdown()
                }
            default:
                // Si ya estaba en idle o desbloqueado, no forzar apertura en pausa
                break
            }
        } else {
            // Sin contenido
            transitionToIdle()
        }
    }
    
    // MARK: - Transiciones de Estado
    
    private func transitionToPlaying() {
        currentState = .lockedPlaying
        showPlayerPanel()
    }
    
    private func startPausedCountdown() {
        let initialSeconds = max(5, AppState.shared.lockScreenPauseTimeoutSeconds)
        currentState = .lockedPaused(remainingSeconds: initialSeconds)
        
        pauseTimer?.invalidate()
        var remaining = initialSeconds
        
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            remaining -= 1
            if remaining > 0 {
                self.currentState = .lockedPaused(remainingSeconds: remaining)
            } else {
                timer.invalidate()
                self.pauseTimer = nil
                self.transitionToIdle()
            }
        }
    }
    
    private func transitionToIdle() {
        currentState = .lockedIdle
        hidePlayerPanel(smooth: true)
    }
    
    public func handleScreenLocked() {
        isPreviewMode = false
    }
    
    public func handleScreenUnlocked() {
        isPreviewMode = false
        transitionToUnlocked(immediate: true)
    }
    
    private func transitionToUnlocked(immediate: Bool) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        
        currentState = .transitioningOut
        hidePlayerPanel(smooth: !immediate)
        currentState = .unlocked
    }
    
    // MARK: - Manejo de Ventana y Space SkyLight
    
    private func showPlayerPanel() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showPlayerPanel()
            }
            return
        }
        
        let targetScreens: [NSScreen]
        if AppState.shared.lockScreenShowOnAllDisplays {
            targetScreens = NSScreen.screens
        } else {
            let mainScrn = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
            targetScreens = [mainScrn]
        }
        
        let isHero = AppState.shared.lockScreenStyle == .heroWidget
        let hasVolume = AppState.shared.lockScreenShowVolumeSlider
        
        let panelWidth: CGFloat = isHero
            ? LockScreenPlayerMetrics.heroPanelWidth
            : LockScreenPlayerMetrics.cardWidth
            
        let panelHeight: CGFloat
        let topRatio: CGFloat
        let heroCardHeight: CGFloat = hasVolume
            ? LockScreenPlayerMetrics.heroCardHeightWithVolume
            : LockScreenPlayerMetrics.heroCardHeight
        
        if isHero {
            panelHeight = hasVolume
                ? LockScreenPlayerMetrics.heroPanelHeightWithVolume
                : LockScreenPlayerMetrics.heroPanelHeight
            topRatio = 0.54
        } else {
            panelHeight = hasVolume
                ? LockScreenPlayerMetrics.cardHeightWithVolume
                : (AppState.shared.lockScreenHideMediaDetails ? 128 : LockScreenPlayerMetrics.cardHeightCompact)
            topRatio = LockScreenPlayerMetrics.defaultTopPositionRatio
        }
        
        let applyPrivateBlur = AppState.shared.lockScreenRenderMode == .privateBlur
        
        // Si ya teníamos paneles, actualizar frames
        if !lockScreenPanels.isEmpty && lockScreenPanels.count == targetScreens.count {
            for (idx, panel) in lockScreenPanels.enumerated() {
                let screenFrame = targetScreens[idx].frame
                let posX = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
                let targetCardTopY = screenFrame.maxY - (screenFrame.height * topRatio) + AppState.shared.lockScreenVerticalOffset
                let posY = targetCardTopY - (isHero ? heroCardHeight : panelHeight)
                panel.setFrame(NSRect(x: posX, y: posY, width: panelWidth, height: panelHeight), display: true)
                panel.alphaValue = 1.0
                panel.orderFrontRegardless()
                
                if applyPrivateBlur {
                    LockScreenSkyLightBridge.shared.setWindowBackgroundBlur(windowNumber: panel.windowNumber, radius: 32)
                } else {
                    LockScreenSkyLightBridge.shared.setWindowBackgroundBlur(windowNumber: panel.windowNumber, radius: 0)
                }
            }
            isPanelVisible = true
            return
        }
        
        // Limpiar cualquier panel previo
        cleanupPanelsOnly()
        
        var newPanels: [LockScreenPanel] = []
        for screen in targetScreens {
            let screenFrame = screen.frame
            let posX = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
            let targetCardTopY = screenFrame.maxY - (screenFrame.height * topRatio) + AppState.shared.lockScreenVerticalOffset
            let posY = targetCardTopY - (isHero ? heroCardHeight : panelHeight)
            let panelRect = NSRect(x: posX, y: posY, width: panelWidth, height: panelHeight)
            
            let panel = LockScreenPanel(contentRect: panelRect)
            let rootView = LockScreenPlayerView()
                .environmentObject(MusicService.shared)
                .environmentObject(AppState.shared)
                .environmentObject(AudioDeviceService.shared)
            
            let hostingView = LockScreenHostingView(rootView: rootView)
            hostingView.sizingOptions = []
            hostingView.frame = NSRect(origin: .zero, size: panelRect.size)
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView
            
            if applyPrivateBlur {
                LockScreenSkyLightBridge.shared.setWindowBackgroundBlur(windowNumber: panel.windowNumber, radius: 32)
            }
            
            newPanels.append(panel)
        }
        
        self.lockScreenPanels = newPanels
        self.isPanelVisible = true
        
        if !isPreviewMode, let spaceID = LockScreenSkyLightBridge.shared.createLockScreenSpace(level: 400) {
            for panel in newPanels {
                panel.alphaValue = 0.0
                panel.orderFrontRegardless()
                LockScreenSkyLightBridge.shared.addWindowToSpace(windowNumber: panel.windowNumber, spaceID: spaceID)
            }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for panel in newPanels {
                    panel.animator().alphaValue = 1.0
                }
            }
        } else {
            for panel in newPanels {
                panel.orderFrontRegardless()
                panel.alphaValue = 1.0
            }
        }
        
        print("🎵 [LockScreenManager] Reproductor de pantalla de bloqueo desplegado en \(newPanels.count) pantalla(s) (preview: \(isPreviewMode)).")
    }
    
    public func showPlayerPanelPreview() {
        isPreviewMode = true
        showPlayerPanel()
    }
    
    public func hidePlayerPanelPreview() {
        isPreviewMode = false
        hidePlayerPanel(smooth: true)
    }
    
    private func hidePlayerPanel(smooth: Bool) {
        guard !lockScreenPanels.isEmpty else {
            LockScreenSkyLightBridge.shared.cleanupActiveSpace()
            isPanelVisible = false
            return
        }
        
        let panelsToClose = lockScreenPanels
        if smooth {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                for panel in panelsToClose {
                    panel.animator().alphaValue = 0.0
                }
            }, completionHandler: { [weak self] in
                for panel in panelsToClose {
                    panel.orderOut(nil)
                }
                self?.lockScreenPanels.removeAll()
                self?.isPanelVisible = false
                LockScreenSkyLightBridge.shared.cleanupActiveSpace()
            })
        } else {
            for panel in panelsToClose {
                panel.orderOut(nil)
            }
            self.lockScreenPanels.removeAll()
            self.isPanelVisible = false
            LockScreenSkyLightBridge.shared.cleanupActiveSpace()
        }
    }
    
    private func cleanupPanelsOnly() {
        for panel in lockScreenPanels {
            panel.orderOut(nil)
        }
        lockScreenPanels.removeAll()
    }
    
    private func observeScreenParameters() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if self?.isPanelVisible == true {
                self?.showPlayerPanel()
            }
        }
    }
    
    public func cleanup() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        cleanupPanelsOnly()
        LockScreenSkyLightBridge.shared.cleanupActiveSpace()
        isPanelVisible = false
    }
}
