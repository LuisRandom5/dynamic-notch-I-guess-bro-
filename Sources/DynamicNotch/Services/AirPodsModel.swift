import Foundation
import IOBluetooth

/// Modelo formal y catálogo de iconos SF Symbols para todas las generaciones de AirPods y Beats.
/// Resuelve la disparidad de iconos entre AirPods 1/2, AirPods 3, AirPods 4, AirPods Pro 1/2 y AirPods Max.
public enum AirPodsModel: String, CaseIterable, Equatable {
    case airPods1 = "AirPods (1.ª generación)"
    case airPods2 = "AirPods (2.ª generación)"
    case airPods3 = "AirPods (3.ª generación)"
    case airPods4 = "AirPods 4"
    case airPods4ANC = "AirPods 4 con ANC"
    case airPodsPro1 = "AirPods Pro (1.ª generación)"
    case airPodsPro2 = "AirPods Pro (2.ª generación)"
    case airPodsPro3 = "AirPods Pro 3"
    case airPodsMax = "AirPods Max"
    case beatsStudio = "Beats Studio"
    case beatsSolo = "Beats Solo"
    case beatsFit = "Beats Fit Pro"
    case beatsEarphones = "Beats"
    case unknownAirPods = "AirPods"

    public var isAirPods4: Bool {
        self == .airPods4 || self == .airPods4ANC
    }
    
    public var isPro: Bool {
        self == .airPodsPro1 || self == .airPodsPro2 || self == .airPodsPro3
    }
    
    public var isMax: Bool {
        self == .airPodsMax
    }

    /// SF Symbol nativo y verificado en macOS para el par de auriculares
    public var symbolName: String {
        switch self {
        case .airPods4, .airPods4ANC:
            return "airpods.gen4"
        case .airPodsPro1, .airPodsPro2, .airPodsPro3:
            return "airpodspro"
        case .airPodsMax:
            return "airpodsmax"
        case .airPods3:
            return "airpods.gen3"
        case .airPods1, .airPods2, .unknownAirPods:
            return "airpods"
        case .beatsStudio, .beatsSolo:
            return "beats.headphones"
        case .beatsFit:
            return "beats.fit.pro"
        case .beatsEarphones:
            return "beats.earphones"
        }
    }

    /// SF Symbol nativo verificado del auricular izquierdo
    public var leftEarbudSymbol: String {
        switch self {
        case .airPods4, .airPods4ANC:
            return "airpods.gen4.left"
        case .airPodsPro1, .airPodsPro2, .airPodsPro3:
            return "airpodpro.left"
        case .airPodsMax:
            return "airpodsmax"
        case .airPods3, .airPods1, .airPods2, .unknownAirPods:
            return "airpod.left"
        case .beatsStudio, .beatsSolo, .beatsFit, .beatsEarphones:
            return "beats.earphones"
        }
    }

    /// SF Symbol nativo verificado del auricular derecho
    public var rightEarbudSymbol: String {
        switch self {
        case .airPods4, .airPods4ANC:
            return "airpods.gen4.right"
        case .airPodsPro1, .airPodsPro2, .airPodsPro3:
            return "airpodpro.right"
        case .airPodsMax:
            return "airpodsmax"
        case .airPods3, .airPods1, .airPods2, .unknownAirPods:
            return "airpod.right"
        case .beatsStudio, .beatsSolo, .beatsFit, .beatsEarphones:
            return "beats.earphones"
        }
    }

    /// SF Symbol nativo verificado para el estuche de carga
    public var caseSymbolName: String {
        switch self {
        case .airPods4, .airPods4ANC:
            return "airpods.gen4.chargingcase.wireless"
        case .airPodsPro1, .airPodsPro2, .airPodsPro3:
            return "airpodspro.chargingcase.wireless"
        case .airPods3:
            return "airpods.gen3.chargingcase.wireless"
        case .airPodsMax:
            return "airpodsmax"
        case .airPods1, .airPods2, .unknownAirPods:
            return "airpods.chargingcase"
        case .beatsStudio, .beatsSolo, .beatsFit, .beatsEarphones:
            return "beats.headphones"
        }
    }

    /// Detección precisa basada en Product ID de Bluetooth (0x2019 = AirPods 4) y nombres de hardware
    public static func detect(from name: String, productId: String = "") -> AirPodsModel {
        let cleanPID = productId.trimmingCharacters(in: .whitespaces).lowercased()
        // Códigos de producto Bluetooth de Apple (los mismos del aviso de la tarjeta del iPhone)
        switch cleanPID {
        case "0x2002":
            return .airPods1
        case "0x200f":
            return .airPods2
        case "0x2013":
            return .airPods3
        case "0x2019":
            return .airPods4
        case "0x201a", "0x201b", "0x201e":
            return .airPods4ANC
        case "0x200e":
            return .airPodsPro1
        case "0x2014", "0x2024":
            return .airPodsPro2
        case "0x2027":
            return .airPodsPro3
        case "0x200a", "0x201f":
            return .airPodsMax
        default:
            break
        }

        let lower = name.lowercased()
        if lower.contains("airpods 4") || lower.contains("4.ª gen") || lower.contains("4th gen") {
            return .airPods4
        } else if lower.contains("pro 3") || lower.contains("pro (3") {
            return .airPodsPro3
        } else if lower.contains("pro 2") || lower.contains("pro (2") {
            return .airPodsPro2
        } else if lower.contains("pro") {
            return .airPodsPro1
        } else if lower.contains("max") {
            return .airPodsMax
        } else if lower.contains("airpods 3") || lower.contains("3.ª gen") || lower.contains("3rd gen") {
            return .airPods3
        } else if lower.contains("airpods 2") || lower.contains("2.ª gen") {
            return .airPods2
        } else if lower.contains("beats studio") {
            return .beatsStudio
        } else if lower.contains("beats solo") {
            return .beatsSolo
        } else if lower.contains("beats fit") {
            return .beatsFit
        } else if lower.contains("beats") || lower.contains("powerbeats") {
            return .beatsEarphones
        }

        // Si el nombre no incluye la generación explícita (ej. "AirPods de Ana"),
        // consultar IOBluetoothDevice conectados actualmente para obtener el nombre de hardware de fábrica
        if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for dev in pairedDevices where dev.isConnected() {
                let dName = (dev.name ?? "").lowercased()
                if dName.contains("airpods 4") {
                    return .airPods4
                } else if dName.contains("pro 2") {
                    return .airPodsPro2
                } else if dName.contains("pro") {
                    return .airPodsPro1
                } else if dName.contains("max") {
                    return .airPodsMax
                } else if dName.contains("airpods 3") {
                    return .airPods3
                }
            }
        }

        if lower.contains("airpods") {
            // Comprobar si entre los dispositivos emparejados hay AirPods 4
            if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                for dev in pairedDevices {
                    let dName = (dev.name ?? "").lowercased()
                    if dName.contains("airpods 4") {
                        return .airPods4
                    }
                }
            }
            return .airPods4
        }

        return .unknownAirPods
    }
}
