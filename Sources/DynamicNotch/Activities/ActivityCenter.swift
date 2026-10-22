import SwiftUI
import Combine
import AppKit

/// Bolita que se va: conserva su lugar (índice) para reabsorberse en el lado del notch donde estaba
public struct DepartingSatellite: Identifiable {
    public let id: String
    public let activity: LiveActivity
    /// Lado y lugar donde estaba (se reabsorbe ahí)
    public let placement: SatellitePlacement
    /// Con el notch desplegándose no hay extremo donde reabsorberse: se desvanece
    public var fades: Bool = false
}

public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()

    // (propiedades de las extensiones: carrusel con música)
    @Published public internal(set) var musicInCarousel = false
    var musicCarouselCreatedAt = Date()
    var musicObserver: AnyCancellable?
    
    // MARK: - Estado de Actividades
    @Published public internal(set) var currentActivity: LiveActivity?
    @Published public internal(set) var activeActivities: [LiveActivity] = []
    @Published public internal(set) var dismissingActivityId: String? = nil
    @Published public internal(set) var lastDismissedActivity: LiveActivity? = nil
    
    // MARK: - Roles Multi-Actividad (Modo A y Modo B)
    @Published public internal(set) var secondaryActivities: [LiveActivity] = []
    @Published public internal(set) var overflowActivities: [LiveActivity] = []
    @Published public internal(set) var overflowCount: Int = 0
    /// Bolitas que se están reabsorbiendo en el notch (dejaron de estar a la vista): se siguen dibujando
    /// mientras dura la absorción (ver LiquidSatelliteHost)
    @Published public internal(set) var departingSatellites: [DepartingSatellite] = []
    /// Cambios de bolitas sin animación líquida (sólo un desvanecido), p. ej. al cambiar de escritorio
    @Published public internal(set) var quietSatelliteChanges = false
    /// Lado de cada bolita visible (estable mientras siga a la vista, ver PresentationEngine.assignSides)
    @Published public internal(set) var satelliteLayout: [String: SatellitePlacement] = [:]
    /// El swipe a lo ancho recorre el carrusel: esa vez los lados siguen el orden nuevo (no la memoria)
    var sidesFollowOrderOnce = false
    /// 3 actividades a la vista: bolitas y mínima pegada en ancho limitado (ver PresentationDecision)
    @Published public internal(set) var isLimitedWidth: Bool = false
    
    // MARK: - Coordinador de Morfeo Líquido y Fusión (Bolita <-> Notch)
    @Published public var fusingActivityId: String? = nil
    @Published public var fusionProgress: CGFloat = 0.0 // 0.0 (satélite) -> 1.0 (en contacto con el notch)
    @Published public var fusionSide: SatelliteSide = .right
    @Published public var expandedActivity: LiveActivity? = nil {
        didSet {
            guard expandedActivity?.id != oldValue?.id else { return }
            expandedIdleTimer?.invalidate()
            expandedIdleTimer = nil
            if expandedActivity != nil { startExpandedIdleTimer() }
        }
    }
    /// Una tarjeta abierta que nadie mira (sin el puntero encima) se cierra sola: antes podía quedarse abierta
    /// para siempre y tapar todo lo demás
    private var expandedIdleTimer: Timer?
    /// Veces que una actividad terminada esperó a que se cerrara su tarjeta (5 s cada una)
    var endWaits: [String: Int] = [:]
    private var expandedLastAttention = Date()
    static let expandedIdleTimeout: TimeInterval = 15

    private func startExpandedIdleTimer() {
        expandedLastAttention = Date()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self, let open = self.expandedActivity else { return }
            if AppState.shared.isHovered || self.alertingActivityId == open.id {
                self.expandedLastAttention = Date()
            } else if Date().timeIntervalSince(self.expandedLastAttention) >= Self.expandedIdleTimeout {
                self.collapseExpandedActivity()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        expandedIdleTimer = timer
    }
    @Published public var isFusing: Bool = false
    
    // Dimensiones y curvatura de tarjeta personalizada
    @Published public var customCardWidth: CGFloat? = nil
    @Published public var customCardHeight: CGFloat? = nil
    @Published public var customTopRadius: CGFloat? = nil
    @Published public var customBottomRadius: CGFloat? = nil
    
    var dismissTimers: [String: Timer] = [:]
    var fusionExpansionTimer: Timer?
    var lastRoleChangeTime: Date = Date.distantPast
    /// Orden del carrusel elegido con el swipe a lo ancho (vale mientras no empiece ni termine una actividad)
    var userOrder: [String]?
    /// Actividad que el usuario trajo al notch con un clic (vale mientras exista)
    var preferredPrimaryId: String?
    let hysteresisDuration: TimeInterval = 3.0 // 3s de estabilidad de rol
    
    var playbackObserver: AnyCancellable?
    
    /// Física de las bolitas sobre el borde derecho de la cápsula (pt): se recoge al desprenderse una gota
    /// y se abulta al absorberla, con rebote elástico (ver ElasticPillShape.trailingImpulse)
    @Published public internal(set) var pillImpulse: CGFloat = 0
    /// Reacción de toda la isla a la gota (como en el iPhone): un retroceso de un par de puntos y un estirón
    /// mínimo que rebota (ver NotchContainerView.scaleX/scaleY)
    @Published public internal(set) var islandRecoil: CGFloat = 0
    @Published public internal(set) var islandJiggle: CGFloat = 1
    var impulseToken = 0
    
    /// Alerta en curso (ver presentAlert): si el usuario interactúa, la tarjeta ya no se cierra sola
    var alertingActivityId: String?
    /// Última alerta por actividad (ActivityLifecycle.shouldAlert no repite antes de 30 s)
    var lastAlertAt: [String: Date] = [:]
    /// Actividades cuyo contenido ya no está al día (staleDate vencida): se dibujan atenuadas
    @Published public internal(set) var staleActivityIds: Set<String> = []
    /// Revisión periódica del ciclo de vida: 8 h máximo y contenido obsoleto
    var lifecycleTimer: Timer?
    var staleTimer: Timer?
    /// Actividades terminadas mostrando su resumen antes de irse (ver end)
    var endTimers: [String: Timer] = [:]
    
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
    
    func finishAlert(id: String) {
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
    struct RoleHandoff {
        let id: String
        let toPrimary: Bool
        let until: Date
    }
    var roleHandoff: RoleHandoff?
    
    /// Después del HUD de volumen/brillo, lo que había en el notch (reproductor, temporizador…) se queda
    /// escondido un momento antes de volver, como en la Isla Dinámica: el notch queda limpio y luego regresa.
    public static var hudReturnDelay: TimeInterval { AppState.shared.hudReturnDelay }
    var hudHoldUntil: Date = .distantPast
    static let reabsorbDuration: TimeInterval = 0.57
    static let notchSettleDuration: TimeInterval = 0.45
    
    init() {
        // Si la música deja de sonar mientras está como bolita del carrusel, todo vuelve a lo normal
        musicObserver = MusicService.shared.$hasActiveMusic
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self, !active, self.musicInCarousel else { return }
                self.restoreMusicToNotch()
            }
    }

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
    func yieldsToPlayback(_ activity: LiveActivity) -> Bool {
        AppState.shared.timerYieldsToMusic && activity.kind == .timer && !activity.isUrgent && MusicService.shared.currentTrack.isPlaying
    }
    
    // MARK: - Publicación y Actualización
    
    /// Publica o actualiza una actividad según las reglas de prioridad y actualización en sitio
    public func publish(_ activity: LiveActivity) {
        // Durante la pausa posterior al HUD, las actualizaciones de otras actividades (temporizador, Claude…)
        // no deben hacer reaparecer el reproductor antes de tiempo
        if Date() >= hudHoldUntil || activity.behavesAsSystemHUD {
            AppState.shared.isHoldingBareNotch = false
        }
        
        if dismissingActivityId == activity.id {
            dismissingActivityId = nil
        }

        // Lo urgente no espera a que cierres una tarjeta abierta: llamada, AirPods, volumen y brillo, avisos del
        // sistema o un mensaje nuevo la recogen para mostrarse (sólo al aparecer, no en cada actualización)
        if let open = expandedActivity, open.id != activity.id, !activeActivities.contains(where: { $0.id == activity.id }),
           activity.isUrgent || activity.behavesAsSystemHUD || activity.id.hasPrefix("notification_") {
            collapseExpandedActivity()
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
    
    /// Como tras el HUD de volumen: el notch se queda limpio (sin alas) y lo que había regresa con su animación
    /// después de la pausa. Se usa al salir de pantalla completa.
    public func holdBareNotchThenRestore() {
        hudHoldUntil = Date().addingTimeInterval(Self.hudReturnDelay)
        let holdUntil = hudHoldUntil
        // Sin animación: el notch aparece ya limpio (la ventana vuelve a mostrarse con un fundido)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            AppState.shared.isHoldingBareNotch = true
            recalculateRoles()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudReturnDelay) { [weak self] in
            guard let self = self, self.hudHoldUntil == holdUntil else { return }
            withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                AppState.shared.isHoldingBareNotch = false
                self.recalculateRoles()
                if self.currentActivity == nil {
                    AppState.shared.reconcileCompactMode()
                }
            }
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
        let isSystemHUD = current.behavesAsSystemHUD
        if isSystemHUD {
            hudHoldUntil = Date().addingTimeInterval(duration + Self.hudReturnDelay)
            // También con la música en pausa mientras sus alas siguen a la vista (modo compacto)
            if MusicService.shared.hasActiveMusic || AppState.shared.mode == .compact {
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
            registerDepartures(from: satelliteLayout, old: secondaryActivities, to: [:])
            satelliteLayout = [:]
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
        
        // La música como bolita sólo mientras siga la actividad que la desplazó
        if musicInCarousel, !MusicService.shared.hasActiveMusic
            || !activeActivities.contains(where: { $0.id == preferredPrimaryId }) {
            musicInCarousel = false
            preferredPrimaryId = nil
            userOrder = nil
        }
        var presentable = presentableActivities()
        if musicInCarousel { presentable.append(musicCarouselActivity()) }

        // La política (orden, histéresis, HUD, bolitas y cola) vive en PresentationEngine, sin estado global
        let now = Date()
        let maxSatellites = max(1, AppState.shared.maxSatelliteBolitas)
        let satelliteSlots = AppState.shared.multiActivityMode == .modeA ? maxSatellites : 1
        let decision = PresentationEngine.decide(
            candidates: presentable.map(presentationCandidate),
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
        let activitiesById = Dictionary(presentable.map { ($0.id, $0) } + activeActivities.map { ($0.id, $0) },
                                        uniquingKeysWith: { first, _ in first })
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
        // El extremo derecho reacciona a la bolita pegada a la derecha
        let newRightLayout = PresentationEngine.assignSides(ids: newSecondaries.map(\.id), previous: sidesFollowOrderOnce ? [:] : satelliteLayout,
                                                            bothSides: AppState.shared.bubblesOnBothSides)
        let oldRightId = satelliteLayout.first { $0.value == SatellitePlacement(isLeft: false, slotIndex: 0) }?.key
        let newRightId = newRightLayout.first { $0.value == SatellitePlacement(isLeft: false, slotIndex: 0) }?.key
        if oldRightId != newRightId {
            if newRightId != nil && oldRightId == nil {
                firePillImpulse(.detach)
            } else if let gone = oldRightId, newRightId == nil, gone != fusingActivityId {
                firePillImpulse(.absorb)
            }
        }
        
        let newLayout = PresentationEngine.assignSides(ids: newSecondaries.map(\.id), previous: sidesFollowOrderOnce ? [:] : satelliteLayout,
                                                       bothSides: AppState.shared.bubblesOnBothSides)
        registerDepartures(from: satelliteLayout, old: secondaryActivities, to: newLayout)
        if newLayout != satelliteLayout { satelliteLayout = newLayout }
        sidesFollowOrderOnce = false
        withAnimation(AnimationSpeedManager.shared.spring(response: 0.35, dampingFraction: 0.82)) {
            self.currentActivity = displayedPrimary
            self.secondaryActivities = newSecondaries
            self.overflowActivities = newOverflow
            self.overflowCount = newOverflow.count
            if self.isLimitedWidth != (newSecondaries.count >= 2) { self.isLimitedWidth = newSecondaries.count >= 2 }
        }
        
        NotchWindowManager.shared.updateHitAreaForCurrentState()
    }
    
    /// Las bolitas que dejan de verse en su lado se siguen dibujando mientras se reabsorben en el notch. Cuenta
    /// el lado: una que pasa de izquierda a derecha (swipe) se reabsorbe de un lado y brota del otro.
    func registerDepartures(from oldLayout: [String: SatellitePlacement], old: [LiveActivity],
                                    to newLayout: [String: SatellitePlacement]) {
        let newKeys = Set(newLayout.map { "\($0.key)|\($0.value.sideKey)" })
        // Si vuelve a su lado antes de terminar de irse, deja de irse
        departingSatellites.removeAll { newKeys.contains("\($0.activity.id)|\($0.placement.sideKey)") }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, expandedActivity == nil, !isFusing,
              !quietSatelliteChanges else { return }
        let notchIsOpen = AppState.shared.mode == .expanded || AppState.shared.mode == .shelf
        for activity in old {
            guard let placement = oldLayout[activity.id], !newKeys.contains("\(activity.id)|\(placement.sideKey)") else { continue }
            let token = "\(activity.id)#\(UUID().uuidString.prefix(8))"
            departingSatellites.append(DepartingSatellite(id: token, activity: activity, placement: placement, fades: notchIsOpen))
            let duration = notchIsOpen ? LiquidSatelliteHost<EmptyView>.fadeDuration + 0.05 : LiquidSatelliteHost<EmptyView>.departureDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.departingSatellites.removeAll { $0.id == token }
            }
        }
    }
    
    /// Como en el iPhone: la actividad de una app no sale en la isla mientras el usuario está viendo esa app
    /// (AppVisibilityMonitor). Las urgentes y la que el usuario tiene abierta sí se quedan.
    func presentableActivities() -> [LiveActivity] {
        let watched = Set(activeActivities.compactMap { ActivitySourceApp.bundleId(for: $0) })
        AppVisibilityMonitor.shared.watch(AppState.shared.hideActivityWhileAppVisible ? watched : [])
        guard AppState.shared.hideActivityWhileAppVisible else { return activeActivities }
        let visible = AppVisibilityMonitor.shared.visibleBundleIds
        guard !visible.isEmpty else { return activeActivities }
        return activeActivities.filter { activity in
            guard let bundleId = ActivitySourceApp.bundleId(for: activity), visible.contains(bundleId) else { return true }
            return activity.isUrgent || expandedActivity?.id == activity.id || fusingActivityId == activity.id
        }
    }
    
    var appVisibilityObserver: AnyCancellable?
    
    /// Recalcular cuando el usuario empieza o deja de ver la app de alguna actividad
    public func startObservingAppVisibility() {
        guard appVisibilityObserver == nil else { return }
        appVisibilityObserver = AppVisibilityMonitor.shared.$visibleBundleIds
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Si cambió por un cambio de escritorio, la bolita sólo se desvanece (sin brotar ni reabsorberse):
                // si no, cada vez que cambias de escritorio salía la animación completa
                guard Date().timeIntervalSince(AppVisibilityMonitor.shared.lastSpaceChange) < 2 else {
                    self.recalculateRoles()
                    return
                }
                self.quietSatelliteChanges = true
                withAnimation(.easeInOut(duration: 0.2)) { self.recalculateRoles() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.quietSatelliteChanges = false }
            }
    }
    
    /// Traduce una actividad a lo que necesita el motor de presentación
    func presentationCandidate(_ activity: LiveActivity) -> PresentationCandidate {
        let canBePrimary: Bool
        if activity.behavesAsSystemHUD {
            canBePrimary = false
        } else if musicInCarousel && activity.id == preferredPrimaryId && canOccupyNotchOnDemand(activity) {
            // El usuario la trajo al notch en lugar de la música (carrusel o clic)
            canBePrimary = true
        } else if activity.prefersBubble || activity.kind == .claude || activity.id == ShelfActivityProvider.activityId {
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
            // Lo mismo para la animación de AirPods y los avisos del sistema (Bloq Mayús, red)
            isSystemHUD: activity.behavesAsSystemHUD,
            canBePrimary: canBePrimary
        )
    }
    
    func islandReact(recoil: CGFloat, jiggle: CGFloat, after delay: TimeInterval, k: Double) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.10)) {
                self.islandRecoil = recoil
                self.islandJiggle = jiggle
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                // Resorte flojo: dos o tres rebotes casi imperceptibles
                withAnimation(.spring(response: 0.42 * k, dampingFraction: 0.36)) {
                    self.islandRecoil = 0
                    self.islandJiggle = 1
                }
            }
        }
    }
    
    enum PillImpulse { case detach, absorb }
    
    /// Desprender: el extremo se ensancha 6 pt para dejar salir la gota y regresa con un rebote leve.
    /// Absorber: cuando la gota llega (~0.3 s, acelera como atraída), la cápsula se abulta 7 pt y se asienta
    /// con un pequeño sobrepaso elástico.
    func firePillImpulse(_ kind: PillImpulse) {
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
            // La gota sale con fuerza: la isla retrocede un poco hacia el otro lado y rebota
            islandReact(recoil: -1.4, jiggle: 1.010, after: 0.30 * k, k: k)
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
                // Al llegar la gota, la isla recibe el golpe: se empuja un poco hacia ella y rebota
                self.islandReact(recoil: 1.2, jiggle: 1.012, after: 0, k: k)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20 * k) {
                    guard self.impulseToken == token else { return }
                    withAnimation(.spring(response: 0.80 * k, dampingFraction: 0.52)) { self.pillImpulse = 0 }
                }
            }
        }
    }
    
    func beginRoleHandoff(id: String, toPrimary: Bool, duration: TimeInterval) {
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
    
    func rescheduleTimer(for activity: LiveActivity) {
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
    
}
