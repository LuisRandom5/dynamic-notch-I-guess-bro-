import SwiftUI
import Combine

/// Paso de la lista de tareas de Claude (update_plan).
public struct ClaudeStep: Identifiable, Equatable {
    public enum Status: String {
        case pending, inProgress = "in_progress", completed
    }
    public let id: Int
    public let title: String
    public let status: Status
}

/// Estado de una sesión de Claude Code reportado por scripts/claude_notch_hook.py.
public struct ClaudeSessionState: Equatable {
    public enum Phase: String {
        case working, waiting, done, ended
    }

    public var session: String
    public var phase: Phase
    public var title: String
    public var project: String
    public var progress: Double
    public var steps: [ClaudeStep]
    public var stepIndex: Int?
    public var action: String
    public var icon: String
    public var tools: Int
    public var files: [String]
    public var startedAt: Date

    public var currentStep: ClaudeStep? {
        guard let i = stepIndex, steps.indices.contains(i) else { return nil }
        return steps[i]
    }
}

/// Uso de la suscripción de Claude reportado por la status line (scripts/claude_statusline.py).
public struct ClaudeUsage: Equatable {
    /// Porcentaje usado (0–100) del límite de la sesión de 5 h y del semanal; nil si Claude Code no lo reporta
    public var fiveHourUsed: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayUsed: Double?
    public var sevenDayResetsAt: Date?
    public var updatedAt: Date
}

/// Convierte los reportes de Claude en la bolita satélite "Claude" (una por sesión) y su tarjeta de estado.
public final class ClaudeActivityProvider: ObservableObject {
    public static let shared = ClaudeActivityProvider()

    /// Tamaño de la tarjeta al fusionarse con el notch
    public static let cardWidth: CGFloat = 440
    public static let cardHeight: CGFloat = 216

    @Published public private(set) var sessions: [String: ClaudeSessionState] = [:]
    @Published public private(set) var usage: ClaudeUsage?
    
    /// Aplica un reporte de uso de la status line (llamar en el hilo principal).
    public func handleUsage(json: [String: Any]) {
        func date(_ key: String) -> Date? {
            (json[key] as? Double).map { Date(timeIntervalSince1970: $0) }
        }
        usage = ClaudeUsage(
            fiveHourUsed: json["fiveHourUsed"] as? Double,
            fiveHourResetsAt: date("fiveHourResetsAt"),
            sevenDayUsed: json["sevenDayUsed"] as? Double,
            sevenDayResetsAt: date("sevenDayResetsAt"),
            updatedAt: Date()
        )
    }

    private var removalTimers: [String: Timer] = [:]

    private init() {}

    public static func activityId(for session: String) -> String {
        "claude_\(session)"
    }

    /// Aplica un reporte JSON del hook (llamar en el hilo principal).
    public func handle(json: [String: Any]) {
        let session = (json["session"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        let phase = ClaudeSessionState.Phase(rawValue: json["state"] as? String ?? "") ?? .working
        let activityId = Self.activityId(for: session)

        if phase == .ended {
            removeSession(session)
            return
        }

        let rawSteps = json["steps"] as? [[String: Any]] ?? []
        let steps = rawSteps.enumerated().map { index, item in
            ClaudeStep(
                id: index,
                title: item["title"] as? String ?? "",
                status: ClaudeStep.Status(rawValue: item["status"] as? String ?? "") ?? .pending
            )
        }
        let previous = sessions[session]
        // El progreso nunca retrocede dentro de un turno (el hook ya lo garantiza; esto cubre mensajes fuera de orden)
        let reported = max(0, min(1, json["progress"] as? Double ?? 0))
        let isNewTurn = (json["event"] as? String) == "UserPromptSubmit"
        let progress = (isNewTurn || previous == nil) ? reported : max(previous?.progress ?? 0, reported)

        let state = ClaudeSessionState(
            session: session,
            phase: phase,
            title: json["title"] as? String ?? "",
            project: json["project"] as? String ?? "",
            progress: phase == .done ? 1.0 : progress,
            steps: steps,
            stepIndex: json["stepIndex"] as? Int,
            action: json["action"] as? String ?? "",
            icon: json["icon"] as? String ?? "sparkle",
            tools: json["tools"] as? Int ?? 0,
            files: json["files"] as? [String] ?? [],
            startedAt: Date(timeIntervalSince1970: json["startedAt"] as? Double ?? Date().timeIntervalSince1970)
        )

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            sessions[session] = state
        }

        removalTimers[session]?.invalidate()
        removalTimers[session] = nil
        if phase == .done {
            // Al terminar, la bolita muestra el anillo completo un momento y luego se retira
            scheduleRemoval(of: session, after: 20)
        } else {
            // Watchdog: si la sesión deja de reportar (Claude cerrado a la fuerza), retirar la bolita
            scheduleRemoval(of: session, after: 30 * 60)
        }

        // La tarjeta lee `sessions` directamente; republicar sólo cuando cambia algo que muestra la bolita
        let exists = ActivityCenter.shared.activeActivities.contains { $0.id == activityId }
        guard !exists || previous?.phase != phase || previous?.progress != state.progress else {
            return
        }
        ActivityCenter.shared.publish(makeActivity(for: state))
    }

    private func makeActivity(for state: ClaudeSessionState) -> LiveActivity {
        let lifecycle: ActivityLifecycleState
        switch state.phase {
        case .working: lifecycle = .active
        case .waiting: lifecycle = .attention
        case .done, .ended: lifecycle = .finished
        }
        return LiveActivity(
            id: Self.activityId(for: state.session),
            kind: .claude,
            style: .card,
            state: lifecycle,
            title: "Claude",
            subtitle: state.action,
            progress: state.progress,
            expandedView: AnyView(ClaudeStatusView(sessionId: state.session)),
            tint: ClaudeMarkView.orange,
            customExpandedWidth: Self.cardWidth,
            customExpandedHeight: Self.cardHeight
        )
    }

    private func scheduleRemoval(of session: String, after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Si el usuario tiene la tarjeta abierta, esperar a que la cierre
            if ActivityCenter.shared.expandedActivity?.id == Self.activityId(for: session) {
                self.scheduleRemoval(of: session, after: 5)
                return
            }
            self.removeSession(session)
        }
        RunLoop.main.add(timer, forMode: .common)
        removalTimers[session] = timer
    }

    private func removeSession(_ session: String) {
        removalTimers[session]?.invalidate()
        removalTimers[session] = nil
        sessions[session] = nil
        ActivityCenter.shared.dismissBolita(id: Self.activityId(for: session))
    }
}
