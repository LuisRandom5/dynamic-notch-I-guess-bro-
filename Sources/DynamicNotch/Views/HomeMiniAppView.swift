import SwiftUI

// MARK: - Casa (mini app dentro de la isla)
// La lavadora y el refri de un vistazo. Al tocar el refri se abre a todo lo ancho con sus controles
// (temperaturas, enfriamiento rápido, super congelación y eco); el botón de la tele abre su control remoto.
public struct HomeMiniAppView: View {
    @ObservedObject private var store = HomeStore.shared
    @ObservedObject private var tv = TVRemote.shared
    @EnvironmentObject var appState: AppState
    public var onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 7) {
            header
            if tv.isShowingRemote && tv.isAvailable {
                TVRemoteCard {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { tv.isShowingRemote = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if !store.isConfigured {
                message(icon: "house.fill",
                        title: L("Conecta tu cuenta de ConnectLife"),
                        detail: L("Para ver aquí tu lavadora y tu refri Hisense."),
                        button: L("Abrir Ajustes")) {
                    SettingsNavigation.shared.selectedTab = .home
                    SettingsWindowController.shared.show()
                }
            } else if store.snapshot.isEmpty {
                switch store.connection {
                case .failed(let error):
                    message(icon: "wifi.exclamationmark", title: L("No se pudo leer la casa"), detail: error,
                            button: L("Reintentar")) { store.refreshNow() }
                default:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Preguntando a ConnectLife…"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if store.showsFridgeControls, let fridge = store.fridge {
                FridgeControlsCard(fridge: fridge, pendingKeys: store.pendingKeys, message: store.controlMessage) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { store.showsFridgeControls = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                HStack(spacing: 8) {
                    if let washer = store.washer {
                        WasherCard(washer: washer)
                    }
                    if let fridge = store.fridge {
                        Button {
                            appState.hapticService.triggerSnap()
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { store.showsFridgeControls = true }
                        } label: {
                            FridgeCard(fridge: fridge)
                        }
                        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.97))
                        .frame(width: store.washer == nil ? nil : 148)
                        .help(L("Cambiar la temperatura y los modos"))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DesignTokens.blue)
            Text(L("Casa"))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if case .failed = store.connection, !store.snapshot.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignTokens.orange)
                    .help(L("La última consulta falló; se muestra lo último que se supo"))
            }
            if store.snapshot.fetchedAt > .distantPast {
                Text(store.snapshot.fetchedAt, style: .relative)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
            }
            Spacer()
            if tv.isAvailable && !tv.isShowingRemote {
                // La tele: abre su control (y dice qué tiene abierto)
                Button(action: {
                    appState.hapticService.triggerSnap()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        store.showsFridgeControls = false
                        tv.isShowingRemote = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "tv")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(tv.currentAppName ?? L("Tele"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help(L("Control de la tele"))
                .task { await tv.refresh() }
            }
            if store.isConfigured && !tv.isShowingRemote {
                Button(action: {
                    appState.hapticService.triggerSnap()
                    store.refreshNow()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 20, height: 16)
                }
                .buttonStyle(.plain)
                .help(L("Actualizar ahora"))
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
    }

    private func message(icon: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignTokens.blue)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(action: action) {
                Text(button)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DesignTokens.blue.opacity(0.35)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Acceso directo en la esquina de la isla abierta, junto al temporizador. El punto avisa que la lavadora está en
/// un ciclo o que algo pide atención.
public struct HomeMiniAppButton: View {
    @ObservedObject private var store = HomeStore.shared
    @EnvironmentObject var appState: AppState
    var willOpen: () -> Void

    public init(willOpen: @escaping () -> Void) {
        self.willOpen = willOpen
    }

    public var body: some View {
        if store.isConfigured {
            let isOpen = appState.activeMiniAppOverlay == .home
            let needsAttention = (store.washer?.hasError ?? false) || (store.fridge?.isDoorAlarm ?? false)
            let isBusy = store.washer?.isCycleActive ?? false
            let tint = needsAttention ? DesignTokens.orange : DesignTokens.blue
            Button(action: {
                appState.hapticService.triggerSnap()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    willOpen()
                    appState.activeMiniAppOverlay = isOpen ? nil : .home
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(isOpen || isBusy || needsAttention ? tint : Color.white.opacity(0.55))
                        .frame(width: 22, height: 16)
                        .background(
                            Capsule()
                                .fill(isOpen ? tint.opacity(0.18) : Color.white.opacity(0.07))
                        )
                    if (isBusy || needsAttention) && !isOpen {
                        Circle()
                            .fill(tint)
                            .frame(width: 4.5, height: 4.5)
                            .offset(x: -1, y: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(L("Casa: lavadora y refri"))
        }
    }
}

// MARK: - Tarjetas

private struct HomeCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }
}

private struct WasherCard: View {
    let washer: WasherStatus

    private var tint: Color {
        if washer.hasError { return DesignTokens.red }
        if washer.isCycleActive { return DesignTokens.blue }
        if washer.phase == .finished { return DesignTokens.green }
        return .white.opacity(0.6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: washer.isCycleActive ? washer.progress : (washer.phase == .finished ? 1 : 0))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "washer.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(washer.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                    Text(washer.statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(washer.hasError ? DesignTokens.red : .white)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if washer.isCycleActive, washer.remainingMinutes > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(HomeActivityProvider.minutesText(washer.remainingMinutes))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(tint)
                            .lineLimit(1)
                        Text(String(format: L("a las %@"),
                                    Date().addingTimeInterval(TimeInterval(washer.remainingMinutes * 60))
                                        .formatted(date: .omitted, time: .shortened)))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }

            if washer.isCycleActive {
                PhaseTimeline(steps: washer.timeline, current: washer.phase, tint: tint)
            }

            Spacer(minLength: 0)

            let details = [washer.program, washer.temperature, washer.spin].compactMap { $0 }
            HStack(spacing: 5) {
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .lineLimit(1)
                }
                if washer.isDoorOpen {
                    Label(L("Puerta abierta"), systemImage: "door.left.hand.open")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        }
        .modifier(HomeCardBackground())
    }
}

/// Lavar → Enjuagar → Centrifugar (→ Secar): la fase actual resaltada
private struct PhaseTimeline: View {
    let steps: [WasherStatus.Phase]
    let current: WasherStatus.Phase
    let tint: Color

    private var currentIndex: Int {
        if let index = steps.firstIndex(of: current) { return index }
        // Pesar y prelavado van antes del lavado
        return current == .weigh || current == .prewash ? -1 : steps.count
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let done = index < currentIndex
                let isCurrent = index == currentIndex
                VStack(spacing: 3) {
                    Capsule()
                        .fill(done || isCurrent ? tint : Color.white.opacity(0.14))
                        .opacity(isCurrent ? 1 : (done ? 0.55 : 1))
                        .frame(height: 3.5)
                    Text(step.shortTitle)
                        .font(.system(size: 9, weight: isCurrent ? .bold : .medium))
                        .foregroundColor(isCurrent ? .white : .white.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct FridgeCard: View {
    let fridge: FridgeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "refrigerator.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(fridge.isDoorOpen ? DesignTokens.orange : Color.cyan)
                Text(fridge.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !fridge.isOnline {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            temperatureRow(L("Refri"), target: fridge.fridgeTarget, actual: fridge.fridgeActual, tint: .cyan)
            temperatureRow(L("Congelador"), target: fridge.freezerTarget, actual: fridge.freezerActual, tint: DesignTokens.blue)

            Spacer(minLength: 0)

            Group {
                if fridge.isDoorOpen {
                    Label(L("Puerta abierta"), systemImage: "door.left.hand.open")
                        .foregroundColor(DesignTokens.orange)
                } else {
                    let modes = [fridge.superCool ? L("Super Frío") : nil,
                                 fridge.superFreeze ? L("Super Congelar") : nil,
                                 fridge.holiday ? L("Vacaciones") : nil].compactMap { $0 }
                    if !modes.isEmpty {
                        Text(modes.joined(separator: " · "))
                    } else if let ambient = fridge.ambient {
                        Text(String(format: L("Afuera %d°"), ambient))
                    }
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .lineLimit(1)
        }
        .modifier(HomeCardBackground())
    }

    private func temperatureRow(_ title: String, target: Int?, actual: Int?, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text(target.map { "\($0)°" } ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(tint)
            if let actual, actual != target {
                Text("\(actual)°")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.4))
                    .help(L("Lo que mide el sensor ahora"))
            }
        }
    }
}

// MARK: - Controles del refri

private struct FridgeControlsCard: View {
    let fridge: FridgeStatus
    let pendingKeys: Set<String>
    let message: String?
    var onBack: () -> Void
    @EnvironmentObject var appState: AppState

    private func isPending(_ key: String) -> Bool { pendingKeys.contains(fridge.puid + "|" + key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Image(systemName: "refrigerator.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.cyan)
                        Text(fridge.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if let message {
                    Text(message)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(DesignTokens.orange)
                        .lineLimit(1)
                } else if !fridge.isOnline {
                    Label(L("Sin conexión"), systemImage: "wifi.slash")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                } else if let ambient = fridge.ambient {
                    Text(String(format: L("Afuera %d°"), ambient))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            HStack(spacing: 8) {
                TemperatureStepper(title: L("Refri"), value: fridge.fridgeTarget, actual: fridge.fridgeActual,
                                   range: fridge.fridgeRange, tint: .cyan, isPending: isPending("refrigerator_temperature"),
                                   isEnabled: fridge.isOnline) { HomeStore.shared.setFridge(.fridgeTemperature($0)) }
                TemperatureStepper(title: L("Congelador"), value: fridge.freezerTarget, actual: fridge.freezerActual,
                                   range: fridge.freezerRange, tint: DesignTokens.blue, isPending: isPending("freeze_temperature"),
                                   isEnabled: fridge.isOnline) { HomeStore.shared.setFridge(.freezerTemperature($0)) }
            }

            HStack(spacing: 6) {
                if fridge.supportsSuperCool {
                    ModeChip(title: L("Enfriamiento rápido"), symbol: "snowflake", isOn: fridge.superCool, tint: .cyan,
                             isPending: isPending("sr_mode"), isEnabled: fridge.isOnline) {
                        HomeStore.shared.setFridge(.superCool(!fridge.superCool))
                    }
                }
                if fridge.supportsSuperFreeze {
                    ModeChip(title: L("Super congelación"), symbol: "snowflake.circle.fill", isOn: fridge.superFreeze,
                             tint: DesignTokens.blue, isPending: isPending("sf_mode"), isEnabled: fridge.isOnline) {
                        HomeStore.shared.setFridge(.superFreeze(!fridge.superFreeze))
                    }
                }
                if fridge.supportsEco {
                    ModeChip(title: L("Eco"), symbol: "leaf.fill", isOn: fridge.eco, tint: DesignTokens.green,
                             isPending: isPending("save_mode"), isEnabled: fridge.isOnline) {
                        HomeStore.shared.setFridge(.eco(!fridge.eco))
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// − 4° + con lo que mide el sensor junto al título
private struct TemperatureStepper: View {
    let title: String
    let value: Int?
    let actual: Int?
    let range: ClosedRange<Int>
    let tint: Color
    let isPending: Bool
    let isEnabled: Bool
    var onChange: (Int) -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            stepButton("minus", enabled: (value ?? range.lowerBound) > range.lowerBound) { onChange(($0) - 1) }
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    if let actual {
                        Text(String(format: L("mide %d°"), actual))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(value.map { "\($0)°" } ?? "—")
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(tint)
                    .opacity(isPending ? 0.6 : 1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", enabled: (value ?? range.upperBound) < range.upperBound) { onChange(($0) + 1) }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping (Int) -> Void) -> some View {
        let active = enabled && isEnabled && value != nil
        return Button {
            guard let value, active else { return }
            appState.hapticService.triggerSnap()
            action(value)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(active ? 0.85 : 0.25))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(active ? 0.12 : 0.05)))
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.85))
        .disabled(!active)
    }
}

private struct ModeChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let tint: Color
    let isPending: Bool
    let isEnabled: Bool
    var action: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            appState.hapticService.triggerSnap()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isOn ? .black : .white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(isOn ? tint : Color.white.opacity(0.09)))
            .opacity(isPending ? 0.6 : 1)
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.92))
        .disabled(!isEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
    }
}

// MARK: - Control de la tele

/// Flechas y OK a la izquierda, atrás / inicio / reproducción al centro, volumen y encendido a la derecha, y abajo
/// las apps. Mientras está abierto pregunta a la tele cada 3 s qué tiene abierto y su volumen.
private struct TVRemoteCard: View {
    @ObservedObject private var tv = TVRemote.shared
    @EnvironmentObject var appState: AppState
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                dPad
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        key("arrow.uturn.backward", .back, help: L("Atrás"))
                        key("house", .home, help: L("Inicio"))
                    }
                    HStack(spacing: 5) {
                        key("backward.fill", .previous, help: L("Anterior"))
                        key("playpause.fill", .playPause, help: L("Reproducir o pausar"))
                        key("forward.fill", .next, help: L("Siguiente"))
                    }
                }
                Spacer(minLength: 0)
                volume
                powerButton
            }
            .frame(height: 64)

            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Image(systemName: "tv")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(L("Volver a Casa"))
                if let problem = tv.problem {
                    Text(problem)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(DesignTokens.orange)
                        .lineLimit(1)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(tv.installed) { app in
                                appChip(app)
                            }
                        }
                    }
                }
            }
            .frame(height: 22)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
        .task {
            while !Task.isCancelled {
                await tv.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var dPad: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08))
            VStack(spacing: 0) {
                arrow("chevron.up", .up)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left)
                    Button { send(.ok) } label: {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 24, height: 24)
                            .overlay(Text("OK").font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.85)))
                    }
                    .buttonStyle(BouncyButtonStyle(scaleAmount: 0.85))
                    arrow("chevron.right", .right)
                }
                arrow("chevron.down", .down)
            }
        }
        .frame(width: 64, height: 64)
    }

    private func arrow(_ symbol: String, _ key: TVRemote.Key) -> some View {
        Button { send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.8))
    }

    private func key(_ symbol: String, _ key: TVRemote.Key, help: String) -> some View {
        Button { send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.88))
        .help(help)
    }

    private var volume: some View {
        VStack(spacing: 3) {
            Button { send(.volumeUp) } label: { volumeIcon("plus") }
                .buttonStyle(BouncyButtonStyle(scaleAmount: 0.88))
            Button { send(.mute) } label: {
                Text(tv.volume.map { "\($0)" } ?? "—")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 30, height: 12)
            }
            .buttonStyle(.plain)
            .help(L("Silenciar"))
            Button { send(.volumeDown) } label: { volumeIcon("minus") }
                .buttonStyle(BouncyButtonStyle(scaleAmount: 0.88))
        }
    }

    private func volumeIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.white.opacity(0.85))
            .frame(width: 30, height: 22)
            .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private var powerButton: some View {
        let isOn = tv.isAwake ?? true
        return Button {
            appState.hapticService.triggerSnap()
            tv.togglePower()
        } label: {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isOn ? .white : .white.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(Circle().fill(isOn ? DesignTokens.red.opacity(0.75) : Color.white.opacity(0.12)))
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.88))
        .help(isOn ? L("Apagar la tele") : L("Prender la tele"))
    }

    private func appChip(_ app: TVRemote.App) -> some View {
        let isOpen = tv.currentPackage == app.package
        return Button {
            appState.hapticService.triggerSnap()
            tv.open(app)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(app.color).frame(width: 6, height: 6)
                Text(app.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isOpen ? .black : .white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOpen ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(BouncyButtonStyle(scaleAmount: 0.92))
    }

    private func send(_ key: TVRemote.Key) {
        appState.hapticService.triggerSnap()
        tv.press(key)
    }
}
