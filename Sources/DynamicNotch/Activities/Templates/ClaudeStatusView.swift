import SwiftUI

/// Contenido del notch cuando la bolita de Claude se fusiona con él.
/// Se adapta al tamaño que le da la fusión:
/// - Alas (altura del notch): marca de Claude a la izquierda y porcentaje a la derecha de la cámara.
/// - Tarjeta: tarea, barra de progreso, paso del plan, acción actual y métricas.
public struct ClaudeStatusView: View {
    public let sessionId: String

    @ObservedObject private var provider = ClaudeActivityProvider.shared
    @ObservedObject private var screen = ScreenService.shared

    public init(sessionId: String) {
        self.sessionId = sessionId
    }

    private static let wingWidth: CGFloat = 52

    public var body: some View {
        GeometryReader { geo in
            if let state = provider.sessions[sessionId] {
                let isWings = geo.size.height < screen.currentGeometry.height + 24
                ZStack(alignment: .top) {
                    wings(state)
                        .frame(width: geo.size.width, height: screen.currentGeometry.height)
                        .opacity(isWings ? 1 : 0)
                    card(state)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .opacity(isWings ? 0 : 1)
                }
                .animation(.easeInOut(duration: 0.18), value: isWings)
            }
        }
    }

    // MARK: - Alas (etapa 1 de la fusión)

    private func wings(_ state: ClaudeSessionState) -> some View {
        HStack(spacing: 0) {
            ClaudeMarkView(size: 15, isAnimating: state.phase == .working)
                .frame(width: Self.wingWidth)
            Spacer(minLength: 0)
            percentLabel(state, size: 12)
                .frame(width: Self.wingWidth)
        }
    }

    // MARK: - Tarjeta (etapa 2 de la fusión)

    private func card(_ state: ClaudeSessionState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(state)
            progressBar(state)
            stepRow(state)
            actionRow(state)
            footer(state)
        }
        .padding(.horizontal, 20)
        .padding(.top, screen.currentGeometry.height + 6)
        .padding(.bottom, 14)
    }

    private func header(_ state: ClaudeSessionState) -> some View {
        HStack(spacing: 10) {
            ClaudeMarkView(size: 20, isAnimating: state.phase == .working)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(state.title.isEmpty ? state.project : state.title)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            phaseBadge(state.phase)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(since: state.startedAt, now: context.date))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func progressBar(_ state: ClaudeSessionState) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(ClaudeMarkView.orange)
                        .frame(width: max(6, geo.size.width * state.progress))
                }
            }
            .frame(height: 5)
            percentLabel(state, size: 11)
                .frame(width: 34, alignment: .trailing)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.progress)
    }

    @ViewBuilder
    private func stepRow(_ state: ClaudeSessionState) -> some View {
        if let step = state.currentStep {
            VStack(alignment: .leading, spacing: 2) {
                Text("PASO \(step.id + 1) DE \(state.steps.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(ClaudeMarkView.orange)
                Text(step.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        } else {
            Text(state.phase == .done ? "Tarea terminada" : "Trabajando en tu petición")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private func actionRow(_ state: ClaudeSessionState) -> some View {
        HStack(spacing: 7) {
            Image(systemName: state.icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(state.phase == .waiting ? .yellow : .white.opacity(0.6))
                .frame(width: 14)
            Text(state.action)
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func footer(_ state: ClaudeSessionState) -> some View {
        let filesText = state.files.isEmpty
            ? "sin archivos editados"
            : (state.files.count == 1 ? "1 archivo editado" : "\(state.files.count) archivos editados")
        return Text("\(state.tools) herramientas · \(filesText)")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.38))
    }

    // MARK: - Piezas

    private func percentLabel(_ state: ClaudeSessionState, size: CGFloat) -> some View {
        Group {
            if state.phase == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: size, weight: .bold))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
            } else {
                Text("\(Int((state.progress * 100).rounded()))%")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ClaudeMarkView.orange)
                    .contentTransition(.numericText())
            }
        }
    }

    private func phaseBadge(_ phase: ClaudeSessionState.Phase) -> some View {
        let (text, color): (String, Color) = {
            switch phase {
            case .working: return ("Trabajando", ClaudeMarkView.orange)
            case .waiting: return ("Te necesita", .yellow)
            case .done, .ended: return ("Listo", Color(red: 0.35, green: 0.85, blue: 0.55))
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
