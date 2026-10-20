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
        // Ignorar sondeos y paquetes BLE si el dispositivo no está verdaderamente conectado
        guard device.isConnected() else {
            return
        }
        
        let name = device.name ?? device.nameOrAddress ?? "AirPods"
        DNDLogger.log("BluetoothDeviceObserver: Hardware Bluetooth connected -> '\(name)', isConnected=\(device.isConnected())")
        
        let isAirPods = name.localizedCaseInsensitiveContains("AirPods") ||
                        name.localizedCaseInsensitiveContains("Beats")
                        
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

public final class BluetoothAudioService: ObservableObject {
    public static let shared = BluetoothAudioService()
    
    @Published public private(set) var currentModel: AirPodsModel = .airPods4
    @Published public private(set) var currentDeviceName: String = "AirPods"
    @Published public private(set) var isAirPodsConnected: Bool = false
    
    public var currentAirPodsModel: AirPodsModel { currentModel }
    /// Código de producto Bluetooth del modelo conectado (p. ej. "0x2019"); vacío si no se conoce
    @Published public private(set) var currentProductId: String = ""

    /// Diagnóstico (/debug/airpods-model): hacer como si estuvieran conectados otros AirPods
    public func simulateModel(productId: String) {
        currentProductId = productId
        currentModel = AirPodsModel.detect(from: "", productId: productId)
    }
    public var currentAirPodsSymbol: String { currentModel.symbolName }
    public var currentAirPodsCaseSymbol: String { currentModel.caseSymbolName }
    public var currentAirPodsLeftSymbol: String { currentModel.leftEarbudSymbol }
    public var currentAirPodsRightSymbol: String { currentModel.rightEarbudSymbol }
    
    private var lastConnectedDevice: String = ""
    private var lastAlertTime: Date = Date.distantPast
    private var lastAlertedDeviceName: String = ""
    private let alertCooldown: TimeInterval = 60.0
    /// Al arrancar, macOS reporta como "recién conectados" los AirPods que ya lo estaban (y con otro nombre:
    /// "AirPods 4" por Bluetooth, "AirPods de …" por Core Audio). En esta ventana sólo se registran, sin animación
    private var monitoringStartedAt: Date = .distantFuture
    private let launchGracePeriod: TimeInterval = 6.0
    
    private init() {
        checkConnectedHardware()
        startMonitoringAudioDevices()
        BluetoothDeviceObserver.shared.startObserving()
    }
    
    private func checkConnectedHardware() {
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for dev in paired where dev.isConnected() {
                let devName = dev.name ?? dev.nameOrAddress ?? ""
                if devName.localizedCaseInsensitiveContains("AirPods") || devName.localizedCaseInsensitiveContains("Beats") {
                    let detected = AirPodsModel.detect(from: devName)
                    self.currentModel = detected
                    self.currentDeviceName = devName
                    self.isAirPodsConnected = true
                    self.lastConnectedDevice = devName
                    self.lastAlertedDeviceName = devName
                    DNDLogger.log("BluetoothAudioService: Hardware inicial detectado: '\(devName)' -> \(detected.rawValue) (symbol: \(detected.symbolName))")
                    break
                }
            }
        }
    }
    
    public func symbolForDeviceName(_ name: String) -> String {
        if isAirPodsConnected && (lastConnectedDevice == name || name.localizedCaseInsensitiveContains("AirPods")) {
            return currentModel.symbolName
        }
        return AirPodsModel.detect(from: name).symbolName
    }
    
    public func handleAirPodsConnected(name: String, isInitialCheck: Bool = false) {
        let detected = AirPodsModel.detect(from: name)
        self.currentModel = detected
        self.currentDeviceName = name
        self.isAirPodsConnected = true
        
        guard AppState.shared.enableAirPodsAnimation else { return }
        
        // Si es el escaneo de arranque o ya está conectado como salida actual, solo registrar sin alertar
        if isInitialCheck || Date().timeIntervalSince(monitoringStartedAt) < launchGracePeriod {
            self.lastConnectedDevice = name
            self.lastAlertedDeviceName = name
            return
        }
        
        // Si es exactamente el mismo dispositivo ya conectado, no disparar repetidamente
        if name == lastConnectedDevice && !lastConnectedDevice.isEmpty {
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastAlertTime)
        
        // Cooldown: si ya se mostró la animación hace menos de 60 segundos para el mismo dispositivo, omitir
        if elapsed < alertCooldown && name == lastAlertedDeviceName {
            DNDLogger.log("BluetoothAudioService.handleAirPodsConnected: en cooldown (\(Int(elapsed))s < \(Int(alertCooldown))s). Omitiendo alerta para '\(name)'")
            self.lastConnectedDevice = name
            return
        }
        
        DNDLogger.log("BluetoothAudioService.handleAirPodsConnected: Disparando alerta de conexión para '\(name)' (\(detected.rawValue))")
        self.lastConnectedDevice = name
        self.lastAlertedDeviceName = name
        self.lastAlertTime = now
        self.fetchBatteryAndTriggerAlert(deviceName: name)
    }
    
    public func handleAirPodsDisconnected(name: String) {
        DNDLogger.log("BluetoothAudioService.handleAirPodsDisconnected: '\(name)'")
        if lastConnectedDevice == name || lastConnectedDevice.localizedCaseInsensitiveContains("AirPods") {
            self.lastConnectedDevice = ""
            self.isAirPodsConnected = false
            self.currentDeviceName = ""
        }
    }
    
    public func startMonitoringAudioDevices() {
        monitoringStartedAt = Date()
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
                        self.lastConnectedDevice = devName
                        self.lastAlertedDeviceName = devName
                        dev.register(forDisconnectNotification: BluetoothDeviceObserver.shared, selector: #selector(BluetoothDeviceObserver.deviceDisconnected(notification:device:)))
                    }
                }
            }
        }
        
        // Verificación inicial silenciosa de estado actual al arrancar
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            BluetoothAudioService.shared.checkDefaultOutputDevice(isInitialCheck: true)
        }
    }
    
    public func checkDefaultOutputDevice(isInitialCheck: Bool = false) {
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
        
        // 1. Comprobar si el dispositivo por defecto/activo es AirPods o Beats
        let isAirPodsDevice = name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats")
        if isAirPodsDevice {
            if isInitialCheck {
                self.lastConnectedDevice = name
                self.lastAlertedDeviceName = name
            } else if name != self.lastConnectedDevice {
                handleAirPodsConnected(name: name, isInitialCheck: false)
            }
            return
        }
        
        // 2. Si la salida activa NO son AirPods (ej. altavoces del Mac), resetear
        if !self.lastConnectedDevice.isEmpty {
            DNDLogger.log("BluetoothAudioService: Salida activa es '\(name)'. Reseteando lastConnectedDevice desde '\(self.lastConnectedDevice)'.")
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
        let detectedModel = AirPodsModel.detect(from: currentDevice, productId: productId)
        let model = detectedModel.rawValue
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentModel = detectedModel
            if !productId.isEmpty { self.currentProductId = productId }
            self.currentDeviceName = currentDevice
            self.isAirPodsConnected = true
            DNDLogger.log("BluetoothAudioService: Modelo confirmado por ProductID (\(productId)) -> \(detectedModel.rawValue) (\(detectedModel.symbolName))")
            // Animaciones oficiales del modelo, listas para la próxima vez que se conecten
            AirPodsAssetService.shared.prefetch(AirPodsAssetService.identity(productId: productId, model: detectedModel))
        }
        
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
        
        // 1. Mostrar de inmediato la animación de las alas del Notch para 0 ms de retardo
        DispatchQueue.main.async {
            AirPodsActivityProvider.shared.publishAirPodsActivity(
                name: deviceName,
                batteryLevel: 95,
                duration: 13.0
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
                    duration: 13.0
                )
            }
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
