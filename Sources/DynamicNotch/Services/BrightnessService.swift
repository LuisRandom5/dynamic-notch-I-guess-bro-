import Foundation
import CoreGraphics
import SwiftUI

// MARK: - BrightnessService (DisplayServices Private API Isolation & Real-Time Monitoring)
/// ⚠️ AVISO DE RIESGO DE API PRIVADA:
/// Este servicio utiliza `DisplayServices.framework` (framework privado del sistema en macOS),
/// cargando dinámicamente mediante `dlopen` y `dlsym` las funciones C no documentadas:
/// - `DisplayServicesGetBrightness(_: UnsafeMutablePointer<Float>) -> Int32`
/// - `DisplayServicesSetBrightness(_: Float) -> Int32`
///
/// Riesgo: Al ser una interfaz privada interna de Apple, su comportamiento o firmas
/// podrían cambiar en versiones mayores futuras de macOS.
/// Para mitigar cualquier riesgo de inestabilidad o caída de la app:
/// 1. El acceso está 100% aislado en este único archivo.
/// 2. Todos los símbolos se resuelven dinámicamente con comprobación de nulidad.
/// 3. Si las APIs no estuvieran disponibles en algún entorno, falla de forma silenciosa y segura.
public final class BrightnessService: ObservableObject {
    public static let shared = BrightnessService()
    
    @Published public private(set) var currentBrightness: Float = 0.5
    
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    
    private var getBrightnessPtr: GetBrightnessFunc?
    private var setBrightnessPtr: SetBrightnessFunc?
    private var isFrameworkAvailable: Bool = false
    
    private var pollingTimer: Timer?
    private var lastPolledBrightness: Float = 0.5
    private var isInitialMonitoring: Bool = true
    
    private init() {
        loadDisplayServices()
        let initial = readCurrentBrightness()
        self.currentBrightness = initial
        self.lastPolledBrightness = initial
        startBrightnessMonitoring()
    }
    
    private func loadDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return
        }
        
        if let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
           let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
            self.getBrightnessPtr = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            self.setBrightnessPtr = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            self.isFrameworkAvailable = true
        }
    }
    
    private var suppressionTimer: Timer?
    public private(set) var isSuppressed: Bool = false
    
    /// Suprime la publicación del slider de brillo durante una ventana de gracia
    /// (por ejemplo, para evitar interrumpir la animación del cargador MagSafe cuando macOS sube el brillo automáticamente)
    public func suppressAutoBrightnessSlider(duration: TimeInterval = 3.5) {
        suppressionTimer?.invalidate()
        isSuppressed = true
        suppressionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.isSuppressed = false
        }
    }
    
    /// Monitoreo activo de brillo (polling ligero cada 150 ms)
    /// NOTA DE COMPORTAMIENTO:
    /// macOS ajusta el brillo automáticamente mediante el sensor de luz ambiental, ahorro de energía, etc.
    /// Para evitar que el notch salte o interrumpa al usuario cuando el sistema hace estos ajustes automáticos,
    /// este timer sincroniza `currentBrightness` y `lastPolledBrightness` de forma puramente silenciosa.
    /// Únicamente las interacciones explícitas del usuario (teclas de brillo F1/F2 o controles manuales)
    /// llamarán a `publishBrightnessActivity` para mostrar el HUD en la Isla Dinámica.
    private let pollingQueue = DispatchQueue(label: "com.luisrandom.DynamicNotch.Brightness", qos: .utility)
    private var isPollingBrightness = false

    private func startBrightnessMonitoring() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isInitialMonitoring = false
        }
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPollingBrightness else { return }
            // La lectura (DisplayServices) se hace fuera del hilo principal: cada 0.15 s robaba tiempo a las
            // animaciones del notch
            self.isPollingBrightness = true
            self.pollingQueue.async { [weak self] in
                guard let self = self else { return }
                let current = self.readCurrentBrightness()
                DispatchQueue.main.async {
                    self.isPollingBrightness = false
                    if abs(current - self.lastPolledBrightness) > 0.005 {
                        self.lastPolledBrightness = current
                        self.currentBrightness = current
                        // Omitir en automático: NO publicar actividad en polling del sistema
                        // para que el notch no salte cuando macOS ajusta el brillo por sensor ambiental.
                    }
                }
            }
        }
    }
    
    /// Lee el brillo del monitor principal (0.0 a 1.0)
    public func readCurrentBrightness() -> Float {
        guard isFrameworkAvailable, let getFn = getBrightnessPtr else {
            return currentBrightness
        }
        
        var val: Float = 0.5
        let status = getFn(CGMainDisplayID(), &val)
        if status == 0 {
            return max(0.0, min(1.0, val))
        }
        return currentBrightness
    }
    
    /// Ajusta el brillo del monitor principal (0.0 a 1.0)
    public func setBrightness(_ value: Float) {
        let clamped = max(0.0, min(1.0, value))
        self.currentBrightness = clamped
        self.lastPolledBrightness = clamped
        
        if isFrameworkAvailable, let setFn = setBrightnessPtr {
            _ = setFn(CGMainDisplayID(), clamped)
        }
        
        // Publica o actualiza la actividad SliderPill en la Isla Dinámica (acción del usuario)
        publishBrightnessActivity(clamped)
    }
    
    /// Incrementa o decrementa el brillo en escalones estándar (1/16 = 0.0625) o finos (1/64 = 0.015625 con Shift+Option)
    public func stepBrightness(up: Bool, fine: Bool = false) {
        let step: Float = fine ? (1.0 / 64.0) : (1.0 / 16.0)
        let current = readCurrentBrightness()
        let newLevel = up ? min(1.0, current + step) : max(0.0, current - step)
        setBrightness(newLevel)
    }
    
    /// Publica la Live Activity de brillo en ActivityCenter con duración natural de 2.5 s
    public func publishBrightnessActivity(_ level: Float) {
        let activity = LiveActivity(
            id: "system_slider",
            priority: 85,
            style: .sliderPill,
            tint: .white,
            duration: 3.0,
            sliderState: .brightness(level: level)
        )
        
        ActivityCenter.shared.publish(activity)
    }
}
