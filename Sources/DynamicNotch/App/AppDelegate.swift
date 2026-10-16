import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (no dock icon clutter, lives in menu bar & floating above notch)
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize services and window
        ScreenService.shared.updateScreenGeometry()
        NotchWindowManager.shared.setupWindow()
        StatusItemManager.shared.setupStatusItem()
        _ = BluetoothAudioService.shared
        ChargingActivityProvider.shared.start()
        _ = VolumeInterceptorService.shared
        _ = BrightnessService.shared
        _ = MusicService.shared
        NowPlayingService.shared.refreshNowPlaying()
        CallDetectorService.shared.startMonitoring()
        _ = FullScreenDetectorService.shared
        WhatsAppWebObserverService.shared.start()
        _ = LockScreenSkyLightBridge.shared
        _ = LockScreenManager.shared
        
        // Mostrar pantalla de onboarding si no se cuenta aún con permisos de accesibilidad
        AccessibilityOnboardingWindowController.showIfNeeded()
        
        // Observadores de notificaciones distribuidas para pruebas y bisección con entrega inmediata
        let notifCenter = ImmediateNotificationCenter.shared
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expand") { _ in
            AppState.shared.autoCollapseOnHoverExit = false
            AppState.shared.expand()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.collapse") { _ in
            AppState.shared.collapse()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.openShelf") { _ in
            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                AppState.shared.mode = .shelf
                AppState.shared.activeTab = .shelf
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testDrop") { notif in
            if let path = notif.userInfo?["path"] as? String {
                let url = URL(fileURLWithPath: path)
                AppState.shared.triggerDropSuccess(urls: [url])
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.showDebug") { _ in
            ActivityDebugWindow.shared.show()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.showAudioSpectrum") { _ in
            AudioSpectrumTestWindowController.shared.show()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.showDragProbe") { _ in
            DragProbeDebugWindowController.shared.toggleWindow()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.openSettings") { _ in
            SettingsWindowController.shared.show()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testLockScreen") { _ in
            LockScreenSkyLightBridge.shared.startCountdownAndArmTest(seconds: 3)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.previewLockScreen") { _ in
            LockScreenSkyLightBridge.shared.showTestPanel(isPreview: true)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.hideLockScreenTest") { _ in
            LockScreenSkyLightBridge.shared.hideTestPanel(reason: "Notificación com.luisrandom.DynamicNotch.hideLockScreenTest")
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.previewLockScreenPlayer") { _ in
            LockScreenManager.shared.showPlayerPanelPreview()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.hideLockScreenPlayer") { _ in
            LockScreenManager.shared.hidePlayerPanelPreview()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testWhatsApp") { _ in
            WhatsAppWebObserverService.shared.simulateTestNotification()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expandQuickReply") { _ in
            NotificationActivityProvider.shared.expandQuickReply()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.dismissNotification") { _ in
            NotificationActivityProvider.shared.dismissNotification()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testIncomingCall") { _ in
            CallActivityProvider.shared.startIncomingCall(name: "FaceTime Audio", handle: "Mamá", isSimulation: true)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testVolumeHUD") { _ in
            AudioDeviceService.shared.stepVolume(up: true)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAirDrop") { _ in
            AirDropActivityProvider.shared.startSimulatedTransfer(fileName: "Foto de Luis.heic", sender: "iPhone de Luis")
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.activateWhatsApp") { _ in
            WhatsAppWebObserverService.shared.activateWhatsAppWeb()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setBisection") { notif in
            guard let key = notif.userInfo?["key"] as? String,
                  let val = notif.userInfo?["value"] as? Bool else { return }
            switch key {
            case "notchStrip": GlassClearManager.shared.showNotchFusionStrip = val
            case "tint": GlassClearManager.shared.showGlassTint = val
            case "shadow": GlassClearManager.shared.showCardShadow = val
            case "baseFill": GlassClearManager.shared.showBaseFill = val
            case "border": GlassClearManager.shared.showSpecularBorder = val
            case "scrim": GlassClearManager.shared.showLocalTextScrim = val
            default: break
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setScrim") { notif in
            if let val = notif.userInfo?["value"] as? Double {
                GlassClearManager.shared.uniformScrimOpacity = val
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setAppearance") { notif in
            if let raw = notif.userInfo?["mode"] as? String,
               let mode = NotchAppearanceMode(rawValue: raw) {
                AppState.shared.appearanceMode = mode
            }
        }
        
        // Iniciar sonda de detección de arrastre pasiva (coste 0 en reposo)
        DragDetectionProbe.shared.startProbe()
        
        // Iniciar observador en tiempo real de transferencias AirDrop
        AirDropObserverService.shared.startObserving()
        
        // Precalentar la canalización de Liquid Glass en GPU para evitar saltos en el primer despliegue
        if #available(macOS 26.0, *) {
            DispatchQueue.main.async {
                let warmUpView = NSHostingView(
                    rootView: GlassEffectContainer {
                        Color.clear.glassEffect(Glass.regular, in: Capsule())
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                )
                warmUpView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
                if let panel = NotchWindowManager.shared.panel {
                    panel.contentView?.addSubview(warmUpView)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        warmUpView.removeFromSuperview()
                    }
                }
            }
        }
        
        print("🍏 Dynamic Notch iniciado con éxito en macOS.")
        print("📐 Dimensiones del notch físico: \(ScreenService.shared.currentGeometry.width)x\(ScreenService.shared.currentGeometry.height)pt")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        NowPlayingService.shared.stop()
        AudioSpectrumEngine.shared.stopCapture()
        AirDropObserverService.shared.stopObserving()
        LockScreenManager.shared.cleanup()
        LockScreenSkyLightBridge.shared.cleanupActiveSpace()
        print("Dynamic Notch finalizado limpiamente.")
    }
}

/// Despachador de notificaciones distribuidas con entrega inmediata (evita la suspensión del sistema en apps LSUIElement)
final class ImmediateNotificationCenter: NSObject {
    static let shared = ImmediateNotificationCenter()
    private var handlers: [String: [(Notification) -> Void]] = [:]
    
    func observe(_ name: String, handler: @escaping (Notification) -> Void) {
        let notifName = NSNotification.Name(name)
        if handlers[name] == nil {
            handlers[name] = []
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(handleNotification(_:)),
                name: notifName,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        handlers[name]?.append(handler)
    }
    
    @objc private func handleNotification(_ notification: Notification) {
        let name = notification.name.rawValue
        DNDLogger.log("ImmediateNotificationCenter.handleNotification -> \(name)")
        DispatchQueue.main.async { [weak self] in
            let count = self?.handlers[name]?.count ?? -1
            DNDLogger.log("ImmediateNotificationCenter: dispatching handlers for \(name), count=\(count)")
            self?.handlers[name]?.forEach { $0(notification) }
        }
    }
}

