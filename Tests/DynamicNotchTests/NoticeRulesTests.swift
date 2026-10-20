import Testing
@testable import DynamicNotch

@Suite struct NoticeRulesTests {
    @Test func fullChargeOncePerConnection() {
        // Conectado y cargando al 97 %: queda pendiente; al llegar al 100 % avisa una vez
        var step = BatteryService.fullChargeStep(pending: false, pluggedIn: true, charging: true, charged: false, percentage: 97)
        #expect(step == (true, false))
        step = BatteryService.fullChargeStep(pending: step.pending, pluggedIn: true, charging: false, charged: true, percentage: 100)
        #expect(step == (false, true))
        step = BatteryService.fullChargeStep(pending: step.pending, pluggedIn: true, charging: false, charged: true, percentage: 100)
        #expect(step == (false, false))
    }

    @Test func noNoticeWhenPluggedInAlreadyFull() {
        let step = BatteryService.fullChargeStep(pending: false, pluggedIn: true, charging: false, charged: true, percentage: 100)
        #expect(step == (false, false))
    }

    @Test func unpluggingCancels() {
        let step = BatteryService.fullChargeStep(pending: true, pluggedIn: false, charging: false, charged: false, percentage: 99)
        #expect(step == (false, false))
    }

    @Test func messagesDoNotStepOnEachOther() {
        typealias P = NotificationActivityProvider
        #expect(P.arrival(hasCurrent: false, sameSender: false, replying: false, elapsed: 0) == .present)
        #expect(P.arrival(hasCurrent: true, sameSender: true, replying: false, elapsed: 0.3) == .updateCurrent)
        #expect(P.arrival(hasCurrent: true, sameSender: false, replying: false, elapsed: 0.3) == .enqueue)
        #expect(P.arrival(hasCurrent: true, sameSender: false, replying: false, elapsed: 3) == .present)
        // Respondiendo: todo espera, incluso del mismo contacto
        #expect(P.arrival(hasCurrent: true, sameSender: true, replying: true, elapsed: 10) == .enqueue)
    }
}
