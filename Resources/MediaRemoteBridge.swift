import Foundation
import AppKit

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW) else { exit(1) }

typealias MRRegisterForNotifications = @convention(c) (DispatchQueue) -> Void
typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias MRGetNowPlayingApplicationIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
typealias MRGetNowPlayingClient = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
typealias MRClientGetBundleIdentifier = @convention(c) (AnyObject) -> CFString?
typealias MRClientGetDisplayName = @convention(c) (AnyObject) -> CFString?
typealias MRSendCommand = @convention(c) (UInt32, AnyObject?) -> Bool

let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")!
let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")!
let playSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")!
let clientSym = dlsym(handle, "MRMediaRemoteGetNowPlayingClient")!
let bundleSym = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier")!
let nameSym = dlsym(handle, "MRNowPlayingClientGetDisplayName")!
let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand")!

let register = unsafeBitCast(regSym, to: MRRegisterForNotifications.self)
let getInfo = unsafeBitCast(infoSym, to: MRGetNowPlayingInfo.self)
let getPlay = unsafeBitCast(playSym, to: MRGetNowPlayingApplicationIsPlaying.self)
let getClient = unsafeBitCast(clientSym, to: MRGetNowPlayingClient.self)
let getBundle = unsafeBitCast(bundleSym, to: MRClientGetBundleIdentifier.self)
let getName = unsafeBitCast(nameSym, to: MRClientGetDisplayName.self)
let sendCommand = unsafeBitCast(cmdSym, to: MRSendCommand.self)

register(DispatchQueue.main)

var lastPayloadString = ""
var artworkCache: [String: String] = [:]
var durationCache: [String: Double] = [:]
var nilDictCount = 0

func emitNowPlaying() {
    getPlay(DispatchQueue.main) { isAppPlaying in
        var bundleId: String? = nil
        var appName: String? = nil
        
        let fetchInfo: () -> Void = {
            getInfo(DispatchQueue.main) { dict in
                guard let dict = dict as? [String: Any] else {
                    nilDictCount += 1
                    if !isAppPlaying && !lastPayloadString.isEmpty && nilDictCount >= 3 {
                        nilDictCount = 0
                        lastPayloadString = ""
                        let emptyMsg = "{\"isPlaying\":false,\"title\":\"\",\"artist\":\"\",\"appSource\":\"\"}\n"
                        FileHandle.standardOutput.write(emptyMsg.data(using: .utf8)!)
                    }
                    return
                }
                nilDictCount = 0
                
                let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let rawDuration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0.0
                let elapsed = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0.0
                let rate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0.0
                let isPlaying = isAppPlaying || rate > 0.0
                
                // Si título y artista están vacíos
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nilDictCount += 1
                    if !isPlaying && !lastPayloadString.isEmpty && nilDictCount >= 3 {
                        nilDictCount = 0
                        lastPayloadString = ""
                        let emptyMsg = "{\"isPlaying\":false,\"title\":\"\",\"artist\":\"\",\"appSource\":\"\"}\n"
                        FileHandle.standardOutput.write(emptyMsg.data(using: .utf8)!)
                    }
                    return
                }
                nilDictCount = 0
                
                // Resolución y caché de duración real
                var resolvedDuration = rawDuration
                if rawDuration > 2.0 {
                    durationCache[title] = rawDuration
                } else if let cached = durationCache[title], cached > 2.0 {
                    resolvedDuration = cached
                } else if resolvedDuration <= 1.0 {
                    resolvedDuration = 180.0 // Duración por defecto si está cargando
                }
                
                // Resolución y caché de carátula
                var artworkBase64 = ""
                if let artData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, artData.count < 3_000_000, !artData.isEmpty {
                    artworkBase64 = artData.base64EncodedString()
                    artworkCache[title] = artworkBase64
                } else if let cached = artworkCache[title], !cached.isEmpty {
                    artworkBase64 = cached
                }
                
                // Si la carátula o duración aún no cargaron en Safari, reintentar en 0.5s
                if (artworkBase64.isEmpty || rawDuration <= 2.0) && isPlaying {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        emitNowPlaying()
                    }
                }
                
                var source = "YouTube"
                let b = (bundleId ?? "").lowercased()
                let name = (appName ?? "").lowercased()
                let t = title.lowercased()
                if b.contains("spotify") || name.contains("spotify") { source = "Spotify" }
                else if b.contains("apple.music") || name.contains("music") { source = "Apple Music" }
                else if t.contains("youtube") || name.contains("youtube") { source = "YouTube" }
                else if b.contains("webkit") || b.contains("safari") || name.contains("safari") { source = "YouTube" }
                else if b.contains("chrome") || name.contains("chrome") { source = "Chrome" }
                else if b.contains("arc") || name.contains("arc") { source = "Arc" }
                else if b.contains("brave") || name.contains("brave") { source = "Brave" }
                else if !name.isEmpty { source = appName! }
                
                let payload: [String: Any] = [
                    "title": title.isEmpty ? "Video Web" : title,
                    "artist": artist.isEmpty ? source : artist,
                    "album": album,
                    "duration": resolvedDuration,
                    "elapsed": elapsed,
                    "isPlaying": isPlaying,
                    "appSource": source,
                    "artwork": artworkBase64
                ]
                
                let checkKey = "\(title)_\(artist)_\(isPlaying)_\(Int(elapsed))_\(Int(resolvedDuration))_\(!artworkBase64.isEmpty)"
                if checkKey != lastPayloadString {
                    lastPayloadString = checkKey
                    if let data = try? JSONSerialization.data(withJSONObject: payload),
                       var str = String(data: data, encoding: .utf8) {
                        str += "\n"
                        FileHandle.standardOutput.write(str.data(using: .utf8)!)
                    }
                }
            }
        }
        
        getClient(DispatchQueue.main) { client in
            if let client = client {
                bundleId = getBundle(client) as String?
                appName = getName(client) as String?
            }
            fetchInfo()
        }
    }
}

// 1. Escuchar notificaciones del sistema
let center = NotificationCenter.default
let notifNames = [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
]
for n in notifNames {
    center.addObserver(forName: NSNotification.Name(n), object: nil, queue: .main) { _ in
        emitNowPlaying()
    }
}

// 2. Heartbeat timer para cambios de posición o streaming
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    emitNowPlaying()
}

// 3. Leer comandos de stdin en segundo plano
let stdinSource = DispatchSource.makeReadSource(fileDescriptor: fileno(stdin), queue: DispatchQueue.global())
stdinSource.setEventHandler {
    var buffer = [UInt8](repeating: 0, count: 256)
    let bytesRead = read(fileno(stdin), &buffer, buffer.count)
    if bytesRead > 0 {
        let cmd = String(decoding: buffer[0..<bytesRead], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            switch cmd {
            case "toggle":
                _ = sendCommand(2, nil)
            case "play":
                _ = sendCommand(0, nil)
            case "pause":
                _ = sendCommand(1, nil)
            case "next":
                _ = sendCommand(4, nil)
            case "prev":
                _ = sendCommand(5, nil)
            case "refresh":
                emitNowPlaying()
            default:
                break
            }
            emitNowPlaying()
        }
    }
}
stdinSource.resume()

// Emit inicial
emitNowPlaying()

RunLoop.main.run()
