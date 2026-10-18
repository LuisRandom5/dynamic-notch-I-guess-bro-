import SwiftUI
import AppKit

/// Bolita satélite de Live Activity para Dynamic Notch.
/// Rediseñada fielmente al lenguaje visual de las presentaciones mínimas de la Dynamic Island de iOS:
/// - Silueta circular precisa con centro negro sólido OLED (#000) idéntico a la cápsula del notch.
/// - Borde exterior sutil (0.75 pt) sin halos morados ni efectos RGB decorativos.
/// - Sin Liquid Glass por defecto en la bolita: integración pura y discreta.
/// - Contenido centrado ópticamente con símbolos SF Symbols limpios y tamaño equilibrado.
/// - Anillo fino y limpio (1.7 pt) semánticamente apropiado SOLO cuando la actividad tiene progreso real (ej. temporizador activo).
/// - Animación de reposo en calma total; micro-escala suave y luminosidad discreta en hover.
/// - Interacción táctil: micro-compresión elástica (0.94x) y fusión orgánica hacia el notch.
public struct NotchBolitaView: View {
    public let activity: LiveActivity
    public let side: SatelliteSide
    
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var appState = AppState.shared
    @ObservedObject var agentProvider = AgentActivityProvider.shared
    @ObservedObject var timerProvider = TimerActivityProvider.shared
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var hoverTimer: Timer?
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    public init(activity: LiveActivity, side: SatelliteSide = .right) {
        self.activity = activity
        self.side = side
    }
    
    private var size: CGFloat {
        appState.bolitaDiameter
    }
    
    private var isFusing: Bool {
        center.fusingActivityId == activity.id
    }
    
    /// Progreso real normalizado (0.0 ... 1.0) para actividades que lo requieren
    private var progress: Double {
        if activity.kind == .timer || activity.id == "live_timer" || activity.id == "sim_timer" {
            if timerProvider.hasActiveSession {
                return timerProvider.progressRatio
            }
        }
        if activity.kind == .agentAI {
            if agentProvider.satelliteProgress > 0 {
                return max(0.02, min(1.0, agentProvider.satelliteProgress))
            }
        }
        if let p = activity.progress {
            return max(0.0, min(1.0, p))
        }
        return 0.0
    }
    
    /// Define si la bolita debe renderizar un anillo fino de progreso
    private var showsProgressRing: Bool {
        switch activity.kind {
        case .timer:
            return true
        case .agentAI:
            return (agentProvider.isSatelliteActive || agentProvider.isActive) && agentProvider.satelliteProgress >= 0.02
        case .download:
            return activity.progress != nil
        default:
            if activity.id == "live_timer" || activity.id == "sim_timer" {
                return true
            }
            if let p = activity.progress, p > 0.01 && p < 0.99 {
                return true
            }
            return false
        }
    }
    
    /// Color semántico del anillo de progreso
    private var ringStrokeColor: Color {
        switch activity.kind {
        case .timer:
            return .orange
        case .agentAI:
            return Color(red: 0.72, green: 0.40, blue: 1.00)
        case .download:
            return .cyan
        default:
            return activity.tint
        }
    }
    
    /// Tinte del icono central
    private var iconColor: Color {
        switch activity.kind {
        case .call:
            return Color(red: 0.20, green: 0.84, blue: 0.46) // Verde teléfono Apple
        case .recording:
            return Color(red: 0.98, green: 0.26, blue: 0.22) // Rojo grabación Apple
        case .vpn:
            return Color(red: 0.22, green: 0.60, blue: 1.00) // Azul seguridad Apple
        case .timer:
            return .orange
        case .agentAI:
            return Color(red: 0.76, green: 0.45, blue: 1.00)
        case .download:
            return .cyan
        case .music:
            return Color(red: 0.98, green: 0.28, blue: 0.45)
        case .generic:
            return .white.opacity(0.92)
        }
    }
    
    /// Nombre de icono canónico
    private var iconName: String {
        if let variant = activity.bolitaVariant {
            return variant.iconName
        }
        switch activity.kind {
        case .call:
            return "phone.fill"
        case .recording:
            return "record.circle.fill"
        case .vpn:
            return "lock.shield.fill"
        case .timer:
            return "timer"
        case .agentAI:
            return "sparkle"
        case .download:
            return "arrow.down"
        case .music:
            return "music.note"
        case .generic:
            return "bell.fill"
        }
    }
    
    // MARK: - Presentación Mínima Dynamic Island (Limpia, Nativa, Sin RGB)
    @ViewBuilder
    private var minimalDynamicIslandView: some View {
        let isSmall = size <= 26
        let ringInset: CGFloat = isSmall ? 3.6 : 4.4
        let ringDiameter = max(0, size - ringInset)
        
        ZStack {
            // 1. Centro negro sólido OLED puro (#000)
            Circle()
                .fill(Color.black)
                .frame(width: size, height: size)
                .overlay(
                    // Borde exterior fino y sutil que define la silueta sin estridencias
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.40), radius: 3, x: 0, y: 1)
            
            // 2. Anillo de progreso fino y semántico (sólo si la actividad lo requiere)
            if showsProgressRing {
                // Pista gris oscura de fondo
                Circle()
                    .stroke(Color.white.opacity(0.13), lineWidth: 1.7)
                    .frame(width: ringDiameter, height: ringDiameter)
                
                // Arco de progreso con trazo semántico limpio sin halos decorativos
                Circle()
                    .trim(from: 0.0, to: CGFloat(max(0.01, min(1.0, progress))))
                    .stroke(
                        ringStrokeColor,
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: progress)
            }
            
            // 3. Contenido representativo centrado ópticamente
            if activity.kind == .recording {
                // Punto de grabación circular rojo minimalista idéntico a iOS
                Circle()
                    .fill(Color(red: 0.98, green: 0.26, blue: 0.22))
                    .frame(width: isSmall ? 6.5 : 7.5, height: isSmall ? 6.5 : 7.5)
            } else if activity.kind == .agentAI {
                let isFinished = (activity.state == .finished || agentProvider.satelliteProgress >= 0.999 || !(agentProvider.isActive)) && agentProvider.isSatelliteActive && agentProvider.satelliteProgress > 0.5
                if isFinished {
                    Image(systemName: "checkmark")
                        .font(.system(size: isSmall ? 8.0 : 9.0, weight: .bold))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
                } else {
                    // Logotipo de IA minimalista, nítido y con amplio espacio negativo negro OLED
                    Image(systemName: "sparkle")
                        .font(.system(size: isSmall ? 8.5 : 9.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.95))
                }
            } else {
                Image(systemName: iconName)
                    .font(.system(size: isSmall ? 10.0 : 11.5, weight: .semibold))
                    .foregroundColor(iconColor)
            }
        }
    }
    
    @ViewBuilder
    private var bolitaContextMenu: some View {
        Button {
            center.makePrimary(id: activity.id)
        } label: {
            Label("Hacer actividad principal", systemImage: "star.fill")
        }
        
        if activity.onTap != nil {
            Button {
                activity.onTap?()
            } label: {
                Label("Abrir actividad", systemImage: "arrow.up.forward.app")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            center.dismissBolita(id: activity.id)
        } label: {
            Label("Descartar", systemImage: "xmark")
        }
    }
    
    private var scaleAmount: CGFloat {
        if isPressed { return 0.94 }
        if isHovered { return 1.05 }
        return 1.0
    }
    
    public var body: some View {
        minimalDynamicIslandView
            .frame(width: size, height: size)
            .contentShape(Circle())
            .scaleEffect(scaleAmount)
            .brightness(isHovered ? 0.04 : 0.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isHovered)
            .animation(.spring(response: 0.16, dampingFraction: 0.75), value: isPressed)
            .highPriorityGesture(
                TapGesture().onEnded {
                    handleTapGesture()
                }
            )
            .contextMenu {
                bolitaContextMenu
            }
            .onHover { hovering in
                self.isHovered = hovering
                handleHoverChanged(hovering)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Haz clic para expandir en el notch")
            .help(accessibilityText)
    }
    
    private var accessibilityText: String {
        let title = activity.title ?? activity.kind.rawValue.capitalized
        if activity.kind == .agentAI {
            return "\(title): \(Int(progress * 100))% completado"
        } else if activity.kind == .timer {
            return "\(title): quedan \(Int(progress * 100))%"
        }
        return title
    }
    
    private func handleTapGesture() {
        if center.expandedActivity?.id == activity.id {
            center.collapseExpandedActivity()
            return
        }
        if center.isFusing && center.fusingActivityId == activity.id {
            center.reverseFusion(for: activity.id)
            return
        }
        if center.expandedActivity != nil && center.expandedActivity?.id != activity.id {
            center.switchExpandedActivity(to: activity, fromSide: side)
            return
        }
        
        // Micro-compresión táctil (0.94x) y disparo de fusión continua
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.isPressed = false
            self.center.initiateFusion(for: self.activity, fromSide: self.side)
        }
    }
    
    private func handleHoverChanged(_ hovering: Bool) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        
        guard hovering && appState.expandOnHover && center.expandedActivity == nil else { return }
        
        let delay = AnimationSpeedManager.shared.adjustedDuration(0.60)
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.isHovered && self.center.expandedActivity == nil {
                    self.center.initiateFusion(for: self.activity, fromSide: self.side)
                }
            }
        }
    }
}

/// Bolita para indicar actividades desbordadas (+N)
public struct NotchOverflowBolitaView: View {
    public let count: Int
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var appState = AppState.shared
    @State private var isHovered: Bool = false
    
    public init(count: Int) {
        self.count = count
    }
    
    private var size: CGFloat {
        appState.bolitaDiameter
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.40), radius: 3, x: 0, y: 1)
            
            Text("+\(count)")
                .font(.system(size: size <= 26 ? 9.5 : 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .brightness(isHovered ? 0.04 : 0.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isHovered)
        .onHover { hovering in
            self.isHovered = hovering
        }
        .onTapGesture {
            if let firstOverflow = center.overflowActivities.first {
                center.initiateFusion(for: firstOverflow, fromSide: .right)
            }
        }
        .help("\(count) actividades más. Clic para ver.")
    }
}

/// Vista envoltorio para compatibilidad con código existente
public struct NotchSatelliteBubbleView: View {
    public init() {}
    
    public var body: some View {
        if let agentActivity = ActivityCenter.shared.activeActivities.first(where: { $0.kind == .agentAI }) {
            NotchBolitaView(activity: agentActivity, side: .right)
        } else if let secondary = ActivityCenter.shared.secondaryActivities.first {
            NotchBolitaView(activity: secondary, side: .right)
        } else {
            EmptyView()
        }
    }
}
