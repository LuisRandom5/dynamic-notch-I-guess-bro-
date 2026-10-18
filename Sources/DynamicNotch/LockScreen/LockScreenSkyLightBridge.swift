import AppKit
import SwiftUI
import Combine

/// Puente de bajo nivel con SkyLight.framework y AppKit SPIs para renderizado en la Pantalla de Bloqueo.
/// Todos los símbolos privados de SkyLight se cargan de forma dinámica mediante `dlopen` + `dlsym`.
/// Si algún símbolo no está disponible en una versión futura de macOS, el Kill Switch desactiva automáticamente
/// la funcionalidad para garantizar estabilidad absoluta sin crashes.
public final class LockScreenSkyLightBridge: ObservableObject {
    public static let shared = LockScreenSkyLightBridge()
    
    // MARK: - Tipos C Privados de SkyLight
    private typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
    private typealias SLSSpaceCreateFunc = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SLSSpaceDestroyFunc = @convention(c) (Int32, UInt64) -> Int32
    private typealias SLSSpaceSetAbsoluteLevelFunc = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias SLSShowSpacesFunc = @convention(c) (Int32, CFArray) -> Int32
    private typealias SLSHideSpacesFunc = @convention(c) (Int32, CFArray) -> Int32
    private typealias SLSSpaceAddWindowsAndRemoveFromSpacesFunc = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias CGSSetWindowBackgroundBlurRadiusFunc = @convention(c) (Int32, Int32, Int32) -> Int32
    
    // Punteros a funciones resueltos
    private var fnMainConnectionID: SLSMainConnectionIDFunc?
    private var fnSpaceCreate: SLSSpaceCreateFunc?
    private var fnSpaceDestroy: SLSSpaceDestroyFunc?
    private var fnSpaceSetAbsoluteLevel: SLSSpaceSetAbsoluteLevelFunc?
    private var fnShowSpaces: SLSShowSpacesFunc?
    private var fnHideSpaces: SLSHideSpacesFunc?
    private var fnSpaceAddWindowsAndRemoveFromSpaces: SLSSpaceAddWindowsAndRemoveFromSpacesFunc?
    private var fnSetWindowBackgroundBlurRadius: CGSSetWindowBackgroundBlurRadiusFunc?
    
    // Handle de la biblioteca dinámica SkyLight
    private var skyLightHandle: UnsafeMutableRawPointer?
    
    // MARK: - Estado Observable
    @Published public private(set) var isSupported: Bool = false
    @Published public private(set) var isScreenLocked: Bool = false
    @Published public private(set) var activeSpaceID: UInt64 = 0
    @Published public private(set) var isTestPanelActive: Bool = false
    @Published public private(set) var testCountdownSeconds: Int = 0
    @Published public private(set) var diagnosticStatus: String = "No inicializado"
    
    // Panel de prueba para el Paso 0
    private var testPanel: NSPanel?
    private var countdownTimer: Timer?
    private var safetyWatchdogTimer: Timer?
    
    private init() {
        loadSkyLightSymbols()
        registerLockStateObservers()
    }
    
    deinit {
        cleanupActiveSpace()
        if let handle = skyLightHandle {
            dlclose(handle)
        }
    }
    
    // MARK: - Carga Dinámica Segura (Kill Switch)
    private func loadSkyLightSymbols() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            let errorMsg = String(cString: dlerror())
            diagnosticStatus = "Error dlopen SkyLight: \(errorMsg)"
            isSupported = false
            print("⚠️ [LockScreenSkyLightBridge] No se pudo cargar SkyLight: \(errorMsg)")
            return
        }
        self.skyLightHandle = handle
        
        guard let symCid = dlsym(handle, "SLSMainConnectionID"),
              let symCreate = dlsym(handle, "SLSSpaceCreate"),
              let symDestroy = dlsym(handle, "SLSSpaceDestroy"),
              let symSetLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let symShow = dlsym(handle, "SLSShowSpaces"),
              let symHide = dlsym(handle, "SLSHideSpaces"),
              let symAddWin = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            diagnosticStatus = "Faltan símbolos privados en SkyLight.framework"
            isSupported = false
            print("⚠️ [LockScreenSkyLightBridge] Faltan símbolos en SkyLight.framework. Kill Switch activado.")
            return
        }
        
        self.fnMainConnectionID = unsafeBitCast(symCid, to: SLSMainConnectionIDFunc.self)
        self.fnSpaceCreate = unsafeBitCast(symCreate, to: SLSSpaceCreateFunc.self)
        self.fnSpaceDestroy = unsafeBitCast(symDestroy, to: SLSSpaceDestroyFunc.self)
        self.fnSpaceSetAbsoluteLevel = unsafeBitCast(symSetLevel, to: SLSSpaceSetAbsoluteLevelFunc.self)
        self.fnShowSpaces = unsafeBitCast(symShow, to: SLSShowSpacesFunc.self)
        self.fnHideSpaces = unsafeBitCast(symHide, to: SLSHideSpacesFunc.self)
        self.fnSpaceAddWindowsAndRemoveFromSpaces = unsafeBitCast(symAddWin, to: SLSSpaceAddWindowsAndRemoveFromSpacesFunc.self)
        
        if let symBlur = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") {
            self.fnSetWindowBackgroundBlurRadius = unsafeBitCast(symBlur, to: CGSSetWindowBackgroundBlurRadiusFunc.self)
        }
        
        self.isSupported = true
        let cid = fnMainConnectionID?() ?? -1
        self.diagnosticStatus = "SkyLight enlazado con éxito (CID: \(cid))"
        print("✅ [LockScreenSkyLightBridge] SkyLight cargado correctamente. CID: \(cid)")
    }
    
    /// Aplica blur de ventana mediante la API privada CGSSetWindowBackgroundBlurRadius de SkyLight
    public func setWindowBackgroundBlur(windowNumber: Int, radius: Int = 30) {
        guard let fn = fnSetWindowBackgroundBlurRadius, let cid = fnMainConnectionID?() else { return }
        _ = fn(cid, Int32(windowNumber), Int32(radius))
    }
    
    // MARK: - Observadores de Estado de Bloqueo
    private func registerLockStateObservers() {
        let distCenter = DistributedNotificationCenter.default()
        
        // 1. Pantalla bloqueada (entregada de inmediato aun en segundo plano)
        distCenter.addObserver(
            self,
            selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 2. Pantalla desbloqueada (entregada de inmediato aun en segundo plano)
        distCenter.addObserver(
            self,
            selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 3. Reposo y activación de pantallas físicas (Ahorro de batería y recursos)
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("💤 [LockScreenSkyLightBridge] Pantallas en reposo. Pausando renderizado.")
            self?.testPanel?.alphaValue = 0.0
        }
        
        wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("☀️ [LockScreenSkyLightBridge] Pantallas despertaron.")
            if self?.isTestPanelActive == true {
                self?.testPanel?.alphaValue = 1.0
            }
        }
        
        wsCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔄 [LockScreenSkyLightBridge] Sesión pasó a inactiva (cambio de usuario).")
            self?.hideTestPanel(reason: "Sesión inactiva")
        }
    }
    
    // MARK: - Manejo de Bloqueo / Desbloqueo
    @objc private func onScreenLocked(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.handleScreenLocked()
        }
    }
    
    @objc private func onScreenUnlocked(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.handleScreenUnlocked()
        }
    }
    
    private func handleScreenLocked() {
        isScreenLocked = true
        print("🔒 [LockScreenSkyLightBridge] Pantalla bloqueada detectada (com.apple.screenIsLocked).")
        
    }
    
    private func handleScreenUnlocked() {
        isScreenLocked = false
        print("🔓 [LockScreenSkyLightBridge] Pantalla desbloqueada detectada (com.apple.screenIsUnlocked).")
        hideTestPanel(reason: "Desbloqueo de pantalla")
    }
    
    // MARK: - Operaciones SkyLight para Ventanas en Pantalla de Bloqueo
    
    /// Crea un Space de sistema no gestionado con nivel absoluto alto (por defecto 400).
    public func createLockScreenSpace(level: Int32 = 400) -> UInt64? {
        guard isSupported,
              let fnCid = fnMainConnectionID,
              let fnCreate = fnSpaceCreate,
              let fnSetLevel = fnSpaceSetAbsoluteLevel,
              let fnShow = fnShowSpaces else {
            return nil
        }
        
        let cid = fnCid()
        let spaceID = fnCreate(cid, 1, nil)
        guard spaceID != 0 else {
            print("❌ [LockScreenSkyLightBridge] Error al crear space con SLSSpaceCreate.")
            return nil
        }
        
        let levelRes = fnSetLevel(cid, spaceID, level)
        let showRes = fnShow(cid, [NSNumber(value: spaceID)] as CFArray)
        print("🌌 [LockScreenSkyLightBridge] Space creado: \(spaceID), nivel: \(level) (resLevel=\(levelRes), resShow=\(showRes))")
        self.activeSpaceID = spaceID
        return spaceID
    }
    
    /// Mueve una ventana al Space especificado.
    public func addWindowToSpace(windowNumber: Int, spaceID: UInt64) {
        guard isSupported,
              let fnCid = fnMainConnectionID,
              let fnAdd = fnSpaceAddWindowsAndRemoveFromSpaces else { return }
        
        let cid = fnCid()
        let result = fnAdd(cid, spaceID, [NSNumber(value: windowNumber)] as CFArray, 7)
        print("🪟 [LockScreenSkyLightBridge] Ventana #\(windowNumber) asignada a Space \(spaceID) (res=\(result))")
    }
    
    /// Oculta y destruye el Space activo liberando recursos de WindowServer sin dejar fugas.
    public func cleanupActiveSpace() {
        guard activeSpaceID != 0,
              isSupported,
              let fnCid = fnMainConnectionID,
              let fnHide = fnHideSpaces,
              let fnDestroy = fnSpaceDestroy else {
            activeSpaceID = 0
            return
        }
        
        let cid = fnCid()
        let spaceToDestroy = activeSpaceID
        activeSpaceID = 0
        
        _ = fnHide(cid, [NSNumber(value: spaceToDestroy)] as CFArray)
        let destroyRes = fnDestroy(cid, spaceToDestroy)
        print("🧹 [LockScreenSkyLightBridge] Space \(spaceToDestroy) destruido limpiamente (res=\(destroyRes)).")
    }
    
    // MARK: - Panel de Prueba de Viabilidad (Paso 0)
    
    /// Inicia cuenta atrás de 3 segundos para que el usuario bloquee la pantalla con Cmd+Ctrl+Q.
    public func startCountdownAndArmTest(seconds: Int = 3) {
        countdownTimer?.invalidate()
        testCountdownSeconds = seconds
        AppState.shared.isLockScreenTestArmed = true
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.testCountdownSeconds > 1 {
                self.testCountdownSeconds -= 1
            } else {
                self.testCountdownSeconds = 0
                timer.invalidate()
                self.diagnosticStatus = "Prueba armada. Bloquea tu Mac con ⌘+⌃+Q ahora."
            }
        }
    }
    
    public func cancelArmedTest() {
        countdownTimer?.invalidate()
        testCountdownSeconds = 0
        AppState.shared.isLockScreenTestArmed = false
        diagnosticStatus = "Prueba cancelada por el usuario"
    }
    
    /// Muestra el panel de prueba de viabilidad sobre la pantalla de bloqueo (o escritorio en modo previsualización).
    public func showTestPanel(isPreview: Bool = false) {
        // Asegurar que corre en el hilo principal
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showTestPanel(isPreview: isPreview)
            }
            return
        }
        
        // Destruir cualquier panel previo
        hideTestPanel(reason: "Recreando panel")
        
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        
        let cardWidth: CGFloat = 420
        let cardHeight: CGFloat = 200
        let posX = screenFrame.origin.x + (screenFrame.width - cardWidth) / 2
        // Debajo del reloj de macOS (ocupa ~12% a 32% superior)
        let topY = screenFrame.maxY - (screenFrame.height * 0.36)
        let posY = topY - cardHeight
        let panelRect = NSRect(x: posX, y: posY, width: cardWidth, height: cardHeight)
        
        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configuración crítica AppKit para Pantalla de Bloqueo
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Nivel por encima del escudo de bloqueo del sistema
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.sharingType = .readOnly
        panel.hidesOnDeactivate = false
        
        // Contenido SwiftUI
        let hostingView = NSHostingView(rootView: LockScreenTestCardView(isPreview: isPreview))
        hostingView.frame = NSRect(origin: .zero, size: panelRect.size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        
        self.testPanel = panel
        self.isTestPanelActive = true
        
        // Asignar al Space SkyLight si no es sólo previsualización de escritorio
        if !isPreview && isSupported {
            if let spaceID = createLockScreenSpace(level: 400) {
                panel.orderFrontRegardless()
                addWindowToSpace(windowNumber: panel.windowNumber, spaceID: spaceID)
            } else {
                panel.orderFrontRegardless()
            }
        } else {
            panel.orderFrontRegardless()
        }
        
        diagnosticStatus = isPreview ? "Previsualizando en escritorio (5 s)" : "Panel de prueba activo sobre Pantalla de Bloqueo"
        
        // Watchdog de seguridad (se cierra solo si no se desbloquea en tiempo límite)
        safetyWatchdogTimer?.invalidate()
        let timeout: TimeInterval = isPreview ? 5.0 : 25.0
        safetyWatchdogTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.hideTestPanel(reason: "Tiempo límite de seguridad alcanzado")
        }
    }
    
    /// Oculta y destruye inmediatamente el panel de prueba y el Space SkyLight sin dejar ventanas fantasma.
    public func hideTestPanel(reason: String = "") {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.hideTestPanel(reason: reason)
            }
            return
        }
        
        safetyWatchdogTimer?.invalidate()
        safetyWatchdogTimer = nil
        
        if let panel = testPanel {
            panel.orderOut(nil)
            self.testPanel = nil
        }
        
        cleanupActiveSpace()
        isTestPanelActive = false
        if !reason.isEmpty {
            diagnosticStatus = "Panel cerrado (\(reason))"
            print("🛑 [LockScreenSkyLightBridge] Panel de prueba ocultado: \(reason)")
        }
    }
}

// MARK: - Tarjeta de Prueba de Viabilidad (Paso 0)
public struct LockScreenTestCardView: View {
    public let isPreview: Bool
    @ObservedObject var bridge = LockScreenSkyLightBridge.shared
    
    public init(isPreview: Bool = false) {
        self.isPreview = isPreview
    }
    
    public var body: some View {
        ZStack {
            // Fondo con bordes y sombra de alta calidad
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.15, blue: 0.32).opacity(0.88),
                            Color(red: 0.05, green: 0.08, blue: 0.20).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.70),
                                    Color.white.opacity(0.20),
                                    Color.blue.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
            
            // Contenido informativo
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.cyan)
                    Text("PRUEBA LOCK SCREEN DYNAMIC NOTCH")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(0.5)
                }
                
                Text(isPreview
                     ? "Previsualización de Posición (Debajo del Reloj)"
                     : "Si ves este cuadro en la pantalla de bloqueo,\nlos SPIs de SkyLight y AppKit funcionan al 100%.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.horizontal, 16)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SkyLight Space ID: \(bridge.activeSpaceID)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text("Nivel: 400 (Above Shielding)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("VisibleWithoutLogin: ✅")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                        Text("Touch ID / Pass: Desbloquea")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(18)
        }
        .frame(width: 420, height: 200)
    }
}
