import AppKit

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
        
        // Mostrar pantalla de onboarding si no se cuenta aún con permisos de accesibilidad
        AccessibilityOnboardingWindowController.showIfNeeded()
        
        print("🍏 Dynamic Notch iniciado con éxito en macOS.")
        print("📐 Dimensiones del notch físico: \(ScreenService.shared.currentGeometry.width)x\(ScreenService.shared.currentGeometry.height)pt")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        print("Dynamic Notch finalizado.")
    }
}
