import AppKit

/// Eje en el que se fija un gesto de 2 dedos.
public enum GestureAxis {
    case horizontal
    case vertical
}

/// Receptor de las decisiones de la máquina de estados (ver `NotchGestureDispatcher`).
public protocol TrackpadGestureDelegate: AnyObject {
    /// ¿El cursor está en la zona donde un gesto debe controlar el notch? Se consulta UNA vez al inicio del gesto.
    func gestureShouldBegin(at screenLocation: NSPoint) -> Bool
    /// ¿El contexto actual tiene acciones horizontales (paginación Música ↔ Bandeja)?
    func gestureAllowsHorizontal() -> Bool
    /// Avance continuo sobre el eje fijado. `translation` es el acumulado del gesto en ese eje
    /// (+ = dedos hacia abajo / derecha). Devuelve true si disparó una acción.
    func gestureMoved(axis: GestureAxis, translation: CGFloat, delta: CGFloat) -> Bool
    /// Paso de una rueda de ratón clásica (sin fases). Devuelve true si disparó una acción.
    func gestureDiscreteStep(axis: GestureAxis, direction: CGFloat) -> Bool
    /// El gesto terminó (dedos levantados, cancelado o perdido).
    func gestureEnded(triggered: Bool)
}

/// Máquina de estados finitos para los swipes de 2 dedos del trackpad.
///
///     idle ─began─▶ tracking ─(distancia mínima)─▶ locked(eje) ─(umbral)─▶ triggered
///                      │                              │                        │
///                      └──────── ended / cancelled ───┴────────────────────────┴─▶ absorbingInertia ─▶ idle
///
/// Reglas:
/// - Un gesto físico dispara como máximo UNA acción.
/// - La inercia (momentum) nunca dispara acciones: se absorbe hasta que termina.
/// - Un nuevo `.began` siempre reinicia la máquina, aunque quede inercia del gesto anterior:
///   no hay debounce por tiempo, así que dos swipes seguidos en < 100 ms funcionan.
/// - El eje se decide con el desplazamiento acumulado (no evento a evento), con sesgo vertical,
///   para que un swipe diagonal rápido no caiga en el overscroll horizontal.
public final class TrackpadGestureRecognizer {
    public enum State: Equatable {
        case idle
        case tracking
        case locked(GestureAxis)
        case triggered
        case rejected
        case absorbingInertia
    }

    /// Distancia acumulada (pt) antes de decidir el eje.
    public static var axisLockDistance: CGFloat = 2.5
    /// El gesto se considera vertical si |dy| ≥ |dx| × este factor (sesgo a favor de lo vertical).
    public static var verticalBias: CGFloat = 0.75
    /// Separación mínima entre pasos de una rueda de ratón clásica.
    public static var discreteStepInterval: TimeInterval = 0.35
    /// Si los dedos dejan de reportar eventos sin un `.ended`, el gesto se da por terminado.
    public static var lostGestureTimeout: TimeInterval = 0.45

    public weak var delegate: TrackpadGestureDelegate?
    public private(set) var state: State = .idle

    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var lastDiscreteActionTime: Date = .distantPast
    private var lostGestureWatchdog: DispatchWorkItem?

    public init() {}

    /// ¿Hay un gesto del notch en curso (dedos sobre el trackpad)?
    public var isGestureInProgress: Bool {
        switch state {
        case .tracking, .locked, .triggered: return true
        default: return false
        }
    }

    /// El mismo evento puede llegar por varias vías (ventana del notch, monitor local y global): se procesa
    /// una sola vez
    private var lastEventTimestamp: TimeInterval = -1
    private var lastEventResult = false
    
    /// Procesa un evento `.scrollWheel`. Devuelve true si el evento pertenece a un gesto del notch
    /// (quien lo recibió en el panel debe tragárselo).
    @discardableResult
    public func handle(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel else { return false }
        if event.timestamp == lastEventTimestamp { return lastEventResult }
        lastEventTimestamp = event.timestamp
        lastEventResult = process(event)
        return lastEventResult
    }
    
    private func process(_ event: NSEvent) -> Bool {
        // Rueda de ratón clásica: ni fase ni inercia
        if event.phase == [] && event.momentumPhase == [] {
            return handleDiscrete(event)
        }

        // Inercia: nunca dispara acciones
        if event.momentumPhase != [] {
            let absorbing = state == .absorbingInertia
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                if absorbing { state = .idle }
            }
            return absorbing
        }

        let phase = event.phase

        // Dedos apoyados sin moverse todavía
        if phase.contains(.mayBegin) {
            finishIfNeeded()
            state = .idle
            return false
        }

        if phase.contains(.began) || state == .idle || state == .absorbingInertia {
            begin()
        }

        let (fingerDx, fingerDy) = Self.fingerDeltas(of: event)

        switch state {
        case .tracking:
            accumX += fingerDx
            accumY += fingerDy
            if hypot(accumX, accumY) >= Self.axisLockDistance {
                let isVertical = abs(accumY) >= abs(accumX) * Self.verticalBias
                if !isVertical && !(delegate?.gestureAllowsHorizontal() ?? false) {
                    state = .rejected
                } else {
                    let axis: GestureAxis = isVertical ? .vertical : .horizontal
                    state = .locked(axis)
                    let translation = isVertical ? accumY : accumX
                    if delegate?.gestureMoved(axis: axis, translation: translation, delta: translation) == true {
                        state = .triggered
                    }
                }
            }
        case .locked(let axis):
            let delta = axis == .vertical ? fingerDy : fingerDx
            if axis == .vertical { accumY += delta } else { accumX += delta }
            let translation = axis == .vertical ? accumY : accumX
            if delegate?.gestureMoved(axis: axis, translation: translation, delta: delta) == true {
                state = .triggered
            }
        default:
            break
        }

        let belongsToNotch = state != .rejected

        if phase.contains(.ended) || phase.contains(.cancelled) {
            finishIfNeeded()
            state = .absorbingInertia
        } else {
            armLostGestureWatchdog()
        }
        return belongsToNotch
    }

    /// Normaliza los deltas a la dirección física de los dedos, sin importar "desplazamiento natural".
    /// dx > 0: dedos a la derecha · dy > 0: dedos hacia abajo (hacia el usuario).
    public static func fingerDeltas(of event: NSEvent) -> (CGFloat, CGFloat) {
        let inverted = event.isDirectionInvertedFromDevice
        let dx = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        let dy = inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
        return (dx, dy)
    }

    // MARK: - Transiciones

    private func begin() {
        finishIfNeeded()
        accumX = 0
        accumY = 0
        let inZone = delegate?.gestureShouldBegin(at: NSEvent.mouseLocation) ?? false
        state = inZone ? .tracking : .rejected
    }

    /// Notifica el fin del gesto actual (si había uno del notch) y vuelve a reposo.
    private func finishIfNeeded() {
        lostGestureWatchdog?.cancel()
        lostGestureWatchdog = nil
        let wasActive = isGestureInProgress
        let triggered = state == .triggered
        if wasActive {
            delegate?.gestureEnded(triggered: triggered)
        }
        if state != .absorbingInertia {
            state = .idle
        }
    }

    private func armLostGestureWatchdog() {
        lostGestureWatchdog?.cancel()
        guard isGestureInProgress else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.isGestureInProgress else { return }
            DNDLogger.log("TrackpadGestureRecognizer: gesto sin .ended, cerrándolo por seguridad")
            self.finishIfNeeded()
            self.state = .idle
        }
        lostGestureWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lostGestureTimeout, execute: item)
    }

    private func handleDiscrete(_ event: NSEvent) -> Bool {
        let (fingerDx, fingerDy) = Self.fingerDeltas(of: event)
        guard fingerDx != 0 || fingerDy != 0 else { return false }
        guard delegate?.gestureShouldBegin(at: NSEvent.mouseLocation) == true else { return false }
        guard Date().timeIntervalSince(lastDiscreteActionTime) >= Self.discreteStepInterval else { return true }

        let isVertical = abs(fingerDy) >= abs(fingerDx)
        if !isVertical && !(delegate?.gestureAllowsHorizontal() ?? false) { return false }
        let axis: GestureAxis = isVertical ? .vertical : .horizontal
        let direction: CGFloat = (isVertical ? fingerDy : fingerDx) > 0 ? 1 : -1
        if delegate?.gestureDiscreteStep(axis: axis, direction: direction) == true {
            lastDiscreteActionTime = Date()
        }
        return true
    }
}
