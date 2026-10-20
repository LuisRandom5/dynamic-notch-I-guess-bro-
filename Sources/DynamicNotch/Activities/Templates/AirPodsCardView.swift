import AppKit
import SwiftUI

/// Tarjeta de los AirPods al tocar la isla, como la del iPhone: auricular izquierdo, estuche y auricular derecho
/// con las imágenes oficiales de Apple (si ya se bajaron) y la batería de cada uno.
struct AirPodsCardView: View {
    let state: AirPodsActivityState
    @ObservedObject private var ble = AirPodsBLEMonitor.shared

    private var identity: AirPodsAssetService.Identity? { AirPodsAssetService.currentIdentity }

    /// Lectura Bluetooth reciente del mismo modelo (trae si algo está cargando)
    private var reading: AirPodsBLEMonitor.Reading? {
        guard let r = ble.latest, Date().timeIntervalSince(r.at) < 60,
              identity.map({ AirPodsAssetService.product(productId: r.productIdHex, model: .unknownAirPods) == $0.product }) ?? false else { return nil }
        return r
    }

    var body: some View {
        IslandExpandedTemplate {
            EmptyView()
        } trailing: {
            EmptyView()
        } center: {
            Text(state.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        } bottom: {
            HStack(alignment: .bottom, spacing: 22) {
                if let identity, identity.product.hasPrefix("AirPodsMax") {
                    VStack(spacing: 6) {
                        if let loop = AirPodsAssetService.shared.clipURL(.maxLoop, for: identity) {
                            ProxCardVideoView(url: loop, rate: 1, zoom: 1.7, loops: true)
                                .frame(width: 96, height: 70)
                        } else {
                            Image(systemName: "airpodsmax")
                                .font(.system(size: 30))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 96, height: 70)
                        }
                        Text("\(state.batteryLevel)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(state.batteryLevel <= 20 ? DesignTokens.red : .white.opacity(0.85))
                    }
                } else {
                    part(image: "ProxCard_L", symbol: BluetoothAudioService.shared.currentAirPodsLeftSymbol,
                         level: reading?.left ?? state.leftPercent, charging: reading?.leftCharging ?? false)
                    part(image: (reading?.caseCharging ?? false) ? "ProxCard_case-closed-charging" : "ProxCard_case-closed-charged",
                         symbol: BluetoothAudioService.shared.currentAirPodsCaseSymbol,
                         level: reading?.caseLevel ?? state.casePercent, charging: reading?.caseCharging ?? false)
                    part(image: "ProxCard_R", symbol: BluetoothAudioService.shared.currentAirPodsLeftSymbol,
                         level: reading?.right ?? state.rightPercent, charging: reading?.rightCharging ?? false, mirrored: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .onAppear { AirPodsBLEMonitor.shared.scan(for: 6) }
    }

    @ViewBuilder
    private func part(image: String, symbol: String, level: Int?, charging: Bool, mirrored: Bool = false) -> some View {
        VStack(spacing: 6) {
            Group {
                if let url = AirPodsAssetService.shared.imageURL(image, for: identity), let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .scaleEffect(x: mirrored ? -1 : 1)
                }
            }
            .frame(width: 52, height: 46)

            HStack(spacing: 3) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DesignTokens.green)
                }
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(level.map { $0 <= 20 } ?? false ? DesignTokens.red : .white.opacity(0.85))
            }
        }
    }
}
