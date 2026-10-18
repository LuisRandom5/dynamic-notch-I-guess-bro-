import AppKit
import SwiftUI

public final class StatusItemManager: NSObject {
    public static let shared = StatusItemManager()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    public func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Notch")
            button.imagePosition = .imageOnly
        }
        
        buildMenu()
    }
    
    public func buildMenu() {
        let menu = NSMenu()
        
        // Header
        let titleItem = NSMenuItem(title: "Dynamic Notch (macOS Nativo)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle expansion
        let toggleTitle = AppState.shared.mode == .expanded ? "Contraer Notch" : "Expandir Notch"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleNotch), keyEquivalent: "d")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // Hover toggle
        let hoverItem = NSMenuItem(
            title: "Expandir al pasar cursor (Hover)",
            action: #selector(toggleHover),
            keyEquivalent: ""
        )
        hoverItem.target = self
        hoverItem.state = AppState.shared.expandOnHover ? .on : .off
        menu.addItem(hoverItem)
        
        // Haptic toggle
        let hapticItem = NSMenuItem(
            title: "Vibración háptica (Trackpad)",
            action: #selector(toggleHaptics),
            keyEquivalent: ""
        )
        hapticItem.target = self
        hapticItem.state = AppState.shared.enableHaptics ? .on : .off
        menu.addItem(hapticItem)
        
        // Sound feedback toggle
        let soundItem = NSMenuItem(
            title: "Sonido inmersivo al regular volumen",
            action: #selector(toggleSoundFeedback),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = AppState.shared.enableSoundFeedback ? .on : .off
        menu.addItem(soundItem)
        
        // Volume suppression toggle
        let hasPermission = VolumeInterceptorService.shared.hasAccessibilityPermission
        
        let hudSuppressItem = NSMenuItem(
            title: "Ocultar HUD nativo de macOS (Volumen y Brillo)",
            action: #selector(toggleSuppressNativeHUD),
            keyEquivalent: ""
        )
        hudSuppressItem.target = self
        hudSuppressItem.state = VolumeInterceptorService.shared.suppressNativeHUD ? .on : .off
        menu.addItem(hudSuppressItem)
        
        let accessItem = NSMenuItem(
            title: hasPermission ? "✓ Permiso de Accesibilidad Concedido" : "⚠️ Configurar Permisos de Accesibilidad...",
            action: #selector(openAccessibilityOnboarding),
            keyEquivalent: ""
        )
        accessItem.target = self
        menu.addItem(accessItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Test demos submenu
        let testMenu = NSMenu()
        
        let brightnessTest = NSMenuItem(title: "Slider Brillo (75%)", action: #selector(testBrightnessSlider), keyEquivalent: "")
        brightnessTest.target = self
        testMenu.addItem(brightnessTest)
        
        let volumeTest = NSMenuItem(title: "Slider Volumen (60%)", action: #selector(testVolumeSlider), keyEquivalent: "")
        volumeTest.target = self
        testMenu.addItem(volumeTest)
        
        let muteTest = NSMenuItem(title: "Slider Volumen Silenciado (Mute)", action: #selector(testMuteSlider), keyEquivalent: "")
        muteTest.target = self
        testMenu.addItem(muteTest)
        
        testMenu.addItem(NSMenuItem.separator())
        
        let magSafeTest = NSMenuItem(title: "Animación MagSafe (88%)", action: #selector(testMagSafe), keyEquivalent: "")
        magSafeTest.target = self
        testMenu.addItem(magSafeTest)
        
        let airPods4Test = NSMenuItem(title: "Animación AirPods 4 (88% / 90% / 100%)", action: #selector(testAirPods4), keyEquivalent: "")
        airPods4Test.target = self
        testMenu.addItem(airPods4Test)
        
        let airPodsTest = NSMenuItem(title: "Animación AirPods Pro (95% / 90% / 100%)", action: #selector(testAirPods), keyEquivalent: "")
        airPodsTest.target = self
        testMenu.addItem(airPodsTest)
        
        let lockScreenTest = NSMenuItem(title: "Previsualizar Reproductor Lock Screen (10s)", action: #selector(testLockScreenPreview), keyEquivalent: "")
        lockScreenTest.target = self
        testMenu.addItem(lockScreenTest)
        
        let batteryLowTest = NSMenuItem(title: "Alerta Batería Baja (12%)", action: #selector(testBatteryLow), keyEquivalent: "")
        batteryLowTest.target = self
        testMenu.addItem(batteryLowTest)
        
        let musicDemoTest = NSMenuItem(title: "Canción Demo (Starboy)", action: #selector(testMusicDemo), keyEquivalent: "")
        musicDemoTest.target = self
        testMenu.addItem(musicDemoTest)
        
        let airDropTest = NSMenuItem(title: "Simular AirDrop (Progreso → Éxito)", action: #selector(testAirDropTransfer), keyEquivalent: "")
        airDropTest.target = self
        testMenu.addItem(airDropTest)
        
        let shelfTest = NSMenuItem(title: "Abrir Bandeja de Archivos", action: #selector(testShelf), keyEquivalent: "")
        shelfTest.target = self
        testMenu.addItem(shelfTest)
        
        testMenu.addItem(NSMenuItem.separator())
        
        let timerCompactTest = NSMenuItem(title: "Temporizador Compacto (Minutka - 30s)", action: #selector(testTimerActivity), keyEquivalent: "")
        timerCompactTest.target = self
        testMenu.addItem(timerCompactTest)
        
        let timerCardTest = NSMenuItem(title: "Temporizador Expandido (Minutka Card - 30s)", action: #selector(testTimerCardActivity), keyEquivalent: "")
        timerCardTest.target = self
        testMenu.addItem(timerCardTest)
        
        let notifTest = NSMenuItem(title: "Notificación Dinámica (WhatsApp)", action: #selector(testNotificationActivity), keyEquivalent: "")
        notifTest.target = self
        testMenu.addItem(notifTest)
        
        testMenu.addItem(NSMenuItem.separator())
        
        let fileDropTest = NSMenuItem(title: "Simular Soltar Archivo (Card Pop-Up)", action: #selector(testSimulatedFileDrop), keyEquivalent: "")
        fileDropTest.target = self
        testMenu.addItem(fileDropTest)
        
        let dragProbeTest = NSMenuItem(title: "🔍 Sonda Drag & Drop (Paso 0)", action: #selector(openDragProbeWindow), keyEquivalent: "")
        dragProbeTest.target = self
        testMenu.addItem(dragProbeTest)
        
        let testSubmenuItem = NSMenuItem(title: "Demostraciones de prueba", action: nil, keyEquivalent: "")
        testSubmenuItem.submenu = testMenu
        menu.addItem(testSubmenuItem)
        
        let debugPanelItem = NSMenuItem(
            title: "Panel de Pruebas (Live Activities)...",
            action: #selector(openDebugPanel),
            keyEquivalent: "p"
        )
        debugPanelItem.target = self
        menu.addItem(debugPanelItem)
        
        let studioItem = NSMenuItem(title: "🎬 Animation Studio (bolitas)", action: #selector(openAnimationStudio), keyEquivalent: "")
        studioItem.target = self
        menu.addItem(studioItem)
        
        let spectrumMonitorItem = NSMenuItem(
            title: "Monitor de Audio Real y Overscroll...",
            action: #selector(openAudioSpectrumMonitor),
            keyEquivalent: "m"
        )
        spectrumMonitorItem.target = self
        menu.addItem(spectrumMonitorItem)
        
        let settingsItem = NSMenuItem(
            title: "Ajustes y Preferencias...",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Salir de Dynamic Notch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openSettingsWindow() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func openAudioSpectrumMonitor() {
        AudioSpectrumTestWindowController.shared.show()
    }
    
    @objc private func toggleNotch() {
        AppState.shared.toggleExpand()
        buildMenu()
    }
    
    @objc private func toggleHover() {
        AppState.shared.expandOnHover.toggle()
        buildMenu()
    }
    
    @objc private func toggleHaptics() {
        AppState.shared.enableHaptics.toggle()
        HapticService.shared.isEnabled = AppState.shared.enableHaptics
        buildMenu()
    }
    
    @objc private func toggleSoundFeedback() {
        AppState.shared.enableSoundFeedback.toggle()
        buildMenu()
    }
    
    @objc private func testMagSafe() {
        ChargingActivityProvider.shared.publishChargingActivity(percentage: 88, isLowPower: false, isPluggedIn: true)
    }
    
    @objc private func testAirPods() {
        if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
            AppState.shared.collapse()
        }
        AppState.shared.enableAirPodsAnimation = true
        AirPodsActivityProvider.shared.publishAirPodsActivity(
            name: "AirPods Pro de Luis",
            batteryLevel: 100,
            leftPercent: 100,
            rightPercent: 100,
            casePercent: 100,
            duration: 13.0
        )
    }
    
    @objc private func testAirPods4() {
        if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
            AppState.shared.collapse()
        }
        AppState.shared.enableAirPodsAnimation = true
        AirPodsActivityProvider.shared.publishAirPodsActivity(
            name: "AirPods 4",
            batteryLevel: 90,
            leftPercent: 88,
            rightPercent: 90,
            casePercent: 100,
            duration: 13.0
        )
    }
    
    @objc private func testLockScreenPreview() {
        LockScreenManager.shared.showPlayerPanelPreview(duration: 10)
    }
    
    @objc private func testBatteryLow() {
        ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: 12)
    }
    
    @objc private func testAirDropTransfer() {
        AirDropActivityProvider.shared.startSimulatedTransfer()
    }
    
    @objc private func testMusicDemo() {
        let isCurrentlyPlaying = MusicService.shared.currentTrack.isPlaying && MusicService.shared.hasActiveMusic
        
        if isCurrentlyPlaying {
            MusicService.shared.togglePlayPause()
        } else {
            MusicService.shared.setDemoTrack(MusicTrack(
                title: "Starboy",
                artist: "The Weeknd ft. Daft Punk",
                album: "Starboy",
                artwork: nil,
                isPlaying: true,
                playbackPosition: 14,
                duration: 230,
                appSource: "Simulado"
            ))
            AppState.shared.activeTab = .music
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                AppState.shared.mode = .compact
            }
        }
    }
    
    @objc private func testShelf() {
        AppState.shared.activeTab = .shelf
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
            AppState.shared.mode = .shelf
        }
    }
    
    @objc private func openAnimationStudio() {
        AnimationStudioWindow.shared.show()
    }
    
    @objc private func openDebugPanel() {
        ActivityDebugWindow.shared.show()
    }
    
    @objc private func openDragProbeWindow() {
        DragProbeDebugWindowController.shared.toggleWindow()
    }
    
    @objc private func toggleSuppressNativeHUD() {
        VolumeInterceptorService.shared.suppressNativeHUD.toggle()
        buildMenu()
    }
    
    @objc private func openAccessibilityOnboarding() {
        AccessibilityOnboardingWindowController.showAlways()
    }
    
    @objc private func testBrightnessSlider() {
        BrightnessService.shared.publishBrightnessActivity(0.75)
    }
    
    @objc private func testVolumeSlider() {
        AudioDeviceService.shared.publishVolumeActivity(volume: 0.60, isMuted: false)
    }
    
    @objc private func testMuteSlider() {
        AudioDeviceService.shared.publishVolumeActivity(volume: 0.60, isMuted: true)
    }
    
    @objc private func testTimerActivity() {
        TimerActivityProvider.shared.startTimer(duration: 30, title: "Minutka", asCard: false)
    }
    
    @objc private func testTimerCardActivity() {
        TimerActivityProvider.shared.startTimer(duration: 30, title: "Minutka", asCard: true)
    }
    
    @objc private func testNotificationActivity() {
        NotificationActivityProvider.shared.showNotification(
            title: "WhatsApp: Carlos",
            message: "¡Hola! El nuevo Dynamic Notch quedó impresionante 🚀",
            appIcon: "message.fill",
            tint: DesignTokens.green
        )
    }
    
    @objc private func testSimulatedFileDrop() {
        AppState.shared.isDropInvitationActive = true
        let desktopUrl = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
        let sampleFile = desktopUrl.appendingPathComponent("Documento_Ejemplo.pdf")
        if !FileManager.default.fileExists(atPath: sampleFile.path) {
            try? "Contenido de prueba para el Notch".write(to: sampleFile, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppState.shared.triggerDropSuccess(urls: [sampleFile])
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
