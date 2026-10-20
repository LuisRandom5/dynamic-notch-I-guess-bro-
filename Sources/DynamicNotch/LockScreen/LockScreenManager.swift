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
/// Implementa la máquina de estados reactiva descrita en docs/archivo/PLAN_GEMINI_3_8_LOCKSCREEN.md (Paso 1).
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
        .sink { [weak self] _, style in
            guard let self = self, self.isPanelVisible else { return }
            AppState.shared.isLockScreenFullscreen = style == .ambientCanvas
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
        
        if (isPlaying && hasContent) || AppState.shared.isLockScreenTestArmed {
            // Reproduciendo activamente o prueba de pantalla bloqueada armada
            pauseTimer?.invalidate()
            pauseTimer = nil
            AppState.shared.isLockScreenTestArmed = false
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
        
        let isOLED = AppState.shared.lockScreenRenderMode == .pureOLED || AppState.shared.effectiveAppearanceMode == .pureOLED
        // Ya no: con la ventana a pantalla completa, el desenfoque de fondo de ventana borraría toda la pantalla
        let applyPrivateBlur = false && !isOLED
        
        // Si ya teníamos paneles, actualizar frames
        if !lockScreenPanels.isEmpty && lockScreenPanels.count == targetScreens.count {
            for (idx, panel) in lockScreenPanels.enumerated() {
                // La ventana cubre la pantalla: LockScreenPlayerView coloca el reproductor en el hueco libre
                panel.setFrame(targetScreens[idx].frame, display: true)
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
        
        // Al aparecer, la presentación inicial es la que eligió el usuario en Ajustes
        AppState.shared.isLockScreenFullscreen = AppState.shared.lockScreenStyle == .ambientCanvas
        
        var newPanels: [LockScreenPanel] = []
        for screen in targetScreens {
            // Toda la pantalla: el paso a pantalla completa es una animación de SwiftUI, sin redimensionar
            // la ventana; las zonas transparentes dejan pasar los clics a la pantalla de inicio de sesión
            let panelRect = screen.frame
            
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
    
    private var previewTimer: Timer?
    @Published public private(set) var testCountdownSeconds: Int = 0
    private var testCountdownTimer: Timer?
    
    public func showPlayerPanelPreview(duration: TimeInterval = 10.0) {
        isPreviewMode = true
        showPlayerPanel()
        
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hidePlayerPanelPreview()
        }
    }
    
    public func hidePlayerPanelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        isPreviewMode = false
        hidePlayerPanel(smooth: true)
    }
    
    public func startCountdownAndArmLockScreenTest(seconds: Int = 5) {
        testCountdownSeconds = seconds
        testCountdownTimer?.invalidate()
        
        testCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.testCountdownSeconds -= 1
            if self.testCountdownSeconds <= 0 {
                timer.invalidate()
                self.testCountdownTimer = nil
                AppState.shared.isLockScreenTestArmed = true
            }
        }
    }
    
    public func cancelArmedTest() {
        testCountdownTimer?.invalidate()
        testCountdownTimer = nil
        testCountdownSeconds = 0
        AppState.shared.isLockScreenTestArmed = false
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
