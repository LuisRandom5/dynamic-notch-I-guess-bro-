import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App de barra de menú: si macOS la "reabre" (al activarla sin ventanas, o un `open` mientras ya corre),
    /// SwiftUI abriría por su cuenta la ventana de la escena `Settings`. Los ajustes se abren sólo desde el menú.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Reducir transparencia / Aumentar contraste cambian el vidrio por negro OLED al instante (no sólo al
        // reabrir la app): AppState.effectiveAppearanceMode los consulta en cada redibujo
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let state = AppState.shared
            state.objectWillChange.send()
            NotchWindowManager.shared.panel?.appearance = NSAppearance(named: .darkAqua) // siempre oscura: el vidrio clear en apariencia clara se ve esmerilado
        }
        
        let myPID = ProcessInfo.processInfo.processIdentifier
        let notifCenter = ImmediateNotificationCenter.shared
        
        // 1. Garantía de Instancia Única (Single-Instance Enforcement):
        // Notificar a cualquier instancia previa que se cierre de inmediato y terminar procesos duplicados
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.luisrandom.DynamicNotch.terminateOlderInstances"),
            object: nil,
            userInfo: ["newPID": myPID],
            deliverImmediately: true
        )
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.luisrandom.DynamicNotch") where app.processIdentifier != myPID {
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.terminateOlderInstances") { notif in
            if let newPID = notif.userInfo?["newPID"] as? Int32, newPID != myPID {
                AudioSpectrumEngine.shared.stopCapture()
                NSApp.terminate(nil)
                exit(0)
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.quitAll") { _ in
            AudioSpectrumEngine.shared.stopCapture()
            NSApp.terminate(nil)
            exit(0)
        }
        
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
        _ = ProceduralMotionEngine.shared
        CallDetectorService.shared.startMonitoring()
        _ = FullScreenDetectorService.shared
        WhatsAppWebObserverService.shared.start()
        MessagesObserverService.shared.start()
        _ = LockScreenSkyLightBridge.shared
        _ = LockScreenManager.shared
        
        // Mostrar pantalla de onboarding si no se cuenta aún con permisos de accesibilidad
        AccessibilityOnboardingWindowController.showIfNeeded()
        
        // Observadores de notificaciones distribuidas para pruebas y bisección con entrega inmediata
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
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testIMessage") { _ in
            MessagesObserverService.shared.simulateTestNotification()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAirPods") { _ in
            AirPodsActivityProvider.shared.publishAirPodsActivity(
                name: "AirPods Pro de Luis",
                batteryLevel: 100,
                leftPercent: 100,
                rightPercent: 100,
                casePercent: 100,
                duration: 13.0
            )
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expandQuickReply") { _ in
            NotificationActivityProvider.shared.expandQuickReply()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.dismissNotification") { _ in
            NotificationActivityProvider.shared.dismissNotification()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testMusicCanvas") { _ in
            AmbientCanvasWindowManager.shared.toggleCanvas()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAgentProgress") { _ in
            AgentActivityProvider.shared.showProgress(payload: AgentLiveProgressPayload())
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAgentFinish") { _ in
            AgentActivityProvider.shared.showProgress(
                payload: AgentLiveProgressPayload(
                    agentName: "Claude",
                    taskName: "Stale cart total",
                    steps: [
                        AgentLiveStep(title: "Read CartStore.swift", isCompleted: true),
                        AgentLiveStep(title: "Edit CartStore.swift", isCompleted: true),
                        AgentLiveStep(title: "Edit SyncEngine.swift", isCompleted: true)
                    ],
                    fileDiff: AgentFileDiff(
                        filename: "Sources/.../SyncEngine.swift",
                        additions: 49,
                        deletions: 19,
                        statusText: "Completed",
                        progress: 1.0
                    ),
                    isCompleted: true
                )
            )
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAgentPermission") { _ in
            AgentActivityProvider.shared.showInteraction(
                type: .permission,
                title: "Antigravity",
                subtitle: "Permiso requerido",
                message: "¿Deseas ejecutar el siguiente comando en la terminal?",
                command: "git push origin main"
            )
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAgentNotification") { _ in
            AgentActivityProvider.shared.showInteraction(
                type: .notification,
                title: "Build Finalizado",
                subtitle: "Dynamic Notch",
                message: "Compilación exitosa con 0 errores.",
                duration: 5.0
            )
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testAgentQuestion") { _ in
            AgentActivityProvider.shared.showInteraction(
                type: .question,
                title: "Antigravity",
                subtitle: "Pregunta de Desarrollo",
                message: "¿Deseas desplegar la versión a producción o a staging?",
                options: [
                    AgentActionOption(id: "staging", label: "Staging"),
                    AgentActionOption(id: "prod", label: "Producción", isPrimary: true)
                ]
            )
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expandAgent") { _ in
            AgentActivityProvider.shared.expandInteraction()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.collapseAgent") { _ in
            AgentActivityProvider.shared.collapseInteraction()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testIncomingCall") { _ in
            CallActivityProvider.shared.startIncomingCall(name: "FaceTime Audio", handle: "Mamá", isSimulation: true)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.testActiveCallPill") { _ in
            CallActivityProvider.shared.startCall(name: "FaceTime Audio", handle: "Mamá", asCard: false, isSimulation: true)
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expandCallCard") { _ in
            CallActivityProvider.shared.expandToCard()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.collapseCallCard") { _ in
            CallActivityProvider.shared.collapseToPill()
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.endCall") { _ in
            CallActivityProvider.shared.endCall()
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
        
        notifCenter.observe("com.luisrandom.DynamicNotch.showRefractionPattern") { _ in
            DispatchQueue.main.async {
                GlassClearManager.shared.showRefractionTestPattern.toggle()
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.expandNotch") { _ in
            DispatchQueue.main.async {
                AppState.shared.mode = .expanded
                AppState.shared.activeTab = .music
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.collapseNotch") { _ in
            DispatchQueue.main.async {
                AppState.shared.mode = .idle
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.togglePlayerDetail") { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                    AppState.shared.isPlayerDetailExpanded.toggle()
                }
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setDarkGlass") { _ in
            DispatchQueue.main.async {
                AppState.shared.appearanceMode = .darkGlass
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setClearGlass") { _ in
            DispatchQueue.main.async {
                AppState.shared.appearanceMode = .clearGlass
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.setOled") { _ in
            DispatchQueue.main.async {
                AppState.shared.appearanceMode = .pureOLED
            }
        }
        
        notifCenter.observe("com.luisrandom.DynamicNotch.switchPage") { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if AppState.shared.mode == .shelf {
                        AppState.shared.mode = .expanded
                        AppState.shared.activeTab = .music
                    } else {
                        AppState.shared.mode = .shelf
                        AppState.shared.activeTab = .shelf
                    }
                }
            }
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
        // Envíos y recepciones en tiempo real desde el registro de sharingd
        AirDropTransferMonitor.shared.start()
        
        // Iniciar servidor local de interacción con herramientas de IA (Antigravity / dnotch)
        AgentIPCService.shared.start()
        
        // El temporizador cede el notch a la música/video (y vuelve cuando se detiene)
        ActivityCenter.shared.startObservingPlayback()
        // La repisa con archivos aparece como bolita
        ShelfActivityProvider.shared.start()
        // Avisos del sistema (Bloq Mayús, red/VPN, cámara/micrófono en uso) y descargas en curso
        SystemStatusActivityProvider.shared.start()
        DownloadsActivityProvider.shared.start()
        
        // Barras que siguen la música: captura de audio sólo mientras algo se reproduce
        AudioSpectrumEngine.shared.startPlaybackGatedCapture()
        // Tempo real de cada canción, por si su audio llega protegido (DRM) y en silencio
        ProceduralMotionEngine.shared.startPrefetchingTempo()
        // Diagnóstico de rendimiento siempre activo (barato): GET /debug/hitches
        FrameHitchMonitor.shared.start()
        // Notch oculto mientras se ve algo a pantalla completa
        FullScreenMediaMonitor.shared.start()
        // Vidrio legible: detecta si detrás del notch hay algo claro (regular) o el fondo de pantalla (clear)
        BackdropBrightnessMonitor.shared.start()
        
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
        AgentIPCService.shared.stop()
        NowPlayingService.shared.stop()
        AudioSpectrumEngine.shared.stopCapture()
        AirDropObserverService.shared.stopObserving()
        AirDropTransferMonitor.shared.stop()
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

