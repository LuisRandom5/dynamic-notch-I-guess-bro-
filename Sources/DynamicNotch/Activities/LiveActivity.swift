import SwiftUI

public enum ActivityStyle: String, Equatable {
    case pill
    case sliderPill
    case airpodsPill
    case card
}

public enum ActivityKind: String, CaseIterable, Identifiable {
    case timer
    case call
    case recording
    case vpn
    case download
    case agentAI
    case claude
    case music
    case generic
    
    public var id: String { rawValue }
    
    public var defaultPriority: Int {
        switch self {
        case .call, .recording: return ActivityRelevance.activeCall
        case .timer: return ActivityRelevance.timer
        case .agentAI, .claude, .download, .vpn: return ActivityRelevance.backgroundTask
        case .music: return ActivityRelevance.music
        case .generic: return ActivityRelevance.generic
        }
    }
}

/// Dos variantes de diseño para las bolitas satélite de Live Activities:
/// - Variante A: Bolita de color de acento con icono o texto corto de alto contraste.
/// - Variante B: Bolita oscura con anillo de progreso animado (Circle().trim()) y acento específico.
public enum BolitaVariant: Equatable {
    case color(bgColor: Color, fgColor: Color, iconName: String, shortText: String? = nil)
    case progressRing(progress: Double, strokeColor: Color, iconName: String, shortText: String? = nil)
    
    public var iconName: String {
        switch self {
        case .color(_, _, let icon, _): return icon
        case .progressRing(_, _, let icon, _): return icon
        }
    }
    
    public var shortText: String? {
        switch self {
        case .color(_, _, _, let text): return text
        case .progressRing(_, _, _, let text): return text
        }
    }
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

public enum SatelliteSide: String, Equatable {
    case right
    case left
}

public enum ActivityLifecycleState: String, Equatable {
    case starting
    case active
    case updated
    case paused
    case attention
    case finished
    case dismissed
}

public struct LiveActivity: Identifiable {
    public let id: String
    public var kind: ActivityKind
    public var priority: Int
    public var style: ActivityStyle
    public var state: ActivityLifecycleState
    public var title: String?
    public var subtitle: String?
    public var progress: Double?
    public var leading: AnyView?
    public var center: AnyView?
    public var trailing: AnyView?
    public var tint: Color
    public var customView: AnyView?
    public var bolitaVariant: BolitaVariant?
    public var expandedView: AnyView?
    public var duration: TimeInterval?
    public var onTap: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var createdAt: Date
    public var lastUpdatedAt: Date
    public var sliderState: SliderPillState?
    public var airpodsState: AirPodsActivityState?
    public var isUrgent: Bool = false
    public var customExpandedWidth: CGFloat? = nil
    public var customExpandedHeight: CGFloat? = nil
    /// Alerta de esta actualización (ActivityCenter la presenta una vez y no la guarda)
    public var alert: ActivityAlertConfiguration? = nil
    /// A partir de cuándo el contenido ya no está al día si no llega otra actualización (se atenúa)
    public var staleDate: Date? = nil
    /// Vive sólo como bolita, nunca ocupa el notch (indicadores como cámara en uso o una descarga: no le
    /// quitan el lugar a la música)
    public var prefersBubble: Bool = false
    /// Aviso breve del sistema (Bloq Mayús, red…): al irse se comporta como el HUD de volumen — el notch se
    /// recoge por completo y lo que había (la música) regresa tras la pausa
    public var isSystemNotice: Bool = false

    /// HUD de volumen/brillo, AirPods o aviso del sistema
    public var behavesAsSystemHUD: Bool {
        style == .sliderPill || style == .airpodsPill || isSystemNotice
    }
    
    public init(
        id: String,
        kind: ActivityKind = .generic,
        priority: Int? = nil,
        style: ActivityStyle,
        state: ActivityLifecycleState = .active,
        title: String? = nil,
        subtitle: String? = nil,
        progress: Double? = nil,
        leading: AnyView? = nil,
        center: AnyView? = nil,
        trailing: AnyView? = nil,
        customView: AnyView? = nil,
        bolitaVariant: BolitaVariant? = nil,
        expandedView: AnyView? = nil,
        tint: Color = DesignTokens.green,
        duration: TimeInterval? = nil,
        sliderState: SliderPillState? = nil,
        airpodsState: AirPodsActivityState? = nil,
        isUrgent: Bool = false,
        customExpandedWidth: CGFloat? = nil,
        customExpandedHeight: CGFloat? = nil,
        onTap: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority ?? kind.defaultPriority
        self.style = style
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.leading = leading
        self.center = center
        self.trailing = trailing
        self.customView = customView
        self.bolitaVariant = bolitaVariant
        self.expandedView = expandedView
        self.tint = tint
        self.duration = duration
        self.sliderState = sliderState
        self.airpodsState = airpodsState
        self.isUrgent = isUrgent
        self.customExpandedWidth = customExpandedWidth
        self.customExpandedHeight = customExpandedHeight
        self.onTap = onTap
        self.onDismiss = onDismiss
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}


