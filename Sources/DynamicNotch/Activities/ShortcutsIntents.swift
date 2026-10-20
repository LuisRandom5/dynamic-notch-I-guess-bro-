import AppIntents
import Foundation

// Acciones de Atajos (y Siri): las mismas actividades de la API pública (docs/API.md), sin escribir JSON.

/// Muestra o actualiza una actividad en la isla
struct ShowIslandActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Mostrar actividad en la isla"
    static let description = IntentDescription("Pone una actividad propia en la Isla Dinámica, o actualiza la que ya tiene ese identificador.")

    @Parameter(title: "Identificador", description: "Letras, números, punto, guion o guion bajo. Úsalo para actualizarla o terminarla después.")
    var identifier: String

    @Parameter(title: "Título")
    var title: String

    @Parameter(title: "Subtítulo")
    var subtitle: String?

    @Parameter(title: "Ícono", description: "Nombre de un símbolo SF, p. ej. hammer.fill", default: "app.badge.fill")
    var icon: String

    @Parameter(title: "Color", description: "green, blue, red, orange, yellow, purple, pink, teal, indigo, gray o #RRGGBB", default: "blue")
    var color: String

    @Parameter(title: "Progreso (0–1)")
    var progress: Double?

    @Parameter(title: "Expandir un momento", default: false)
    var alert: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Mostrar \(\.$title) en la isla como \(\.$identifier)") {
            \.$subtitle
            \.$icon
            \.$color
            \.$progress
            \.$alert
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var json: [String: Any] = ["id": identifier, "title": title, "icon": icon, "color": color, "alert": alert]
        if let subtitle { json["subtitle"] = subtitle }
        if let progress { json["progress"] = progress }
        let outcome = try await IslandIntentRunner.apply(json)
        return .result(dialog: outcome)
    }
}

/// Termina una actividad (muestra su resumen unos segundos y se va)
struct EndIslandActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Terminar actividad de la isla"
    static let description = IntentDescription("Termina la actividad con ese identificador; puede cambiar el título del resumen.")

    @Parameter(title: "Identificador")
    var identifier: String

    @Parameter(title: "Título final")
    var title: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Terminar \(\.$identifier)") {
            \.$title
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var json: [String: Any] = ["id": identifier, "action": "end"]
        if let title { json["title"] = title }
        let outcome = try await IslandIntentRunner.apply(json)
        return .result(dialog: outcome)
    }
}

enum IslandIntentRunner {
    struct Failure: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { "\(message)" }
    }

    @MainActor
    static func apply(_ json: [String: Any]) throws -> IntentDialog {
        let request: PublicActivityAPI.Request
        do {
            request = try PublicActivityAPI.parse(json)
        } catch {
            throw Failure(message: "\(error)")
        }
        switch PublicActivityAPI.apply(request) {
        case .started: return "Listo, está en la isla."
        case .updated: return "Actualizada."
        case .ended: return "Terminada."
        case .notFound: throw Failure(message: "No hay una actividad con ese identificador.")
        case .tooMany: throw Failure(message: "Ya hay \(PublicActivityAPI.maxActive) actividades de Atajos o scripts a la vez.")
        }
    }
}

/// Frases para Siri y acciones listas en Atajos
struct DynamicNotchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowIslandActivityIntent(),
            phrases: ["Mostrar actividad en \(.applicationName)", "Poner algo en la isla de \(.applicationName)"],
            shortTitle: "Mostrar actividad",
            systemImageName: "capsule.fill"
        )
        AppShortcut(
            intent: EndIslandActivityIntent(),
            phrases: ["Terminar actividad de \(.applicationName)"],
            shortTitle: "Terminar actividad",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
