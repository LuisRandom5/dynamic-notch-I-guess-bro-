import Foundation
import Combine
import IOKit.ps

public struct BatteryStatus: Equatable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    
    public static let fallback = BatteryStatus(percentage: 100, isCharging: false, isPluggedIn: true)
}

public final class BatteryService: ObservableObject {
    public static let shared = BatteryService()
    
    @Published public private(set) var status: BatteryStatus = .fallback
    
    public var onPowerConnected: ((Int) -> Void)?
    public var onPowerDisconnected: (() -> Void)?
    
    private var runLoopSource: CFRunLoopSource?
    private var previousPluggedIn: Bool?
    
    private init() {
        refreshBatteryStatus(notifyOnChange: false)
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    public func refreshBatteryStatus(notifyOnChange: Bool = true) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }
        
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = description[kIOPSPowerSourceStateKey] as? String ?? ""
            let isPluggedIn = powerState == kIOPSACPowerValue
            
            let percentage = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : current
            let newStatus = BatteryStatus(percentage: percentage, isCharging: isCharging, isPluggedIn: isPluggedIn)
            
            let wasPluggedIn = self.previousPluggedIn
            self.previousPluggedIn = isPluggedIn
            self.status = newStatus
            
            if notifyOnChange, let wasPluggedIn = wasPluggedIn {
                if !wasPluggedIn && isPluggedIn {
                    // Charger just connected (MagSafe snap!)
                    DispatchQueue.main.async { [weak self] in
                        self?.onPowerConnected?(percentage)
                    }
                } else if wasPluggedIn && !isPluggedIn {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPowerDisconnected?()
                    }
                }
            }
            break
        }
    }
    
    private func startMonitoring() {
        let callback: IOPowerSourceCallbackType = { _ in
            BatteryService.shared.refreshBatteryStatus(notifyOnChange: true)
        }
        
        let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue()
        self.runLoopSource = source
        if let source = source {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
    
    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            self.runLoopSource = nil
        }
    }
}
