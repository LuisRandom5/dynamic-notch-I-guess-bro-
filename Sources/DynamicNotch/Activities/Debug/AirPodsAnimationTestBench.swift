import SwiftUI

/// Banco de pruebas: cualquier modelo y color de AirPods con su animación oficial, sin cambiar los AirPods
/// conectados. El paquete de cada modelo se baja de Apple la primera vez (~4–12 MB).
struct AirPodsAnimationTestBench: View {
    @ObservedObject private var appState = AppState.shared
    @State private var product = "AirPods1,4"
    @State private var maxColor: AirPodsMaxColor = .silver
    @State private var status = ""

    /// Producto de Apple → nombre y colores disponibles en el catálogo
    private static let models: [(product: String, title: String)] = [
        ("AirPods1,1", "AirPods (1.ª gen.)"),
        ("AirPods1,2", "AirPods (2.ª gen.)"),
        ("AirPods1,3", "AirPods (3.ª gen.)"),
        ("AirPods1,4", "AirPods 4"),
        ("AirPods1,5", "AirPods 4 con ANC"),
        ("AirPodsPro1,1", "AirPods Pro"),
        ("AirPodsPro1,2", "AirPods Pro 2 (Lightning)"),
        ("AirPodsPro1,3", "AirPods Pro 2 (USB-C)"),
        ("AirPods3,7", "AirPods Pro 3"),
        ("AirPods3,8", "AirPods Pro 3 (variante)"),
        ("AirPodsMax1,1", "AirPods Max (Lightning)"),
        ("AirPodsMax1,2", "AirPods Max (USB-C)")
    ]

    private static func colors(for product: String) -> [AirPodsMaxColor] {
        switch product {
        case "AirPodsMax1,1": return [.silver, .spaceGray, .blue, .pink, .green]
        case "AirPodsMax1,2": return [.silver, .midnight, .blue, .purple, .orange]
        default: return []
        }
    }

    private var identity: AirPodsAssetService.Identity {
        AirPodsAssetService.Identity(product: product,
                                     variant: Self.colors(for: product).isEmpty ? "White" : maxColor.catalogVariant)
    }

    var body: some View {
        GroupBox("AirPods: animaciones oficiales (todos los modelos)") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Modelo", selection: $product) {
                    ForEach(Self.models, id: \.product) { Text($0.title).tag($0.product) }
                }
                .onChange(of: product) { _, newValue in
                    if let first = Self.colors(for: newValue).first, !Self.colors(for: newValue).contains(maxColor) {
                        maxColor = first
                    }
                    status = ""
                }

                if !Self.colors(for: product).isEmpty {
                    Picker("Color", selection: $maxColor) {
                        ForEach(Self.colors(for: product)) { Text($0.title).tag($0) }
                    }
                }

                Picker("Animación en las alas", selection: $appState.airPodsAnimationStyle) {
                    ForEach(AirPodsAnimationStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Button {
                        show()
                    } label: {
                        Label("Mostrar en la isla", systemImage: "airpods")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Abrir la tarjeta") {
                        if let activity = ActivityCenter.shared.activeActivities.first(where: { $0.id == AirPodsActivityProvider.shared.providerId }) {
                            ActivityCenter.shared.expandActivity(activity)
                        }
                    }
                }

                Text(status.isEmpty ? (AirPodsAssetService.shared.isAvailable(identity) ? "Listo: ya está guardado." : "Se baja de Apple la primera vez que lo muestres.") : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func show() {
        let identity = identity
        let title = Self.models.first { $0.product == product }?.title ?? product
        let publish = {
            AirPodsActivityProvider.shared.publishAirPodsActivity(
                name: title, batteryLevel: 82, leftPercent: 80, rightPercent: 85, casePercent: 46,
                duration: 8, assetProduct: identity.product, assetVariant: identity.variant
            )
        }
        if AirPodsAssetService.shared.isAvailable(identity) {
            status = ""
            publish()
            return
        }
        status = "Bajando de Apple…"
        AirPodsAssetService.shared.ensureAvailable(identity) { ready in
            status = ready ? "" : "No se pudo bajar (¿sin internet?)."
            if ready { publish() }
        }
    }
}
