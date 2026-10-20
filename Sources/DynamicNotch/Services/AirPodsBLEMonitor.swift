import CoreBluetooth
import Foundation

/// Lee el aviso Bluetooth que los AirPods mandan para la tarjeta del iPhone ("proximity pairing", fabricante
/// Apple 0x004C, tipo 0x07): modelo, color, batería de cada auricular y del estuche, y si están cargando.
/// Sólo escucha (nunca se conecta ni manda nada) y sólo unos segundos cuando hace falta (al conectar los AirPods
/// o al abrir su tarjeta), para no gastar batería.
public final class AirPodsBLEMonitor: NSObject, ObservableObject, CBCentralManagerDelegate {
    public static let shared = AirPodsBLEMonitor()

    public struct Reading: Equatable {
        public let productId: UInt16
        public let color: UInt8
        /// 0…100 (nil = sin dato, p. ej. el auricular está en el estuche cerrado)
        public let left: Int?
        public let right: Int?
        public let caseLevel: Int?
        public let leftCharging: Bool
        public let rightCharging: Bool
        public let caseCharging: Bool
        public let rssi: Int
        public let raw: String
        public let at: Date

        public var productIdHex: String { String(format: "0x%04x", productId) }
    }

    @Published public private(set) var latest: Reading?
    /// Diagnóstico: tipos de aviso de Apple vistos en el último escaneo (tipo → cuántos)
    public private(set) var appleTypesSeen: [UInt8: Int] = [:]
    public var stateDescription: String {
        guard let central else { return "sin iniciar" }
        return "estado \(central.state.rawValue), permiso \(CBManager.authorization.rawValue), escaneando \(central.isScanning)"
    }
    private var central: CBCentralManager?
    private var stopWork: DispatchWorkItem?
    private var pendingDuration: TimeInterval = 0

    private override init() {
        super.init()
    }

    /// Escucha unos segundos (y se detiene sola)
    public func scan(for seconds: TimeInterval = 8) {
        DispatchQueue.main.async { [self] in
            if central == nil {
                pendingDuration = seconds
                central = CBCentralManager(delegate: self, queue: .main)
                return
            }
            startScanning(for: seconds)
        }
    }

    private func startScanning(for seconds: TimeInterval) {
        guard let central, central.state == .poweredOn else { return }
        if !central.isScanning {
            appleTypesSeen = [:]
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.central?.stopScan() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, pendingDuration > 0 {
            startScanning(for: pendingDuration)
            pendingDuration = 0
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        if data.count > 2, data[0] == 0x4C, data[1] == 0x00 { appleTypesSeen[data[2], default: 0] += 1 }
        guard let reading = Self.parse(data, rssi: RSSI.intValue) else { return }
        // El más cercano gana (puede haber AirPods de otras personas alrededor)
        if let current = latest, Date().timeIntervalSince(current.at) < 3, current.rssi > reading.rssi + 8,
           current.productId != reading.productId || current.color != reading.color {
            return
        }
        if latest?.raw != reading.raw || latest.map({ Date().timeIntervalSince($0.at) > 2 }) ?? true {
            latest = reading
        }
    }

    // MARK: Formato del aviso (pura, con tests)

    /// `data` = datos de fabricante completos: 4C 00 | 07 | largo | 01 | modelo (2, little-endian) | estado |
    /// baterías (der/izq) | carga + estuche | tapa | color | …
    public static func parse(_ data: Data, rssi: Int = 0) -> Reading? {
        let b = [UInt8](data)
        guard b.count >= 13, b[0] == 0x4C, b[1] == 0x00, b[2] == 0x07, b[3] >= 0x09 else { return nil }
        let productId = UInt16(b[6]) << 8 | UInt16(b[5])
        guard productId & 0xFF00 == 0x2000 else { return nil }
        let status = b[7]
        let pods = b[8]
        let chargeAndCase = b[9]
        let color = b[11]
        func level(_ nibble: UInt8) -> Int? { nibble <= 10 ? Int(nibble) * 10 : nil }
        // El bit 0x20 del estado dice cuál auricular es el "principal": de él depende el orden
        let flipped = status & 0x20 == 0
        let first = level(pods >> 4), second = level(pods & 0x0F)
        let chargeFlags = chargeAndCase >> 4
        let firstCharging = chargeFlags & 0x02 != 0, secondCharging = chargeFlags & 0x01 != 0
        return Reading(
            productId: productId,
            color: color,
            left: flipped ? first : second,
            right: flipped ? second : first,
            caseLevel: level(chargeAndCase & 0x0F),
            leftCharging: flipped ? firstCharging : secondCharging,
            rightCharging: flipped ? secondCharging : firstCharging,
            caseCharging: chargeFlags & 0x04 != 0,
            rssi: rssi,
            raw: b.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " "),
            at: Date()
        )
    }
}
