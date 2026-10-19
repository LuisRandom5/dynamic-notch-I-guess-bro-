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
    /// Bolitas satélite, en orden de lugar
    public var secondaryIds: [String]
    /// En cola: no caben en las bolitas
    public var overflowIds: [String]
    /// Momento del último cambio de principal (para la histéresis)
    public var lastRoleChangeTime: Date
}

/// Política de presentación de la isla, sin SwiftUI ni estado global, para poder probarla.
/// Reglas (como la Isla Dinámica, ver PLAN_ISLA_DINAMICA.md §1.1):
/// - Orden: urgentes primero, luego mayor prioridad; con la misma, gana la que se inició primero.
/// - Histéresis: la principal no cambia antes de `hysteresis` s salvo por una urgente.
/// - El HUD del sistema se muestra siempre; lo que había queda en pausa y tras él el notch se queda limpio
///   hasta `hudHoldUntil` (una urgente sí puede entrar).
public enum PresentationEngine {
    public struct Policy: Equatable {
        public var hysteresis: TimeInterval
        public var satelliteSlots: Int

        public init(hysteresis: TimeInterval = 3.0, satelliteSlots: Int = 1) {
            self.hysteresis = hysteresis
            self.satelliteSlots = max(1, satelliteSlots)
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
                              policy: Policy) -> PresentationDecision {
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
        return PresentationDecision(
            primaryId: primaryId,
            hiddenByHUDId: hiddenByHUD,
            isHoldingAfterHUD: isHoldingAfterHUD,
            secondaryIds: remaining.prefix(policy.satelliteSlots).map(\.id),
            overflowIds: remaining.dropFirst(policy.satelliteSlots).map(\.id),
            lastRoleChangeTime: lastChange
        )
    }
}
