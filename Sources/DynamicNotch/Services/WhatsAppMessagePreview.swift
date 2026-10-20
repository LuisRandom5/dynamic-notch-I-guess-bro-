import Foundation

/// Tipo de contenido de un mensaje de WhatsApp que no es (sólo) texto
public enum WhatsAppMediaKind: String, CaseIterable {
    case photo, video, voice, sticker, gif, document, location, contact, poll

    /// Como lo dice la notificación del iPhone
    public var label: String { L(spanishLabel) }

    private var spanishLabel: String {
        switch self {
        case .photo: return "📷 Foto"
        case .video: return "🎥 Video"
        case .voice: return "🎤 Mensaje de voz"
        case .sticker: return "Sticker"
        case .gif: return "GIF"
        case .document: return "📄 Documento"
        case .location: return "📍 Ubicación"
        case .contact: return "👤 Contacto"
        case .poll: return "📊 Encuesta"
        }
    }

    /// Icono SF Symbols para la tarjeta del aviso
    public var symbol: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .voice: return "mic.fill"
        case .sticker: return "face.smiling.inverse"
        case .gif: return "play.square.stack.fill"
        case .document: return "doc.fill"
        case .location: return "mappin.and.ellipse"
        case .contact: return "person.crop.circle.fill"
        case .poll: return "chart.bar.fill"
        }
    }

    /// Nombre del icono de WhatsApp Web (`data-icon`, p. ej. "status-image", "msg-video")
    public init?(webIcon: String) {
        let name = webIcon.lowercased()
        if name.contains("sticker") { self = .sticker }
        else if name.contains("gif") { self = .gif }
        else if name.contains("ptt") || name.contains("audio") || name.contains("mic") { self = .voice }
        else if name.contains("video") { self = .video }
        else if name.contains("image") || name.contains("photo") || name.contains("camera") { self = .photo }
        else if name.contains("document") || name.hasPrefix("doc") || name.contains("-doc") { self = .document }
        else if name.contains("location") { self = .location }
        else if name.contains("vcard") || name.contains("contact") { self = .contact }
        else if name.contains("poll") { self = .poll }
        else { return nil }
    }

    /// La vista previa es sólo la palabra genérica que pone WhatsApp ("Foto", "Sticker", "Audio"…)
    public init?(genericWord text: String) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch word {
        case "foto", "photo", "imagen", "image": self = .photo
        case "video", "vídeo": self = .video
        case "audio", "mensaje de voz", "nota de voz", "voice message": self = .voice
        case "sticker", "stícker": self = .sticker
        case "gif": self = .gif
        case "documento", "document", "archivo": self = .document
        case "ubicación", "ubicacion", "location", "ubicación en tiempo real", "live location": self = .location
        case "contacto", "contact": self = .contact
        case "encuesta", "poll": self = .poll
        default: return nil
        }
    }
}

/// Texto del aviso a partir de la vista previa de un chat de WhatsApp: el mensaje real, y si es una foto,
/// un sticker, un audio… lo dice ("📷 Foto", "Sticker", "🎤 Mensaje de voz (0:07)") en vez de quedar vacío.
public enum WhatsAppMessagePreview {
    public static func describe(_ rawText: String, media: WhatsAppMediaKind? = nil) -> String {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // En grupos la vista previa trae al autor: "Ana: Foto" → "Ana: 📷 Foto"
        if let colon = text.range(of: ": "), text.distance(from: text.startIndex, to: colon.lowerBound) <= 32 {
            let author = String(text[..<colon.lowerBound])
            let body = String(text[colon.upperBound...])
            if media != nil || WhatsAppMediaKind(genericWord: body) != nil {
                return "\(author): \(describeBody(body, media: media))"
            }
        }
        return describeBody(text, media: media)
    }

    private static func describeBody(_ rawBody: String, media: WhatsAppMediaKind?) -> String {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = WhatsAppMediaKind(genericWord: body)
        guard let kind = media ?? generic else { return body }
        if body.isEmpty || generic != nil { return kind.label }
        // Un audio muestra su duración en vez de texto
        if kind == .voice, body.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return "\(kind.label) (\(body))"
        }
        // Foto o video con texto: el texto es el pie de foto
        return "\(kind.label.split(separator: " ").first.map(String.init) ?? kind.label) \(body)"
    }

    /// Tipo de contenido que ya viene descrito en el texto del aviso (para el icono de la tarjeta)
    public static func mediaKind(of message: String) -> WhatsAppMediaKind? {
        var text = message
        if let colon = text.range(of: ": "), text.distance(from: text.startIndex, to: colon.lowerBound) <= 32 {
            text = String(text[colon.upperBound...])
        }
        return WhatsAppMediaKind.allCases.first { kind in
            text.hasPrefix(kind.label) || (kind.label.first?.isEmoji == true && text.hasPrefix(String(kind.label.prefix(1)) + " "))
        }
    }
}

private extension Character {
    var isEmoji: Bool { unicodeScalars.first.map { $0.properties.isEmojiPresentation } ?? false }
}
