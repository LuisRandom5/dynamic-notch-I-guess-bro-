import AppKit
import QuartzCore

/// Diagnóstico de rendimiento: mide el intervalo real entre cuadros de la pantalla y registra los "tirones"
/// (cuadros que tardan más de ~2 refrescos) con lo que estaba haciendo el notch en ese momento.
/// Consultar con GET /debug/hitches.
@MainActor
public final class FrameHitchMonitor: NSObject {
    public static let shared = FrameHitchMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var hitches: [(time: Date, ms: Double, context: String)] = []
    private(set) var frameCount = 0
    private(set) var slowFrameCount = 0

    public func start() {
        guard displayLink == nil, let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        let interval = (link.timestamp - lastTimestamp) * 1000
        let expected = max(1, (link.targetTimestamp - link.timestamp) * 1000)
        frameCount += 1
        guard interval > max(22, expected * 1.45) else { return }
        slowFrameCount += 1
        let center = ActivityCenter.shared
        let app = AppState.shared
        let context = "mode=\(app.mode) expanded=\(center.expandedActivity?.id ?? "-") fusing=\(center.fusingActivityId ?? "-") sats=\(center.secondaryActivities.count) blurHold=\(app.gestureBlurHold) collapse=\(app.interactiveCollapseProgress)"
        hitches.append((Date(), interval, context))
        if hitches.count > 200 { hitches.removeFirst(hitches.count - 200) }
    }

    public func report(reset: Bool) -> [String: Any] {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let result: [String: Any] = [
            "frames": frameCount,
            "slowFrames": slowFrameCount,
            "hitches": hitches.suffix(40).map { "\(f.string(from: $0.time)) \(Int($0.ms))ms \($0.context)" }
        ]
        if reset {
            hitches.removeAll()
            frameCount = 0
            slowFrameCount = 0
        }
        return result
    }
}
