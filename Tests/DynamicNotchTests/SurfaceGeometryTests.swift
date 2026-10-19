import CoreGraphics
import Testing
@testable import DynamicNotch

@Suite struct SurfaceGeometryTests {
    // MacBook Air 13" (1470×956 pt): zonas auxiliares a cada lado de un notch de ~185 pt × 32 pt
    let airFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let airLeft = CGRect(x: 0, y: 924, width: 642, height: 32)
    let airRight = CGRect(x: 827, y: 924, width: 643, height: 32)
    let monitorFrame = CGRect(x: 1470, y: 0, width: 2560, height: 1440)

    @Test func physicalNotchEmbracesTheBezel() throws {
        let g = try #require(SurfaceGeometry.physicalNotch(screenFrame: airFrame, auxiliaryTopLeft: airLeft, auxiliaryTopRight: airRight))
        #expect(g.kind == .physicalNotch)
        #expect(g.hasPhysicalNotch)
        // 185 + 3 de margen subpixel, 32 + 1
        #expect(g.width == 188)
        #expect(g.height == 33)
        #expect(g.notchBoundsInScreen.origin == CGPoint(x: 640.5, y: 923))
        #expect(g.cameraCutoutWidth == g.width)
        #expect(g.hangsFromTopEdge)
    }

    @Test func noAuxiliaryAreasMeansNoNotch() {
        #expect(SurfaceGeometry.physicalNotch(screenFrame: monitorFrame, auxiliaryTopLeft: nil, auxiliaryTopRight: nil) == nil)
        #expect(SurfaceGeometry.physicalNotch(screenFrame: monitorFrame, auxiliaryTopLeft: .zero, auxiliaryTopRight: .zero) == nil)
    }

    @Test func virtualNotchIsCenteredAndHangs() {
        let g = SurfaceGeometry.virtualNotch(screenFrame: monitorFrame)
        #expect(g.kind == .virtualNotch)
        #expect(!g.hasPhysicalNotch)
        #expect(g.notchBoundsInScreen == CGRect(x: 1470 + 1280 - 90, y: 1440 - 32, width: 180, height: 32))
        #expect(g.hangsFromTopEdge)
    }

    @Test func fallbackMatchesThePreviousDefault() {
        let g = SurfaceGeometry.fallback
        #expect(g.notchBoundsInScreen == CGRect(x: 645, y: 924, width: 180, height: 32))
        #expect(g.screenBounds == CGRect(x: 0, y: 0, width: 1470, height: 956))
    }

    @Test func floatingIslandSitsBelowTheTopEdge() {
        let g = SurfaceGeometry.floatingIsland(screenFrame: monitorFrame, size: CGSize(width: 126, height: 37), topInset: 6)
        #expect(g.kind == .floatingIsland)
        #expect(!g.hangsFromTopEdge)
        #expect(g.notchBoundsInScreen.maxY == CGFloat(1440 - 6))
        #expect(g.centerX == monitorFrame.midX)
        #expect(g.cameraCutoutWidth == 126)
    }

    @Test func resolvePrefersThePhysicalNotchScreen() {
        // El monitor externo va primero en la lista, pero la isla va en la pantalla con notch
        let r = SurfaceGeometry.resolve(
            screens: [(monitorFrame, nil, nil), (airFrame, airLeft, airRight)],
            preferredIndex: 0
        )
        #expect(r.geometry.kind == .physicalNotch)
        #expect(r.screenIndex == 1)
    }

    @Test func resolveWithoutNotchUsesThePreferredScreen() {
        let r = SurfaceGeometry.resolve(screens: [(airFrame, nil, nil), (monitorFrame, nil, nil)], preferredIndex: 1)
        #expect(r.geometry.kind == .virtualNotch)
        #expect(r.screenIndex == 1)
        #expect(r.geometry.screenBounds == monitorFrame)
    }

    @Test func resolveWithNoScreensFallsBack() {
        let r = SurfaceGeometry.resolve(screens: [], preferredIndex: nil)
        #expect(r.geometry == .fallback)
        #expect(r.screenIndex == nil)
    }

    // MARK: Preferencia de pantalla (Fase B)

    var twoScreens: [(frame: CGRect, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?)] {
        [(airFrame, airLeft, airRight), (monitorFrame, nil, nil)]
    }

    @Test func automaticKeepsTheNotch() {
        let r = SurfaceGeometry.resolve(screens: twoScreens, placement: .automatic, mainIndex: 0, cursorIndex: 1, islandStyle: .floating)
        #expect(r.geometry.kind == .physicalNotch)
        #expect(r.screenIndex == 0)
    }

    @Test func withoutNotchPicksTheMonitorAsAFloatingIsland() {
        let r = SurfaceGeometry.resolve(screens: twoScreens, placement: .withoutNotch, mainIndex: 0, cursorIndex: nil, islandStyle: .floating)
        #expect(r.geometry.kind == .floatingIsland)
        #expect(r.screenIndex == 1)
        #expect(r.geometry.notchBoundsInScreen.size == SurfaceGeometry.floatingIslandSize)
        #expect(r.geometry.topInset == SurfaceGeometry.floatingIslandTopInset)
        #expect(r.geometry.centerX == monitorFrame.midX)
    }

    @Test func hangingStyleDrawsAVirtualNotch() {
        let r = SurfaceGeometry.resolve(screens: twoScreens, placement: .withoutNotch, mainIndex: 0, cursorIndex: nil, islandStyle: .hanging)
        #expect(r.geometry.kind == .virtualNotch)
        #expect(r.geometry.hangsFromTopEdge)
    }

    @Test func followCursorUsesTheCursorScreen() {
        let onMonitor = SurfaceGeometry.resolve(screens: twoScreens, placement: .followCursor, mainIndex: 0, cursorIndex: 1, islandStyle: .floating)
        #expect(onMonitor.geometry.kind == .floatingIsland)
        let onAir = SurfaceGeometry.resolve(screens: twoScreens, placement: .followCursor, mainIndex: 0, cursorIndex: 0, islandStyle: .floating)
        #expect(onAir.geometry.kind == .physicalNotch)
    }

    @Test func withoutNotchFallsBackWhenEveryScreenHasOne() {
        let r = SurfaceGeometry.resolve(screens: [(airFrame, airLeft, airRight)], placement: .withoutNotch, mainIndex: 0, cursorIndex: nil, islandStyle: .floating)
        #expect(r.geometry.kind == .physicalNotch)
    }

    @Test func singlePlainScreenGetsTheIsland() {
        let r = SurfaceGeometry.resolve(screens: [(monitorFrame, nil, nil)], placement: .automatic, mainIndex: 0, cursorIndex: nil, islandStyle: .floating)
        #expect(r.geometry.kind == .floatingIsland)
    }

    @Test func menuBarIslandFitsInsideTheBar() {
        let m = SurfaceGeometry.menuBarIslandMetrics(menuBarHeight: 24)
        #expect(m.size.height == 22)
        #expect(m.topInset == 1)
        #expect(m.topInset + m.size.height <= 24)
        // Barra oculta: alto típico
        #expect(SurfaceGeometry.menuBarIslandMetrics(menuBarHeight: 0).size.height == 22)
    }

    @Test func islandMetricsProviderIsUsed() {
        let r = SurfaceGeometry.resolve(screens: twoScreens, placement: .withoutNotch, mainIndex: 0, cursorIndex: nil,
                                        islandStyle: .floating, islandMetrics: { _ in (CGSize(width: 90, height: 22), 1) })
        #expect(r.geometry.notchBoundsInScreen.size == CGSize(width: 90, height: 22))
        #expect(r.geometry.topInset == 1)
    }
}
