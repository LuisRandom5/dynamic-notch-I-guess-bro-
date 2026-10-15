import SwiftUI

public enum ActivityStyle: String, Equatable {
    case pill
    case sliderPill
    case airpodsPill
    case card
}

public struct AirPodsActivityState: Equatable {
    public let name: String
    public let batteryLevel: Int
    public let leftPercent: Int?
    public let rightPercent: Int?
    public let casePercent: Int?
    
    public init(
        name: String,
        batteryLevel: Int,
        leftPercent: Int? = nil,
        rightPercent: Int? = nil,
        casePercent: Int? = nil
    ) {
        self.name = name
        self.batteryLevel = batteryLevel
        self.leftPercent = leftPercent
        self.rightPercent = rightPercent
        self.casePercent = casePercent
    }
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
    public var airpodsState: AirPodsActivityState?
    
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
        airpodsState: AirPodsActivityState? = nil,
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
        self.airpodsState = airpodsState
        self.onTap = onTap
        self.createdAt = createdAt
    }
}

