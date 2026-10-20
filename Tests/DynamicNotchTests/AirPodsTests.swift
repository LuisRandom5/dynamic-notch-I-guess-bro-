import Foundation
import Testing
@testable import DynamicNotch

@Suite struct AirPodsTests {
    /// Aviso de ejemplo: AirPods 4 (0x2019), izq. 80 %, der. 90 %, estuche 50 % cargando, izquierdo cargando
    private let frame = Data([0x4C, 0x00, 0x07, 0x19, 0x01, 0x19, 0x20, 0x2B, 0x98, 0x55, 0x01, 0x00, 0x00, 0xAA, 0xBB])

    @Test func parsesTheProximityPairingFrame() throws {
        let reading = try #require(AirPodsBLEMonitor.parse(frame, rssi: -50))
        #expect(reading.productIdHex == "0x2019")
        #expect(reading.left == 80)
        #expect(reading.right == 90)
        #expect(reading.caseLevel == 50)
        #expect(reading.caseCharging)
        #expect(reading.leftCharging && !reading.rightCharging)
    }

    @Test func ignoresOtherAppleFrames() {
        // Tipo 0x10 (Nearby Info) y fabricante que no es Apple
        #expect(AirPodsBLEMonitor.parse(Data([0x4C, 0x00, 0x10, 0x05, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0])) == nil)
        #expect(AirPodsBLEMonitor.parse(Data([0x06, 0x00, 0x07, 0x19, 0x01, 0x19, 0x20, 0, 0, 0, 0, 0, 0])) == nil)
    }

    @Test func productTypesByBluetoothCode() {
        #expect(AirPodsAssetService.product(productId: "0x2019", model: .unknownAirPods) == "AirPods1,4")
        #expect(AirPodsAssetService.product(productId: "0x2024", model: .unknownAirPods) == "AirPodsPro1,3")
        #expect(AirPodsAssetService.product(productId: "0x201f", model: .unknownAirPods) == "AirPodsMax1,2")
        // Sin código: por modelo; Beats no tiene animación oficial
        #expect(AirPodsAssetService.product(productId: "", model: .airPodsPro3) == "AirPods3,7")
        #expect(AirPodsAssetService.product(productId: "", model: .beatsFit) == nil)
        #expect(AirPodsModel.detect(from: "", productId: "0x200f") == .airPods2)
    }
}
