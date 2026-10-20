import AppKit
import EventKit
import SwiftUI

/// Próxima reunión, como las actividades del iPhone: desde 5 min antes hasta 5 min después de que empiece, una
/// bolita con la cuenta regresiva; al entrar a los 5 min se expande un momento. Clic = unirse (si el evento trae
/// un enlace de Zoom, Meet, Teams, Webex o FaceTime) o abrir Calendario.
///
/// Apagado por defecto: el permiso de Calendario se pide sólo al encenderlo en Ajustes.
public final class CalendarActivityProvider {
    public static let shared = CalendarActivityProvider()
    public static let activityId = "calendar_next_meeting"

    /// Cuánto antes del inicio aparece y cuánto después se va
    private static let leadTime: TimeInterval = 5 * 60
    private static let trailTime: TimeInterval = 5 * 60

    private let store = EKEventStore()
    private var timer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var shownEventKey: String?
    private var alertedEventKeys: Set<String> = []

    private init() {}

    public static var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status.rawValue == 3 // .authorized antes de macOS 14
    }

    /// Al arrancar la app: sólo si el ajuste está encendido y ya hay permiso (nunca pide permiso solo)
    public func start() {
        guard AppState.shared.calendarActivityEnabled, Self.isAuthorized else { return }
        beginMonitoring()
    }

    /// Desde Ajustes: al encender pide el permiso (una vez); si se niega, el ajuste se apaga
    public func setEnabled(_ enabled: Bool) {
        guard enabled else {
            stop()
            return
        }
        if Self.isAuthorized {
            beginMonitoring()
            return
        }
        let completion: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self?.beginMonitoring()
                } else {
                    DNDLogger.log("Calendario: permiso negado; se apaga \"Próxima reunión\"")
                    AppState.shared.calendarActivityEnabled = false
                }
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    private func beginMonitoring() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        if shownEventKey != nil { ActivityCenter.shared.end(id: Self.activityId, dismissAfter: 0) }
        shownEventKey = nil
    }

    private func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-Self.trailTime - 4 * 3600),
            end: now.addingTimeInterval(Self.leadTime),
            calendars: nil
        )
        let candidate = store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.status != .canceled, !Self.isDeclined(event) else { return false }
                let untilStart = event.startDate.timeIntervalSince(now)
                return untilStart <= Self.leadTime && untilStart >= -Self.trailTime
            }
            .min { $0.startDate < $1.startDate }

        guard let event = candidate else {
            if shownEventKey != nil {
                shownEventKey = nil
                ActivityCenter.shared.end(id: Self.activityId, dismissAfter: 0)
            }
            return
        }
        let key = "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
        let isNew = key != shownEventKey
        shownEventKey = key
        publish(event, key: key, alert: isNew && !alertedEventKeys.contains(key))
        if isNew { alertedEventKeys.insert(key) }
        if alertedEventKeys.count > 50 { alertedEventKeys.removeAll() }
    }

    private func publish(_ event: EKEvent, key: String, alert: Bool) {
        let tint = event.calendar.map { Color(nsColor: $0.color) } ?? DesignTokens.blue
        let meetingURL = Self.meetingURL(in: event)
        let service = meetingURL.flatMap(Self.serviceName(for:))
        let title = event.title?.isEmpty == false ? event.title! : L("Reunión")
        let subtitle = [service.map { String(format: L("Unirse con %@"), $0) }, event.location?.isEmpty == false && meetingURL == nil ? event.location : nil]
            .compactMap { $0 }
            .first ?? L("Próxima reunión")

        var activity = LiveActivity(
            id: Self.activityId,
            priority: ActivityRelevance.backgroundTask,
            style: .pill,
            title: title,
            subtitle: subtitle,
            leading: AnyView(
                Image(systemName: meetingURL == nil ? "calendar" : "video.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            ),
            // Cuenta regresiva hasta el inicio (y luego el tiempo transcurrido)
            trailing: AnyView(
                Text(event.startDate, style: .timer)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(tint)
                    .fixedSize()
            ),
            bolitaVariant: .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: meetingURL == nil ? "calendar" : "video.fill"),
            tint: tint,
            onTap: {
                if let meetingURL {
                    NSWorkspace.shared.open(meetingURL)
                } else if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                    NSWorkspace.shared.openApplication(at: calendar, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        )
        let open = activity.onTap ?? {}
        activity.expandedView = AnyView(
            IslandExpandedTemplate {
                Image(systemName: meetingURL == nil ? "calendar" : "video.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
            } trailing: {
                Text(event.startDate, style: .timer)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .fixedSize()
            } center: {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(event.startDate > Date() ? String(format: L("Empieza a las %@"), event.startDate.formatted(date: .omitted, time: .shortened)) : L("Ya empezó"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            } bottom: {
                Button(action: open) {
                    Text(service.map { String(format: L("Unirse con %@"), $0) } ?? L("Abrir Calendario"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(ContainerRelativeShape().fill(tint.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }
        )
        activity.prefersBubble = true
        if alert { activity.alert = ActivityAlertConfiguration(sound: false) }
        ActivityCenter.shared.publish(activity)
    }

    /// Prueba (dnpost testMeeting): una reunión de ejemplo en 4 min, sin leer ni guardar nada en Calendario
    public func showSample() {
        let event = EKEvent(eventStore: store)
        event.title = "Revisión de diseño"
        event.startDate = Date().addingTimeInterval(4 * 60)
        event.endDate = event.startDate.addingTimeInterval(30 * 60)
        event.notes = "https://meet.google.com/abc-defg-hij"
        publish(event, key: "sample", alert: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            ActivityCenter.shared.end(id: Self.activityId, dismissAfter: 0)
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    /// Enlace de videollamada en la URL, la ubicación o las notas del evento
    static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, serviceName(for: url) != nil { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        return meetingURL(inText: text)
    }

    static func meetingURL(inText text: String) -> URL? {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first { serviceName(for: $0) != nil }
    }

    static func serviceName(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("zoom.us") { return "Zoom" }
        if host == "meet.google.com" { return "Meet" }
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") { return "Teams" }
        if host.hasSuffix("webex.com") { return "Webex" }
        if host == "facetime.apple.com" { return "FaceTime" }
        return nil
    }
}
