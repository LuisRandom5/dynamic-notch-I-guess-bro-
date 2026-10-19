import CoreGraphics
import Testing
@testable import DynamicNotch

@Suite struct IslandMetricsTests {
    @Test func expandedHeightStaysInApplesRange() {
        #expect(IslandMetrics.expandedHeight(forContent: 40) == 84)
        #expect(IslandMetrics.expandedHeight(forContent: 120.2) == 121)
        #expect(IslandMetrics.expandedHeight(forContent: 300) == 160)
    }

    @Test func concentricRadiusFollowsTheOuterCurve() {
        #expect(IslandMetrics.concentricRadius(outer: 32, margin: 14) == 18)
        #expect(IslandMetrics.concentricRadius(outer: 10, margin: 14) == 0)
    }

    @Test func scaleComparesToTheIphoneIsland() {
        #expect(IslandMetrics.scale(notchHeight: IslandMetrics.compactHeight) == 1)
        #expect(IslandMetrics.scale(notchHeight: 0) == 1)
        #expect(abs(IslandMetrics.scale(notchHeight: 33) - 0.9) < 0.01)
    }
}
