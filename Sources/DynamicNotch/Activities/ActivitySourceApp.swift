import AppKit

/// La app de la que viene una actividad y si el usuario ya la tiene a la vista.
public enum ActivitySourceApp {
    /// App que abre un clic en la bolita (como en el iPhone: tocar una actividad abre su app)
    public static func bundleId(for activity: LiveActivity) -> String? {
        switch activity.kind {
        case .claude: return "com.anthropic.claudefordesktop"
        case .timer: return "com.apple.clock"
        case .agentAI: return "com.google.antigravity"
        case .call: return "com.apple.FaceTime"
        default: return nil
        }
    }

    /// ¿La app tiene una ventana visible en el escritorio (Space) actual, en cualquier pantalla?
    /// Sólo cuenta lo que está en pantalla: las ventanas de otros escritorios no aparecen en la lista.
    public static func hasVisibleWindow(bundleId: String) -> Bool {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).map(\.processIdentifier))
        guard !pids.isEmpty else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.width > 120 && bounds.height > 120
        }
    }

    /// El usuario ya está viendo la app de esta actividad (una alerta no aportaría nada)
    public static func isVisible(for activity: LiveActivity) -> Bool {
        guard let bundleId = bundleId(for: activity) else { return false }
        return hasVisibleWindow(bundleId: bundleId)
    }
}
