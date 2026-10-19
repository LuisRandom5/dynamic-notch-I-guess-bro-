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
                hudHold: TimeInterval = -100, at now: TimeInterval = 0, slots: Int = 1) -> PresentationDecision {
        PresentationEngine.decide(candidates: candidates, currentPrimaryId: current,
                                  lastRoleChangeTime: t0.addingTimeInterval(lastChange),
                                  hudHoldUntil: t0.addingTimeInterval(hudHold),
                                  now: t0.addingTimeInterval(now),
                                  policy: .init(hysteresis: 3, satelliteSlots: slots))
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

    @Test func slotsNeverBelowOne() {
        #expect(PresentationEngine.Policy(satelliteSlots: 0).satelliteSlots == 1)
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
}
