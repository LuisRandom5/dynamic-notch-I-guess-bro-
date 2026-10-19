import SwiftUI
import Combine
import AppKit

/// Bolita que se va: conserva su lugar (índice) para reabsorberse en el lado del notch donde estaba
public struct DepartingSatellite: Identifiable {
    public let id: String
    public let activity: LiveActivity
    public let index: Int
}

public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()
    
    // MARK: - Estado de Actividades
    @Published public private(set) var currentActivity: LiveActivity?
    @Published public private(set) var activeActivities: [LiveActivity] = []
    @Published public private(set) var dismissingActivityId: String? = nil
    @Published public private(set) var lastDismissedActivity: LiveActivity? = nil
    
    // MARK: - Roles Multi-Actividad (Modo A y Modo B)
    @Published public private(set) var secondaryActivities: [LiveActivity] = []
    @Published public private(set) var overflowActivities: [LiveActivity] = []
    @Published public private(set) var overflowCount: Int = 0
    /// Bolitas que se están reabsorbiendo en el notch (dejaron de estar a la vista): se siguen dibujando
    /// mientras dura la absorción (ver LiquidSatelliteHost)
    @Published public private(set) var departingSatellites: [DepartingSatellite] = []
    /// 3 actividades a la vista: bolitas y mínima pegada en ancho limitado (ver PresentationDecision)
    @Published public private(set) var isLimitedWidth: Bool = false
    
    // MARK: - Coordinador de Morfeo Líquido y Fusión (Bolita <-> Notch)
    @Published public var fusingActivityId: String? = nil
    @Published public var fusionProgress: CGFloat = 0.0 // 0.0 (satélite) -> 1.0 (en contacto con el notch)
    @Published public var fusionSide: SatelliteSide = .right
    @Published public var expandedActivity: LiveActivity? = nil
    @Published public var isFusing: Bool = false
    
    // Dimensiones y curvatura de tarjeta personalizada
    @Published public var customCardWidth: CGFloat? = nil
    @Published public var customCardHeight: CGFloat? = nil
    @Published public var customTopRadius: CGFloat? = nil
    @Published public var customBottomRadius: CGFloat? = nil
    
    private var dismissTimers: [String: Timer] = [:]
    private var fusionExpansionTimer: Timer?
    private var lastRoleChangeTime: Date = Date.distantPast
    /// Orden del carrusel elegido con el swipe a lo ancho (vale mientras no empiece ni termine una actividad)
    private var userOrder: [String]?
    /// Actividad que el usuario trajo al notch con un clic (vale mientras exista)
    private var preferredPrimaryId: String?
    private let hysteresisDuration: TimeInterval = 3.0 // 3s de estabilidad de rol
    
    private var playbackObserver: AnyCancellable?
    
    /// Física de las bolitas sobre el borde derecho de la cápsula (pt): se recoge al desprenderse una gota
    /// y se abulta al absorberla, con rebote elástico (ver ElasticPillShape.trailingImpulse)
    @Published public private(set) var pillImpulse: CGFloat = 0
    private var impulseToken = 0
    
    /// Alerta en curso (ver presentAlert): si el usuario interactúa, la tarjeta ya no se cierra sola
    private var alertingActivityId: String?
    /// Última alerta por actividad (ActivityLifecycle.shouldAlert no repite antes de 30 s)
    private var lastAlertAt: [String: Date] = [:]
    /// Actividades cuyo contenido ya no está al día (staleDate vencida): se dibujan atenuadas
    @Published public private(set) var staleActivityIds: Set<String> = []
    /// Revisión periódica del ciclo de vida: 8 h máximo y contenido obsoleto
    private var lifecycleTimer: Timer?
    private var staleTimer: Timer?
    /// Actividades terminadas mostrando su resumen antes de irse (ver end)
    private var endTimers: [String: Timer] = [:]
    
    /// Alerta de la Isla Dinámica: ante una actualización importante (terminó, necesita atención), la
    /// actividad se expande un momento para mostrarla y regresa sola a su lugar. Sólo si nada más ocupa el
    /// notch (no interrumpe al usuario).
    public func presentAlert(id: String, duration: TimeInterval? = nil) {
        guard AppState.shared.liveActivityAlertsEnabled else { return }
        let duration = duration ?? AppState.shared.liveActivityAlertDuration
        guard let activity = activeActivities.first(where: { $0.id == id }),
              expandedActivity == nil, !isFusing,
              AppState.shared.mode != .expanded, AppState.shared.mode != .shelf,
              !AppState.shared.isHovered else { return }
        if secondaryActivities.contains(where: { $0.id == id }) {
            // Bolita: se funde con el notch y muestra su tarjeta
            alertingActivityId = id
            initiateFusion(for: activity)
        } else if currentActivity?.id == id, activity.expandedView != nil {
            // En el notch: se expande en su tarjeta
            alertingActivityId = id
            expandActivity(activity)
        } else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.finishAlert(id: id)
        }
    }
    
    /// El usuario tocó: la tarjeta abierta por una alerta pasa a ser suya (no se cierra sola)
    public func cancelAlertAutoCollapse() {
        alertingActivityId = nil
    }
    
    private func finishAlert(id: String) {
        guard alertingActivityId == id else { return }
        // El cursor está encima: el usuario la está viendo, se queda hasta que se vaya
        if AppState.shared.isHovered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.finishAlert(id: id) }
            return
        }
        alertingActivityId = nil
        if expandedActivity?.id == id {
            collapseExpandedActivity()
        }
    }
    
    /// Último clic atendido por una bolita: el panel lo consulta para no tomarlo también como tap al notch
    public var lastSatelliteTapAt: Date = .distantPast
    
    /// Cambio de rol escalonado de una misma actividad (notch ⇄ bolita). Si el notch cambiara de ancho
    /// mientras la bolita entra o sale, se encimarían; así primero termina un movimiento y luego empieza el otro:
    /// - hacia el notch: la bolita se reabsorbe y DESPUÉS el notch se expande con la actividad
    /// - hacia la bolita: el notch se recoge y DESPUÉS la bolita brota de él
    private struct RoleHandoff {
        let id: String
        let toPrimary: Bool
        let until: Date
    }
    private var roleHandoff: RoleHandoff?
    
    /// Después del HUD de volumen/brillo, lo que había en el notch (reproductor, temporizador…) se queda
    /// escondido un momento antes de volver, como en la Isla Dinámica: el notch queda limpio y luego regresa.
    public static var hudReturnDelay: TimeInterval { AppState.shared.hudReturnDelay }
    private var hudHoldUntil: Date = .distantPast
    private static let reabsorbDuration: TimeInterval = 0.70
    private static let notchSettleDuration: TimeInterval = 0.56
    
    private init() {}
    
    /// Recalcula los roles cuando empieza o se detiene la música/video: un temporizador cede el notch
    /// (y pasa a bolita) mientras algo suena, y lo recupera cuando se detiene.
    /// Se llama una vez al arrancar, después de crear los servicios.
    public func startObservingPlayback() {
        guard playbackObserver == nil else { return }
        playbackObserver = MusicService.shared.$currentTrack
            .map(\.isPlaying)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateRoles()
            }
    }
    
    /// Actividades "de fondo" (temporizador, cronómetro) que viven como bolita mientras suena algo.
    private func yieldsToPlayback(_ activity: LiveActivity) -> Bool {
        AppState.shared.timerYieldsToMusic && activity.kind == .timer && !activity.isUrgent && MusicService.shared.currentTrack.isPlaying
    }
    
    // MARK: - Publicación y Actualización
    
    /// Publica o actualiza una actividad según las reglas de prioridad y actualización en sitio
    public func publish(_ activity: LiveActivity) {
        // Durante la pausa posterior al HUD, las actualizaciones de otras actividades (temporizador, Claude…)
        // no deben hacer reaparecer el reproductor antes de tiempo
        if Date() >= hudHoldUntil || activity.style == .sliderPill || activity.style == .airpodsPill {
            AppState.shared.isHoldingBareNotch = false
        }
        
        if dismissingActivityId == activity.id {
            dismissingActivityId = nil
        }
        
        // La alerta es de esta actualización: se presenta una vez y no se guarda con la actividad
        let alert = activity.alert
        var activity = activity
        activity.alert = nil
        // Vuelve a estar en curso: cancela su cierre pendiente
        if activity.state != .finished, let pending = endTimers.removeValue(forKey: activity.id) {
            pending.invalidate()
        }
        startLifecycleTimerIfNeeded()
        defer {
            refreshStaleActivities()
            if let alert { scheduleAlert(id: activity.id, configuration: alert, isUrgent: activity.isUrgent) }
        }
        
        // Actualización en sitio si ya existe
        if let index = activeActivities.firstIndex(where: { $0.id == activity.id }) {
            // Conserva cuándo empezó: es el desempate de la Isla Dinámica (gana la que se inició primero)
            activity.createdAt = activeActivities[index].createdAt
            activeActivities[index] = activity
            if currentActivity?.id == activity.id {
                currentActivity = activity
            }
            if expandedActivity?.id == activity.id {
                expandedActivity = activity
            }
            rescheduleTimer(for: activity)
            recalculateRoles()
            return
        }
        
        // Nueva actividad
        activeActivities.append(activity)
        rescheduleTimer(for: activity)
        recalculateRoles()
    }
    
    /// Alto dinámico de la expandida (IslandExpandedTemplate): la tarjeta se ajusta a lo que mide su contenido,
    /// dentro del rango de Apple, y cambia con una animación de layout cuando llega más o menos información
    public func reportExpandedContentHeight(_ height: CGFloat) {
        guard expandedActivity != nil, height > 0 else { return }
        let target = IslandMetrics.expandedHeight(forContent: height)
        guard abs((customCardHeight ?? 0) - target) > 0.5 else { return }
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.42, dampingFraction: 0.86)) {
            customCardHeight = target
        }
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    // MARK: - Ciclo de vida: alertas, 8 h, obsoleto y cierre con resumen
    
    /// Alerta de una actualización (ActivityAlertConfiguration): se espera un instante para que la bolita o el
    /// notch se asienten y se aplica la política (no si el usuario está usando el notch, no más de una cada 30 s)
    private func scheduleAlert(id: String, configuration: ActivityAlertConfiguration, isUrgent: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.activeActivities.contains(where: { $0.id == id }) else { return }
            let app = AppState.shared
            let userIsBusy = self.expandedActivity != nil || self.isFusing || app.isHovered
                || app.mode == .expanded || app.mode == .shelf
            guard ActivityLifecycle.shouldAlert(enabled: app.liveActivityAlertsEnabled, isUrgent: isUrgent,
                                                userIsBusy: userIsBusy, lastAlertAt: self.lastAlertAt[id], now: Date()) else { return }
            self.lastAlertAt[id] = Date()
            if configuration.sound && app.liveActivityAlertSound {
                NSSound(named: "Tink")?.play()
            }
            self.presentAlert(id: id, duration: configuration.duration)
        }
    }
    
    /// Termina una actividad como la Isla Dinámica: muestra su estado final (resumen) un momento y se va.
    /// - final: el último contenido (se publica como terminado); nil = el que ya tiene
    /// - dismissAfter: cuánto se queda el resumen (nil = ajuste "Resumen al terminar")
    /// - onRemove: limpieza del proveedor al irse; si no hay, se quita de la isla
    public func end(id: String, final: LiveActivity? = nil, dismissAfter: TimeInterval? = nil, onRemove: (() -> Void)? = nil) {
        if var final {
            final.state = .finished
            publish(final)
        }
        endTimers[id]?.invalidate()
        let delay = dismissAfter ?? AppState.shared.liveActivityEndSummaryDuration
        let finish: () -> Void = { [weak self] in
            guard let self = self else { return }
            // Si el usuario tiene su tarjeta abierta, espera a que la cierre
            if self.expandedActivity?.id == id && self.alertingActivityId != id {
                self.end(id: id, dismissAfter: 5, onRemove: onRemove)
                return
            }
            self.endTimers[id] = nil
            if let onRemove {
                onRemove()
            } else if self.currentActivity?.id == id {
                self.dismissWithAnimation(id: id)
            } else {
                self.remove(id: id)
            }
        }
        guard delay > 0 else { finish(); return }
        let timer = Timer(timeInterval: delay, repeats: false) { _ in finish() }
        RunLoop.main.add(timer, forMode: .common)
        endTimers[id] = timer
    }
    
    private func startLifecycleTimerIfNeeded() {
        guard lifecycleTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.sweepLifecycle() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        lifecycleTimer = timer
    }
    
    /// Cada 30 s: termina lo que pasó de 8 h (la repisa no es una actividad con fin) y marca lo obsoleto
    private func sweepLifecycle() {
        let now = Date()
        let expired = activeActivities.filter {
            $0.id != ShelfActivityProvider.activityId && ActivityLifecycle.isExpired(createdAt: $0.createdAt, now: now)
        }
        for activity in expired {
            DNDLogger.log("ActivityCenter: '\(activity.id)' llegó a 8 h; se termina")
            activity.onDismiss?()
            end(id: activity.id, dismissAfter: 0)
        }
        refreshStaleActivities()
        if activeActivities.isEmpty {
            lifecycleTimer?.invalidate()
            lifecycleTimer = nil
        }
    }
    
    /// Marca lo obsoleto y programa la revisión justo para la próxima `staleDate` (no espera al barrido)
    private func refreshStaleActivities() {
        let now = Date()
        let stale = Set(activeActivities.filter { ActivityLifecycle.isStale(staleDate: $0.staleDate, now: now) }.map(\.id))
        if stale != staleActivityIds { staleActivityIds = stale }
        staleTimer?.invalidate()
        staleTimer = nil
        if let next = activeActivities.compactMap(\.staleDate).filter({ $0 > now }).min() {
            let timer = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
                self?.refreshStaleActivities()
            }
            RunLoop.main.add(timer, forMode: .common)
            staleTimer = timer
        }
    }
    
    /// Alias para compatibilidad
    public func show(_ activity: LiveActivity) {
        publish(activity)
    }
    
    /// Quita una actividad por su ID de forma inmediata
    public func remove(id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        endTimers.removeValue(forKey: id)?.invalidate()
        lastAlertAt[id] = nil
        if staleActivityIds.contains(id) { staleActivityIds.remove(id) }
        if dismissingActivityId == id {
            dismissingActivityId = nil
        }
        
        if expandedActivity?.id == id {
            // La tarjeta abierta se recoge hacia el notch con su animación (antes desaparecía de golpe, p. ej.
            // cuando termina la sesión de Claude con su tarjeta abierta)
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.36, dampingFraction: 0.85)) {
                expandedActivity = nil
                customCardWidth = nil
                customCardHeight = nil
                customTopRadius = nil
                customBottomRadius = nil
            }
            fusionExpansionTimer?.invalidate()
            fusionExpansionTimer = nil
            fusingActivityId = nil
            isFusing = false
            fusionProgress = 0.0
        }
        
        NotificationActivityProvider.shared.handleActivityRemoved(id: id)
        AgentActivityProvider.shared.handleActivityRemoved(id: id)
        
        let wasCurrent = currentActivity?.id == id
        activeActivities.removeAll(where: { $0.id == id })
        if wasCurrent || activeActivities.isEmpty {
            customCardWidth = nil
            customCardHeight = nil
            customTopRadius = nil
            customBottomRadius = nil
        }
        recalculateRoles()
        if currentActivity == nil {
            AppState.shared.isHoldingBareNotch = false
            AppState.shared.reconcileCompactMode()
        }
    }
    
    public func pauseDismissTimer(for id: String) {
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
    }
    
    /// Cierre animado coordinado hacia el notch
    public func dismissWithAnimation(id: String) {
        guard let current = currentActivity, current.id == id else {
            remove(id: id)
            return
        }
        
        dismissTimers[id]?.invalidate()
        dismissTimers.removeValue(forKey: id)
        dismissingActivityId = id
        lastDismissedActivity = current
        
        NotificationActivityProvider.shared.handleActivityRemoved(id: id)
        AgentActivityProvider.shared.handleActivityRemoved(id: id)
        
        let isCard = current.style == .card
        let duration = isCard ? ExitAnimationMetrics.cardDismissDuration : ExitAnimationMetrics.sliderDismissDuration
        
        if isCard && AppState.shared.mode == .compact && MusicService.shared.hasActiveMusic {
            AppState.shared.isHoldingBareNotch = true
        }
        
        // HUD del sistema (volumen/brillo) y animación de AirPods: al cerrarse, el notch se recoge por completo
        // y queda limpio unos segundos; después lo que había (p. ej. el reproductor) vuelve a abrirse con su
        // animación, como en el sistema (antes la de AirPods saltaba directo al reproductor)
        let isSystemHUD = current.style == .sliderPill || current.style == .airpodsPill
        if isSystemHUD {
            hudHoldUntil = Date().addingTimeInterval(duration + Self.hudReturnDelay)
            if MusicService.shared.hasActiveMusic {
                AppState.shared.isHoldingBareNotch = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.activeActivities.removeAll(where: { $0.id == id })
            self.customCardWidth = nil
            self.customCardHeight = nil
            self.customTopRadius = nil
            self.customBottomRadius = nil
            self.recalculateRoles()
            self.dismissingActivityId = nil
            
            if isSystemHUD {
                let holdUntil = self.hudHoldUntil
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, holdUntil.timeIntervalSinceNow)) {
                    // Otro HUD extendió la pausa: ese se encarga de terminarla
                    guard self.hudHoldUntil == holdUntil else { return }
                    withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                        AppState.shared.isHoldingBareNotch = false
                        self.recalculateRoles()
                        if self.currentActivity == nil {
                            AppState.shared.reconcileCompactMode()
                        }
                    }
                }
            } else if isCard && (AppState.shared.mode == .compact || AppState.shared.shouldShowCompact) && MusicService.shared.hasActiveMusic {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard self.currentActivity == nil else {
                        AppState.shared.isHoldingBareNotch = false
                        return
                    }
                    withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                        AppState.shared.isHoldingBareNotch = false
                        AppState.shared.reconcileCompactMode()
                    }
                }
            } else {
                AppState.shared.isHoldingBareNotch = false
                if self.currentActivity == nil {
                    AppState.shared.reconcileCompactMode()
                }
            }
        }
    }
    
    // MARK: - Motor de Prioridad y Selección con Histéresis
    
    public func recalculateRoles() {
        guard !activeActivities.isEmpty else {
            registerDepartures(from: secondaryActivities, to: [])
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.35, dampingFraction: 0.82)) {
                self.currentActivity = nil
                self.secondaryActivities = []
                self.overflowActivities = []
                self.overflowCount = 0
                self.isLimitedWidth = false
            }
            if expandedActivity != nil {
                collapseExpandedActivity()
            }
            return
        }
        
        // La política (orden, histéresis, HUD, bolitas y cola) vive en PresentationEngine, sin estado global
        let now = Date()
        let maxSatellites = max(1, AppState.shared.maxSatelliteBolitas)
        let satelliteSlots = AppState.shared.multiActivityMode == .modeA ? maxSatellites : 1
        let decision = PresentationEngine.decide(
            candidates: activeActivities.map(presentationCandidate),
            currentPrimaryId: currentActivity?.id,
            lastRoleChangeTime: lastRoleChangeTime,
            hudHoldUntil: hudHoldUntil,
            now: now,
            policy: .init(hysteresis: hysteresisDuration, satelliteSlots: satelliteSlots),
            previousSecondaryIds: secondaryActivities.map(\.id),
            userOrder: userOrder,
            preferredPrimaryId: preferredPrimaryId
        )
        lastRoleChangeTime = decision.lastRoleChangeTime
        if !decision.appliedUserOrder { userOrder = nil }
        if let preferred = preferredPrimaryId, !activeActivities.contains(where: { $0.id == preferred }) {
            preferredPrimaryId = nil
        }
        let activitiesById = Dictionary(activeActivities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let primaryId = decision.primaryId
        let chosenPrimary = primaryId.flatMap { activitiesById[$0] }
        var newSecondaries = decision.secondaryIds.compactMap { activitiesById[$0] }
        let newOverflow = decision.overflowIds.compactMap { activitiesById[$0] }
        
        // Detección de un cambio de rol notch ⇄ bolita (ver RoleHandoff)
        if let handoff = roleHandoff, handoff.until <= now { roleHandoff = nil }
        if roleHandoff == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if let promoted = primaryId, secondaryActivities.contains(where: { $0.id == promoted }) {
                beginRoleHandoff(id: promoted, toPrimary: true, duration: Self.reabsorbDuration)
            } else if let demoted = currentActivity?.id, demoted != primaryId,
                      newSecondaries.contains(where: { $0.id == demoted }) {
                beginRoleHandoff(id: demoted, toPrimary: false, duration: Self.notchSettleDuration)
            }
        }
        
        // Primer tiempo del cambio escalonado: la actividad que cambia de rol no está en ningún lado
        var displayedPrimary = chosenPrimary
        if let handoff = roleHandoff {
            if handoff.toPrimary {
                // El notch conserva lo que mostraba mientras la bolita se reabsorbe
                displayedPrimary = currentActivity.flatMap { held in
                    held.id == handoff.id ? nil : activeActivities.first(where: { $0.id == held.id })
                }
            }
            newSecondaries.removeAll { $0.id == handoff.id || $0.id == displayedPrimary?.id }
        }
        
        // Física: una gota nueva a la derecha se desprende (la cápsula retrocede); una que se va se absorbe
        // (la cápsula se abulta al recibirla). Sólo con el notch cerrado y sin la bolita que se está fundiendo.
        let oldRightId = secondaryActivities.first?.id
        let newRightId = newSecondaries.first?.id
        if oldRightId != newRightId {
            if newRightId != nil && oldRightId == nil {
                firePillImpulse(.detach)
            } else if let gone = oldRightId, newRightId == nil, gone != fusingActivityId {
                firePillImpulse(.absorb)
            }
        }
        
        registerDepartures(from: secondaryActivities, to: newSecondaries)
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.35, dampingFraction: 0.82)) {
            self.currentActivity = displayedPrimary
            self.secondaryActivities = newSecondaries
            self.overflowActivities = newOverflow
            self.overflowCount = newOverflow.count
            if self.isLimitedWidth != (newSecondaries.count >= 2) { self.isLimitedWidth = newSecondaries.count >= 2 }
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Lado de la bolita en el lugar `index`: la segunda va a la izquierda si el usuario quiere ambos lados
    public static func satelliteSideKey(index: Int) -> String {
        AppState.shared.bubblesOnBothSides && index == 1 ? "L" : "R"
    }
    
    /// Las bolitas que dejan de verse en su lado se siguen dibujando mientras se reabsorben en el notch. Cuenta
    /// el lado: una que pasa de izquierda a derecha (swipe) se reabsorbe de un lado y brota del otro.
    private func registerDepartures(from old: [LiveActivity], to new: [LiveActivity]) {
        let newKeys = Set(new.enumerated().map { "\($0.element.id)|\(Self.satelliteSideKey(index: $0.offset))" })
        // Si vuelve a su lado antes de terminar de irse, deja de irse
        departingSatellites.removeAll { newKeys.contains("\($0.activity.id)|\(Self.satelliteSideKey(index: $0.index))") }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, expandedActivity == nil, !isFusing else { return }
        for (index, activity) in old.enumerated() where !newKeys.contains("\(activity.id)|\(Self.satelliteSideKey(index: index))") {
            let token = "\(activity.id)#\(UUID().uuidString.prefix(8))"
            departingSatellites.append(DepartingSatellite(id: token, activity: activity, index: index))
            DispatchQueue.main.asyncAfter(deadline: .now() + LiquidSatelliteHost<EmptyView>.departureDuration) { [weak self] in
                self?.departingSatellites.removeAll { $0.id == token }
            }
        }
    }
    
    /// Traduce una actividad a lo que necesita el motor de presentación
    private func presentationCandidate(_ activity: LiveActivity) -> PresentationCandidate {
        let canBePrimary: Bool
        if activity.style == .sliderPill {
            canBePrimary = false
        } else if activity.kind == .claude || activity.id == ShelfActivityProvider.activityId {
            // Claude y la repisa viven siempre como bolita satélite
            canBePrimary = false
        } else if yieldsToPlayback(activity) {
            // La música o el video toman el notch; el temporizador sigue visible como bolita en vivo
            canBePrimary = false
        } else if activity.kind == .agentAI {
            // El progreso de IA en segundo plano nunca ocupa el notch: sólo una interacción modal activa
            // (pregunta o solicitud de permiso)
            canBePrimary = AgentActivityProvider.shared.isActive && activity.id.hasPrefix("agent_") && activity.id != "agent_live_progress"
        } else {
            canBePrimary = true
        }
        return PresentationCandidate(
            id: activity.id,
            // Relevancia dinámica: la que pide atención (p. ej. Claude esperando permiso) sube
            priority: ActivityRelevance.effective(base: activity.priority, needsAttention: activity.state == .attention),
            isUrgent: activity.isUrgent,
            createdAt: activity.createdAt,
            // HUD de volumen/brillo: se muestra siempre al instante y esconde lo que hubiera en el notch;
            // lo escondido no pasa a bolita (eso provocaría animaciones cruzadas)
            isSystemHUD: activity.style == .sliderPill,
            canBePrimary: canBePrimary
        )
    }
    
    private enum PillImpulse { case detach, absorb }
    
    /// Desprender: el extremo se ensancha 6 pt para dejar salir la gota y regresa con un rebote leve.
    /// Absorber: cuando la gota llega (~0.3 s, acelera como atraída), la cápsula se abulta 7 pt y se asienta
    /// con un pequeño sobrepaso elástico.
    private func firePillImpulse(_ kind: PillImpulse) {
        let mode = AppState.shared.mode
        guard mode != .expanded && mode != .shelf, expandedActivity == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        impulseToken += 1
        let token = impulseToken
        switch kind {
        case .detach:
            // Como en la Isla Dinámica: el extremo se ensancha un poco para dejar salir la gota y, cuando la
            // cintura se adelgaza, regresa con un pequeño retroceso elástico
            // Tiempos al ritmo de la gota (ver LiquidSatelliteHost)
            // Escalan con la duración de la gota (1.32 s fue la referencia) para seguir sincronizados con ella
            let k = LiquidMotionTuning.v.emergeResponse / 1.32
            withAnimation(.easeOut(duration: 0.36 * k)) { pillImpulse = CGFloat(LiquidMotionTuning.v.widenImpulse) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.44 * k) { [weak self] in
                guard let self = self, self.impulseToken == token else { return }
                withAnimation(.spring(response: 0.92 * k, dampingFraction: 0.62)) { self.pillImpulse = 0 }
            }
        case .absorb:
            let k = LiquidMotionTuning.v.absorbResponse / 1.12
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52 * k) { [weak self] in
                guard let self = self, self.impulseToken == token else { return }
                // Si mientras tanto el notch se desplegó (p. ej. la repisa), no abultar la tarjeta
                let mode = AppState.shared.mode
                guard mode != .expanded && mode != .shelf, self.expandedActivity == nil else { return }
                withAnimation(.easeOut(duration: 0.20 * k)) { self.pillImpulse = CGFloat(LiquidMotionTuning.v.absorbBulge) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20 * k) {
                    guard self.impulseToken == token else { return }
                    withAnimation(.spring(response: 0.80 * k, dampingFraction: 0.52)) { self.pillImpulse = 0 }
                }
            }
        }
    }
    
    private func beginRoleHandoff(id: String, toPrimary: Bool, duration: TimeInterval) {
        let delay = AnimationSpeedManager.shared.adjustedDuration(duration)
        let handoff = RoleHandoff(id: id, toPrimary: toPrimary, until: Date().addingTimeInterval(delay))
        roleHandoff = handoff
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.roleHandoff?.until == handoff.until else { return }
            self.roleHandoff = nil
            // Segundo tiempo: la actividad ocupa su nuevo lugar (con la histéresis ya resuelta)
            self.lastRoleChangeTime = .distantPast
            self.recalculateRoles()
        }
    }
    
    private func rescheduleTimer(for activity: LiveActivity) {
        dismissTimers[activity.id]?.invalidate()
        dismissTimers.removeValue(forKey: activity.id)
        
        if let duration = activity.duration, duration > 0 {
            let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if NotificationActivityProvider.shared.currentNotificationId == activity.id &&
                        NotificationActivityProvider.shared.isQuickReplyExpanded {
                        return
                    }
                    self?.dismissWithAnimation(id: activity.id)
                }
            }
            dismissTimers[activity.id] = timer
        }
    }
    
    // MARK: - Coordinador de Morfeo Líquido y Fusión (Bolita -> Notch -> Expansión)
    
    /// Inicia la animación de fusión orgánica en 2 fases con soporte para interrupción y reversibilidad:
    /// Fase 1: Bolita (micro-compresión 0.94x + haptic/audio) -> elongación direccional en el eje de movimiento -> fusión continua con el notch
    /// Fase 2: Cápsula se expande progresivamente hacia abajo (anclada arriba en y=0) revelando el contenido
    public func initiateFusion(for activity: LiveActivity, fromSide: SatelliteSide = .right) {
        // Interrupción interactiva: si ya está expandida esta misma actividad, colapsar suavemente
        if expandedActivity?.id == activity.id {
            collapseExpandedActivity()
            return
        }
        
        // Interrupción interactiva: si ya se está fusionando esta misma actividad, revertir suavemente hacia la bolita
        if isFusing && fusingActivityId == activity.id {
            reverseFusion(for: activity.id)
            return
        }
        
        // Interrupción interactiva: si hay otra actividad expandida, redirigir suavemente sin reiniciar bruscamente
        if let currentExp = expandedActivity, currentExp.id != activity.id {
            switchExpandedActivity(to: activity, fromSide: fromSide)
            return
        }
        
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        fusingActivityId = activity.id
        fusionSide = fromSide
        isFusing = true
        fusionProgress = 0.0
        
        // 1. Respuesta háptica y sonora inmediata
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        // Sin rebote: la bolita viaja con desaceleración natural y se funde (ver LiquidSatelliteModifier)
        let spring = AnimationSpeedManager.shared.spring(response: 0.34, dampingFraction: 0.92)
        let travelDuration = AnimationSpeedManager.shared.adjustedDuration(0.24)
        
        // 2. Fase 1: Desplazamiento orgánico y elongación sutil hacia la silueta del notch
        withAnimation(spring) {
            self.fusionProgress = 1.0
        }
        
        // 3. Fase 2: Expansión continua de la cápsula hacia abajo (anclada arriba en y=0)
        let timer = Timer(timeInterval: travelDuration, repeats: false) { [weak self] _ in
            guard let self = self, self.fusingActivityId == activity.id else { return }
            
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.40, dampingFraction: 0.82)) {
                self.expandedActivity = activity
                // Sin medidas propias: la plantilla expandida de Apple (ancho 408, alto según su contenido)
                self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
                self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
                self.customTopRadius = 24
                self.customBottomRadius = IslandExpandedTemplateMetrics.defaultOuterRadius
                self.recalculateRoles()
            }
            
            if activity.kind == .agentAI {
                AgentActivityProvider.shared.isProgressHUDExpanded = true
            }
            
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fusionExpansionTimer = timer
    }
    
    /// Revierte suavemente la transición en curso hacia la posición satélite compacta sin saltos visuales
    public func reverseFusion(for id: String) {
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playActionDismissed()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        
        let spring = AnimationSpeedManager.shared.spring(response: 0.34, dampingFraction: 0.82)
        let travelDuration = AnimationSpeedManager.shared.adjustedDuration(0.20)
        
        withAnimation(spring) {
            self.fusionProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + travelDuration) { [weak self] in
            guard let self = self else { return }
            if self.expandedActivity == nil {
                self.fusingActivityId = nil
                self.isFusing = false
            }
            self.recalculateRoles()
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    /// Redirige la transición hacia una nueva actividad desde el estado visual actual
    public func switchExpandedActivity(to newActivity: LiveActivity, fromSide: SatelliteSide = .right) {
        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        fusingActivityId = newActivity.id
        fusionSide = fromSide
        
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.38, dampingFraction: 0.82)) {
            self.expandedActivity = newActivity
            self.customCardWidth = newActivity.customExpandedWidth ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
            self.customCardHeight = newActivity.customExpandedHeight ?? (newActivity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
            self.customTopRadius = 24
            self.customBottomRadius = IslandExpandedTemplateMetrics.defaultOuterRadius
            self.fusionProgress = 1.0
            self.recalculateRoles()
        }
        
        if newActivity.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = true
        } else {
            AgentActivityProvider.shared.isProgressHUDExpanded = false
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Contrae la actividad expandida de vuelta al notch y expulsa suavemente la bolita a su slot satélite
    public func collapseExpandedActivity() {
        guard expandedActivity != nil || isFusing else { return }
        alertingActivityId = nil
        

        fusionExpansionTimer?.invalidate()
        fusionExpansionTimer = nil
        
        SoundFeedbackService.shared.playActionDismissed()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        
        if expandedActivity?.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = false
        }
        
        let contractDuration = AnimationSpeedManager.shared.adjustedDuration(0.22)
        
        // Fase 2 reverso: Contracción vertical de la cápsula hacia el notch (top anclado en y=0)
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.36, dampingFraction: 0.85)) {
            self.expandedActivity = nil
            self.customCardWidth = nil
            self.customCardHeight = nil
            self.customTopRadius = nil
            self.customBottomRadius = nil
            self.recalculateRoles()
        }
        
        // Fase 1 reverso: Desprendimiento y regreso elástico de la bolita a su slot satélite
        DispatchQueue.main.asyncAfter(deadline: .now() + (contractDuration * 0.35)) { [weak self] in
            guard let self = self else { return }
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.40, dampingFraction: 0.90)) {
                self.fusionProgress = 0.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + contractDuration) {
                if self.expandedActivity == nil {
                    self.fusingActivityId = nil
                    self.isFusing = false
                }
                NotchWindowManager.shared.updateHitAreaForCurrentState()
            }
        }
    }
    
    /// Descarta una bolita secundaria o actividad
    public func dismissBolita(id: String) {
        dismissWithAnimation(id: id)
    }
    
    /// Promueve una actividad a principal de forma inmediata
    /// Trae una actividad al notch (clic en su bolita o "Hacer actividad principal"). Se queda ahí mientras
    /// exista, salvo que llegue algo urgente.
    public func makePrimary(id: String) {
        guard let activity = activeActivities.first(where: { $0.id == id }), canTakeNotch(activity) else { return }
        preferredPrimaryId = id
        recalculateRoles()
        SoundFeedbackService.shared.playBubblePop()
    }
    
    /// Puede ocupar el notch (Claude, la repisa o el temporizador con música viven sólo como bolita)
    public func canTakeNotch(_ activity: LiveActivity) -> Bool {
        presentationCandidate(activity).canBePrimary
    }
    
    /// Hay al menos dos actividades entre bolitas y cola: el swipe a lo ancho las recorre
    public var canCycleActivities: Bool {
        secondaryActivities.count + overflowActivities.count >= 2
    }
    
    /// Swipe a lo ancho, como la Isla Dinámica del iPhone 18 Pro: avanza o regresa el carrusel de bolitas
    /// (la primera visible pasa a la cola y entra la siguiente)
    public func cycleActivities(forward: Bool) {
        let ring = secondaryActivities.map(\.id) + overflowActivities.map(\.id)
        guard ring.count >= 2, expandedActivity == nil, !isFusing else { return }
        userOrder = PresentationEngine.rotated(ring, forward: forward)
        recalculateRoles()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    
    /// Expande directamente una actividad hacia su tarjeta rica
    public func expandActivity(_ activity: LiveActivity) {
        if expandedActivity?.id == activity.id {
            collapseExpandedActivity()
            return
        }
        
        SoundFeedbackService.shared.playBubblePop()
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.38, dampingFraction: 0.82)) {
            self.expandedActivity = activity
            self.customCardWidth = activity.customExpandedWidth ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudWidth : IslandMetrics.expandedWidth.upperBound)
            self.customCardHeight = activity.customExpandedHeight ?? (activity.kind == .agentAI ? AgentLiveProgressView.hudHeight : IslandExpandedTemplateMetrics.initialHeight)
            self.customTopRadius = 24
            self.customBottomRadius = 28
            self.recalculateRoles()
        }
        
        if activity.kind == .agentAI {
            AgentActivityProvider.shared.isProgressHUDExpanded = true
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Maneja el click sobre la actividad principal
    public func handleTap() {
        guard let activity = currentActivity else { return }
        if let onTap = activity.onTap {
            onTap()
        } else if activity.expandedView != nil {
            expandActivity(activity)
        } else {
            AppState.shared.expand()
        }
    }
}
