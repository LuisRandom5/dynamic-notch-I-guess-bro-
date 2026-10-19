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
                              previousSecondaryIds: [String] = []) -> PresentationDecision {
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
        let visible = remaining.prefix(policy.satelliteSlots).map(\.id)
        let kept = previousSecondaryIds.filter { visible.contains($0) }
        let secondaryIds = kept + visible.filter { !kept.contains($0) }
        return PresentationDecision(
            primaryId: primaryId,
            hiddenByHUDId: hiddenByHUD,
            isHoldingAfterHUD: isHoldingAfterHUD,
            secondaryIds: secondaryIds,
            overflowIds: remaining.dropFirst(policy.satelliteSlots).map(\.id),
            lastRoleChangeTime: lastChange
        )
    }
}
