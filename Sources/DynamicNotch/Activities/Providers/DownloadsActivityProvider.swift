import AppKit
import SwiftUI

/// Descargas en curso como una sola actividad (HIG: mejor una actividad que rota que varias): Safari y las
/// apps que publican su progreso (`NSProgress` de archivo) en la carpeta Descargas. Vive como bolita con el
/// anillo de progreso; al terminar muestra el anillo completo un momento y se reabsorbe.
public final class DownloadsActivityProvider {
    public static let shared = DownloadsActivityProvider()
    public static let activityId = "downloads"

    private struct Tracked {
        let progress: Progress
        let name: String
        var observation: NSKeyValueObservation?
    }

    private var subscriber: Any?
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var lastPublishedAt = Date.distantPast
    private var pendingPublish = false
    private var completedNames: [String] = []

    private init() {}

    public func start() {
        guard subscriber == nil,
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            DispatchQueue.main.async { self?.track(progress) }
            return { [weak self] in
                DispatchQueue.main.async { self?.untrack(progress) }
            }
        }
    }

    private func track(_ progress: Progress) {
        let key = ObjectIdentifier(progress)
        guard tracked[key] == nil else { return }
        let url = progress.fileURL ?? (progress.userInfo[.fileURLKey] as? URL)
        // Safari descarga a "archivo.ext.download": se muestra el nombre final
        let rawName = url?.lastPathComponent ?? "Descarga"
        let name = rawName.hasSuffix(".download") ? String(rawName.dropLast(".download".count)) : rawName
        var entry = Tracked(progress: progress, name: name)
        entry.observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.schedulePublish() }
        }
        tracked[key] = entry
        DNDLogger.log("Descargas: siguiendo '\(name)'")
        schedulePublish()
    }

    private func untrack(_ progress: Progress) {
        guard let entry = tracked.removeValue(forKey: ObjectIdentifier(progress)) else { return }
        entry.observation?.invalidate()
        if progress.fractionCompleted >= 0.999 || progress.isFinished {
            completedNames.append(entry.name)
        }
        if tracked.isEmpty {
            finish()
        } else {
            schedulePublish()
        }
    }

    /// Como mucho dos actualizaciones por segundo (el progreso de otro proceso llega muy seguido)
    private func schedulePublish() {
        guard !pendingPublish else { return }
        let wait = max(0, 0.5 - Date().timeIntervalSince(lastPublishedAt))
        pendingPublish = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self else { return }
            self.pendingPublish = false
            self.lastPublishedAt = Date()
            self.publishCurrent()
        }
    }

    private func publishCurrent() {
        guard AppState.shared.downloadsActivityEnabled, !tracked.isEmpty else { return }
        let entries = Array(tracked.values)
        let fraction = entries.map { min(1, max(0, $0.progress.fractionCompleted)) }.reduce(0, +) / Double(entries.count)
        let subtitle = entries.count == 1 ? entries[0].name : "\(entries.count) archivos"
        ActivityCenter.shared.publish(makeActivity(title: "Descargando", subtitle: subtitle, progress: fraction))
    }

    /// Terminaron todas: anillo completo como resumen y se va (ActivityCenter.end)
    private func finish() {
        let finishedAny = !completedNames.isEmpty
        let subtitle = completedNames.count == 1 ? completedNames[0] : "\(completedNames.count) archivos"
        completedNames.removeAll()
        guard ActivityCenter.shared.activeActivities.contains(where: { $0.id == Self.activityId }) else { return }
        if finishedAny {
            ActivityCenter.shared.end(id: Self.activityId,
                                      final: makeActivity(title: "Descargado", subtitle: subtitle, progress: 1),
                                      dismissAfter: 6)
        } else {
            // Cancelada: se va sin resumen
            ActivityCenter.shared.end(id: Self.activityId, dismissAfter: 0)
        }
    }

    private func makeActivity(title: String, subtitle: String, progress: Double) -> LiveActivity {
        let tint = DesignTokens.blue
        let done = progress >= 0.999
        var activity = LiveActivity(
            id: Self.activityId,
            kind: .download,
            priority: ActivityRelevance.backgroundTask,
            style: .pill,
            title: title,
            subtitle: subtitle,
            progress: progress,
            bolitaVariant: .progressRing(progress: progress, strokeColor: tint, iconName: done ? "checkmark" : "arrow.down"),
            tint: tint,
            onTap: {
                if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    NSWorkspace.shared.open(downloads)
                }
            }
        )
        activity.prefersBubble = true
        return activity
    }
}
