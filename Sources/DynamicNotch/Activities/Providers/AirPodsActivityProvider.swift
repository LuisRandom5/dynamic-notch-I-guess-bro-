import SwiftUI

public final class AirPodsActivityProvider: ObservableObject {
    public static let shared = AirPodsActivityProvider()
    public let providerId: String = "airpods"
    
    private init() {}
    
    public func publishAirPodsActivity(
        name: String,
        batteryLevel: Int,
        leftPercent: Int? = nil,
        rightPercent: Int? = nil,
        casePercent: Int? = nil,
        duration: TimeInterval = 13.0
    ) {
        guard AppState.shared.enableAirPodsAnimation else { return }
        
        let state = AirPodsActivityState(
            name: name,
            batteryLevel: batteryLevel,
            leftPercent: leftPercent,
            rightPercent: rightPercent,
            casePercent: casePercent
        )
        
        let activity = LiveActivity(
            id: providerId,
            priority: 1000, // Máxima prioridad de evento hardware (supera llamadas y volumen)
            style: .airpodsPill,
            tint: DesignTokens.green,
            duration: duration,
            airpodsState: state,
            isUrgent: true
        )
        
        DispatchQueue.main.async {
            ActivityCenter.shared.show(activity)
        }
    }
}
