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
        duration: TimeInterval = 13.0,
        assetProduct: String? = nil,
        assetVariant: String? = nil
    ) {
        guard AppState.shared.enableAirPodsAnimation else { return }
        // Para la próxima vez: las animaciones oficiales de este modelo (se bajan una vez de Apple)
        if assetProduct == nil { AirPodsAssetService.shared.prefetch(AirPodsAssetService.currentIdentity) }
        
        let state = AirPodsActivityState(
            name: name,
            batteryLevel: batteryLevel,
            leftPercent: leftPercent,
            rightPercent: rightPercent,
            casePercent: casePercent,
            assetProduct: assetProduct,
            assetVariant: assetVariant
        )
        
        var activity = LiveActivity(
            id: providerId,
            priority: ActivityRelevance.hardwareEvent, // supera llamadas y volumen
            style: .airpodsPill,
            // Al tocar la isla: la tarjeta con cada auricular y el estuche, como el iPhone
            expandedView: AnyView(AirPodsCardView(state: state)),
            tint: DesignTokens.green,
            duration: duration,
            airpodsState: state,
            isUrgent: true
        )
        activity.title = name
        // Escucha unos segundos el aviso Bluetooth: dice si algo está cargando (y, con suerte, el color)
        AirPodsBLEMonitor.shared.scan(for: 6)
        
        DispatchQueue.main.async {
            ActivityCenter.shared.show(activity)
        }
    }
}
