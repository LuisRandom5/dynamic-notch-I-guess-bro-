import AppKit
import AudioToolbox

public final class HapticService {
    public static let shared = HapticService()
    
    public var isEnabled: Bool = true
    
    private init() {}
    
    public func triggerExpand() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
    
    public func triggerSnap() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
    
    public func triggerDrop() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
}
