import SwiftUI

public enum ActivityStyle: String, Equatable {
    case pill
    case sliderPill
    case card
}

public enum SliderPillState: Equatable {
    case brightness(level: Float)
    case volume(level: Float, isMuted: Bool)
    
    public var level: Float {
        switch self {
        case .brightness(let lvl):
            return lvl
        case .volume(let lvl, _):
            return lvl
        }
    }
    
    public var isMuted: Bool {
        switch self {
        case .brightness:
            return false
        case .volume(_, let muted):
            return muted
        }
    }
}

public struct LiveActivity: Identifiable {
    public let id: String
    public var priority: Int
    public var style: ActivityStyle
    public var leading: AnyView?
    public var center: AnyView?
    public var trailing: AnyView?
    public var tint: Color
    public var duration: TimeInterval? // nil = persistente mientras la condición sea verdadera
    public var onTap: (() -> Void)?
    public let createdAt: Date
    public var sliderState: SliderPillState?
    
    public init(
        id: String,
        priority: Int,
        style: ActivityStyle,
        leading: AnyView? = nil,
        center: AnyView? = nil,
        trailing: AnyView? = nil,
        tint: Color = DesignTokens.green,
        duration: TimeInterval? = nil,
        sliderState: SliderPillState? = nil,
        onTap: (() -> Void)? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.priority = priority
        self.style = style
        self.leading = leading
        self.center = center
        self.trailing = trailing
        self.tint = tint
        self.duration = duration
        self.sliderState = sliderState
        self.onTap = onTap
        self.createdAt = createdAt
    }
}
