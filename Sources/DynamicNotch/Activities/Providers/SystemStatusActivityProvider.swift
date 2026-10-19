import AppKit
import CoreAudio
import CoreMediaIO
import Network
import SwiftUI
import SystemConfiguration

/// Avisos del sistema al estilo de la Isla Dinámica del iPhone (interruptor de silencio, punto de cámara…):
/// - Bloq Mayús: aviso breve al activarlo o desactivarlo.
/// - Red: sin internet / conectado de nuevo, y VPN activada o desactivada.
/// - Cámara y micrófono en uso: bolita mientras alguna app los usa. Sólo se CONSULTA si el dispositivo está
///   en uso por alguien (`…IsRunningSomewhere`); el app nunca abre la cámara ni el micrófono.
public final class SystemStatusActivityProvider {
    public static let shared = SystemStatusActivityProvider()

    private static let capsLockId = "system_capslock"
    private static let networkId = "system_network"
    private static let privacyId = "system_privacy"

    private var flagsMonitors: [Any] = []
    private var capsLockOn = false
    private let pathMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.luisrandom.DynamicNotch.Network", qos: .utility)
    private var lastNetwork: (online: Bool, vpn: Bool)?
    private var pendingNetwork: DispatchWorkItem?
    private var privacyTimer: Timer?
    private let privacyQueue = DispatchQueue(label: "com.luisrandom.DynamicNotch.Privacy", qos: .utility)
    private var privacyState: (camera: Bool, microphone: Bool) = (false, false)
    /// Al arrancar el estado actual sólo se registra (no es un cambio)
    private var startedAt = Date.distantFuture
    private static let launchGrace: TimeInterval = 5

    private init() {}

    public func start() {
        startedAt = Date()
        startCapsLock()
        startNetwork()
        startPrivacy()
    }

    private var isPastLaunchGrace: Bool { Date().timeIntervalSince(startedAt) > Self.launchGrace }

    // MARK: Bloq Mayús

    private func startCapsLock() {
        capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            flagsMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handler(event)
            return event
        }) {
            flagsMonitors.append(local)
        }
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let on = flags.contains(.capsLock)
        guard on != capsLockOn else { return }
        capsLockOn = on
        guard AppState.shared.capsLockIndicatorEnabled else { return }
        publishBrief(
            id: Self.capsLockId,
            icon: on ? "capslock.fill" : "capslock",
            label: on ? "Bloq Mayús" : "Mayús desact.",
            tint: on ? DesignTokens.green : Color.white.opacity(0.7),
            duration: 1.6
        )
    }

    // MARK: Red y VPN

    private func startNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = path.status == .satisfied
            let vpn = online && Self.primaryInterfaceIsTunnel()
            DispatchQueue.main.async { self.networkChanged(online: online, vpn: vpn, path: path) }
        }
        pathMonitor.start(queue: networkQueue)
    }

    /// La interfaz principal es un túnel (VPN de túnel completo): utun, ipsec, ppp…
    private static func primaryInterfaceIsTunnel() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "DynamicNotch" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = global["PrimaryInterface"] as? String else { return false }
        return ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { primary.hasPrefix($0) }
    }

    private func networkChanged(online: Bool, vpn: Bool, path: NWPath) {
        // Se espera a que la red se asiente: al cambiar de Wi-Fi pasa un instante sin conexión
        pendingNetwork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.announceNetwork(online: online, vpn: vpn, path: path) }
        pendingNetwork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func announceNetwork(online: Bool, vpn: Bool, path: NWPath) {
        let previous = lastNetwork
        lastNetwork = (online, vpn)
        guard let previous, isPastLaunchGrace, AppState.shared.networkIndicatorEnabled else { return }
        if previous.online != online {
            let viaWiFi = path.usesInterfaceType(.wifi)
            publishBrief(
                id: Self.networkId,
                icon: online ? (viaWiFi ? "wifi" : "network") : "wifi.slash",
                label: online ? "Conectado" : "Sin internet",
                tint: online ? DesignTokens.green : DesignTokens.red,
                duration: online ? 2.0 : 3.0
            )
        } else if previous.vpn != vpn {
            publishBrief(
                id: Self.networkId,
                icon: vpn ? "lock.shield.fill" : "lock.open.fill",
                label: vpn ? "VPN activada" : "VPN desactivada",
                tint: vpn ? DesignTokens.blue : Color.white.opacity(0.7),
                duration: 2.0
            )
        }
    }

    // MARK: Cámara y micrófono en uso

    private func startPrivacy() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.pollPrivacy() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        privacyTimer = timer
        pollPrivacy()
    }

    private func pollPrivacy() {
        guard AppState.shared.privacyIndicatorEnabled else {
            if privacyState.camera || privacyState.microphone {
                privacyState = (false, false)
                ActivityCenter.shared.remove(id: Self.privacyId)
            }
            return
        }
        privacyQueue.async { [weak self] in
            let camera = Self.isAnyCameraRunning()
            let microphone = Self.isDefaultInputRunning()
            DispatchQueue.main.async { self?.updatePrivacy(camera: camera, microphone: microphone) }
        }
    }

    private func updatePrivacy(camera: Bool, microphone: Bool) {
        guard camera != privacyState.camera || microphone != privacyState.microphone else { return }
        privacyState = (camera, microphone)
        guard camera || microphone else {
            ActivityCenter.shared.end(id: Self.privacyId, dismissAfter: 0)
            return
        }
        // Como los puntos de privacidad del iPhone: verde la cámara, naranja el micrófono
        let icon = camera ? "video.fill" : "mic.fill"
        let tint = camera ? DesignTokens.green : DesignTokens.orange
        let title = camera && microphone ? "Cámara y micrófono" : (camera ? "Cámara" : "Micrófono")
        var activity = LiveActivity(
            id: Self.privacyId,
            kind: .recording,
            priority: ActivityRelevance.generic,
            style: .pill,
            title: title,
            subtitle: "En uso por una app",
            leading: AnyView(Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(tint)),
            trailing: AnyView(Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(tint)),
            bolitaVariant: .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: icon),
            tint: tint
        )
        activity.prefersBubble = true
        ActivityCenter.shared.publish(activity)
    }

    /// ¿Alguna cámara está en uso por algún proceso? (CoreMediaIO, sin abrirla)
    private static func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else {
            return false
        }
        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var running: UInt32 = 0
            var dataUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &dataUsed, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }

    /// ¿El micrófono predeterminado está en uso por algún proceso? (CoreAudio, sin abrirlo)
    private static func isDefaultInputRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: Aviso breve

    /// Aviso de pocos segundos en el notch, como el del interruptor de silencio del iPhone: entra de inmediato
    /// (urgente) y regresa a lo que había
    private func publishBrief(id: String, icon: String, label: String, tint: Color, duration: TimeInterval) {
        ActivityCenter.shared.publish(LiveActivity(
            id: id,
            priority: ActivityRelevance.systemStatus,
            style: .pill,
            title: label,
            leading: AnyView(
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(tint)
                    .contentTransition(.symbolEffect(.replace))
            ),
            trailing: AnyView(
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .fixedSize()
            ),
            bolitaVariant: .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: icon),
            tint: tint,
            duration: duration,
            isUrgent: true
        ))
    }
}
