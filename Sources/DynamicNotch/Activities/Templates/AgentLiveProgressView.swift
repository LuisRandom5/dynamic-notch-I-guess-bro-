import SwiftUI
import AppKit

public struct AgentLiveStep: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let isActive: Bool
    
    public init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false, isActive: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isActive = isActive
    }
}

public struct AgentFileDiff: Equatable {
    public let filename: String
    public let additions: Int
    public let deletions: Int
    public let statusText: String
    public let progress: Double // 0.0 ... 1.0
    
    public init(
        filename: String = "Sources/DynamicNotch",
        additions: Int = 0,
        deletions: Int = 0,
        statusText: String = "Trabajando...",
        progress: Double = 0.50
    ) {
        self.filename = filename
        self.additions = additions
        self.deletions = deletions
        self.statusText = statusText
        self.progress = max(0.0, min(1.0, progress))
    }
}

public enum AgentHUDDisplayMode: String, CaseIterable {
    case checklist = "checklist"
    case quotas = "quotas"
}

public struct AgentLiveProgressPayload: Equatable {
    public let agentName: String
    public let taskName: String
    public let steps: [AgentLiveStep]
    public let fileDiff: AgentFileDiff?
    public let isCompleted: Bool
    public let progress: Double?
    public let remainingTimeText: String?
    
    public init(
        agentName: String = "Antigravity",
        taskName: String = "Dynamic Notch",
        steps: [AgentLiveStep] = [
            AgentLiveStep(title: "Analizar requerimientos", isCompleted: true),
            AgentLiveStep(title: "Ejecutar cambios", isCompleted: false, isActive: true)
        ],
        fileDiff: AgentFileDiff? = AgentFileDiff(),
        isCompleted: Bool = false,
        progress: Double? = nil,
        remainingTimeText: String? = nil
    ) {
        self.agentName = agentName
        self.taskName = taskName
        self.steps = steps
        self.fileDiff = fileDiff
        self.isCompleted = isCompleted
        self.progress = progress
        self.remainingTimeText = remainingTimeText
    }
}

/// Vista HUD para Dynamic Notch que monitorea el progreso de la IA en tiempo real (Estilo Imagen 2).
/// Incluye encabezado con switch de píldora (Checklist ↔ Cuotas), columna izquierda con insignia de IA
/// y checklist de pasos, y columna derecha con tarjeta de archivo, diffs (+49 -19), estado y barra animada.
public struct AgentLiveProgressView: View {
    public let payloadFallback: AgentLiveProgressPayload?
    
    @ObservedObject private var agentProvider = AgentActivityProvider.shared
    @ObservedObject private var creditsService = AICreditsService.shared
    @State private var displayMode: AgentHUDDisplayMode = .checklist
    @State private var pulseActiveStep: Bool = false
    
    public static let hudWidth: CGFloat = 442
    public static let hudHeight: CGFloat = 224
    
    public init(payload: AgentLiveProgressPayload? = nil) {
        self.payloadFallback = payload
    }
    
    private var payload: AgentLiveProgressPayload {
        agentProvider.currentProgressPayload ?? payloadFallback ?? AgentLiveProgressPayload()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Encabezado: "Progress" y Pills de Cambio de Modo
            headerSection
            
            // MARK: - Contenido Dinámico según Modo Seleccionado
            if displayMode == .checklist {
                twoColumnProgressView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                quotasDashboardView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 34) // Despeje para la cámara del notch físico
        .padding(.bottom, 16)
        .frame(width: Self.hudWidth, height: Self.hudHeight, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseActiveStep = true
            }
        }
    }
    
    // MARK: - Encabezado
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                
                Text("Progress")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                if payload.isCompleted {
                    Text("✓ Completado")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.30, green: 0.85, blue: 0.45).opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Pills conmutadoras (Checklist vs Cuotas)
            HStack(spacing: 3) {
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        displayMode = .checklist
                    }
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(displayMode == .checklist ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            displayMode == .checklist
                                ? Color.white.opacity(0.20)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        displayMode = .quotas
                    }
                }) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(displayMode == .quotas ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            displayMode == .quotas
                                ? Color.white.opacity(0.20)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            
            // Botón Colapsar hacia la Burbuja Satélite
            Button(action: {
                agentProvider.collapseProgressHUD()
            }) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.50))
                    .padding(5)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("Colapsar a burbuja satélite")
        }
    }
    
    // MARK: - Distribución de Dos Columnas (Checklist + Tarjeta Archivo)
    
    private var twoColumnProgressView: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
            // Columna Izquierda: Badge de IA y Pasos
            VStack(alignment: .leading, spacing: 6) {
                // Badge de Agente y Tarea
                HStack(spacing: 6) {
                    agentIconView(for: payload.agentName)
                    
                    Text("\(payload.agentName) • \(payload.taskName)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.bottom, 2)
                
                // Lista de pasos
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(payload.steps.prefix(3)) { step in
                        HStack(spacing: 7) {
                            if step.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.45))
                                    .frame(width: 12)
                            } else if step.isActive {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
                                    .scaleEffect(pulseActiveStep ? 1.15 : 0.90)
                                    .frame(width: 12)
                            } else {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                    .frame(width: 6, height: 6)
                                    .frame(width: 12)
                            }
                            
                            Text(step.title)
                                .font(.system(size: 11, weight: step.isActive ? .semibold : .regular, design: .rounded))
                                .foregroundColor(
                                    step.isActive
                                        ? .white
                                        : (step.isCompleted ? .white.opacity(0.72) : .white.opacity(0.40))
                                )
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Columna Derecha: Tarjeta de Archivo Activo y Barra de Progreso
            if let diff = payload.fileDiff {
                VStack(alignment: .leading, spacing: 7) {
                    // Fila superior: Documento y Diffs (+49 -19)
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.80))
                        
                        Text(shortenedPath(diff.filename))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.90))
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 4) {
                            Text("+\(diff.additions)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.35, green: 0.88, blue: 0.45))
                            
                            Text("-\(diff.deletions)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.95, green: 0.42, blue: 0.42))
                        }
                    }
                    
                    // Estado de la acción ("Saving...", "Searching...", etc.) y tiempo restante estimado
                    HStack {
                        Text(diff.statusText)
                            .font(.system(size: 10.5, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        if let timeText = payload.remainingTimeText, !timeText.isEmpty {
                            Text(timeText)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(red: 0.78, green: 0.50, blue: 1.00))
                                .lineLimit(1)
                        } else {
                            Text("\(Int(diff.progress * 100))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.50))
                        }
                    }
                    
                    // Barra de progreso con indicador circular
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.65, blue: 1.00),
                                            Color(red: 0.80, green: 0.45, blue: 1.00)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(diff.progress)), height: 4)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.white.opacity(0.6), radius: 3)
                                .offset(x: max(0, min(geo.size.width - 8, geo.size.width * CGFloat(diff.progress) - 4)))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                )
                .frame(width: 178)
            }
        }
        
        // Footer: Uso Semanal de Antigravity AI
        let quota = creditsService.primaryQuota
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.72, green: 0.40, blue: 1.00))
            
            Text("Antigravity:")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
            
            Text("\(Int(quota.remainingPercent * 100))% restante")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.72, green: 0.40, blue: 1.00))
            
            Text("(\(quota.usedRequests)/\(quota.totalRequests))")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.50))
            
            Spacer()
            
            Text(quota.resetTimeString)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
    
    // MARK: - Vista de Cuotas y Límites de IA
    
    private var quotasDashboardView: some View {
        VStack(spacing: 8) {
            ForEach(creditsService.quotas) { quota in
                HStack(spacing: 10) {
                    // Ícono de marca
                    ZStack {
                        Circle()
                            .fill(Color(hex: quota.brandColorHex).opacity(0.20))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: quota.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: quota.brandColorHex))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(quota.name)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(Int(quota.remainingPercent * 100))% restante")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: quota.brandColorHex))
                        }
                        
                        // Barra de progreso horizontal
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 4)
                                
                                Capsule()
                                    .fill(Color(hex: quota.brandColorHex))
                                    .frame(width: geo.size.width * CGFloat(quota.remainingPercent), height: 4)
                            }
                        }
                        .frame(height: 4)
                        
                        HStack {
                            Text(quota.periodDescription)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundColor(.white.opacity(0.45))
                            
                            Spacer()
                            
                            Text(quota.resetTimeString)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func agentIconView(for agent: String) -> some View {
        let lower = agent.lowercased()
        if lower.contains("claude") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.45, blue: 0.20))
                    .frame(width: 18, height: 18)
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
        } else if lower.contains("gemini") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.25, green: 0.50, blue: 0.95))
                    .frame(width: 18, height: 18)
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.60, green: 0.35, blue: 1.00), Color(red: 0.18, green: 0.72, blue: 1.00)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func shortenedPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 2 {
            let last = components.last ?? ""
            let first = components.first ?? ""
            return "\(first)/.../\(last)"
        }
        return path
    }
}

// Extensión para color hex
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
