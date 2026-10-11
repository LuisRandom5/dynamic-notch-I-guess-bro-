import AppKit
import SwiftUI

public struct NotchGeometry: Equatable {
    public var hasPhysicalNotch: Bool
    public var width: CGFloat
    public var height: CGFloat
    public var screenBounds: CGRect
    public var notchBoundsInScreen: CGRect

    public static let fallback = NotchGeometry(
        hasPhysicalNotch: false,
        width: 180,
        height: 32,
        screenBounds: CGRect(x: 0, y: 0, width: 1470, height: 956),
        notchBoundsInScreen: CGRect(x: 645, y: 924, width: 180, height: 32)
    )
}

public enum NotchMode: String, CaseIterable, Equatable {
    case idle
    case compact
    case expanded
    case shelf
}

public enum NotchTab: String, CaseIterable, Identifiable {
    case music = "Música"
    case alerts = "Alertas"
    case shelf = "Bandeja"

    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .music: return "music.note"
        case .alerts: return "bell.fill"
        case .shelf: return "folder.fill"
        }
    }
}

public struct MusicTrack: Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var artwork: NSImage?
    public var isPlaying: Bool
    public var playbackPosition: TimeInterval
    public var duration: TimeInterval
    public var appSource: String // "Apple Music", "Spotify", "Simulado"

    public static let placeholder = MusicTrack(
        title: "Starboy",
        artist: "The Weeknd ft. Daft Punk",
        album: "Starboy",
        artwork: nil,
        isPlaying: false,
        playbackPosition: 42,
        duration: 230,
        appSource: "Apple Music"
    )
}

public enum AlertType: Equatable {
    case magsafe(percent: Int)
    case batteryLow(percent: Int)
    case airpods(name: String, leftPercent: Int, rightPercent: Int, casePercent: Int)
    case airdrop(sender: String, fileName: String)
    case timer(remaining: String)
    case custom(title: String, subtitle: String, symbol: String)
}

public struct NotchAlert: Identifiable, Equatable {
    public let id = UUID()
    public var type: AlertType
    public var timestamp: Date = Date()
    
    public static func == (lhs: NotchAlert, rhs: NotchAlert) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ShelfItem: Identifiable, Equatable {
    public let id = UUID()
    public var url: URL
    public var name: String
    public var icon: NSImage
    
    public static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}
