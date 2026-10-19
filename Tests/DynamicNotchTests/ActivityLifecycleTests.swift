import Foundation
import Testing
@testable import DynamicNotch

@Suite struct ActivityLifecycleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)

    // MARK: 8 horas

    @Test func endsAfterEightHours() {
        #expect(!ActivityLifecycle.isExpired(createdAt: t0, now: t0.addingTimeInterval(7.9 * 3600)))
        #expect(ActivityLifecycle.isExpired(createdAt: t0, now: t0.addingTimeInterval(8 * 3600)))
    }

    // MARK: Obsoleta

    @Test func staleOnlyAfterItsDate() {
        #expect(!ActivityLifecycle.isStale(staleDate: nil, now: t0))
        #expect(!ActivityLifecycle.isStale(staleDate: t0.addingTimeInterval(60), now: t0))
        #expect(ActivityLifecycle.isStale(staleDate: t0, now: t0))
    }

    // MARK: Alertas

    @Test func firstAlertIsShown() {
        #expect(ActivityLifecycle.shouldAlert(enabled: true, isUrgent: false, userIsBusy: false, lastAlertAt: nil, now: t0))
    }

    @Test func noAlertWhenDisabledOrBusy() {
        #expect(!ActivityLifecycle.shouldAlert(enabled: false, isUrgent: true, userIsBusy: false, lastAlertAt: nil, now: t0))
        #expect(!ActivityLifecycle.shouldAlert(enabled: true, isUrgent: true, userIsBusy: true, lastAlertAt: nil, now: t0))
    }

    @Test func alertsAreThrottledPerActivity() {
        let last = t0.addingTimeInterval(-10)
        #expect(!ActivityLifecycle.shouldAlert(enabled: true, isUrgent: false, userIsBusy: false, lastAlertAt: last, now: t0))
        #expect(ActivityLifecycle.shouldAlert(enabled: true, isUrgent: false, userIsBusy: false,
                                              lastAlertAt: t0.addingTimeInterval(-31), now: t0))
    }

    @Test func urgentSkipsTheThrottle() {
        #expect(ActivityLifecycle.shouldAlert(enabled: true, isUrgent: true, userIsBusy: false,
                                              lastAlertAt: t0.addingTimeInterval(-2), now: t0))
    }
}
