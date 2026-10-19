import Testing
@testable import DynamicNotch

@Suite struct WhatsAppMessagePreviewTests {
    @Test func plainTextStaysAsIs() {
        #expect(WhatsAppMessagePreview.describe("¿Vienes hoy?") == "¿Vienes hoy?")
        #expect(WhatsAppMessagePreview.describe("Ana: ¿Vienes hoy?") == "Ana: ¿Vienes hoy?")
    }

    @Test func genericWordsBecomeLabels() {
        #expect(WhatsAppMessagePreview.describe("Foto") == "📷 Foto")
        #expect(WhatsAppMessagePreview.describe("Sticker") == "Sticker")
        #expect(WhatsAppMessagePreview.describe("Ana: Sticker", media: .sticker) == "Ana: Sticker")
        #expect(WhatsAppMessagePreview.describe("Ana: Foto") == "Ana: 📷 Foto")
    }

    @Test func webIconsTellTheKind() {
        #expect(WhatsAppMediaKind(webIcon: "status-image") == .photo)
        #expect(WhatsAppMediaKind(webIcon: "status-ptt") == .voice)
        #expect(WhatsAppMediaKind(webIcon: "status-sticker") == .sticker)
        #expect(WhatsAppMediaKind(webIcon: "status-dblcheck") == nil)
        #expect(WhatsAppMessagePreview.describe("", media: .photo) == "📷 Foto")
        #expect(WhatsAppMessagePreview.describe("0:07", media: .voice) == "🎤 Mensaje de voz (0:07)")
        #expect(WhatsAppMessagePreview.describe("Mira esto", media: .photo) == "📷 Mira esto")
    }

    @Test func kindIsRecoveredFromTheNoticeText() {
        #expect(WhatsAppMessagePreview.mediaKind(of: "📷 Foto") == .photo)
        #expect(WhatsAppMessagePreview.mediaKind(of: "Ana: 🎤 Mensaje de voz (0:07)") == .voice)
        #expect(WhatsAppMessagePreview.mediaKind(of: "📷 Mira esto") == .photo)
        #expect(WhatsAppMessagePreview.mediaKind(of: "Sticker") == .sticker)
        #expect(WhatsAppMessagePreview.mediaKind(of: "Hola") == nil)
    }
}
