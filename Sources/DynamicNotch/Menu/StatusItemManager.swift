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
            // Panel propio como los del Centro de Control, pegado a la barra: un NSMenu en `statusItem.menu`
            // sale separado de la barra (≈ 26 pt) en macOS 27 con notch, igual que en otras apps
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    @objc private func togglePanel() {
        guard let frame = buttonFrameOnScreen else { return }
        StatusPanelController.shared.toggle(below: frame)
    }
    
    /// Demostraciones, paneles de prueba y laboratorios (sólo en la compilación de desarrollo)
    func developerMenu() -> NSMenu {
        // Test demos submenu
        let testMenu = NSMenu()
    
        let brightnessTest = NSMenuItem(title: L("Slider Brillo (75%)"), action: #selector(testBrightnessSlider), keyEquivalent: "")
        brightnessTest.target = self
        testMenu.addItem(brightnessTest)
    
        let volumeTest = NSMenuItem(title: L("Slider Volumen (60%)"), action: #selector(testVolumeSlider), keyEquivalent: "")
        volumeTest.target = self
        testMenu.addItem(volumeTest)
    
        let muteTest = NSMenuItem(title: L("Slider Volumen Silenciado (Mute)"), action: #selector(testMuteSlider), keyEquivalent: "")
        muteTest.target = self
        testMenu.addItem(muteTest)
    
        testMenu.addItem(NSMenuItem.separator())
    
        let magSafeTest = NSMenuItem(title: L("Animación MagSafe (88%)"), action: #selector(testMagSafe), keyEquivalent: "")
        magSafeTest.target = self
        testMenu.addItem(magSafeTest)
    
        let airPods4Test = NSMenuItem(title: L("Animación AirPods 4 (88% / 90% / 100%)"), action: #selector(testAirPods4), keyEquivalent: "")
        airPods4Test.target = self
        testMenu.addItem(airPods4Test)
    
        let airPodsTest = NSMenuItem(title: L("Animación AirPods Pro (95% / 90% / 100%)"), action: #selector(testAirPods), keyEquivalent: "")
        airPodsTest.target = self
        testMenu.addItem(airPodsTest)
    
        let lockScreenTest = NSMenuItem(title: L("Previsualizar Reproductor Lock Screen (10s)"), action: #selector(testLockScreenPreview), keyEquivalent: "")
        lockScreenTest.target = self
        testMenu.addItem(lockScreenTest)
    
        let batteryLowTest = NSMenuItem(title: L("Alerta Batería Baja (12%)"), action: #selector(testBatteryLow), keyEquivalent: "")
        batteryLowTest.target = self
        testMenu.addItem(batteryLowTest)
    
        let musicDemoTest = NSMenuItem(title: L("Canción Demo (Starboy)"), action: #selector(testMusicDemo), keyEquivalent: "")
        musicDemoTest.target = self
        testMenu.addItem(musicDemoTest)
    
        let airDropTest = NSMenuItem(title: L("Simular AirDrop (Progreso → Éxito)"), action: #selector(testAirDropTransfer), keyEquivalent: "")
        airDropTest.target = self
        testMenu.addItem(airDropTest)
    
        let shelfTest = NSMenuItem(title: L("Abrir Bandeja de Archivos"), action: #selector(testShelf), keyEquivalent: "")
        shelfTest.target = self
        testMenu.addItem(shelfTest)
    
        testMenu.addItem(NSMenuItem.separator())
    
        let timerCompactTest = NSMenuItem(title: L("Temporizador Compacto (Minutka - 30s)"), action: #selector(testTimerActivity), keyEquivalent: "")
        timerCompactTest.target = self
        testMenu.addItem(timerCompactTest)
    
        let timerCardTest = NSMenuItem(title: L("Temporizador Expandido (Minutka Card - 30s)"), action: #selector(testTimerCardActivity), keyEquivalent: "")
        timerCardTest.target = self
        testMenu.addItem(timerCardTest)
    
        let notifTest = NSMenuItem(title: L("Notificación Dinámica (WhatsApp)"), action: #selector(testNotificationActivity), keyEquivalent: "")
        notifTest.target = self
        testMenu.addItem(notifTest)
    
        testMenu.addItem(NSMenuItem.separator())
    
        // Novedades 2.1 (cada una corre su demo sin tocar nada del sistema)
        let newIn21: [(String, Selector)] = [
            (L("Carga completa (100 %)"), #selector(testFullCharge)),
            (L("Concentración activada"), #selector(testFocus)),
            (L("Próxima reunión (ejemplo con Meet)"), #selector(testMeeting)),
            (L("WhatsApp: foto"), #selector(testWhatsAppPhoto)),
            (L("WhatsApp: dos mensajes seguidos (fila)"), #selector(testNotificationQueue)),
            (L("Actividad de la API (compilando, 10 s)"), #selector(testAPIActivity))
        ]
        for (title, action) in newIn21 {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            testMenu.addItem(item)
        }

        testMenu.addItem(NSMenuItem.separator())

        let fileDropTest = NSMenuItem(title: L("Simular Soltar Archivo (Card Pop-Up)"), action: #selector(testSimulatedFileDrop), keyEquivalent: "")
        fileDropTest.target = self
        testMenu.addItem(fileDropTest)
    
        let dragProbeTest = NSMenuItem(title: L("🔍 Sonda Drag & Drop (Paso 0)"), action: #selector(openDragProbeWindow), keyEquivalent: "")
        dragProbeTest.target = self
        testMenu.addItem(dragProbeTest)
    
        testMenu.addItem(NSMenuItem.separator())
    
        let debugPanelItem = NSMenuItem(
            title: "Panel de Pruebas (Live Activities)...",
            action: #selector(openDebugPanel),
            keyEquivalent: "p"
        )
        debugPanelItem.target = self
        testMenu.addItem(debugPanelItem)
    
        let studioItem = NSMenuItem(title: L("🎬 Animation Studio (bolitas)"), action: #selector(openAnimationStudio), keyEquivalent: "")
        studioItem.target = self
        testMenu.addItem(studioItem)
    
        let spectrumMonitorItem = NSMenuItem(
            title: "Monitor de Audio Real y Overscroll...",
            action: #selector(openAudioSpectrumMonitor),
            keyEquivalent: "m"
        )
        spectrumMonitorItem.target = self
        testMenu.addItem(spectrumMonitorItem)
        return testMenu
    }

    
    /// Diagnóstico: abre el menú como si se hiciera clic en el icono (/debug/status-menu)
    public func openMenuForDiagnostics() {
        togglePanel()
    }

    /// Dónde está el icono en la pantalla (para capturar el menú)
    public var buttonFrameOnScreen: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    
    @objc private func openAudioSpectrumMonitor() {
        AudioSpectrumTestWindowController.shared.show()
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
            name: "AirPods Pro",
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
    
    @objc private func testFullCharge() {
        ChargingActivityProvider.shared.publishFullyChargedActivity()
    }

    @objc private func testFocus() {
        SystemStatusActivityProvider.shared.simulateFocusChange(on: true)
    }

    @objc private func testMeeting() {
        CalendarActivityProvider.shared.showSample()
    }

    @objc private func testWhatsAppPhoto() {
        WhatsAppWebObserverService.shared.simulateTestNotification(message: WhatsAppMessagePreview.describe("Foto"))
    }

    /// Carlos y, medio segundo después, Ana: Ana espera a que Carlos se vea 2.5 s
    @objc private func testNotificationQueue() {
        WhatsAppWebObserverService.shared.simulateTestNotification()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WhatsAppWebObserverService.shared.simulateTestNotification(sender: "Ana", message: "¿Ya viste lo que te mandé?")
        }
    }

    /// Una actividad como las de `dynamicnotch`: progreso de 0 a 100 % en 10 s y resumen
    @objc private func testAPIActivity() {
        func send(_ json: [String: Any]) {
            if let request = try? PublicActivityAPI.parse(json) { PublicActivityAPI.apply(request) }
        }
        send(["id": "demo-build", "action": "start", "title": "Compilando", "icon": "hammer.fill", "progress": 0.0])
        for step in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step)) {
                if step < 10 {
                    send(["id": "demo-build", "progress": Double(step) / 10])
                } else {
                    send(["id": "demo-build", "action": "end", "title": "Listo", "icon": "checkmark.circle.fill",
                          "color": "green", "progress": 1.0, "dismissAfter": 4])
                }
            }
        }
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
        DemoMessages.mark("WhatsApp: Carlos")
        NotificationActivityProvider.shared.showNotification(
            title: "WhatsApp: Carlos",
            message: "¡Hola! El nuevo Dynamic Notch quedó impresionante 🚀",
            appIcon: "message.fill",
            tint: DesignTokens.green
        )
    }
    
    @objc private func testSimulatedFileDrop() {
        AppState.shared.isDropInvitationActive = true
        // Archivo de ejemplo en la carpeta temporal (antes se creaba en el escritorio del usuario)
        let sampleFile = FileManager.default.temporaryDirectory.appendingPathComponent("Documento de ejemplo.txt")
        if !FileManager.default.fileExists(atPath: sampleFile.path) {
            try? "Contenido de prueba para el Notch".write(to: sampleFile, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppState.shared.triggerDropSuccess(urls: [sampleFile])
        }
    }
    
}
