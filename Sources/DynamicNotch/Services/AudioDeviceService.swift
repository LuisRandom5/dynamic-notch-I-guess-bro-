import CoreAudio
import AudioToolbox
import AppKit

public struct AudioOutputDevice: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let isDefault: Bool
    public let isAirPods: Bool
    
    public var icon: String {
        AudioDeviceService.shared.iconForDevice(name: name, isAirPods: isAirPods)
    }
}

public final class AudioDeviceService: NSObject, ObservableObject {
    public static let shared = AudioDeviceService()
    
    @Published public private(set) var currentDeviceName: String = "Altavoces"
    @Published public private(set) var currentVolume: Float = 0.5
    @Published public private(set) var isMuted: Bool = false
    public var onVolumeChanged: ((Float, Bool) -> Void)?
    
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var activeListenedDeviceID: AudioDeviceID = 0
    
    private var isInitialListenerTrigger = true
    
    private override init() {
        super.init()
        updateCurrentDeviceName()
        startVolumeMonitoring()
        // Después de 1 segundo, permitir que los cambios de CoreAudio publiquen la actividad SliderPill
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isInitialListenerTrigger = false
        }
    }
    
    public func getOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        
        let currentID = getDefaultOutputDeviceID()
        var result: [AudioOutputDevice] = []
        
        for id in devices {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            
            if streamSize > 0 {
                let name = getDeviceName(id: id)
                let isAirPods = name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats")
                result.append(AudioOutputDevice(
                    id: id,
                    name: name,
                    isDefault: id == currentID,
                    isAirPods: isAirPods
                ))
            }
        }
        
        return result
    }
    
    public func getDefaultOutputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
    
    public func setDefaultOutputDevice(id: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newID = id
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &newID
        )
        updateCurrentDeviceName()
    }
    
    public func cycleOutputDevice() {
        let devices = getOutputDevices()
        guard devices.count > 1 else { return }
        let currentID = getDefaultOutputDeviceID()
        if let idx = devices.firstIndex(where: { $0.id == currentID }) {
            let nextIdx = (idx + 1) % devices.count
            setDefaultOutputDevice(id: devices[nextIdx].id)
            AppState.shared.hapticService.triggerSnap()
        } else if let first = devices.first {
            setDefaultOutputDevice(id: first.id)
            AppState.shared.hapticService.triggerSnap()
        }
    }
    
    public func getDeviceName(id: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        withUnsafeMutablePointer(to: &cfName) { ptr in
            _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, ptr)
        }
        return (cfName as String?) ?? "Dispositivo de audio"
    }
    
    public func updateCurrentDeviceName() {
        let id = getDefaultOutputDeviceID()
        self.currentDeviceName = getDeviceName(id: id)
    }
    
    public var isAirPodsActive: Bool {
        let name = currentDeviceName.lowercased()
        return name.contains("airpods") || name.contains("beats") || name.contains("powerbeats")
    }
    
    public var isAirPlayActive: Bool {
        let name = currentDeviceName.lowercased()
        return name.contains("airplay") || name.contains("apple tv") || name.contains("tv")
    }
    
    /// Devuelve el icono exacto correspondiente al dispositivo actual conectado (ej: airpods.gen4 para AirPods 4)
    public var currentDeviceIcon: String {
        if isAirPodsActive {
            return BluetoothAudioService.shared.currentAirPodsSymbol
        }
        return iconForDevice(name: currentDeviceName, isAirPods: false)
    }
    
    /// Devuelve el SF Symbol exacto para cualquier dispositivo de audio por su nombre y tipo
    public func iconForDevice(name: String, isAirPods: Bool = false) -> String {
        let lower = name.lowercased()
        if isAirPods || lower.contains("airpods") || lower.contains("beats") || lower.contains("powerbeats") {
            return BluetoothAudioService.shared.symbolForDeviceName(name)
        } else if lower.contains("headphone") || lower.contains("auricular") || lower.contains("auriculares") || lower.contains("cascos") {
            return "headphones"
        } else if lower.contains("tv") || lower.contains("apple tv") || lower.contains("airplay") {
            return "airplayaudio"
        } else if lower.contains("homepod") || lower.contains("speaker") || lower.contains("altavoz") || lower.contains("altavoces") {
            return "speaker.wave.2.fill"
        } else {
            return "laptopcomputer"
        }
    }
    
    @objc public func selectDeviceMenuItem(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? AudioDeviceID {
            setDefaultOutputDevice(id: id)
        }
    }
    
    @objc public func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Volume Monitoring
    public func startVolumeMonitoring() {
        let devID = getDefaultOutputDeviceID()
        attachListeners(to: devID)
        
        var defaultDevAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleDefaultDeviceChanged()
            }
        }
        self.defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDevAddress,
            DispatchQueue.main,
            block
        )
    }
    
    private func attachListeners(to deviceID: AudioDeviceID) {
        detachListeners()
        guard deviceID != 0 else { return }
        self.activeListenedDeviceID = deviceID
        
        self.currentVolume = readVolume(for: deviceID)
        self.isMuted = readMute(for: deviceID)
        
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let newVol = self.readVolume(for: self.activeListenedDeviceID)
                let newMute = self.readMute(for: self.activeListenedDeviceID)
                self.currentVolume = newVol
                self.isMuted = newMute
                self.onVolumeChanged?(newVol, newMute)
                if !self.isInitialListenerTrigger {
                    self.publishVolumeActivity(volume: newVol, isMuted: newMute)
                }
            }
        }
        self.volumeListenerBlock = volBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, DispatchQueue.main, volBlock)
        
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let newVol = self.readVolume(for: self.activeListenedDeviceID)
                let newMute = self.readMute(for: self.activeListenedDeviceID)
                self.currentVolume = newVol
                self.isMuted = newMute
                self.onVolumeChanged?(newVol, newMute)
                if !self.isInitialListenerTrigger {
                    self.publishVolumeActivity(volume: newVol, isMuted: newMute)
                }
            }
        }
        self.muteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, muteBlock)
    }
    
    private func detachListeners() {
        guard activeListenedDeviceID != 0 else { return }
        if let block = volumeListenerBlock {
            var volAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(activeListenedDeviceID, &volAddress, DispatchQueue.main, block)
            volumeListenerBlock = nil
        }
        if let block = muteListenerBlock {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(activeListenedDeviceID, &muteAddress, DispatchQueue.main, block)
            muteListenerBlock = nil
        }
        activeListenedDeviceID = 0
    }
    
    private func handleDefaultDeviceChanged() {
        updateCurrentDeviceName()
        let newID = getDefaultOutputDeviceID()
        attachListeners(to: newID)
    }
    
    public func readVolume(for deviceID: AudioDeviceID) -> Float {
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0.5
        var volSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volAddress, 0, nil, &volSize, &vol)
        if status == noErr {
            return vol
        }
        return 0.5
    }
    
    public func readMute(for deviceID: AudioDeviceID) -> Bool {
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &isMuted)
        if status == noErr {
            return isMuted != 0
        }
        return false
    }
    
    public func setVolume(_ volume: Float) {
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != 0 else { return }
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = max(0.0, min(1.0, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &volAddress, 0, nil, size, &vol)
        self.currentVolume = vol
    }
    
    public func setMuted(_ muted: Bool) {
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != 0 else { return }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMutedVal: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &isMutedVal)
        self.isMuted = muted
        publishVolumeActivity(volume: currentVolume, isMuted: muted)
    }
    
    public func stepVolume(up: Bool) {
        let step: Float = 1.0 / 16.0 // 16 niveles estándar en macOS
        let newVol = up ? min(1.0, currentVolume + step) : max(0.0, currentVolume - step)
        setVolume(newVol)
        if isMuted && up {
            setMuted(false)
        } else {
            publishVolumeActivity(volume: newVol, isMuted: isMuted)
        }
        
        // Sonidito inmersivo al regular volumen (pop/tick nativo de macOS)
        playVolumeFeedbackSound()
    }
    
    private var volumeSoundID: SystemSoundID = 0
    private var isVolumeSoundLoaded: Bool = false
    
    /// Reproduce el sonido nativo auténtico de volumen de macOS (volume.aiff)
    public func playVolumeFeedbackSound() {
        guard AppState.shared.enableSoundFeedback && !isMuted else { return }
        if !isVolumeSoundLoaded {
            let soundURL = URL(fileURLWithPath: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff")
            if FileManager.default.fileExists(atPath: soundURL.path) {
                AudioServicesCreateSystemSoundID(soundURL as CFURL, &volumeSoundID)
                isVolumeSoundLoaded = true
            }
        }
        if isVolumeSoundLoaded && volumeSoundID != 0 {
            AudioServicesPlaySystemSound(volumeSoundID)
        } else {
            NSSound.beep()
        }
    }
    
    /// Publica la actividad SliderPill en la Isla Dinámica con duración natural de 2.5 s
    public func publishVolumeActivity(volume: Float, isMuted: Bool) {
        // Si el reproductor extendido o la repisa están abiertos, no publicar el HUD flotante
        // ya que el reproductor posee su propio slider reactivo en pantalla.
        if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
            return
        }
        let activity = LiveActivity(
            id: "system_slider",
            priority: 85,
            style: .sliderPill,
            tint: isMuted ? DesignTokens.red : DesignTokens.green,
            duration: 2.5,
            sliderState: .volume(level: volume, isMuted: isMuted)
        )
        ActivityCenter.shared.publish(activity)
    }
    
    // MARK: - Control de Micrófono Físico de Entrada (Mute/Unmute Real)
    public func getDefaultInputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
    
    public func isMicrophoneMuted() -> Bool {
        let deviceID = getDefaultInputDeviceID()
        guard deviceID != 0 else { return false }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddress) else { return false }
        var isMutedVal: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &isMutedVal)
        return isMutedVal == 1
    }
    
    private var preMuteVolumeScalar: Float32 = 0.60
    
    public func setMicrophoneMuted(_ muted: Bool) {
        let deviceID = getDefaultInputDeviceID()
        guard deviceID != 0 else { return }
        
        // 1. Silenciado directo por hardware CoreAudio (kAudioDevicePropertyMute)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            var isMutedVal: UInt32 = muted ? 1 : 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &isMutedVal)
        }
        
        // 2. Control nativo del volumen escalar CoreAudio (kAudioDevicePropertyVolumeScalar)
        // 100% thread-safe, sin AppleScript, sincronizado instantáneamente con macOS
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &volAddress) {
            var size = UInt32(MemoryLayout<Float32>.size)
            if muted {
                var currentVol: Float32 = 0.0
                if AudioObjectGetPropertyData(deviceID, &volAddress, 0, nil, &size, &currentVol) == noErr && currentVol > 0.05 {
                    self.preMuteVolumeScalar = currentVol
                }
                var zeroVol: Float32 = 0.0
                AudioObjectSetPropertyData(deviceID, &volAddress, 0, nil, size, &zeroVol)
            } else {
                var restoreVol: Float32 = max(0.25, self.preMuteVolumeScalar)
                AudioObjectSetPropertyData(deviceID, &volAddress, 0, nil, size, &restoreVol)
            }
        }
    }
}
