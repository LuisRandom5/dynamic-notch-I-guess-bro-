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
    @ObservedObject var claudeProvider = ClaudeActivityProvider.shared
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHolding: Bool = false
    /// Presión en curso: el temporizador de "mantener" y si ya se disparó (para no tratar el soltar como clic)
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var holdFired: Bool = false
    @State private var hoverTimer: Timer?
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    public init(activity: LiveActivity, side: SatelliteSide = .right) {
        self.activity = activity
        self.side = side
    }
    
    private var size: CGFloat {
        appState.effectiveBolitaDiameter
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
        if activity.kind == .claude, let session = claudeSession {
            return session.progress
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
    
    /// Sesión de Claude que representa esta bolita (sólo para kind == .claude)
    private var claudeSession: ClaudeSessionState? {
        guard activity.kind == .claude else { return nil }
        return claudeProvider.sessions[String(activity.id.dropFirst("claude_".count))]
    }
    
    private var isTimerPaused: Bool {
        activity.kind == .timer && timerProvider.hasActiveSession && !timerProvider.isRunning
    }
    
    /// Define si la bolita debe renderizar un anillo fino de progreso
    private var showsProgressRing: Bool {
        switch activity.kind {
        case .timer, .claude:
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
        case .claude:
            switch claudeSession?.phase {
            case .waiting: return .yellow // Claude espera tu respuesta o un permiso
            default: return ClaudeMarkView.orange
            }
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
        case .claude:
            return ClaudeMarkView.orange
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
        case .agentAI, .claude:
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
        // Estilo Isla Dinámica del iPhone: círculo negro con margen y, dentro, un anillo grueso con su pista
        // tenue y el icono al centro
        // Más margen negro alrededor: el anillo y el icono ocupan menos del círculo
        let ringDiameter = size * 0.58
        let ringWidth = max(2.2, size * 0.075)
        
        ZStack {
            // 1. Fondo: negro OLED junto al notch negro, o el mismo Liquid Glass del notch desplegado
            NotchBubbleBackground(size: size)
            
            // 2. Pista del anillo: siempre visible (da la silueta de la bolita); el arco sólo con progreso
            Circle()
                .stroke(showsProgressRing ? ringStrokeColor.opacity(0.28) : Color.white.opacity(0.16), lineWidth: ringWidth)
                .frame(width: ringDiameter, height: ringDiameter)
            
            if showsProgressRing {
                Circle()
                    .trim(from: 0.0, to: CGFloat(max(0.01, min(1.0, progress))))
                    .stroke(
                        ringStrokeColor,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .opacity(isTimerPaused ? 0.45 : 1)
                    // El temporizador avanza cada 0.1 s: interpolación lineal para que el anillo se vacíe
                    // de forma continua (un resorte lo haría ir "a jalones")
                    .animation(activity.kind == .timer ? .linear(duration: 0.1) : .spring(response: 0.35, dampingFraction: 0.82), value: progress)
            }
            
            // 3. Contenido representativo centrado ópticamente
            if activity.kind == .claude {
                // Marca de Claude: respira mientras trabaja; el anillo pulsa si espera respuesta del usuario
                ClaudeMarkView(size: size * 0.29, isAnimating: claudeSession?.phase == .working)
            } else if activity.kind == .timer && timerProvider.hasActiveSession {
                // Sólo el icono: la bolita es una miniatura en vivo, el anillo ya dice cuánto falta
                Image(systemName: timerProvider.mode == .countdown ? "timer" : "stopwatch")
                    .font(.system(size: size * 0.24, weight: .semibold))
                    .foregroundColor(DesignTokens.orange)
                    .opacity(isTimerPaused ? 0.6 : 1)
            } else if activity.id == ShelfActivityProvider.activityId {
                // Repisa: cantidad de archivos en azul (con 1 archivo, el icono de bandeja)
                let count = activity.bolitaVariant?.shortText ?? ""
                if count == "1" || count.isEmpty {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: size * 0.23, weight: .semibold))
                        .foregroundColor(ShelfActivityProvider.blue)
                } else {
                    Text(count)
                        .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(ShelfActivityProvider.blue)
                        .contentTransition(.numericText())
                }
            } else if activity.kind == .recording {
                // Punto de grabación circular rojo minimalista idéntico a iOS
                Circle()
                    .fill(Color(red: 0.98, green: 0.26, blue: 0.22))
                    .frame(width: size * 0.21, height: size * 0.21)
            } else if activity.kind == .agentAI {
                let isFinished = (activity.state == .finished || agentProvider.satelliteProgress >= 0.999 || !(agentProvider.isActive)) && agentProvider.isSatelliteActive && agentProvider.satelliteProgress > 0.5
                if isFinished {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.23, weight: .bold))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
                } else {
                    // Logotipo de IA minimalista, nítido y con amplio espacio negativo negro OLED
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.95))
                }
            } else {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.24, weight: .semibold))
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
        if isPressed || isHolding { return 0.92 }
        // Al pasar el cursor la bolita crece: invita a tocarla
        if isHovered { return 1.12 }
        return 1.0
    }
    
    public var body: some View {
        minimalDynamicIslandView
            .frame(width: size, height: size)
            .contentShape(Circle())
            .scaleEffect(scaleAmount)
            .brightness(isHovered ? 0.04 : 0.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: isHovered)
            .animation(.spring(response: 0.16, dampingFraction: 0.75), value: isPressed)
            .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isHolding)
            // Clic = abrir la app · mantener presionado (0.35 s) = expandir, como la Isla Dinámica del iPhone
            // Un solo gesto que mide la presión: en macOS `LongPressGesture.exclusively(before: TapGesture)` se
            // quedaba con el clic corto y el TapGesture nunca llegaba (clic muerto)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in beginPressIfNeeded() }
                    .onEnded { value in endPress(cancelled: hypot(value.translation.width, value.translation.height) > 12) }
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
            .accessibilityHint("Haz clic para abrir la app; mantén presionado para expandir")
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
    
    /// App que abre un clic en la bolita (como en el iPhone: tocar una actividad abre su app)
    private var sourceAppBundleId: String? {
        switch activity.kind {
        case .claude: return "com.anthropic.claudefordesktop"
        case .timer: return "com.apple.clock"
        case .agentAI: return "com.google.antigravity"
        case .call: return "com.apple.FaceTime"
        default: return nil
        }
    }
    
    /// Clic, como en el iPhone: abre la app de la actividad. Si la bolita no tiene app propia, hace lo de
    /// mantener presionado (expandir), para que ningún clic quede muerto.
    private func handleTapGesture() {
        center.lastSatelliteTapAt = Date()
        center.cancelAlertAutoCollapse()
        // La repisa no tiene app ni tarjeta: su bolita abre la repisa del notch
        if activity.id == ShelfActivityProvider.activityId {
            activity.onTap?()
            return
        }
        if center.expandedActivity?.id == activity.id {
            center.collapseExpandedActivity()
            return
        }
        switch appState.bubbleTapAction {
        case .expand:
            handleLongPress()
            return
        case .bringToNotch:
            // Como el iPhone con varias actividades: tocar una la trae al lugar principal. Las que sólo viven
            // como bolita (Claude, la repisa) no tienen presentación en el notch: se expanden
            if center.canTakeNotch(activity) {
                center.makePrimary(id: activity.id)
            } else {
                handleLongPress()
            }
            return
        case .openApp:
            break
        }
        // Si su app ya está al frente, abrirla no haría nada visible: se expande la tarjeta (p. ej. Claude
        // trabajando mientras lo ves en su ventana → la tarjeta muestra qué está haciendo)
        let frontmostId = Self.frontmostBundleId()
        DNDLogger.log("Bolita: clic en \(activity.kind.rawValue) (app al frente: \(frontmostId ?? "-"))")
        if let bundleId = sourceAppBundleId,
           bundleId != frontmostId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { self.isPressed = false }
            SoundFeedbackService.shared.playBubblePop()
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let onTap = activity.onTap {
            onTap()
            return
        }
        handleLongPress()
    }
    
    /// App al frente leída de la lista de ventanas: `NSWorkspace.frontmostApplication` se queda viejo en una
    /// app que nunca se activa (seguía diciendo Safari con Claude al frente)
    private static func frontmostBundleId() -> String? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let top = windows.first(where: {
            ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? Int32) != ownPID
        }), let pid = top[kCGWindowOwnerPID as String] as? Int32 else {
            return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Inicio de la presión: la bolita se comprime y, si se mantiene `bubbleHoldDuration`, se expande
    private func beginPressIfNeeded() {
        guard holdWorkItem == nil, !holdFired else { return }
        isHolding = true
        let item = DispatchWorkItem {
            holdFired = true
            isHolding = false
            holdWorkItem = nil
            handleLongPress()
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + appState.bubbleHoldDuration, execute: item)
    }

    /// Al soltar: si no alcanzó a ser "mantener", es un clic (salvo que el cursor se haya ido lejos)
    private func endPress(cancelled: Bool) {
        let wasHold = holdFired
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdFired = false
        isHolding = false
        if !wasHold && !cancelled { handleTapGesture() }
    }

    /// Mantener presionado, como en el iPhone: la actividad se expande en su tarjeta
    private func handleLongPress() {
        center.lastSatelliteTapAt = Date()
        center.cancelAlertAutoCollapse()
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
        appState.effectiveBolitaDiameter
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
