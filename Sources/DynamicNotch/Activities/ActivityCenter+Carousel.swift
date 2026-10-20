import SwiftUI
import Combine
import AppKit

// Carrusel (swipe a lo ancho), traer al notch y la música como bolita
extension ActivityCenter {
    // MARK: - La música en el carrusel

    /// La música no es una actividad: es lo que muestra el notch cuando no hay otra. Al recorrer el carrusel
    /// (o traer una bolita al notch) se vuelve una bolita más con este id, y regresa al notch al volver a ella,
    /// al tocar su bolita, al terminar la actividad que la desplazó o al dejar de sonar.
    public static let musicCarouselId = "music.nowplaying"

    /// Bolita de la música mientras otra actividad ocupa el notch
    func musicCarouselActivity() -> LiveActivity {
        let pink = Color(red: 0.98, green: 0.28, blue: 0.45)
        let track = MusicService.shared.currentTrack
        var activity = LiveActivity(
            id: Self.musicCarouselId,
            kind: .music,
            style: .pill,
            title: track.title.isEmpty ? "Música" : track.title,
            subtitle: track.artist,
            bolitaVariant: .color(bgColor: pink.opacity(0.22), fgColor: pink, iconName: "music.note"),
            tint: pink,
            onTap: { [weak self] in self?.restoreMusicToNotch() },
            createdAt: musicCarouselCreatedAt
        )
        activity.prefersBubble = true
        return activity
    }

    /// Lo muestra el notch ahora mismo la música (sin otra actividad encima)
    var musicIsInNotch: Bool {
        !musicInCarousel && currentActivity == nil && MusicService.shared.hasActiveMusic
    }

    /// Puede mostrarse en el notch si el usuario la elige (aunque normalmente viva como bolita): tiene vista
    /// compacta. Claude, la repisa, los agentes y los avisos del sistema no.
    func canOccupyNotchOnDemand(_ activity: LiveActivity) -> Bool {
        guard !activity.behavesAsSystemHUD, activity.kind != .claude, activity.kind != .agentAI,
              activity.id != ShelfActivityProvider.activityId, activity.id != Self.musicCarouselId else { return false }
        return activity.leading != nil || activity.trailing != nil
    }

    /// Anillo del carrusel con la música, o nil si la música no participa (no está en el notch ni como bolita)
    func musicCarouselRing() -> [String]? {
        let bubbles = secondaryActivities.map(\.id) + overflowActivities.map(\.id)
        if musicInCarousel, let primary = currentActivity?.id {
            return [primary] + bubbles
        }
        guard musicIsInNotch, !bubbles.isEmpty,
              bubbles.contains(where: { id in activeActivities.first { $0.id == id }.map(canOccupyNotchOnDemand) ?? false })
        else { return nil }
        return [Self.musicCarouselId] + bubbles
    }

    /// Lleva una bolita al notch y la música pasa a bolita
    func displaceMusic(with id: String, bubbleOrder: [String]?) {
        musicCarouselCreatedAt = Date()
        musicInCarousel = true
        preferredPrimaryId = id
        userOrder = bubbleOrder
        sidesFollowOrderOnce = bubbleOrder != nil
        recalculateRoles()
    }

    /// La música regresa al notch (clic en su bolita, o el carrusel volvió a ella)
    public func restoreMusicToNotch(bubbleOrder: [String]? = nil) {
        guard musicInCarousel else { return }
        musicInCarousel = false
        preferredPrimaryId = nil
        userOrder = bubbleOrder
        sidesFollowOrderOnce = bubbleOrder != nil
        recalculateRoles()
    }

    /// Clic "Traerla al notch" en una bolita que normalmente no ocupa el notch, con la música sonando
    public func canTakeNotchFromMusic(_ activity: LiveActivity) -> Bool {
        musicIsInNotch && canOccupyNotchOnDemand(activity)
    }
    

    /// Descarta una bolita secundaria o actividad
    public func dismissBolita(id: String) {
        dismissWithAnimation(id: id)
    }
    
    /// Promueve una actividad a principal de forma inmediata
    /// Trae una actividad al notch (clic en su bolita o "Hacer actividad principal"). Se queda ahí mientras
    /// exista, salvo que llegue algo urgente.
    public func makePrimary(id: String) {
        if id == Self.musicCarouselId {
            restoreMusicToNotch()
            return
        }
        if let activity = activeActivities.first(where: { $0.id == id }), !canTakeNotch(activity), canTakeNotchFromMusic(activity) {
            displaceMusic(with: id, bubbleOrder: nil)
            SoundFeedbackService.shared.playBubblePop()
            return
        }
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
        secondaryActivities.count + overflowActivities.count >= 2 || musicCarouselRing() != nil
    }
    
    /// Swipe a lo ancho, como la Isla Dinámica del iPhone 18 Pro: avanza o regresa el carrusel de bolitas
    /// (la primera visible pasa a la cola y entra la siguiente)
    public func cycleActivities(forward: Bool) {
        guard expandedActivity == nil, !isFusing else { return }
        if let ring = musicCarouselRing() {
            // La música participa: lo que llega al frente pasa al notch (la música incluida)
            let musicId = Self.musicCarouselId
            guard let step = PresentationEngine.carouselStep(ring: ring, forward: forward, canOccupyNotch: { id in
                id == musicId || (self.activeActivities.first { $0.id == id }.map(self.canOccupyNotchOnDemand) ?? false)
            }) else { return }
            if step.primary == musicId {
                restoreMusicToNotch(bubbleOrder: step.bubbles)
            } else {
                displaceMusic(with: step.primary, bubbleOrder: step.bubbles)
            }
        } else {
            let ring = secondaryActivities.map(\.id) + overflowActivities.map(\.id)
            guard ring.count >= 2 else { return }
            userOrder = PresentationEngine.rotated(ring, forward: forward)
            sidesFollowOrderOnce = true
            recalculateRoles()
        }
        if AppState.shared.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
