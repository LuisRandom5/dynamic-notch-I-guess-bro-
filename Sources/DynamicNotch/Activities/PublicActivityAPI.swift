import AppKit
import SwiftUI

/// API pública de actividades (v1): cualquier script, Atajo o app inicia, actualiza y termina su propia actividad
/// en la isla, como `ActivityAttributes` + `ContentState` del iPhone. Llega por HTTP local
/// (`POST 127.0.0.1:48123/activity`), por el comando `dynamicnotch` o por `dynamicnotch://activity?…`.
/// Contrato completo y ejemplos: docs/API.md.
public enum PublicActivityAPI {
    public static let version = 1
    /// Como el límite de las Live Activities del iPhone
    public static let maxPayloadBytes = 4096
    /// Actividades de la API vivas a la vez (evita que un script llene la isla)
    public static let maxActive = 4
    static let idPrefix = "api."

    public enum Action: String {
        case start, update, end
    }

    public enum Placement: String {
        /// Bolita junto a la isla: no le quita el lugar a la música (por defecto)
        case bubble
        /// Puede ocupar el notch si es la más relevante
        case notch
    }

    public struct Request: Equatable {
        public var id: String
        public var action: Action?
        public var title: String?
        public var subtitle: String?
        public var icon: String?
        public var colorHex: String?
        public var progress: Double?
        public var value: String?
        public var relevance: Int?
        public var staleAfter: TimeInterval?
        public var alert: Bool
        public var sound: Bool
        public var url: URL?
        public var placement: Placement
        public var dismissAfter: TimeInterval?
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case tooLarge
        case invalidJSON
        case missingId
        case invalidId
        case invalidField(String)

        public var description: String {
            switch self {
            case .tooLarge: return "El cuerpo pasa de \(PublicActivityAPI.maxPayloadBytes) bytes"
            case .invalidJSON: return "JSON inválido"
            case .missingId: return "Falta \"id\""
            case .invalidId: return "\"id\" sólo admite letras, números, punto, guion y guion bajo (1–64)"
            case .invalidField(let name): return "Valor inválido en \"\(name)\""
            }
        }
    }

    // MARK: Validación (pura, con tests)

    public static func parse(_ data: Data) throws -> Request {
        guard data.count <= maxPayloadBytes else { throw ValidationError.tooLarge }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ValidationError.invalidJSON }
        return try parse(json)
    }

    /// Acepta números como número o como texto (los parámetros de una URL siempre son texto)
    public static func parse(_ json: [String: Any]) throws -> Request {
        guard let rawId = string(json["id"]) else { throw ValidationError.missingId }
        guard rawId.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else { throw ValidationError.invalidId }

        var action: Action?
        if let raw = string(json["action"]) {
            guard let parsed = Action(rawValue: raw.lowercased()) else { throw ValidationError.invalidField("action") }
            action = parsed
        }
        var placement = Placement.bubble
        if let raw = string(json["placement"]) {
            guard let parsed = Placement(rawValue: raw.lowercased()) else { throw ValidationError.invalidField("placement") }
            placement = parsed
        }
        var progress: Double?
        if json["progress"] != nil {
            guard let value = number(json["progress"]), value.isFinite else { throw ValidationError.invalidField("progress") }
            progress = min(1, max(0, value))
        }
        var relevance: Int?
        if json["relevance"] != nil {
            guard let value = number(json["relevance"]) else { throw ValidationError.invalidField("relevance") }
            relevance = Int(min(1000, max(0, value)))
        }
        var staleAfter: TimeInterval?
        if json["staleAfter"] != nil {
            guard let value = number(json["staleAfter"]), value > 0 else { throw ValidationError.invalidField("staleAfter") }
            staleAfter = min(8 * 3600, value)
        }
        var dismissAfter: TimeInterval?
        if json["dismissAfter"] != nil {
            guard let value = number(json["dismissAfter"]), value >= 0 else { throw ValidationError.invalidField("dismissAfter") }
            dismissAfter = min(60, value)
        }
        var url: URL?
        if let raw = string(json["url"]) {
            guard let parsed = URL(string: raw), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else {
                throw ValidationError.invalidField("url")
            }
            url = parsed
        }
        var colorHex: String?
        if let raw = string(json["color"]) {
            guard color(from: raw) != nil else { throw ValidationError.invalidField("color") }
            colorHex = raw
        }
        // "alert": true o {"sound": true}
        var alert = false
        var sound = false
        if let flag = json["alert"] as? Bool {
            alert = flag
        } else if let raw = json["alert"] as? String {
            alert = ["1", "true", "yes", "si", "sí"].contains(raw.lowercased())
        } else if let object = json["alert"] as? [String: Any] {
            alert = true
            sound = object["sound"] as? Bool ?? false
        }
        if let raw = json["sound"] as? Bool { sound = raw }

        return Request(
            id: rawId,
            action: action,
            title: string(json["title"]).map { String($0.prefix(80)) },
            subtitle: string(json["subtitle"]).map { String($0.prefix(160)) },
            icon: string(json["icon"]).map { String($0.prefix(64)) },
            colorHex: colorHex,
            progress: progress,
            value: string(json["value"]).map { String($0.prefix(12)) },
            relevance: relevance,
            staleAfter: staleAfter,
            alert: alert,
            sound: sound,
            url: url,
            placement: placement,
            dismissAfter: dismissAfter
        )
    }

    /// "#RRGGBB" o un nombre: green, blue, red, orange, yellow, purple, pink, teal, indigo, gray
    public static func color(from raw: String) -> Color? {
        let named: [String: Color] = [
            "green": DesignTokens.green, "blue": DesignTokens.blue, "red": DesignTokens.red,
            "orange": DesignTokens.orange, "yellow": DesignTokens.yellow, "purple": .purple, "pink": .pink,
            "teal": .teal, "indigo": .indigo, "gray": .gray, "grey": .gray
        ]
        if let color = named[raw.lowercased()] { return color }
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: Aplicar

    public enum Outcome: Equatable {
        case started, updated, ended
        case notFound
        case tooMany
    }

    /// Lo último que mandó cada actividad (una actualización sólo trae lo que cambia)
    private static var lastRequests: [String: Request] = [:]

    /// Debe llamarse en el hilo principal
    @discardableResult
    public static func apply(_ incoming: Request) -> Outcome {
        let activityId = idPrefix + incoming.id
        let exists = ActivityCenter.shared.activeActivities.contains { $0.id == activityId }
        let action = incoming.action ?? (exists ? .update : .start)

        if action == .end {
            guard exists else { return .notFound }
            let activity = makeActivity(merged(incoming))
            lastRequests[incoming.id] = nil
            ActivityCenter.shared.end(id: activityId, final: activity, dismissAfter: incoming.dismissAfter)
            return .ended
        }
        if action == .update && !exists { return .notFound }
        if !exists {
            let alive = ActivityCenter.shared.activeActivities.filter { $0.id.hasPrefix(idPrefix) }.count
            guard alive < maxActive else { return .tooMany }
            lastRequests[incoming.id] = nil
        }
        let request = merged(incoming)
        lastRequests[incoming.id] = request
        ActivityCenter.shared.publish(makeActivity(request))
        return exists ? .updated : .started
    }

    private static func merged(_ incoming: Request) -> Request {
        guard let previous = lastRequests[incoming.id] else { return incoming }
        var result = incoming
        result.title = incoming.title ?? previous.title
        result.subtitle = incoming.subtitle ?? previous.subtitle
        result.icon = incoming.icon ?? previous.icon
        result.colorHex = incoming.colorHex ?? previous.colorHex
        result.progress = incoming.progress ?? previous.progress
        result.value = incoming.value ?? previous.value
        result.relevance = incoming.relevance ?? previous.relevance
        result.staleAfter = incoming.staleAfter ?? previous.staleAfter
        result.url = incoming.url ?? previous.url
        return result
    }

    static func makeActivity(_ request: Request) -> LiveActivity {
        let tint = request.colorHex.flatMap(color(from:)) ?? DesignTokens.blue
        let icon = request.icon.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil } ?? "app.badge.fill"
        let shortText = request.value ?? request.progress.map { "\(Int(($0 * 100).rounded()))%" }
        let bolita: BolitaVariant = request.progress.map {
            .progressRing(progress: $0, strokeColor: tint, iconName: icon, shortText: request.value)
        } ?? .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: icon, shortText: request.value)

        var activity = LiveActivity(
            id: idPrefix + request.id,
            priority: request.relevance ?? ActivityRelevance.backgroundTask,
            style: .pill,
            title: request.title ?? request.id,
            subtitle: request.subtitle,
            progress: request.progress,
            leading: AnyView(
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            trailing: AnyView(
                Text(shortText ?? (request.title ?? ""))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
            ),
            bolitaVariant: bolita,
            tint: tint,
            onTap: request.url.map { url in { NSWorkspace.shared.open(url) } }
        )
        activity.prefersBubble = request.placement == .bubble
        if let staleAfter = request.staleAfter { activity.staleDate = Date().addingTimeInterval(staleAfter) }
        if request.alert { activity.alert = ActivityAlertConfiguration(sound: request.sound) }
        return activity
    }

    /// `dynamicnotch://activity?id=build&title=Compilando&progress=0.4` (Atajos: acción "Abrir URL")
    public static func handle(url: URL) -> Outcome? {
        guard url.scheme?.lowercased() == "dynamicnotch", url.host?.lowercased() == "activity",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              url.absoluteString.utf8.count <= maxPayloadBytes else { return nil }
        var json: [String: Any] = [:]
        for item in items { json[item.name] = item.value ?? "" }
        // Sin valor: --alert / --sound como banderas
        for flag in ["alert", "sound"] where json[flag] as? String == "" { json[flag] = true }
        guard let request = try? parse(json) else {
            DNDLogger.log("PublicActivityAPI: URL inválida \(url.absoluteString.prefix(120))")
            return nil
        }
        return apply(request)
    }

    /// Actividades de la API vivas (GET /activity)
    public static func activeSummary() -> [[String: Any]] {
        ActivityCenter.shared.activeActivities
            .filter { $0.id.hasPrefix(idPrefix) }
            .map { activity in
                var item: [String: Any] = ["id": String(activity.id.dropFirst(idPrefix.count))]
                if let title = activity.title { item["title"] = title }
                if let progress = activity.progress { item["progress"] = progress }
                return item
            }
    }
}
