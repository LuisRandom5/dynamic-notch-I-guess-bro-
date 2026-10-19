import Foundation

/// Lo mínimo de una actividad para decidir dónde se presenta. `ActivityCenter` lo arma a partir de
/// `LiveActivity` y del estado del app (música sonando, agente modal…), así el motor no depende de nada más.
public struct PresentationCandidate: Equatable {
    public let id: String
    public let priority: Int
    public let isUrgent: Bool
    public let createdAt: Date
    /// HUD de volumen/brillo: tiene preferencia sobre todo y no pasa a bolita
    public let isSystemHUD: Bool
    /// Puede ocupar el notch (Claude, la repisa, el temporizador con música… viven sólo como bolita)
    public let canBePrimary: Bool

    public init(id: String, priority: Int, isUrgent: Bool = false, createdAt: Date,
                isSystemHUD: Bool = false, canBePrimary: Bool = true) {
        self.id = id
        self.priority = priority
        self.isUrgent = isUrgent
        self.createdAt = createdAt
        self.isSystemHUD = isSystemHUD
        self.canBePrimary = canBePrimary
    }
}

/// Reparto de las actividades entre el notch, las bolitas y la cola
public struct PresentationDecision: Equatable {
    /// La que ocupa el notch (o el HUD del sistema mientras se muestra)
    public var primaryId: String?
    /// La que iba en el notch y queda en pausa por el HUD (ni notch ni bolita)
    public var hiddenByHUDId: String?
    /// Tras el HUD el notch se queda limpio unos segundos antes de que vuelva lo anterior
    public var isHoldingAfterHUD: Bool
    /// Bolitas separadas, en orden de lugar: [0] = la principal (derecha), [1] = la segunda (izquierda, o
    /// segunda a la derecha si el usuario quiere todas de un lado)
    public var secondaryIds: [String]
    /// En cola: no caben en las bolitas
    public var overflowIds: [String]
    /// Momento del último cambio de principal (para la histéresis)
    public var lastRoleChangeTime: Date

    /// Se respetó el orden elegido por el usuario (swipe a lo ancho). Si no, ya no aplica y se descarta
    public var appliedUserOrder: Bool = false
    /// Se respetó la principal elegida por el usuario (clic en una bolita)
    public var appliedPreferredPrimary: Bool = false

    /// Bolitas visibles y luego la cola: el "carrusel" que recorre el swipe a lo ancho
    public var ringIds: [String] { secondaryIds + overflowIds }

    /// Con dos bolitas separadas (3 actividades a la vista) todo se muestra en ancho limitado, como la Isla
    /// Dinámica: compacta y mínima caben en un círculo de 28 pt
    public var isLimitedWidth: Bool { secondaryIds.count >= 2 }
}

/// Política de presentación de la isla, sin SwiftUI ni estado global, para poder probarla.
/// Reglas (como la Isla Dinámica, ver PLAN_ISLA_DINAMICA.md §1.1):
/// - Orden: urgentes primero, luego mayor prioridad; con la misma, gana la que se inició primero.
/// - Histéresis: la principal no cambia antes de `hysteresis` s salvo por una urgente.
/// - El HUD del sistema se muestra siempre; lo que había queda en pausa y tras él el notch se queda limpio
///   hasta `hudHoldUntil` (una urgente sí puede entrar).
/// - A la vista: 1 en el notch + hasta 2 separadas; el resto en cola. Las separadas no cambian de lugar
///   mientras siguen visibles (las nuevas ocupan el lugar libre); si se libera el primero, la otra lo ocupa.
/// - Lo que el usuario elige manda sobre la relevancia: el orden del carrusel (swipe a lo ancho) mientras no
///   empiece ni termine ninguna actividad, y la principal que trajo al notch con un clic mientras exista.
///   Sólo una urgente o el HUD del sistema pasan por encima.
public enum PresentationEngine {
    /// Como la Isla Dinámica: una pegada y hasta dos separadas
    public static let maxDetachedSlots = 2

    public struct Policy: Equatable {
        public var hysteresis: TimeInterval
        /// Bolitas separadas a la vista (1…2)
        public var satelliteSlots: Int

        public init(hysteresis: TimeInterval = 3.0, satelliteSlots: Int = 1) {
            self.hysteresis = hysteresis
            self.satelliteSlots = min(PresentationEngine.maxDetachedSlots, max(1, satelliteSlots))
        }
    }

    /// Orden determinista de relevancia
    public static func sorted(_ candidates: [PresentationCandidate]) -> [PresentationCandidate] {
        candidates.sorted { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent && !b.isUrgent }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.createdAt < b.createdAt
        }
    }

    public static func decide(candidates: [PresentationCandidate],
                              currentPrimaryId: String?,
                              lastRoleChangeTime: Date,
                              hudHoldUntil: Date,
                              now: Date,
                              policy: Policy,
                              previousSecondaryIds: [String] = [],
                              userOrder: [String]? = nil,
                              preferredPrimaryId: String? = nil) -> PresentationDecision {
        let sorted = sorted(candidates)
        let systemHUD = sorted.first { $0.isSystemHUD }
        let primaryCandidates = sorted.filter { !$0.isSystemHUD && $0.canBePrimary }

        // Histéresis de rol para evitar intercambios ante micro-actualizaciones
        var lastChange = lastRoleChangeTime
        var chosen = primaryCandidates.first
        if let currentId = currentPrimaryId,
           let current = primaryCandidates.first(where: { $0.id == currentId }) {
            if let top = primaryCandidates.first, top.id != currentId {
                if top.isUrgent || now.timeIntervalSince(lastRoleChangeTime) >= policy.hysteresis {
                    chosen = top
                    lastChange = now
                } else {
                    chosen = current
                }
            } else {
                chosen = current
            }
        } else {
            lastChange = now
        }

        // La principal que eligió el usuario se queda (sin esperar la histéresis) salvo ante una urgente
        var appliedPreferredPrimary = false
        if let preferredId = preferredPrimaryId,
           let preferred = primaryCandidates.first(where: { $0.id == preferredId }),
           !(primaryCandidates.first.map { $0.isUrgent && $0.id != preferredId } ?? false) {
            if chosen?.id != preferredId { lastChange = now }
            chosen = preferred
            appliedPreferredPrimary = true
        }

        // Mientras el HUD está visible (y unos segundos después), lo que iba en el notch queda en pausa
        let isHoldingAfterHUD = systemHUD == nil && now < hudHoldUntil && !(chosen?.isUrgent ?? false)
        let hiddenByHUD = (systemHUD != nil || isHoldingAfterHUD) ? chosen?.id : nil
        if let hud = systemHUD {
            chosen = hud
        } else if isHoldingAfterHUD {
            chosen = nil
        }

        let primaryId = chosen?.id
        let remaining = sorted.filter { $0.id != primaryId && $0.id != hiddenByHUD && !$0.isSystemHUD }
        // Cuáles se ven lo decide la relevancia; en qué lugar, la estabilidad: las que ya estaban conservan su
        // orden y las nuevas toman el siguiente lugar libre
        let remainingIds = remaining.map(\.id)
        let secondaryIds: [String]
        let overflowIds: [String]
        let appliedUserOrder: Bool
        if let order = userOrder, order.count == remainingIds.count, Set(order) == Set(remainingIds) {
            // El usuario recorrió el carrusel: su orden manda mientras sean las mismas actividades
            secondaryIds = Array(order.prefix(policy.satelliteSlots))
            overflowIds = Array(order.dropFirst(policy.satelliteSlots))
            appliedUserOrder = true
        } else {
            let visible = remaining.prefix(policy.satelliteSlots).map(\.id)
            let kept = previousSecondaryIds.filter { visible.contains($0) }
            secondaryIds = kept + visible.filter { !kept.contains($0) }
            overflowIds = remaining.dropFirst(policy.satelliteSlots).map(\.id)
            appliedUserOrder = false
        }
        var decision = PresentationDecision(
            primaryId: primaryId,
            hiddenByHUDId: hiddenByHUD,
            isHoldingAfterHUD: isHoldingAfterHUD,
            secondaryIds: secondaryIds,
            overflowIds: overflowIds,
            lastRoleChangeTime: lastChange
        )
        decision.appliedUserOrder = appliedUserOrder
        decision.appliedPreferredPrimary = appliedPreferredPrimary && primaryId == preferredPrimaryId
        return decision
    }

    /// Siguiente orden del carrusel: hacia adelante la primera visible pasa al final y todo avanza un lugar
    public static func rotated(_ ring: [String], forward: Bool) -> [String] {
        guard ring.count >= 2 else { return ring }
        return forward
            ? Array(ring.dropFirst()) + [ring[0]]
            : [ring[ring.count - 1]] + Array(ring.dropLast())
    }
}
