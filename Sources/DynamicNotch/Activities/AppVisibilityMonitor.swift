import AppKit
import Combine

/// ¿El usuario está viendo la app de una actividad? Como en el iPhone, la actividad de una app no sale en la
/// isla mientras esa app está a la vista (p. ej. la ventana de Claude abierta en el otro monitor).
///
/// "A la vista" = una ventana suya en pantalla (en el escritorio actual de cualquier monitor) con al menos un
/// cuarto de su área sin tapar por otras ventanas. Se revisa cada segundo fuera del hilo principal, y sólo
/// mientras haya actividades con app propia.
public final class AppVisibilityMonitor: ObservableObject {
    public static let shared = AppVisibilityMonitor()

    /// Apps (bundle id) que el usuario tiene a la vista
    @Published public private(set) var visibleBundleIds: Set<String> = []

    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.AppVisibility", qos: .utility)
    private var timer: Timer?
    private var watched: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    /// Lectura distinta de la publicada que espera confirmarse con la siguiente (evita parpadeos)
    private var pendingVisible: Set<String>?
    /// Último cambio de escritorio: lo que cambie por eso se muestra sin la animación líquida (ver ActivityCenter)
    public private(set) var lastSpaceChange: Date = .distantPast

    private init() {}

    /// Apps a vigilar (las de las actividades activas); sin ninguna, el monitor se detiene
    public func watch(_ bundleIds: Set<String>) {
        guard bundleIds != watched else { return }
        watched = bundleIds
        if bundleIds.isEmpty {
            timer?.invalidate()
            timer = nil
            // Al volver a vigilar se registran de nuevo: sin quitarlos se acumulaban y cada cambio de app
            // disparaba varias revisiones
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers.removeAll()
            if !visibleBundleIds.isEmpty { visibleBundleIds = [] }
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification,
                         NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    // El cambio de ventanas tarda un instante en reflejarse
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refresh() }
                })
            }
            // Cambio de escritorio: mientras dura la transición de macOS salen en pantalla ventanas de los dos
            // escritorios (la app podía "verse" un instante y la bolita se escondía y volvía a salir). Se revisa
            // cuando la transición ya terminó.
            observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lastSpaceChange = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self?.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        let targets = watched
        guard !targets.isEmpty, !SystemIdleState.isScreenUnavailable else { return }
        let pidsByBundle: [String: Set<pid_t>] = Dictionary(uniqueKeysWithValues: targets.map { id in
            (id, Set(NSRunningApplication.runningApplications(withBundleIdentifier: id).map(\.processIdentifier)))
        })
        queue.async { [weak self] in
            let visible = Self.visibleBundles(pidsByBundle: pidsByBundle)
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard visible != self.visibleBundleIds else {
                    self.pendingVisible = nil
                    return
                }
                // Un cambio cuenta sólo si dos lecturas seguidas coinciden: una ventana a medio animar (cambio de
                // escritorio, Mission Control, minimizar) no hace brincar la bolita
                if self.pendingVisible == visible {
                    self.pendingVisible = nil
                    self.visibleBundleIds = visible
                } else {
                    self.pendingVisible = visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
                }
            }
        }
    }

    /// Lista de ventanas de adelante hacia atrás: una ventana se ve si suficientes puntos de su área no caen
    /// dentro de alguna ventana normal que esté delante
    private static func visibleBundles(pidsByBundle: [String: Set<pid_t>]) -> Set<String> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var occluders: [CGRect] = []
        var visible: Set<String> = []
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 40, bounds.height > 40 else { continue }
            if let bundle = pidsByBundle.first(where: { $0.value.contains(pid) })?.key,
               !visible.contains(bundle), bounds.width > 120, bounds.height > 120,
               visibleFraction(of: bounds, under: occluders) >= 0.25 {
                visible.insert(bundle)
            }
            occluders.append(bounds)
        }
        return visible
    }

    /// Fracción de una rejilla de 12 × 8 puntos del rectángulo que no tapa ninguna ventana de delante
    static func visibleFraction(of rect: CGRect, under occluders: [CGRect]) -> Double {
        guard !occluders.isEmpty else { return 1 }
        let columns = 12, rows = 8
        var uncovered = 0
        for c in 0..<columns {
            for r in 0..<rows {
                let point = CGPoint(x: rect.minX + rect.width * (CGFloat(c) + 0.5) / CGFloat(columns),
                                    y: rect.minY + rect.height * (CGFloat(r) + 0.5) / CGFloat(rows))
                if !occluders.contains(where: { $0.contains(point) }) { uncovered += 1 }
            }
        }
        return Double(uncovered) / Double(columns * rows)
    }
}
