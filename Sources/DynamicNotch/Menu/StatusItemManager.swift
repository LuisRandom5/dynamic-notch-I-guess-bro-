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
        
        let airPodsTest = NSMenuItem(title: "Animación AirPods Pro (95% / 90% / 100%)", action: #selector(testAirPods), keyEquivalent: "")
        airPodsTest.target = self
        testMenu.addItem(airPodsTest)
        
        let batteryLowTest = NSMenuItem(title: "Alerta Batería Baja (12%)", action: #selector(testBatteryLow), keyEquivalent: "")
        batteryLowTest.target = self
        testMenu.addItem(batteryLowTest)
        
        let musicDemoTest = NSMenuItem(title: "Canción Demo (Starboy)", action: #selector(testMusicDemo), keyEquivalent: "")
        musicDemoTest.target = self
        testMenu.addItem(musicDemoTest)
        
        let shelfTest = NSMenuItem(title: "Abrir Bandeja de Archivos", action: #selector(testShelf), keyEquivalent: "")
        shelfTest.target = self
        testMenu.addItem(shelfTest)
        
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
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Salir de Dynamic Notch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
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
    
    @objc private func testMagSafe() {
        ChargingActivityProvider.shared.publishChargingActivity(percentage: 88, isLowPower: false, isPluggedIn: true)
    }
    
    @objc private func testAirPods() {
        AppState.shared.triggerAlert(
            .airpods(name: "AirPods Pro", leftPercent: 95, rightPercent: 90, casePercent: 100),
            duration: 4.5
        )
    }
    
    @objc private func testBatteryLow() {
        AppState.shared.triggerAlert(.batteryLow(percent: 12), duration: 4.0)
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
            AppState.shared.mode = .expanded
        }
    }
    
    @objc private func openDebugPanel() {
        ActivityDebugWindow.shared.show()
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
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
