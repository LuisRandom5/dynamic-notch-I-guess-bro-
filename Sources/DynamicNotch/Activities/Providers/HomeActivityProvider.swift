import SwiftUI

/// Avisos de la casa en la isla (los datos los trae HomeStore):
/// - Lavadora en un ciclo: bolita con el anillo de progreso y lo que le falta.
/// - Al terminar: "La ropa está lista" (con sonido); si en 15 min nadie abrió la puerta, lo recuerda una vez.
/// - Error de la lavadora, puerta del refri abierta, o el refri/congelador calientes por un rato.
/// Cada alerta también sale en la tele si está activado (TVNotifier).
@MainActor
public final class HomeActivityProvider: ObservableObject {
    public static let shared = HomeActivityProvider()
    public static let washerActivityId = "home_washer"
    public static let fridgeActivityId = "home_fridge"

    /// Cuánto esperar con la ropa adentro antes de recordarlo
    static let unloadReminderDelay: TimeInterval = 15 * 60
    /// Pasado esto se deja de esperar a que la saquen
    static let unloadGiveUp: TimeInterval = 2 * 60 * 60
    /// Refri ≥ 10 °C o congelador ≥ −8 °C durante este tiempo
    static let warmAlertDelay: TimeInterval = 15 * 60
    static let fridgeWarmLimit = 10
    static let freezerWarmLimit = -8

    @Published public var washerActivityEnabled: Bool = UserDefaults.standard.object(forKey: "homeWasherActivityEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(washerActivityEnabled, forKey: "homeWasherActivityEnabled")
            if !washerActivityEnabled { endWasher() }
        }
    }
    @Published public var fridgeAlertsEnabled: Bool = UserDefaults.standard.object(forKey: "homeFridgeAlertsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(fridgeAlertsEnabled, forKey: "homeFridgeAlertsEnabled")
            if !fridgeAlertsEnabled { endFridge() }
        }
    }

    /// Terminó y la ropa sigue adentro (para preguntar más seguido mientras tanto)
    private var finishedAt: Date?
    private var remindedUnload = false
    private var fridgeWarmSince: Date?
    private var freezerWarmSince: Date?
    private var alertedFridgeWarm = false
    private var fridgeShowing = false
    /// Desde cuándo se ve la puerta abierta (sin alarma todavía)
    private var doorOpenSince: Date?
    /// Puerta abierta este tiempo = como si pitara (el refri pita al minuto, más o menos)
    static let doorOpenAlertDelay: TimeInterval = 60

    /// HomeStore pregunta más seguido mientras hay algo que vigilar de cerca
    public var wantsFastPolling: Bool { finishedAt != nil }

    private init() {}

    func update(previous: HomeSnapshot, current: HomeSnapshot) {
        // Mientras se prueba un aviso simulado, los datos reales esperan (si no, lo taparían a los 30 s)
        guard simulationEndsAt.map({ Date() >= $0 }) ?? true else { return }
        updateWasher(previous: previous.washers.first, current: current.washers.first)
        updateFridge(current.fridges.first)
    }

    // MARK: - Lavadora

    private func updateWasher(previous: WasherStatus?, current: WasherStatus?) {
        guard washerActivityEnabled, let current else {
            if current == nil { endWasher() }
            return
        }
        let wasActive = previous?.isCycleActive ?? false

        if current.hasError && current.isOnline {
            if !(previous?.hasError ?? false) {
                publishWasher(current, headline: current.statusTitle, tint: DesignTokens.red, symbol: "exclamationmark.triangle.fill", alert: true)
            }
            return
        }

        if current.isCycleActive {
            finishedAt = nil
            remindedUnload = false
            publishWasher(current, headline: current.statusTitle, tint: DesignTokens.blue, symbol: current.phase.symbol, alert: false)
            return
        }

        // Acaba de terminar: el último dato decía que le faltaba poco (si lo cancelaron a la mitad, no se avisa)
        if wasActive, current.isOnline, let previous, current.phase == .finished || previous.remainingMinutes <= 5 {
            finishedAt = Date()
            remindedUnload = false
            DNDLogger.log("Casa: la lavadora terminó")
            publishFinished(current, alert: true)
            return
        }

        guard let finishedAt else {
            endWasher()
            return
        }
        let waited = Date().timeIntervalSince(finishedAt)
        if current.isDoorOpen || waited > Self.unloadGiveUp || !current.isOnline {
            // Ya la sacaron (o ya pasó mucho): el resumen se va solo
            self.finishedAt = nil
            ActivityCenter.shared.end(id: Self.washerActivityId, dismissAfter: current.isDoorOpen ? 4 : 0)
        } else if waited >= Self.unloadReminderDelay && !remindedUnload {
            remindedUnload = true
            DNDLogger.log("Casa: la ropa sigue adentro, recordando")
            publishFinished(current, alert: true, reminder: true)
        }
    }

    private func publishWasher(_ washer: WasherStatus, headline: String, tint: Color, symbol: String, alert: Bool) {
        let remaining = washer.remainingMinutes
        let detail = [washer.program, remaining > 0 ? Self.minutesText(remaining) : nil].compactMap { $0 }.joined(separator: " · ")
        let endTime = remaining > 0 ? Date().addingTimeInterval(TimeInterval(remaining * 60)) : nil
        var activity = LiveActivity(
            id: Self.washerActivityId,
            priority: alert ? ActivityRelevance.notification : ActivityRelevance.backgroundTask,
            style: .pill,
            title: headline,
            subtitle: detail.isEmpty ? washer.name : detail,
            progress: washer.progress,
            leading: AnyView(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            trailing: AnyView(
                Text(remaining > 0 ? Self.minutesText(remaining) : headline)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .fixedSize()
            ),
            bolitaVariant: .progressRing(progress: washer.progress, strokeColor: tint, iconName: symbol,
                                         shortText: remaining > 0 ? "\(remaining)" : nil),
            tint: tint,
            isUrgent: alert && washer.hasError,
            onTap: { AppState.shared.openWithMiniApp(.home) }
        )
        activity.expandedView = AnyView(
            IslandExpandedTemplate {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } trailing: {
                Text(remaining > 0 ? Self.minutesText(remaining) : "")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .fixedSize()
            } center: {
                VStack(spacing: 2) {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text([washer.program, washer.temperature, washer.spin].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            } bottom: {
                VStack(spacing: 5) {
                    ProgressView(value: washer.progress)
                        .progressViewStyle(.linear)
                        .tint(tint)
                    if let endTime {
                        Text(String(format: L("Termina a las %@"), endTime.formatted(date: .omitted, time: .shortened)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        )
        // Siempre bolita: la alerta la expande y regresa a bolita (como el calendario). Antes nacía en el notch y
        // a la siguiente consulta se volvía bolita: tres cambios de forma en un minuto
        activity.prefersBubble = true
        // Sin noticias en 6 min (tres consultas perdidas): se atenúa
        activity.staleDate = Date().addingTimeInterval(6 * 60)
        if alert {
            activity.alert = ActivityAlertConfiguration(sound: true)
            TVNotifier.shared.notify(.init(title: washer.name + ": " + headline,
                                           message: L("Revisa la pantalla de la lavadora"),
                                           symbol: "exclamationmark.triangle.fill", tint: DesignTokens.red))
        }
        ActivityCenter.shared.publish(activity)
    }

    private func publishFinished(_ washer: WasherStatus, alert: Bool, reminder: Bool = false) {
        let tint = DesignTokens.green
        let title = reminder ? L("La ropa sigue en la lavadora") : L("La ropa está lista")
        let subtitle = reminder ? L("Sácala para que no se arrugue") : (washer.program ?? washer.name)
        var activity = LiveActivity(
            id: Self.washerActivityId,
            priority: alert ? ActivityRelevance.notification : ActivityRelevance.backgroundTask,
            style: .pill,
            title: title,
            subtitle: subtitle,
            progress: 1,
            leading: AnyView(
                Image(systemName: "washer.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            trailing: AnyView(
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(tint)
            ),
            bolitaVariant: .progressRing(progress: 1, strokeColor: tint, iconName: "checkmark"),
            tint: tint,
            onTap: { AppState.shared.openWithMiniApp(.home) }
        )
        activity.expandedView = AnyView(
            IslandExpandedTemplate {
                Image(systemName: "washer.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } trailing: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } center: {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            } bottom: {
                EmptyView()
            }
        )
        // Bolita verde hasta que abran la puerta; la alerta la expande un momento
        activity.prefersBubble = true
        if alert {
            activity.alert = ActivityAlertConfiguration(sound: true)
            TVNotifier.shared.notify(.init(title: title, message: subtitle, symbol: "washer.fill", tint: DesignTokens.green))
        }
        ActivityCenter.shared.publish(activity)
    }

    private func endWasher() {
        finishedAt = nil
        guard ActivityCenter.shared.activeActivities.contains(where: { $0.id == Self.washerActivityId }) else { return }
        ActivityCenter.shared.end(id: Self.washerActivityId, dismissAfter: 0)
    }

    // MARK: - Refri

    private func updateFridge(_ fridge: FridgeStatus?) {
        guard fridgeAlertsEnabled, let fridge, fridge.isOnline else {
            endFridge()
            return
        }
        let now = Date()
        if let actual = fridge.fridgeActual, actual >= Self.fridgeWarmLimit {
            fridgeWarmSince = fridgeWarmSince ?? now
        } else {
            fridgeWarmSince = nil
        }
        if let actual = fridge.freezerActual, actual >= Self.freezerWarmLimit {
            freezerWarmSince = freezerWarmSince ?? now
        } else {
            freezerWarmSince = nil
        }
        let fridgeWarm = fridgeWarmSince.map { now.timeIntervalSince($0) >= Self.warmAlertDelay } ?? false
        let freezerWarm = freezerWarmSince.map { now.timeIntervalSince($0) >= Self.warmAlertDelay } ?? false
        if fridge.isDoorOpen {
            doorOpenSince = doorOpenSince ?? now
        } else {
            doorOpenSince = nil
        }
        // Pitando, o abierta en dos consultas seguidas con un minuto de diferencia
        let doorLeftOpen = fridge.isDoorAlarm
            || (doorOpenSince.map { now.timeIntervalSince($0) >= Self.doorOpenAlertDelay - 5 } ?? false)

        if doorLeftOpen {
            let freezerOnly = (fridge.isFreezerDoorAlarm || fridge.isFreezerDoorOpen)
                && !(fridge.isFridgeDoorAlarm || fridge.isFridgeDoorOpen)
            let title = freezerOnly
                ? L("La puerta del congelador está abierta")
                : L("La puerta del refri está abierta")
            publishFridge(title: title, subtitle: fridge.name, symbol: "door.left.hand.open", tint: DesignTokens.orange,
                          alert: !fridgeShowing)
        } else if fridgeWarm || freezerWarm {
            let title = freezerWarm && !fridgeWarm
                ? String(format: L("El congelador está a %d°"), fridge.freezerActual ?? 0)
                : String(format: L("El refri está a %d°"), fridge.fridgeActual ?? 0)
            publishFridge(title: title, subtitle: L("Revisa que la puerta cierre bien"), symbol: "thermometer.high",
                          tint: DesignTokens.red, alert: !alertedFridgeWarm)
            alertedFridgeWarm = true
        } else {
            alertedFridgeWarm = false
            endFridge()
        }
    }

    private func publishFridge(title: String, subtitle: String, symbol: String, tint: Color, alert: Bool) {
        fridgeShowing = true
        var activity = LiveActivity(
            id: Self.fridgeActivityId,
            priority: ActivityRelevance.notification,
            style: .pill,
            title: title,
            subtitle: subtitle,
            leading: AnyView(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            trailing: AnyView(
                Image(systemName: "refrigerator.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            bolitaVariant: .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: "refrigerator.fill"),
            tint: tint,
            onTap: {
                HomeStore.shared.showsFridgeControls = true
                AppState.shared.openWithMiniApp(.home)
            }
        )
        activity.expandedView = AnyView(
            IslandExpandedTemplate {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } trailing: {
                Image(systemName: "refrigerator.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } center: {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            } bottom: {
                EmptyView()
            }
        )
        activity.prefersBubble = true
        if alert {
            activity.alert = ActivityAlertConfiguration(sound: true)
            let isWarm = symbol == "thermometer.high"
            TVNotifier.shared.notify(.init(title: title,
                                           message: isWarm ? subtitle : L("Ciérrala para que no se pierda el frío"),
                                           symbol: isWarm ? "thermometer.high" : "refrigerator.fill", tint: tint))
        }
        ActivityCenter.shared.publish(activity)
    }

    private func endFridge() {
        guard fridgeShowing else { return }
        fridgeShowing = false
        ActivityCenter.shared.end(id: Self.fridgeActivityId, dismissAfter: 0)
    }

    // MARK: - Pruebas (panel de pruebas y testHomeFridgeDoor)

    /// Cada aviso de Casa, para verlo sin esperar a que pase de verdad
    public enum Simulation: String, CaseIterable, Identifiable {
        case washing, finished, reminder, error, fridgeDoor, fridgeWarm
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .washing: return "Lavando (bolita)"
            case .finished: return "La ropa está lista"
            case .reminder: return "La ropa sigue adentro"
            case .error: return "Error de la lavadora"
            case .fridgeDoor: return "Puerta del refri abierta"
            case .fridgeWarm: return "Refri caliente"
            }
        }
        public var symbol: String {
            switch self {
            case .washing: return "washer.fill"
            case .finished, .reminder: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .fridgeDoor: return "door.left.hand.open"
            case .fridgeWarm: return "thermometer.high"
            }
        }
    }

    /// Hasta cuándo manda la simulación sobre los datos reales
    private var simulationEndsAt: Date?
    static let simulationDuration: TimeInterval = 45

    private static func sampleWasher(_ status: [String: String] = [:]) -> WasherStatus {
        WasherStatus(name: L("Lavadora"), model: "", isOnline: true, status: [
            "machine_status": "2", "Current_program_phase": "4", "Selected_program_ID": "7",
            "Selected_program_remaining_time_in_minutes": "24", "Selected_program_total_time_in_minutes": "130",
            "temperature": "4", "Spin_speed_rpm": "10", "Door_status": "3", "error_code": "0",
        ].merging(status) { _, new in new })
    }

    /// Muestra el aviso en la isla y, si está activado, en la tele. A los 45 s regresa lo real.
    public func simulate(_ simulation: Simulation) {
        simulationEndsAt = Date().addingTimeInterval(Self.simulationDuration)
        // Que cada toque se vea expandido (normalmente hay 30 s entre alertas de la misma actividad)
        ActivityCenter.shared.lastAlertAt[Self.washerActivityId] = nil
        ActivityCenter.shared.lastAlertAt[Self.fridgeActivityId] = nil
        switch simulation {
        case .washing:
            let washer = Self.sampleWasher()
            publishWasher(washer, headline: washer.statusTitle, tint: DesignTokens.blue, symbol: washer.phase.symbol, alert: false)
        case .finished:
            finishedAt = Date()
            publishFinished(Self.sampleWasher(["Current_program_phase": "10", "machine_status": "1"]), alert: true)
        case .reminder:
            finishedAt = Date().addingTimeInterval(-Self.unloadReminderDelay)
            publishFinished(Self.sampleWasher(["Current_program_phase": "10", "machine_status": "1"]), alert: true, reminder: true)
        case .error:
            let washer = Self.sampleWasher(["error_code": "5", "machine_status": "4"])
            publishWasher(washer, headline: washer.statusTitle, tint: DesignTokens.red, symbol: "exclamationmark.triangle.fill", alert: true)
        case .fridgeDoor:
            fridgeShowing = false
            updateFridge(FridgeStatus(name: L("Refri"), model: "", isOnline: true,
                                      status: ["refr_room_open": "1", "open_the_door_alarm": "1"]))
        case .fridgeWarm:
            fridgeShowing = false
            alertedFridgeWarm = false
            fridgeWarmSince = Date().addingTimeInterval(-Self.warmAlertDelay)
            updateFridge(FridgeStatus(name: L("Refri"), model: "", isOnline: true,
                                      status: ["refrigerator_temperature": "4", "refrigerator_real_temperature": "11"]))
        }
        let ends = simulationEndsAt
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.simulationDuration) { [weak self] in
            guard let self, self.simulationEndsAt == ends else { return }
            self.endSimulation()
        }
    }

    /// Quita lo simulado y vuelve a mostrar lo real
    public func endSimulation() {
        simulationEndsAt = nil
        finishedAt = nil
        fridgeWarmSince = nil
        endWasher()
        endFridge()
        update(previous: HomeSnapshot(), current: HomeStore.shared.snapshot)
    }

    /// El aviso de la tele de cada prueba (sin tocar la isla)
    public static func tvNotice(for simulation: Simulation) -> TVNotifier.Notice {
        switch simulation {
        case .washing:
            return .init(title: L("Lavando"), message: L("Algodón · faltan 24 min"), symbol: "washer.fill", tint: DesignTokens.blue)
        case .finished:
            return .init(title: L("La ropa está lista"), message: L("Algodón"), symbol: "washer.fill", tint: DesignTokens.green)
        case .reminder:
            return .init(title: L("La ropa sigue en la lavadora"), message: L("Sácala para que no se arrugue"),
                         symbol: "washer.fill", tint: DesignTokens.green)
        case .error:
            return .init(title: L("Lavadora: Error F05"), message: L("Revisa la pantalla de la lavadora"),
                         symbol: "exclamationmark.triangle.fill", tint: DesignTokens.red)
        case .fridgeDoor:
            return .init(title: L("La puerta del refri está abierta"), message: L("Ciérrala para que no se pierda el frío"),
                         symbol: "refrigerator.fill", tint: DesignTokens.orange)
        case .fridgeWarm:
            return .init(title: String(format: L("El refri está a %d°"), 11), message: L("Revisa que la puerta cierre bien"),
                         symbol: "thermometer.high", tint: DesignTokens.red)
        }
    }

    static func minutesText(_ minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d h %02d min", minutes / 60, minutes % 60) : "\(minutes) min"
    }
}
