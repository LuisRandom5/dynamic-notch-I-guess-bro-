import AppKit
import Combine

public final class MusicService: ObservableObject {
    public static let shared = MusicService()
    
    @Published public private(set) var currentTrack: MusicTrack = .placeholder
    @Published public private(set) var hasActiveMusic: Bool = false
    
    private var progressTimer: Timer?
    
    private init() {
        setupDistributedNotifications()
        checkActivePlayers()
    }
    
    private func setupDistributedNotifications() {
        let center = DistributedNotificationCenter.default()
        
        // Listen to Apple Music
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppleMusicNotification(notification)
        }
        
        // Listen to Spotify
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpotifyNotification(notification)
        }
    }
    
    private func handleAppleMusicNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = playerState.caseInsensitiveCompare("Playing") == .orderedSame
        let title = userInfo["Name"] as? String ?? "Desconocido"
        let artist = userInfo["Artist"] as? String ?? "Desconocido"
        let album = userInfo["Album"] as? String ?? ""
        let totalTimeMs = userInfo["Total Time"] as? Double ?? 180000.0
        
        // Sincronizar posición real
        let position = fetchCurrentPlaybackPosition(app: "Apple Music")
        
        self.currentTrack = MusicTrack(
            title: title,
            artist: artist,
            album: album,
            artwork: fetchAppleMusicArtwork(),
            isPlaying: isPlaying,
            playbackPosition: position,
            duration: totalTimeMs / 1000.0,
            appSource: "Apple Music"
        )
        self.hasActiveMusic = isPlaying
        updateProgressTimer(isPlaying: isPlaying)
    }
    
    private func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = playerState.caseInsensitiveCompare("Playing") == .orderedSame
        let title = userInfo["Name"] as? String ?? "Desconocido"
        let artist = userInfo["Artist"] as? String ?? "Desconocido"
        let album = userInfo["Album"] as? String ?? ""
        let durationSec = userInfo["Duration"] as? Double ?? 180.0
        
        let position = fetchCurrentPlaybackPosition(app: "Spotify")
        let artwork = fetchSpotifyArtwork()
        
        self.currentTrack = MusicTrack(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            isPlaying: isPlaying,
            playbackPosition: position,
            duration: durationSec,
            appSource: "Spotify"
        )
        self.hasActiveMusic = isPlaying
        updateProgressTimer(isPlaying: isPlaying)
    }
    
    public func openMusicApp() {
        if currentTrack.appSource == "Spotify" {
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
            } else if let url = URL(string: "music://") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    public func togglePlayPause() {
        if currentTrack.appSource == "Spotify" {
            runAppleScript("tell application \"Spotify\" to playpause")
        } else if currentTrack.appSource == "Apple Music" {
            runAppleScript("tell application \"Music\" to playpause")
        } else {
            // Simulated toggle
            currentTrack.isPlaying.toggle()
            hasActiveMusic = currentTrack.isPlaying
            updateProgressTimer(isPlaying: currentTrack.isPlaying)
        }
    }
    
    @Published public var isShuffle: Bool = false
    
    public func toggleShuffle() {
        if currentTrack.appSource == "Spotify" {
            let script = """
            tell application "Spotify"
                set shuffling to not shuffling
                return shuffling
            end tell
            """
            if let result = runAppleScript(script) {
                isShuffle = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } else {
                isShuffle.toggle()
            }
        } else if currentTrack.appSource == "Apple Music" {
            let script = """
            tell application "Music"
                set shuffle enabled to not shuffle enabled
                return shuffle enabled
            end tell
            """
            if let result = runAppleScript(script) {
                isShuffle = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } else {
                isShuffle.toggle()
            }
        } else {
            isShuffle.toggle()
        }
    }
    
    public func nextTrack() {
        if currentTrack.appSource == "Spotify" {
            runAppleScript("tell application \"Spotify\" to next track")
        } else if currentTrack.appSource == "Apple Music" {
            runAppleScript("tell application \"Music\" to next track")
        }
    }
    
    public func previousTrack() {
        if currentTrack.appSource == "Spotify" {
            runAppleScript("tell application \"Spotify\" to previous track")
        } else if currentTrack.appSource == "Apple Music" {
            runAppleScript("tell application \"Music\" to previous track")
        }
    }
    
    public func seek(to position: TimeInterval) {
        currentTrack.playbackPosition = position
        if currentTrack.appSource == "Music" {
            runAppleScript("tell application \"Music\" to set player position to \(Int(position))")
        }
    }
    
    public func setDemoTrack(_ track: MusicTrack) {
        self.currentTrack = track
        self.hasActiveMusic = track.isPlaying
        updateProgressTimer(isPlaying: track.isPlaying)
    }
    
    private func updateProgressTimer(isPlaying: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        
        if isPlaying {
            progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.currentTrack.playbackPosition < self.currentTrack.duration {
                    self.currentTrack.playbackPosition += 1.0
                }
            }
        }
    }
    
    private func fetchAppleMusicArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            if exists (current track) then
                try
                    return raw data of artwork 1 of current track
                end try
            end if
        end tell
        """
        guard let scriptObj = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let descriptor = scriptObj.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let data = descriptor.data
        return NSImage(data: data)
    }
    
    private func fetchSpotifyArtwork() -> NSImage? {
        let script = """
        tell application "Spotify"
            if exists (current track) then
                try
                    return artwork url of current track
                end try
            end if
        end tell
        """
        guard let scriptObj = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let descriptor = scriptObj.executeAndReturnError(&error)
        guard error == nil, let urlString = descriptor.stringValue, let url = URL(string: urlString) else {
            return nil
        }
        if let data = try? Data(contentsOf: url) {
            return NSImage(data: data)
        }
        return nil
    }
    
    public func fetchCurrentPlaybackPosition(app: String) -> TimeInterval {
        if app == "Spotify" {
            let script = "tell application \"Spotify\" to player position"
            if let str = runAppleScript(script), let pos = Double(str.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pos
            }
        } else {
            let script = "tell application \"Music\" to player position"
            if let str = runAppleScript(script), let pos = Double(str.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pos
            }
        }
        return 0
    }
    
    private func checkActivePlayers() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check Apple Music first
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first != nil {
                let script = """
                tell application "Music"
                    if player state is not stopped then
                        return {player state as string, name of current track, artist of current track, album of current track, player position as string, duration of current track as string}
                    end if
                end tell
                """
                if let scriptObj = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    let desc = scriptObj.executeAndReturnError(&error)
                    if error == nil && desc.numberOfItems >= 6 {
                        let state = desc.atIndex(1)?.stringValue ?? ""
                        let isPlaying = state.lowercased() == "playing"
                        let title = desc.atIndex(2)?.stringValue ?? "Desconocido"
                        let artist = desc.atIndex(3)?.stringValue ?? "Desconocido"
                        let album = desc.atIndex(4)?.stringValue ?? ""
                        let posStr = desc.atIndex(5)?.stringValue?.replacingOccurrences(of: ",", with: ".") ?? "0"
                        let durStr = desc.atIndex(6)?.stringValue?.replacingOccurrences(of: ",", with: ".") ?? "180"
                        let pos = Double(posStr) ?? 0
                        let dur = Double(durStr) ?? 180
                        
                        let artwork = self.fetchAppleMusicArtwork()
                        DispatchQueue.main.async {
                            self.currentTrack = MusicTrack(
                                title: title,
                                artist: artist,
                                album: album,
                                artwork: artwork,
                                isPlaying: isPlaying,
                                playbackPosition: pos,
                                duration: dur,
                                appSource: "Apple Music"
                            )
                            self.hasActiveMusic = isPlaying
                            self.updateProgressTimer(isPlaying: isPlaying)
                        }
                        return
                    }
                }
            }
            
            // Check Spotify
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil {
                let script = """
                tell application "Spotify"
                    if player state is not stopped then
                        return {player state as string, name of current track, artist of current track, album of current track, player position as string, duration of current track as string}
                    end if
                end tell
                """
                if let scriptObj = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    let desc = scriptObj.executeAndReturnError(&error)
                    if error == nil && desc.numberOfItems >= 6 {
                        let state = desc.atIndex(1)?.stringValue ?? ""
                        let isPlaying = state.lowercased() == "playing"
                        let title = desc.atIndex(2)?.stringValue ?? "Desconocido"
                        let artist = desc.atIndex(3)?.stringValue ?? "Desconocido"
                        let album = desc.atIndex(4)?.stringValue ?? ""
                        let posStr = desc.atIndex(5)?.stringValue?.replacingOccurrences(of: ",", with: ".") ?? "0"
                        let durStr = desc.atIndex(6)?.stringValue?.replacingOccurrences(of: ",", with: ".") ?? "180"
                        let pos = Double(posStr) ?? 0
                        let dur = Double(durStr) ?? 180
                        
                        let artwork = self.fetchSpotifyArtwork()
                        DispatchQueue.main.async {
                            self.currentTrack = MusicTrack(
                                title: title,
                                artist: artist,
                                album: album,
                                artwork: artwork,
                                isPlaying: isPlaying,
                                playbackPosition: pos,
                                duration: dur,
                                appSource: "Spotify"
                            )
                            self.hasActiveMusic = isPlaying
                            self.updateProgressTimer(isPlaying: isPlaying)
                        }
                    }
                }
            }
        }
    }
    
    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        return output?.stringValue
    }
}
