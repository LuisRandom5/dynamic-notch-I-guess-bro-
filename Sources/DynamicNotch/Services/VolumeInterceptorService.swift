import AppKit
import Carbon
import CoreAudio

// MARK: - Volume & Media Keys Interceptor Service
/// Intercepta las teclas multimedia a bajo nivel (`NX_SYSDEFINED`) utilizando un `CGEventTap` (.cghidEventTap).
/// Captura y gestiona en exclusiva:
/// - Volumen: `0` (Subir), `1` (Bajar), `7` (Silenciar / Mute)
/// - Brillo: `2`, `145` (Subir), `3`, `144` (Bajar)
///
/// Si `suppressNativeHUD` está activado, retorna `nil` para descartar el evento antes de que
/// llegue a `OSDUIHelper` de macOS, eliminando el HUD cuadrado gris y gestionando el cambio
/// exclusivamente dentro de la Isla Dinámica con la plantilla SliderPill.
public final class VolumeInterceptorService: ObservableObject {
    public static let shared = VolumeInterceptorService()
    
    @Published public private(set) var isIntercepting: Bool = false
    @Published public private(set) var hasAccessibilityPermission: Bool = false
    @Published public var suppressNativeHUD: Bool = true // Elección del usuario: suprimir HUD nativo
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    
    private init() {
        _ = checkPermission()
        startInterception()
        startHealthCheck()
    }
    
    public func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        self.hasAccessibilityPermission = trusted
        return trusted
    }
    
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Monitor periódico cada 1.5s: si el usuario otorga el permiso de Accesibilidad
    /// mientras la app está abierta, el interceptor se conecta inmediatamente en automático.
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = self.checkPermission()
            if trusted && !self.isIntercepting {
                self.startInterception()
            }
        }
    }
    
    public func startInterception() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << NX_SYSDEFINED)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            // Re-activar si macOS deshabilitó el tap temporalmente por timeout
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let instance = Unmanaged<VolumeInterceptorService>.fromOpaque(refcon).takeUnretainedValue()
                    instance.reenableTap()
                }
                return Unmanaged.passRetained(event)
            }
            
            guard type.rawValue == UInt32(NX_SYSDEFINED) else {
                return Unmanaged.passRetained(event)
            }
            
            // Inspeccionar evento multimedia NX_SYSDEFINED (subtype 8 = teclas auxiliares del sistema)
            let nsEvent = NSEvent(cgEvent: event)
            guard let nsEvent = nsEvent, nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passRetained(event)
            }
            
            let data1 = nsEvent.data1
            let keyCode = Int((data1 & 0xFFFF0000) >> 16)
            let keyFlags = (data1 & 0x0000FFFF)
            let isKeyUp = ((keyFlags & 0xFF00) >> 8) == 0xB
            
            guard let refcon = refcon else {
                return Unmanaged.passRetained(event)
            }
            let service = Unmanaged<VolumeInterceptorService>.fromOpaque(refcon).takeUnretainedValue()
            
            // MARK: 1) TECLAS DE VOLUMEN Y MUTE (0 = Up, 1 = Down, 7 = Mute)
            if keyCode == 0 || keyCode == 1 || keyCode == 7 {
                if !isKeyUp {
                    DispatchQueue.main.async {
                        if keyCode == 0 {
                            AudioDeviceService.shared.stepVolume(up: true)
                        } else if keyCode == 1 {
                            AudioDeviceService.shared.stepVolume(up: false)
                        } else if keyCode == 7 {
                            AudioDeviceService.shared.setMuted(!AudioDeviceService.shared.isMuted)
                        }
                    }
                }
                
                // Si el usuario eligió suprimir el HUD nativo, retornar nil para que macOS no pinte su HUD gris
                if service.suppressNativeHUD {
                    return nil
                } else {
                    return Unmanaged.passRetained(event)
                }
            }
            
            // MARK: 2) TECLAS DE BRILLO (2/145 = Brightness Up, 3/144 = Brightness Down)
            if keyCode == 2 || keyCode == 3 || keyCode == 145 || keyCode == 144 {
                if !isKeyUp {
                    DispatchQueue.main.async {
                        let isUp = (keyCode == 2 || keyCode == 145)
                        BrightnessService.shared.stepBrightness(up: isUp)
                    }
                }
                
                // Si el usuario eligió suprimir el HUD nativo, retornar nil
                if service.suppressNativeHUD {
                    return nil
                } else {
                    return Unmanaged.passRetained(event)
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        let observerSelf = Unmanaged.passUnretained(self).toOpaque()
        
        // Intentar primero con .cghidEventTap (upstream donde entran los eventos antes de OSDUIHelper)
        var createdTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: observerSelf
        )
        
        // Si .cghidEventTap no está disponible, intentar con .cgSessionEventTap
        if createdTap == nil {
            createdTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: observerSelf
            )
        }
        
        guard let tap = createdTap else {
            self.isIntercepting = false
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.isIntercepting = true
    }
    
    public func reenableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    public func stopInterception() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        isIntercepting = false
    }
}
