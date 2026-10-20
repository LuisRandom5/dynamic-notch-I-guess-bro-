import SwiftUI
import AppKit

/// Herramienta de diagnóstico: dibuja los avisos (mensaje de WhatsApp, foto, carga y batería baja) sobre fondo
/// negro y los guarda en /tmp/dn_notices.png, para revisarlos aunque la pantalla esté apagada.
@MainActor
enum NoticeRenderer {
    static func render() {
        let width = NotificationActivityProvider.compactWidth
        let height = NotificationActivityProvider.compactHeight
        func card(_ message: String, title: String = "Carlos") -> some View {
            QuickReplyNotificationView(id: "render_\(message.hashValue)", title: title, message: message)
                .frame(width: width, height: height, alignment: .top)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32).fill(Color.black))
        }
        func pill(_ label: String, labelColor: Color, percentage: Int, tint: Color, bolt: Bool) -> some View {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(labelColor)
                    .fixedSize()
                    .frame(width: 85, alignment: .center)
                Color.black.frame(width: 185)
                ChargingTrailingView(percentage: percentage, tintColor: tint, showBolt: bolt, compact: true)
                    .frame(width: 85, alignment: .center)
            }
            .frame(height: 32)
            .background(Capsule().fill(Color.black))
        }
        let sheet = VStack(spacing: 16) {
            card("¡Hola! ¿Cómo va el nuevo reproductor de pantalla de bloqueo? Te mando lo que quedó ayer")
            card(WhatsAppMessagePreview.describe("Foto"))
            card(WhatsAppMessagePreview.describe("Ana: Sticker", media: .sticker), title: "Familia")
            card(WhatsAppMessagePreview.describe("0:07", media: .voice))
            card("2 mensajes nuevos sin leer", title: "WhatsApp")
            pill("Cargando", labelColor: .white.opacity(0.92), percentage: 83, tint: DesignTokens.green, bolt: true)
            pill("Batería baja", labelColor: DesignTokens.red, percentage: 10, tint: DesignTokens.red, bolt: false)
        }
        .padding(20)
        .background(Color(white: 0.55))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "/tmp/dn_notices.png"))
    }
}
