import Foundation

// MARK: - Aparatos de la casa
// Lo que reporta ConnectLife traducido a algo que se puede mostrar. Lógica pura (sin red ni SwiftUI) para poder
// probarla. Los códigos salen de los mapas de la integración de Home Assistant (connectlife-ha,
// data_dictionaries/025.yaml y 025-1wj120514v0t.yaml para la lavasecadora; 026.yaml para el refri).

public enum HomeApplianceKind: Equatable {
    case washer
    case fridge
    case other

    /// deviceTypeCode de ConnectLife
    public init(typeCode: String) {
        switch typeCode {
        case "003", "004", "025", "027": self = .washer
        case "026": self = .fridge
        default: self = .other
        }
    }
}

// MARK: Lavadora / lavasecadora

public struct WasherStatus: Equatable {
    public enum Machine: Equatable {
        case off, standby, running, paused, alarm, unknown
    }

    public enum Phase: Int, Equatable, CaseIterable {
        case none = 0
        case weigh = 1
        case prewash = 2
        case wash = 3
        case rinse = 4
        case spin = 7
        case dry = 8
        case finished = 10
        case delayed = 11

        public var title: String {
            switch self {
            case .none: return L("En espera")
            case .weigh: return L("Pesando")
            case .prewash: return L("Prelavado")
            case .wash: return L("Lavando")
            case .rinse: return L("Enjuagando")
            case .spin: return L("Centrifugando")
            case .dry: return L("Secando")
            case .finished: return L("Terminó")
            case .delayed: return L("Inicio diferido")
            }
        }

        public var shortTitle: String {
            switch self {
            case .weigh: return L("Pesar")
            case .prewash: return L("Prelavar")
            case .wash: return L("Lavar")
            case .rinse: return L("Enjuagar")
            case .spin: return L("Centrifugar")
            case .dry: return L("Secar")
            default: return title
            }
        }

        public var symbol: String {
            switch self {
            case .dry: return "wind"
            case .spin: return "arrow.triangle.2.circlepath"
            case .finished: return "checkmark"
            case .delayed: return "clock"
            default: return "washer.fill"
            }
        }
    }

    public var name: String
    public var model: String
    public var isOnline: Bool
    public var machine: Machine
    public var phase: Phase
    public var program: String?
    public var remainingMinutes: Int
    public var totalMinutes: Int
    public var temperature: String?
    public var spin: String?
    public var isDoorOpen: Bool
    public var errorCode: Int
    /// Programa con secado (para saber si la línea de fases termina en "Secar")
    public var includesDrying: Bool

    /// Está a la mitad de un ciclo (incluye la pausa y el inicio diferido)
    public var isCycleActive: Bool {
        guard isOnline else { return false }
        switch machine {
        case .running, .paused: return phase != .finished
        default: return false
        }
    }

    public var hasError: Bool { errorCode != 0 || machine == .alarm }

    /// 0…1 según el tiempo que lleva
    public var progress: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1, max(0, Double(totalMinutes - remainingMinutes) / Double(totalMinutes)))
    }

    /// "Lavando", "En pausa · Lavando"…
    public var statusTitle: String {
        if !isOnline { return L("Sin conexión") }
        if hasError { return L("Error") + (errorCode != 0 ? " F\(String(format: "%02d", errorCode))" : "") }
        switch machine {
        case .paused: return L("En pausa")
        case .off: return L("Apagada")
        case .standby: return phase == .finished ? Phase.finished.title : L("Lista")
        default: return phase.title
        }
    }

    /// Las fases que tiene el ciclo en curso, en orden, para la línea de pasos
    public var timeline: [Phase] {
        var steps: [Phase] = [.wash, .rinse, .spin]
        if includesDrying || phase == .dry { steps.append(.dry) }
        return steps
    }

    public init(name: String, model: String, isOnline: Bool, status: [String: String]) {
        self.name = name.isEmpty ? L("Lavadora") : name
        self.model = model
        self.isOnline = isOnline
        let int = { (key: String) -> Int? in status[key].flatMap { Int($0) ?? Double($0).map { Int($0) } } }

        switch int("machine_status") {
        case 0: machine = .off
        case 1: machine = .standby
        case 2: machine = .running
        case 3: machine = .paused
        case 4: machine = .alarm
        default: machine = .unknown
        }
        phase = int("Current_program_phase").flatMap(Phase.init(rawValue:)) ?? .none
        program = int("Selected_program_ID").flatMap(Self.programName)
        remainingMinutes = int("Selected_program_remaining_time_in_minutes") ?? 0
        totalMinutes = int("Selected_program_total_time_in_minutes") ?? 0
        temperature = int("temperature").flatMap(Self.temperatureLabel)
        spin = int("Spin_speed_rpm").flatMap { $0 > 0 ? "\($0 * 100) rpm" : nil }
        // Door_status: 1 abierta, 3 cerrada (2 "otro")
        isDoorOpen = int("Door_status") == 1
        errorCode = int("error_code") ?? 0
        let dryTime = int("dry_time") ?? 0
        let programId = int("Selected_program_ID") ?? 0
        includesDrying = dryTime > 0 || [1, 2, 22].contains(programId) || (int("DryingSwitch") ?? 0) != 0
    }

    static func programName(_ id: Int) -> String? {
        switch id {
        case 1: return L("Algodón + secado")
        case 2: return L("Sintéticos + secado")
        case 4: return L("Refrescar")
        case 5: return L("Antialérgico")
        case 6: return L("Limpieza de tina")
        case 7: return L("Algodón")
        case 8: return L("Sintéticos")
        case 10: return L("Lana")
        case 11: return L("Rápido 15'")
        case 12: return L("Mixto")
        case 14: return L("Centrifugado")
        case 16: return L("Bebé")
        case 18: return L("Ropa deportiva")
        case 20: return L("Enjuague y centrifugado")
        case 21: return L("Delicados")
        case 22: return L("Lavar y secar 60'")
        case 41: return L("Power 49'")
        case 44: return L("Ropa de cama")
        case 45: return L("Jeans")
        case 55: return L("A mano")
        default: return nil
        }
    }

    static func temperatureLabel(_ code: Int) -> String? {
        switch code {
        case 0: return L("Fría")
        case 2: return "20°"
        case 3: return "30°"
        case 4: return "40°"
        case 6: return "60°"
        case 9: return "90°"
        default: return nil
        }
    }
}

// MARK: Refri

public struct FridgeStatus: Equatable {
    /// Para mandarle comandos
    public var puid: String
    public var name: String
    public var model: String
    public var isOnline: Bool
    /// Temperatura que elegiste y la que mide el aparato (°C)
    public var fridgeTarget: Int?
    public var fridgeActual: Int?
    public var freezerTarget: Int?
    public var freezerActual: Int?
    public var ambient: Int?
    /// El refri ya está pitando por la puerta (open_*_door_alarm)
    public var isFridgeDoorAlarm: Bool
    public var isFreezerDoorAlarm: Bool
    /// La puerta está abierta en este momento (refr_room_open, free_room_open…), aunque todavía no pite
    public var isFridgeDoorOpen: Bool
    public var isFreezerDoorOpen: Bool
    /// Super Frío (sr_mode), Super Congelar (sf_mode), Vacaciones
    public var superCool: Bool
    public var superFreeze: Bool
    public var holiday: Bool
    /// Ahorro de energía (save_mode)
    public var eco: Bool
    /// Lo que este modelo tiene (existing_*_mode)
    public var supportsSuperCool: Bool
    public var supportsSuperFreeze: Bool
    public var supportsEco: Bool
    /// Rangos que reporta el propio refri (si no, los de connectlife-ha)
    public var fridgeRange: ClosedRange<Int>
    public var freezerRange: ClosedRange<Int>

    public var isDoorAlarm: Bool { isFridgeDoorAlarm || isFreezerDoorAlarm }
    public var isDoorOpen: Bool { isFridgeDoorOpen || isFreezerDoorOpen || isDoorAlarm }

    public init(puid: String = "", name: String, model: String, isOnline: Bool, status: [String: String]) {
        self.puid = puid
        self.name = name.isEmpty ? L("Refri") : name
        self.model = model
        self.isOnline = isOnline
        let int = { (key: String) -> Int? in status[key].flatMap { Int($0) ?? Double($0).map { Int($0) } } }
        // −40 es "no hay sensor" (p. ej. un compartimento que este modelo no tiene)
        let temp = { (key: String) -> Int? in int(key).flatMap { $0 <= -40 ? nil : $0 } }
        fridgeTarget = temp("refrigerator_temperature")
        fridgeActual = temp("refrigerator_real_temperature")
        freezerTarget = temp("freeze_temperature")
        freezerActual = temp("freeze_real_temperature")
        ambient = temp("environment_real_temperature")
        // Cada modelo usa unos u otros: se toman todos los que existen en el refri BCD-668
        isFridgeDoorAlarm = int("open_the_door_alarm") == 1 || int("open_refrigerator_door_alarm") == 1
            || int("open_variation_door_alarm") == 1
        isFreezerDoorAlarm = int("open_freeze_door_alarm") == 1
        isFridgeDoorOpen = int("refr_room_open") == 1 || int("vari_room_open") == 1 || int("var_room_open_2") == 1
        isFreezerDoorOpen = int("free_room_open") == 1 || int("free_room_open_2") == 1
        superCool = int("sr_mode") == 1
        superFreeze = int("sf_mode") == 1
        holiday = int("holiday_mode") == 1
        eco = int("save_mode") == 1
        // Si el refri no dice si lo tiene, se ofrece igual (la app ConnectLife lo muestra)
        supportsSuperCool = int("existing_sr_mode").map { $0 == 1 } ?? true
        supportsSuperFreeze = int("existing_sf_mode").map { $0 == 1 } ?? true
        supportsEco = int("existing_save_mode").map { $0 == 1 } ?? true
        fridgeRange = Self.range(int("refrigerator_min_temperature"), int("refrigerator_max_temperature"), fallback: 0...8)
        freezerRange = Self.range(int("freeze_min_temperature"), int("freeze_max_temperature"), fallback: -30...(-5))
    }

    private static func range(_ low: Int?, _ high: Int?, fallback: ClosedRange<Int>) -> ClosedRange<Int> {
        guard let low, let high, low < high, low > -40 else { return fallback }
        return low...high
    }
}

/// Lo que se puede cambiar del refri: el comando que se manda y la propiedad que cambia en su estado
public enum FridgeControl: Equatable {
    case fridgeTemperature(Int)
    case freezerTemperature(Int)
    case superCool(Bool)
    case superFreeze(Bool)
    case eco(Bool)

    /// Comando de ConnectLife (connectlife-ha, data_dictionaries/026.yaml)
    public var command: (name: String, value: String) {
        switch self {
        case .fridgeTemperature(let value): return ("SET_REFRIGERATOR_TEMPERATURE", "\(value)")
        case .freezerTemperature(let value): return ("SET_FREEZE_TEMPERATURE", "\(value)")
        case .superCool(let on): return ("SET_SR_MODE", on ? "1" : "0")
        case .superFreeze(let on): return ("SET_SF_MODE", on ? "1" : "0")
        case .eco(let on): return ("SET_SAVE_MODE", on ? "1" : "0")
        }
    }

    /// La propiedad del estado que debe cambiar (para mostrarlo al instante y confirmarlo después)
    public var statusKey: String {
        switch self {
        case .fridgeTemperature: return "refrigerator_temperature"
        case .freezerTemperature: return "freeze_temperature"
        case .superCool: return "sr_mode"
        case .superFreeze: return "sf_mode"
        case .eco: return "save_mode"
        }
    }

    public var statusValue: String { command.value }

    public var title: String {
        switch self {
        case .fridgeTemperature: return L("Temperatura del refri")
        case .freezerTemperature: return L("Temperatura del congelador")
        case .superCool: return L("Enfriamiento rápido")
        case .superFreeze: return L("Super congelación")
        case .eco: return L("Eco")
        }
    }
}

// MARK: Todo junto

public struct HomeSnapshot: Equatable {
    public var washers: [WasherStatus] = []
    public var fridges: [FridgeStatus] = []
    public var fetchedAt: Date = .distantPast

    public init(washers: [WasherStatus] = [], fridges: [FridgeStatus] = [], fetchedAt: Date = .distantPast) {
        self.washers = washers
        self.fridges = fridges
        self.fetchedAt = fetchedAt
    }

    public init(appliances: [ConnectLifeAppliance], fetchedAt: Date = Date()) {
        self.fetchedAt = fetchedAt
        for appliance in appliances {
            switch HomeApplianceKind(typeCode: appliance.typeCode) {
            case .washer:
                washers.append(WasherStatus(name: appliance.nickname, model: appliance.featureName,
                                            isOnline: appliance.isOnline, status: appliance.status))
            case .fridge:
                fridges.append(FridgeStatus(puid: appliance.puid, name: appliance.nickname, model: appliance.featureName,
                                            isOnline: appliance.isOnline, status: appliance.status))
            case .other:
                break
            }
        }
    }

    public var isEmpty: Bool { washers.isEmpty && fridges.isEmpty }
}
