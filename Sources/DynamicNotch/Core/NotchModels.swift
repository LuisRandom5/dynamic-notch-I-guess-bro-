import AppKit
import SwiftUI

// NotchGeometry es ahora un alias de SurfaceGeometry (ver SurfaceGeometry.swift)

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
    public var originalURL: URL?
    public var name: String
    public var icon: NSImage
    public var sizeString: String
    public var isStashed: Bool
    public var isReadOnlySource: Bool
    
    public var isImage: Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "bmp", "icns"].contains(ext)
    }
    
    public init(
        url: URL,
        originalURL: URL? = nil,
        isStashed: Bool = false,
        isReadOnlySource: Bool = false,
        name: String? = nil,
        icon: NSImage? = nil
    ) {
        self.url = url
        self.originalURL = originalURL
        self.isStashed = isStashed
        self.isReadOnlySource = isReadOnlySource
        self.name = name ?? url.lastPathComponent
        if let icon = icon {
            self.icon = icon
        } else {
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "bmp", "icns"]
            if imageExtensions.contains(ext), let img = NSImage(contentsOf: url) {
                self.icon = img
            } else {
                let img = NSWorkspace.shared.icon(forFile: url.path)
                img.size = NSSize(width: 128, height: 128)
                self.icon = img
            }
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useAll]
            bcf.countStyle = .file
            self.sizeString = bcf.string(fromByteCount: size)
        } else {
            self.sizeString = ""
        }
    }
    
    public static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}

