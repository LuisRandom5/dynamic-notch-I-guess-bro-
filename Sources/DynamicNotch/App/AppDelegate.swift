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
        
        // Mostrar pantalla de onboarding si no se cuenta aún con permisos de accesibilidad
        AccessibilityOnboardingWindowController.showIfNeeded()
        
        // Observadores de notificaciones distribuidas para pruebas y bisección
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.expand"),
            object: nil,
            queue: .main
        ) { _ in
            AppState.shared.autoCollapseOnHoverExit = false
            AppState.shared.expand()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.collapse"),
            object: nil,
            queue: .main
        ) { _ in
            AppState.shared.collapse()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.openShelf"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                AppState.shared.mode = .shelf
                AppState.shared.activeTab = .shelf
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.testDrop"),
            object: nil,
            queue: .main
        ) { notif in
            if let path = notif.userInfo?["path"] as? String {
                let url = URL(fileURLWithPath: path)
                AppState.shared.triggerDropSuccess(urls: [url])
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.showDebug"),
            object: nil,
            queue: .main
        ) { _ in
            ActivityDebugWindow.shared.show()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.showAudioSpectrum"),
            object: nil,
            queue: .main
        ) { _ in
            AudioSpectrumTestWindowController.shared.show()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.showDragProbe"),
            object: nil,
            queue: .main
        ) { _ in
            DragProbeDebugWindowController.shared.toggleWindow()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.setBisection"),
            object: nil,
            queue: .main
        ) { notif in
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
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.setScrim"),
            object: nil,
            queue: .main
        ) { notif in
            if let val = notif.userInfo?["value"] as? Double {
                GlassClearManager.shared.uniformScrimOpacity = val
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.luisrandom.DynamicNotch.setAppearance"),
            object: nil,
            queue: .main
        ) { notif in
            if let raw = notif.userInfo?["mode"] as? String,
               let mode = NotchAppearanceMode(rawValue: raw) {
                AppState.shared.appearanceMode = mode
            }
        }
        
        // Iniciar sonda de detección de arrastre pasiva (coste 0 en reposo)
        DragDetectionProbe.shared.startProbe()
        
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
        print("Dynamic Notch finalizado limpiamente.")
    }
}
