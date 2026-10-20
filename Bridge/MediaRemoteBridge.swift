// Puente de "lo que está sonando" (MediaRemote). Desde macOS 15.4 MediaRemote sólo responde a procesos firmados
// por Apple, así que esto se compila como biblioteca y la carga `/usr/bin/perl` (que viene en todos los Mac y es de
// Apple): ver Resources/MediaRemoteBridge.pl y NowPlayingService. Antes se corría con `/usr/bin/swift`, que sólo
// existe con las herramientas de desarrollo instaladas (en otros Mac salía la ventana para instalarlas).
// Protocolo: una línea JSON por cambio en la salida estándar; comandos por la entrada estándar (toggle, next…).
import Foundation
import AppKit

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
let handle: UnsafeMutableRawPointer = dlopen(path, RTLD_NOW) ?? { exit(1) }()

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


var lastPayloadString = ""
var lastSentArtKey = ""
var artworkCache: [String: String] = [:]
var durationCache: [String: Double] = [:]
var nilDictCount = 0
var retryTrackKey = ""
var retryCount = 0
var pendingRetryWorkItem: DispatchWorkItem? = nil

func emitNowPlaying() {
    getPlay(DispatchQueue.main) { isAppPlaying in
        var bundleId: String? = nil
        var appName: String? = nil
        
        let fetchInfo: () -> Void = {
            getInfo(DispatchQueue.main) { dict in
                guard let dict = dict as? [String: Any] else {
                    nilDictCount += 1
                    if !isAppPlaying && !lastPayloadString.isEmpty && nilDictCount >= 4 {
                        nilDictCount = 0
                        lastPayloadString = ""
                        lastSentArtKey = ""
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
                    if !isPlaying && !lastPayloadString.isEmpty && nilDictCount >= 4 {
                        nilDictCount = 0
                        lastPayloadString = ""
                        lastSentArtKey = ""
                        let emptyMsg = "{\"isPlaying\":false,\"title\":\"\",\"artist\":\"\",\"appSource\":\"\"}\n"
                        FileHandle.standardOutput.write(emptyMsg.data(using: .utf8)!)
                    }
                    return
                }
                nilDictCount = 0
                
                // Ignorar sonidos efímeros de chat web (WhatsApp, Telegram, Slack) para que nunca secuestren el reproductor
                let tLower = title.lowercased()
                if tLower.contains("whatsapp") || tLower.contains("telegram") || tLower.contains("slack") || tLower.contains("messenger") || (rawDuration <= 4.0 && artist.isEmpty && title.hasPrefix("(")) {
                    return
                }
                
                let trackKey = "\(title)_\(artist)"
                if trackKey != retryTrackKey {
                    retryTrackKey = trackKey
                    retryCount = 0
                    lastSentArtKey = ""
                    pendingRetryWorkItem?.cancel()
                    pendingRetryWorkItem = nil
                }
                
                // Resolución y caché de duración real
                var resolvedDuration = rawDuration
                if rawDuration > 2.0 {
                    durationCache[title] = rawDuration
                    if durationCache.count > 40 { durationCache.removeAll(keepingCapacity: true); durationCache[title] = rawDuration }
                } else if let cached = durationCache[title], cached > 2.0 {
                    resolvedDuration = cached
                } else if resolvedDuration <= 1.0 {
                    resolvedDuration = 180.0 // Duración por defecto si está cargando
                }
                
                // Resolución inteligente de carátula: buscar en claves estándar y comprimir en JPEG ligero si supera 250KB
                var rawArtData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                if rawArtData == nil {
                    for (k, v) in dict {
                        if k.lowercased().contains("artwork") {
                            if let d = v as? Data {
                                rawArtData = d
                                break
                            }
                        }
                    }
                }
                
                let artworkUrl = dict["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String ?? ""
                
                var processedArtData: Data? = nil
                if let raw = rawArtData, raw.count > 0 {
                    if raw.count > 250_000,
                       let img = NSImage(data: raw),
                       let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                        processedArtData = jpeg
                    } else {
                        processedArtData = raw
                    }
                }
                
                let artByteCount = processedArtData?.count ?? 0
                let currentArtKey = "\(title)_\(artist)_\(artByteCount)"
                var hasArtwork = artByteCount > 0 || (artworkCache[title] != nil) || (artworkCache[trackKey] != nil)
                var artworkBase64ToSend = ""
                
                if artByteCount > 0, let artData = processedArtData {
                    let encoded = artData.base64EncodedString()
                    if artworkCache.count > 25 { artworkCache.removeAll(keepingCapacity: true) }
                    artworkCache[title] = encoded
                    artworkCache[trackKey] = encoded
                    if currentArtKey != lastSentArtKey {
                        artworkBase64ToSend = encoded
                        lastSentArtKey = currentArtKey
                    }
                    hasArtwork = true
                    
                    // Guardar directamente en caché de disco para acceso instantáneo por ArtworkResolverService
                    if !title.isEmpty {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let combined = "\(cleanTitle)_\(cleanArtist)"
                        if let key = combined.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                            if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                                let dir = cachesURL.appendingPathComponent("com.luisrandom.DynamicNotch/Artworks", isDirectory: true)
                                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                                let fileURL = dir.appendingPathComponent("\(key).jpg")
                                try? artData.write(to: fileURL)
                            }
                        }
                    }
                } else if let cached = artworkCache[trackKey] ?? artworkCache[title], !cached.isEmpty {
                    if currentArtKey != lastSentArtKey {
                        artworkBase64ToSend = cached
                        lastSentArtKey = currentArtKey
                    }
                    hasArtwork = true
                }
                
                // Reintento acotado (máx 2 veces por pista) si la carátula o duración aún no cargaron en navegador
                if (!hasArtwork || rawDuration <= 2.0) && isPlaying && retryCount < 2 && pendingRetryWorkItem == nil {
                    retryCount += 1
                    let work = DispatchWorkItem {
                        pendingRetryWorkItem = nil
                        emitNowPlaying()
                    }
                    pendingRetryWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
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
                
                let checkKey = "\(title)_\(artist)_\(isPlaying)_\(Int(elapsed))_\(Int(resolvedDuration))_\(hasArtwork)_\(!artworkBase64ToSend.isEmpty)"
                if checkKey != lastPayloadString {
                    lastPayloadString = checkKey
                    let payload: [String: Any] = [
                        "title": title.isEmpty ? "Video Web" : title,
                        "artist": artist.isEmpty ? source : artist,
                        "album": album,
                        "duration": resolvedDuration,
                        "elapsed": elapsed,
                        "isPlaying": isPlaying,
                        "appSource": source,
                        "artwork": artworkBase64ToSend,
                        "artworkUrl": artworkUrl
                    ]
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

func startBridge() {
    register(DispatchQueue.main)

    // 1. Escuchar notificaciones del sistema (tiempo real sin latencia)
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

    // 2. Heartbeat ligero de respaldo (2.5s en vez de 1.0s para ahorrar CPU cuando está en segundo plano)
    Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
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
                case "shuffle":
                    _ = sendCommand(6, nil)
                case "repeat":
                    _ = sendCommand(7, nil)
                case "refresh", "getArtwork":
                    lastPayloadString = ""
                    lastSentArtKey = ""
                    emitNowPlaying()
                default:
                    break
                }
                emitNowPlaying()
            }
        } else {
            // EOF o pipe roto: el proceso padre DynamicNotch se cerró. Terminar limpiamente sin bucle de CPU.
            stdinSource.cancel()
            exit(0)
        }
    }
    stdinSource.setCancelHandler {
        exit(0)
    }
    stdinSource.resume()

    // Emit inicial
    emitNowPlaying()
}

/// Punto de entrada que llama perl (`DynaLoader::dl_install_xsub`): los dos argumentos son los de una XSUB y no se usan
@_cdecl("dn_media_bridge_main")
public func dnMediaBridgeMain(_ perl: UnsafeMutableRawPointer?, _ cv: UnsafeMutableRawPointer?) {
    setvbuf(stdout, nil, _IOLBF, 0)
    startBridge()
    RunLoop.main.run()
}
