import CoreAudio
import Foundation

public final class BluetoothAudioService {
    public static let shared = BluetoothAudioService()
    
    private var lastConnectedDevice: String = ""
    
    private init() {
        startMonitoringAudioDevices()
    }
    
    public func startMonitoringAudioDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
            &address,
            listener,
            nil
        )
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
        
        guard status == noErr else { return }
        
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
        
        guard nameStatus == noErr, let name = cfName as String? else { return }
        
        // If AirPods connected and was not already reported
        if name.localizedCaseInsensitiveContains("AirPods") {
            if name != lastConnectedDevice {
                self.lastConnectedDevice = name
                self.fetchBatteryAndTriggerAlert(deviceName: name)
            }
        } else {
            // Reset when disconnecting
            self.lastConnectedDevice = ""
        }
    }
    
    private func fetchBatteryAndTriggerAlert(deviceName: String) {
        // Query battery in background
        DispatchQueue.global(qos: .userInitiated).async {
            var leftBat = 95
            var rightBat = 95
            var caseBat = 100
            
            // Run system_profiler quietly to find real battery
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPBluetoothDataType"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            if (try? task.run()) != nil {
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if let leftMatch = self.extractBattery(from: output, key: "Battery Level (Left):") {
                        leftBat = leftMatch
                    }
                    if let rightMatch = self.extractBattery(from: output, key: "Battery Level (Right):") {
                        rightBat = rightMatch
                    }
                    if let caseMatch = self.extractBattery(from: output, key: "Battery Level (Case):") {
                        caseBat = caseMatch
                    }
                }
            }
            
            DispatchQueue.main.async {
                AppState.shared.triggerAlert(
                    .airpods(
                        name: deviceName,
                        leftPercent: leftBat,
                        rightPercent: rightBat,
                        casePercent: caseBat
                    ),
                    duration: 4.5
                )
            }
        }
    }
    
    private func extractBattery(from text: String, key: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        let substring = text[range.upperBound...]
        let line = substring.components(separatedBy: .newlines).first ?? ""
        let digits = line.filter { $0.isNumber }
        return Int(digits)
    }
}
