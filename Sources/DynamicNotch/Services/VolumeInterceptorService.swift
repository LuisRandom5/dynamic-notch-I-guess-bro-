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
        if isIntercepting {
            self.hasAccessibilityPermission = true
            return true
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        self.hasAccessibilityPermission = trusted
        return trusted
    }
    
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Monitor periódico cada 1.0s: intenta conectar el interceptor en automático
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isIntercepting {
                self.startInterception()
            }
        }
    }
    
    private var activeKeysDown: Set<Int> = []
    private var lastBrightnessStepTime: CFAbsoluteTime = 0
    
    public func startInterception() {
        guard eventTap == nil else { return }
        
        let sysDefinedMask = CGEventMask(1 << NX_SYSDEFINED)
        let fullMask = sysDefinedMask | CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        
        // El evento que se deja pasar se devuelve SIN retener: con passRetained cada tecla pulsada quedaba en
        // memoria para siempre (miles de CGEvent por hora)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            // Re-activar si macOS deshabilitó el tap temporalmente por timeout
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let instance = Unmanaged<VolumeInterceptorService>.fromOpaque(refcon).takeUnretainedValue()
                    instance.reenableTap()
                }
                return Unmanaged.passUnretained(event)
            }
            
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }
            let service = Unmanaged<VolumeInterceptorService>.fromOpaque(refcon).takeUnretainedValue()
            
            // Captura de keyCodes virtuales especiales de brillo en teclados Apple Silicon (144 = Up, 145 = Down)
            if type == .keyDown || type == .keyUp {
                let vk = Int(event.getIntegerValueField(.keyboardEventKeycode))
                guard vk == 144 || vk == 145 else {
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - service.lastBrightnessStepTime > 0.035 {
                        service.lastBrightnessStepTime = now
                        let flags = event.flags
                        let isFine = flags.contains(.maskShift) && flags.contains(.maskAlternate)
                        let isUp = (vk == 144)
                        DispatchQueue.main.async {
                            BrightnessService.shared.stepBrightness(up: isUp, fine: isFine)
                        }
                    }
                }
                return service.suppressNativeHUD ? nil : Unmanaged.passUnretained(event)
            }
            
            guard type.rawValue == UInt32(NX_SYSDEFINED) else {
                return Unmanaged.passUnretained(event)
            }
            
            // Inspeccionar evento multimedia NX_SYSDEFINED (subtype 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS).
            // NOTA CRÍTICA: En AppKit, `NSEvent.EventSubtype.screenChanged` también vale 8 y emite
            // `data1 == 0x00020000` (`keyCode == 2`, `keyFlags == 0x0000`, `keyState == 0x00`).
            // Por ello exigimos estrictamente `keyState == 0x0A` (NX_KEYDOWN) o `0x0B` (NX_KEYUP)
            // y `keyRepeat == 0` o `1`, descartando cualquier evento de cambio de ventana/pantalla.
            guard let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            
            let data1 = UInt32(truncatingIfNeeded: nsEvent.data1)
            let keyCode = Int((data1 & 0xFFFF0000) >> 16)
            let keyFlags = Int(data1 & 0x0000FFFF)
            let keyState = (keyFlags & 0xFF00) >> 8
            let keyRepeat = keyFlags & 0x00FF
            
            guard (keyState == 0x0A || keyState == 0x0B), (keyRepeat == 0 || keyRepeat == 1) else {
                return Unmanaged.passUnretained(event)
            }
            
            let isKeyDown = (keyState == 0x0A)
            if isKeyDown {
                if keyRepeat == 0 {
                    service.activeKeysDown.insert(keyCode)
                } else if !service.activeKeysDown.contains(keyCode) {
                    // Ignorar auto-repeat huérfano si nunca hubo un keyDown físico inicial
                    return Unmanaged.passUnretained(event)
                }
            } else {
                service.activeKeysDown.remove(keyCode)
            }
            
            // MARK: 1) TECLAS DE VOLUMEN Y MUTE (0 = Up, 1 = Down, 7 = Mute)
            if keyCode == 0 || keyCode == 1 || keyCode == 7 {
                if isKeyDown {
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
                
                if service.suppressNativeHUD {
                    return nil
                } else {
                    return Unmanaged.passUnretained(event)
                }
            }
            
            // MARK: 2) TECLAS DE BRILLO (2/145 = Brightness Up, 3/144 = Brightness Down)
            if keyCode == 2 || keyCode == 3 || keyCode == 145 || keyCode == 144 {
                if isKeyDown {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - service.lastBrightnessStepTime > 0.035 {
                        service.lastBrightnessStepTime = now
                        let isShiftOption = (keyFlags & 0x0008) != 0 || (nsEvent.modifierFlags.contains(.shift) && nsEvent.modifierFlags.contains(.option))
                        let isUp = (keyCode == 2 || keyCode == 145)
                        DispatchQueue.main.async {
                            BrightnessService.shared.stepBrightness(up: isUp, fine: isShiftOption)
                        }
                    }
                }
                
                if service.suppressNativeHUD {
                    return nil
                } else {
                    return Unmanaged.passUnretained(event)
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        let observerSelf = Unmanaged.passUnretained(self).toOpaque()
        
        // Intentar primero con .cghidEventTap (upstream donde entran los eventos antes de OSDUIHelper)
        var createdTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: fullMask,
            callback: callback,
            userInfo: observerSelf
        )
        
        if createdTap == nil {
            createdTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: sysDefinedMask,
                callback: callback,
                userInfo: observerSelf
            )
        }
        
        // Si .cghidEventTap no está disponible, intentar con .cgSessionEventTap
        if createdTap == nil {
            createdTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: sysDefinedMask,
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
        self.hasAccessibilityPermission = true
        DNDLogger.log("✅ VolumeInterceptorService: Interceptor multimedia activo")
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
