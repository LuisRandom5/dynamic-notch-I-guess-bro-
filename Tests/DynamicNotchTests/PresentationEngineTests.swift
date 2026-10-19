import Foundation
import Testing
@testable import DynamicNotch

/// Política de presentación: quién va en el notch, en las bolitas y en la cola
@Suite struct PresentationEngineTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func candidate(_ id: String, priority: Int = 500, urgent: Bool = false, startedAt offset: TimeInterval = 0,
                   hud: Bool = false, canBePrimary: Bool = true) -> PresentationCandidate {
        PresentationCandidate(id: id, priority: priority, isUrgent: urgent, createdAt: t0.addingTimeInterval(offset),
                              isSystemHUD: hud, canBePrimary: canBePrimary)
    }

    func decide(_ candidates: [PresentationCandidate], current: String? = nil, lastChange: TimeInterval = -100,
                hudHold: TimeInterval = -100, at now: TimeInterval = 0, slots: Int = 1,
                previous: [String] = [], userOrder: [String]? = nil,
                preferred: String? = nil) -> PresentationDecision {
        PresentationEngine.decide(candidates: candidates, currentPrimaryId: current,
                                  lastRoleChangeTime: t0.addingTimeInterval(lastChange),
                                  hudHoldUntil: t0.addingTimeInterval(hudHold),
                                  now: t0.addingTimeInterval(now),
                                  policy: .init(hysteresis: 3, satelliteSlots: slots),
                                  previousSecondaryIds: previous,
                                  userOrder: userOrder,
                                  preferredPrimaryId: preferred)
    }

    // MARK: Orden

    @Test func higherPriorityTakesTheNotch() {
        let d = decide([candidate("music", priority: 500), candidate("call", priority: 900)])
        #expect(d.primaryId == "call")
        #expect(d.secondaryIds == ["music"])
    }

    @Test func samePriorityFirstStartedWins() {
        // Como la Isla Dinámica: sin relevancia distinta gana la que se inició primero
        let d = decide([candidate("b", startedAt: 5), candidate("a", startedAt: 1)])
        #expect(d.primaryId == "a")
        #expect(d.secondaryIds == ["b"])
    }

    @Test func urgentBeatsPriority() {
        let d = decide([candidate("call", priority: 900), candidate("alert", priority: 100, urgent: true)])
        #expect(d.primaryId == "alert")
    }

    @Test func bubbleOnlyActivitiesNeverTakeTheNotch() {
        // Claude o la repisa: siempre bolita, aunque sean las únicas
        let d = decide([candidate("claude", priority: 700, canBePrimary: false)])
        #expect(d.primaryId == nil)
        #expect(d.secondaryIds == ["claude"])
    }

    // MARK: Bolitas y cola

    @Test func extraActivitiesQueueBeyondTheSlots() {
        let d = decide([candidate("a", priority: 900), candidate("b", priority: 800),
                        candidate("c", priority: 700), candidate("d", priority: 600)], slots: 2)
        #expect(d.primaryId == "a")
        #expect(d.secondaryIds == ["b", "c"])
        #expect(d.overflowIds == ["d"])
    }

    @Test func slotsStayBetweenOneAndTwo() {
        // Como la Isla Dinámica: 1 pegada + hasta 2 separadas
        #expect(PresentationEngine.Policy(satelliteSlots: 0).satelliteSlots == 1)
        #expect(PresentationEngine.Policy(satelliteSlots: 4).satelliteSlots == 2)
    }

    @Test func atMostThreeVisible() {
        let d = decide([candidate("a", priority: 900), candidate("b", priority: 800), candidate("c", priority: 700),
                        candidate("d", priority: 600), candidate("e", priority: 500)], slots: 4)
        #expect(d.primaryId == "a")
        #expect(d.secondaryIds == ["b", "c"])
        #expect(d.overflowIds == ["d", "e"])
    }

    // MARK: Lugares estables

    @Test func detachedKeepTheirPlaceWhenAMoreRelevantOneArrives() {
        // "c" (derecha) y "b" (izquierda) ya estaban; llega "x", más relevante que "b": "c" sigue a la derecha
        // y "x" toma el lugar que deja "b"
        let d = decide([candidate("a", priority: 900), candidate("x", priority: 850),
                        candidate("b", priority: 600), candidate("c", priority: 700)],
                       current: "a", slots: 2, previous: ["c", "b"])
        #expect(d.secondaryIds == ["c", "x"])
        #expect(d.overflowIds == ["b"])
    }

    @Test func orderIsKeptEvenIfRelevanceSwaps() {
        // "b" sube de relevancia por encima de "c": no se intercambian de lado
        let d = decide([candidate("a", priority: 900), candidate("b", priority: 800), candidate("c", priority: 700)],
                       current: "a", slots: 2, previous: ["c", "b"])
        #expect(d.secondaryIds == ["c", "b"])
    }

    @Test func remainingOneMovesToTheFirstPlace() {
        // Se va la de la derecha: la de la izquierda ocupa el primer lugar (siempre hay una a la derecha)
        let d = decide([candidate("a", priority: 900), candidate("b", priority: 600)],
                       current: "a", slots: 2, previous: ["c", "b"])
        #expect(d.secondaryIds == ["b"])
    }

    @Test func limitedWidthWithTwoDetached() {
        let three = decide([candidate("a", priority: 900), candidate("b", priority: 800), candidate("c", priority: 700)], slots: 2)
        #expect(three.isLimitedWidth)
        let two = decide([candidate("a", priority: 900), candidate("b", priority: 800)], slots: 2)
        #expect(!two.isLimitedWidth)
    }

    // MARK: Histéresis

    @Test func currentPrimaryStaysDuringHysteresis() {
        // Una más relevante llega 1 s después del último cambio: espera su turno
        let d = decide([candidate("timer", priority: 800), candidate("music", priority: 500)],
                       current: "music", lastChange: -1)
        #expect(d.primaryId == "music")
        #expect(d.secondaryIds == ["timer"])
        #expect(d.lastRoleChangeTime == t0.addingTimeInterval(-1))
    }

    @Test func primaryChangesAfterHysteresis() {
        let d = decide([candidate("timer", priority: 800), candidate("music", priority: 500)],
                       current: "music", lastChange: -4)
        #expect(d.primaryId == "timer")
        #expect(d.lastRoleChangeTime == t0)
    }

    @Test func urgentSkipsHysteresis() {
        let d = decide([candidate("call", priority: 900, urgent: true), candidate("music", priority: 500)],
                       current: "music", lastChange: -0.5)
        #expect(d.primaryId == "call")
    }

    // MARK: HUD del sistema

    @Test func hudTakesTheNotchAndPausesThePrimary() {
        let d = decide([candidate("music", priority: 500), candidate("volume", priority: 100, hud: true)],
                       current: "music")
        #expect(d.primaryId == "volume")
        #expect(d.hiddenByHUDId == "music")
        // Lo pausado no pasa a bolita (evita animaciones cruzadas)
        #expect(d.secondaryIds.isEmpty)
    }

    @Test func notchStaysCleanAfterHUD() {
        let d = decide([candidate("music", priority: 500)], current: nil, hudHold: 2, at: 0)
        #expect(d.isHoldingAfterHUD)
        #expect(d.primaryId == nil)
        #expect(d.hiddenByHUDId == "music")
        #expect(d.secondaryIds.isEmpty)
    }

    @Test func primaryReturnsWhenHoldEnds() {
        let d = decide([candidate("music", priority: 500)], current: nil, hudHold: 2, at: 2.1)
        #expect(!d.isHoldingAfterHUD)
        #expect(d.primaryId == "music")
    }

    @Test func urgentCanInterruptTheHold() {
        let d = decide([candidate("call", priority: 900, urgent: true)], hudHold: 2, at: 0)
        #expect(!d.isHoldingAfterHUD)
        #expect(d.primaryId == "call")
    }

    @Test func emptyInputDecidesNothing() {
        let d = decide([])
        #expect(d.primaryId == nil)
        #expect(d.secondaryIds.isEmpty)
        #expect(d.overflowIds.isEmpty)
    }

    // MARK: Carrusel (swipe a lo ancho)

    @Test func rotationMovesEveryOneOnePlace() {
        #expect(PresentationEngine.rotated(["a", "b", "c"], forward: true) == ["b", "c", "a"])
        #expect(PresentationEngine.rotated(["a", "b", "c"], forward: false) == ["c", "a", "b"])
        #expect(PresentationEngine.rotated(["a"], forward: true) == ["a"])
    }

    @Test func userOrderBringsAQueuedOneIntoView() {
        // b y c a la vista, d en cola; el usuario avanza: c pasa a la derecha, d entra y b se va a la cola
        let all = [candidate("a", priority: 900), candidate("b", priority: 800),
                   candidate("c", priority: 700), candidate("d", priority: 600)]
        let first = decide(all, current: "a", slots: 2)
        #expect(first.ringIds == ["b", "c", "d"])
        let next = decide(all, current: "a", slots: 2, previous: first.secondaryIds,
                          userOrder: PresentationEngine.rotated(first.ringIds, forward: true))
        #expect(next.secondaryIds == ["c", "d"])
        #expect(next.overflowIds == ["b"])
        #expect(next.appliedUserOrder)
    }

    @Test func userOrderEndsWhenAnActivityStartsOrEnds() {
        let all = [candidate("a", priority: 900), candidate("b", priority: 800), candidate("c", priority: 700),
                   candidate("e", priority: 650)]
        let d = decide(all, current: "a", slots: 2, previous: ["c", "d"], userOrder: ["c", "d", "b"])
        #expect(!d.appliedUserOrder)
        #expect(d.secondaryIds == ["c", "b"])
    }

    // MARK: Principal elegida por el usuario

    @Test func preferredPrimarySkipsHysteresisAndRelevance() {
        let d = decide([candidate("call", priority: 920), candidate("airdrop", priority: 880)],
                       current: "call", lastChange: -0.5, preferred: "airdrop")
        #expect(d.primaryId == "airdrop")
        #expect(d.secondaryIds == ["call"])
        #expect(d.appliedPreferredPrimary)
    }

    @Test func urgentBeatsPreferredPrimary() {
        let d = decide([candidate("incoming", priority: 950, urgent: true), candidate("airdrop", priority: 880)],
                       current: "airdrop", preferred: "airdrop")
        #expect(d.primaryId == "incoming")
        #expect(!d.appliedPreferredPrimary)
    }

    @Test func bubbleOnlyActivityCannotBePreferredPrimary() {
        let d = decide([candidate("claude", priority: 700, canBePrimary: false)], preferred: "claude")
        #expect(d.primaryId == nil)
        #expect(!d.appliedPreferredPrimary)
    }
}
