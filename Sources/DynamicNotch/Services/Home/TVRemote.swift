import Foundation
import SwiftUI

// MARK: - Control de la tele
// Control remoto de la tele con Google TV desde Casa, por ADB en la red local (la "depuración por USB" de la tele,
// puerto 5555; la Mac ya está autorizada). Usa el `adb` oficial de Google (brew install --cask
// android-platform-tools): cada tecla es `input keyevent` y tarda ~0.13 s. Qué app está abierta, si está prendida y
// el volumen salen de `dumpsys` y `cmd media_session`. Si el proceso de adb se queda trabado ("No route to host",
// pasa al despertar la Mac), se reinicia y se vuelve a conectar.
//
// Más adelante se puede cambiar el día a día al protocolo del control de Google TV (puertos 6466/6467), que no
// depende de la depuración; ADB seguiría para abrir apps.
@MainActor
public final class TVRemote: ObservableObject {
    public static let shared = TVRemote()

    public enum Key: String {
        case wake = "KEYCODE_WAKEUP", sleep = "KEYCODE_SLEEP"
        case up = "KEYCODE_DPAD_UP", down = "KEYCODE_DPAD_DOWN", left = "KEYCODE_DPAD_LEFT", right = "KEYCODE_DPAD_RIGHT"
        case ok = "KEYCODE_DPAD_CENTER", back = "KEYCODE_BACK", home = "KEYCODE_HOME"
        case volumeUp = "KEYCODE_VOLUME_UP", volumeDown = "KEYCODE_VOLUME_DOWN", mute = "KEYCODE_VOLUME_MUTE"
        case playPause = "KEYCODE_MEDIA_PLAY_PAUSE", next = "KEYCODE_MEDIA_NEXT", previous = "KEYCODE_MEDIA_PREVIOUS"
    }

    public struct App: Identifiable, Equatable {
        public let package: String
        public let name: String
        public let color: Color
        public var id: String { package }
    }

    /// Las apps que se ofrecen (si están instaladas), en este orden
    static let catalog: [App] = [
        App(package: "com.google.android.youtube.tv", name: "YouTube", color: Color(red: 1, green: 0.2, blue: 0.2)),
        App(package: "com.netflix.ninja", name: "Netflix", color: Color(red: 0.9, green: 0.04, blue: 0.08)),
        App(package: "com.spotify.tv.android", name: "Spotify", color: Color(red: 0.12, green: 0.84, blue: 0.38)),
        App(package: "com.amazon.amazonvideo.livingroom", name: "Prime Video", color: Color(red: 0.0, green: 0.66, blue: 0.88)),
        App(package: "com.wbd.stream", name: "Max", color: Color(red: 0.25, green: 0.3, blue: 1)),
        App(package: "com.disney.disneyplus", name: "Disney+", color: Color(red: 0.07, green: 0.55, blue: 0.85)),
        App(package: "com.apple.atve.androidtv.appletv", name: "Apple TV", color: .gray),
        App(package: "com.crunchyroll.crunchyroid", name: "Crunchyroll", color: .orange),
        App(package: "tv.twitch.android.app", name: "Twitch", color: .purple),
        App(package: "com.google.android.youtube.tvmusic", name: "YT Music", color: .red),
        App(package: "com.stremio.one", name: "Stremio", color: .indigo),
    ]

    @Published public var isShowingRemote = false
    @Published public private(set) var isAwake: Bool?
    @Published public private(set) var currentPackage: String?
    @Published public private(set) var volume: Int?
    @Published public private(set) var installed: [App] = []
    @Published public private(set) var problem: String?

    private let adbPath: String? = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb",
                                    NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    private var loadedApps = false

    private init() {}

    private var serial: String? { TVNotifier.shared.tvHost.map { "\($0):5555" } }

    /// Hay `adb` y una tele elegida en Ajustes › Casa
    public var isAvailable: Bool { adbPath != nil && serial != nil }

    public var currentAppName: String? {
        guard let currentPackage else { return nil }
        return Self.catalog.first { $0.package == currentPackage }?.name
            ?? (currentPackage.contains("launcher") || currentPackage.contains("tvlauncher") ? L("Inicio") : nil)
    }

    // MARK: - Acciones

    public func press(_ key: Key) {
        Task {
            let ok = await adb(["shell", "input", "keyevent", key.rawValue])
            guard ok != nil else { return }
            switch key {
            case .volumeUp, .volumeDown, .mute, .wake, .sleep: await refresh()
            default: break
            }
        }
    }

    public func togglePower() {
        press(isAwake == false ? .wake : .sleep)
    }

    public func open(_ app: App) {
        Task {
            _ = await adb(["shell", "monkey", "-p", app.package, "-c", "android.intent.category.LEANBACK_LAUNCHER", "1"])
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
        }
    }

    /// Prendida, app abierta y volumen, en una sola llamada
    public func refresh() async {
        guard let output = await adb(["shell",
            "dumpsys power | grep -m1 mWakefulness=; dumpsys window | grep -m1 mCurrentFocus; cmd media_session volume --stream 3 --get 2>/dev/null | tail -1"])
        else { return }
        isAwake = output.contains("mWakefulness=Awake") ? true : (output.contains("mWakefulness=") ? false : isAwake)
        if let range = output.range(of: #"u0 ([a-zA-Z0-9_.]+)/"#, options: .regularExpression) {
            currentPackage = String(output[range].dropFirst(3).dropLast())
        }
        if let range = output.range(of: #"volume is \d+"#, options: .regularExpression) {
            volume = Int(output[range].split(separator: " ").last ?? "")
        }
        if !loadedApps { await loadApps() }
    }

    private func loadApps() async {
        guard let output = await adb(["shell", "pm list packages"]) else { return }
        let packages = Set(output.split(separator: "\n").map { $0.replacingOccurrences(of: "package:", with: "") })
        installed = Self.catalog.filter { packages.contains($0.package) }
        loadedApps = true
    }

    // MARK: - adb

    /// Corre adb con la tele; si no la encuentra, se conecta (y si sigue sin poder, reinicia adb) y reintenta una vez
    private func adb(_ arguments: [String]) async -> String? {
        guard let adbPath, let serial else {
            problem = adbPath == nil ? L("Falta adb en la Mac (brew install --cask android-platform-tools)") : L("Elige tu tele en Ajustes › Casa")
            return nil
        }
        var result = await Self.run(adbPath, ["-s", serial] + arguments)
        if result.status != 0 {
            _ = await Self.run(adbPath, ["connect", serial])
            result = await Self.run(adbPath, ["-s", serial] + arguments)
        }
        if result.status != 0 {
            // El servidor de adb se queda trabado al despertar la Mac: se reinicia
            _ = await Self.run(adbPath, ["kill-server"])
            _ = await Self.run(adbPath, ["connect", serial])
            result = await Self.run(adbPath, ["-s", serial] + arguments)
        }
        if result.status != 0 {
            DNDLogger.log("Tele: adb falló (\(arguments.first ?? "")): \(result.output.prefix(160))")
            problem = result.output.contains("unauthorized")
                ? L("Acepta la depuración en la tele")
                : L("La tele no responde: ¿está prendida y con la depuración activada?")
            return nil
        }
        problem = nil
        return result.output
    }

    private nonisolated static func run(_ path: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                // Que una tele dormida no deje colgado el control
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
