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
        // Para la próxima vez: las animaciones oficiales de este modelo (se bajan una vez de Apple)
        AirPodsAssetService.shared.prefetch(model: BluetoothAudioService.shared.currentAirPodsModel)
        
        let state = AirPodsActivityState(
            name: name,
            batteryLevel: batteryLevel,
            leftPercent: leftPercent,
            rightPercent: rightPercent,
            casePercent: casePercent
        )
        
        let activity = LiveActivity(
            id: providerId,
            priority: ActivityRelevance.hardwareEvent, // supera llamadas y volumen
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
