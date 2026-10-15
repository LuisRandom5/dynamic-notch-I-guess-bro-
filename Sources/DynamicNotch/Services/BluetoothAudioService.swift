import CoreAudio
import Foundation
import IOBluetooth

private final class BluetoothDeviceObserver: NSObject {
    static let shared = BluetoothDeviceObserver()
    private var connectNotification: IOBluetoothUserNotification?
    
    func startObserving() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(notification:device:))
        )
        DNDLogger.log("BluetoothDeviceObserver: IOBluetooth connect notifications registered: \(connectNotification != nil)")
    }
    
    @objc func deviceConnected(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? device.nameOrAddress ?? "AirPods"
        DNDLogger.log("BluetoothDeviceObserver: Hardware Bluetooth connected -> '\(name)', isConnected=\(device.isConnected())")
        
        let isAirPods = name.localizedCaseInsensitiveContains("AirPods") ||
                        name.localizedCaseInsensitiveContains("Beats") ||
                        device.deviceClassMinor == 1
                        
        if isAirPods {
            DispatchQueue.main.async {
                BluetoothAudioService.shared.handleAirPodsConnected(name: name)
            }
        }
        
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(notification:device:)))
    }
    
    @objc func deviceDisconnected(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? device.nameOrAddress ?? "AirPods"
        DNDLogger.log("BluetoothDeviceObserver: Hardware Bluetooth disconnected -> '\(name)'")
        DispatchQueue.main.async {
            BluetoothAudioService.shared.handleAirPodsDisconnected(name: name)
        }
    }
}

public final class BluetoothAudioService {
    public static let shared = BluetoothAudioService()
    
    private var lastConnectedDevice: String = ""
    
    private init() {
        startMonitoringAudioDevices()
        BluetoothDeviceObserver.shared.startObserving()
    }
    
    public func handleAirPodsConnected(name: String) {
        DNDLogger.log("BluetoothAudioService.handleAirPodsConnected: '\(name)'")
        if name != lastConnectedDevice {
            self.lastConnectedDevice = name
            self.fetchBatteryAndTriggerAlert(deviceName: name)
        }
    }
    
    public func handleAirPodsDisconnected(name: String) {
        DNDLogger.log("BluetoothAudioService.handleAirPodsDisconnected: '\(name)'")
        if lastConnectedDevice == name || lastConnectedDevice.localizedCaseInsensitiveContains("AirPods") {
            self.lastConnectedDevice = ""
        }
    }
    
    public func startMonitoringAudioDevices() {
        var defaultDevAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var devListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listener: AudioObjectPropertyListenerProc = { _, _, _, _ in
            DispatchQueue.main.async {
                BluetoothAudioService.shared.checkDefaultOutputDevice()
            }
            return noErr
        }
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDevAddress,
            listener,
            nil
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devListAddress,
            listener,
            nil
        )
        
        // Verificación de dispositivos Bluetooth ya emparejados y conectados
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for dev in paired {
                if dev.isConnected() {
                    let devName = dev.name ?? dev.nameOrAddress ?? ""
                    if devName.localizedCaseInsensitiveContains("AirPods") || devName.localizedCaseInsensitiveContains("Beats") {
                        DNDLogger.log("BluetoothAudioService: Paired AirPods already connected on launch: '\(devName)'")
                        dev.register(forDisconnectNotification: BluetoothDeviceObserver.shared, selector: #selector(BluetoothDeviceObserver.deviceDisconnected(notification:device:)))
                    }
                }
            }
        }
        
        // Verificación inicial de estado actual
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            BluetoothAudioService.shared.checkDefaultOutputDevice()
        }
    }
    
    public func checkDefaultOutputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        guard status == noErr else {
            DNDLogger.log("BluetoothAudioService.checkDefaultOutputDevice: Failed to query default output device")
            return
        }
        
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var cfName: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        let nameStatus = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                ptr
            )
        }
        
        guard nameStatus == noErr, let name = cfName as String? else {
            DNDLogger.log("BluetoothAudioService.checkDefaultOutputDevice: Failed to get device name for id \(deviceID)")
            return
        }
        
        DNDLogger.log("BluetoothAudioService.checkDefaultOutputDevice: Active output device is '\(name)', last reported: '\(lastConnectedDevice)'")
        
        // 1. Comprobar si el dispositivo por defecto es AirPods o Beats
        let isAirPodsDevice = name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats")
        if isAirPodsDevice {
            handleAirPodsConnected(name: name)
            return
        }
        
        // 2. Comprobar si alguno de los dispositivos de salida conectados en el sistema es AirPods
        let allOutputs = AudioDeviceService.shared.getOutputDevices()
        for dev in allOutputs {
            if dev.isAirPods {
                DNDLogger.log("BluetoothAudioService: Found connected AirPods in audio device list: '\(dev.name)'")
                handleAirPodsConnected(name: dev.name)
                return
            }
        }
        
        if !self.lastConnectedDevice.isEmpty {
            DNDLogger.log("BluetoothAudioService: AirPods disconnected. Resetting last reported device from '\(self.lastConnectedDevice)' to empty.")
            self.lastConnectedDevice = ""
        }
    }
    
    public struct ConnectedAirPodsDetails {
        public let deviceName: String
        public let modelName: String
        public let primaryBattery: Int
        public let leftBattery: Int?
        public let rightBattery: Int?
        public let caseBattery: Int?
    }
    
    public func queryConnectedAirPods() -> ConnectedAirPodsDetails? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        return parseAirPodsDetails(from: output)
    }
    
    private func parseAirPodsDetails(from text: String) -> ConnectedAirPodsDetails? {
        guard let connectedRange = text.range(of: "Connected:") else { return nil }
        let connectedSection: String
        if let notConnectedRange = text.range(of: "Not Connected:", range: connectedRange.upperBound..<text.endIndex) {
            connectedSection = String(text[connectedRange.upperBound..<notConnectedRange.lowerBound])
        } else {
            connectedSection = String(text[connectedRange.upperBound...])
        }
        
        // Buscar el bloque de AirPods dentro de Connected
        let lines = connectedSection.components(separatedBy: .newlines)
        var currentDevice = ""
        var isTargetDevice = false
        var deviceLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Un nombre de dispositivo está precedido por 10 o 14 espacios y termina en ':'
            if line.hasPrefix("          ") && !line.hasPrefix("              ") && trimmed.hasSuffix(":") {
                let name = String(trimmed.dropLast())
                if isTargetDevice { break }
                if name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats") {
                    currentDevice = name
                    isTargetDevice = true
                }
            } else if isTargetDevice {
                deviceLines.append(trimmed)
            }
        }
        
        guard isTargetDevice && !currentDevice.isEmpty else { return nil }
        let deviceBlock = deviceLines.joined(separator: "\n")
        
        // Extraer baterías (claves en macOS moderno)
        let left = extractBattery(from: deviceBlock, key: "Left Battery Level:")
            ?? extractBattery(from: deviceBlock, key: "Battery Level (Left):")
        let right = extractBattery(from: deviceBlock, key: "Right Battery Level:")
            ?? extractBattery(from: deviceBlock, key: "Battery Level (Right):")
        let caseB = extractBattery(from: deviceBlock, key: "Case Battery Level:")
            ?? extractBattery(from: deviceBlock, key: "Battery Level (Case):")
        let single = extractBattery(from: deviceBlock, key: "Battery Level (Single):")
            ?? extractBattery(from: deviceBlock, key: "Battery Level:")
        
        // Extraer Product ID para identificar el modelo exacto
        let productId = extractProductId(from: deviceBlock)
        let model = modelName(for: productId, fallbackName: currentDevice)
        
        var primary = 100
        if let l = left, let r = right {
            primary = max(l, r)
        } else if let s = single {
            primary = s
        } else if let l = left {
            primary = l
        } else if let r = right {
            primary = r
        }
        
        return ConnectedAirPodsDetails(
            deviceName: currentDevice,
            modelName: model,
            primaryBattery: primary,
            leftBattery: left,
            rightBattery: right,
            caseBattery: caseB
        )
    }
    
    private func fetchBatteryAndTriggerAlert(deviceName: String) {
        DNDLogger.log("BluetoothAudioService.fetchBatteryAndTriggerAlert for: \(deviceName)")
        
        // 1. Mostrar de inmediato la animación 3D del Notch para 0 ms de retardo
        DispatchQueue.main.async {
            AirPodsActivityProvider.shared.publishAirPodsActivity(
                name: deviceName,
                batteryLevel: 95,
                duration: 4.8
            )
        }
        
        // 2. Consultar system_profiler en segundo plano para obtener porcentajes reales
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let details = self.queryConnectedAirPods()
            
            let displayName = details?.deviceName ?? deviceName
            let primaryBattery = details?.primaryBattery ?? 95
            let leftBat = details?.leftBattery
            let rightBat = details?.rightBattery
            let caseBat = details?.caseBattery
            
            DNDLogger.log("BluetoothAudioService.fetchBatteryAndTriggerAlert details queried: \(displayName), bat=\(primaryBattery)%, L=\(leftBat ?? -1), R=\(rightBat ?? -1), C=\(caseBat ?? -1)")
            
            DispatchQueue.main.async {
                AirPodsActivityProvider.shared.publishAirPodsActivity(
                    name: displayName,
                    batteryLevel: primaryBattery,
                    leftPercent: leftBat,
                    rightPercent: rightBat,
                    casePercent: caseBat,
                    duration: 4.5
                )
            }
        }
    }
    
    private func modelName(for productId: String, fallbackName: String) -> String {
        switch productId.lowercased() {
        case "0x2019", "0x201e":
            return "AirPods 4"
        case "0x200e":
            return "AirPods Pro"
        case "0x2024", "0x2027":
            return "AirPods Pro 2"
        case "0x200f":
            return "AirPods 3"
        case "0x200a", "0x201f":
            return "AirPods Max"
        case "0x2002":
            return "AirPods 2"
        case "0x2001":
            return "AirPods"
        default:
            if fallbackName.localizedCaseInsensitiveContains("Pro") {
                return "AirPods Pro"
            } else if fallbackName.localizedCaseInsensitiveContains("Max") {
                return "AirPods Max"
            }
            return fallbackName
        }
    }
    
    private func extractProductId(from text: String) -> String {
        guard let range = text.range(of: "Product ID:") else { return "" }
        let substring = text[range.upperBound...]
        let line = substring.components(separatedBy: .newlines).first ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractBattery(from text: String, key: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        let substring = text[range.upperBound...]
        let line = substring.components(separatedBy: .newlines).first ?? ""
        let digits = line.filter { $0.isNumber }
        return Int(digits)
    }
}
