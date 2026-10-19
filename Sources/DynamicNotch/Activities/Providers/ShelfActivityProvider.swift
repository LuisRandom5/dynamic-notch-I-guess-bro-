import SwiftUI
import Combine

/// La repisa con archivos se muestra como una bolita satélite (icono de bandeja azul + cantidad), igual que
/// las demás actividades en vivo, en lugar de ensanchar el notch con un contador dentro de las alas.
/// Al tocarla se abre la repisa; mientras la repisa está abierta la bolita se oculta.
public final class ShelfActivityProvider {
    public static let shared = ShelfActivityProvider()
    public static let activityId = "shelf_items"
    public static let blue = DesignTokens.blue

    private var cancellable: AnyCancellable?
    private var lastCount = -1

    private init() {}

    public func start() {
        guard cancellable == nil else { return }
        cancellable = Publishers.CombineLatest(AppState.shared.$shelfItems, AppState.shared.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items, mode in
                self?.update(count: items.count, isShelfOpen: mode == .shelf)
            }
    }

    private var wasShelfOpen = false
    private var pendingPublish: DispatchWorkItem?

    private func update(count: Int, isShelfOpen: Bool) {
        let justClosed = wasShelfOpen && !isShelfOpen
        wasShelfOpen = isShelfOpen
        let visibleCount = isShelfOpen ? 0 : count
        guard visibleCount != lastCount else { return }
        lastCount = visibleCount
        pendingPublish?.cancel()
        pendingPublish = nil

        // Al cerrar la repisa, la bolita espera a que el notch termine de recogerse: si brota de un notch que
        // todavía se está encogiendo, el cuello y la gota se ven cortados
        if justClosed && visibleCount > 0 {
            let work = DispatchWorkItem { [weak self] in self?.publish(count: visibleCount) }
            pendingPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            return
        }
        publish(count: visibleCount)
    }

    private func publish(count visibleCount: Int) {
        pendingPublish = nil

        guard visibleCount > 0 else {
            ActivityCenter.shared.remove(id: Self.activityId)
            return
        }
        let activity = LiveActivity(
            id: Self.activityId,
            kind: .generic,
            priority: ActivityRelevance.shelf, // la más discreta: nunca desplaza a otra bolita
            style: .pill,
            title: visibleCount == 1 ? "1 archivo en la repisa" : "\(visibleCount) archivos en la repisa",
            bolitaVariant: .color(bgColor: .black, fgColor: Self.blue, iconName: "tray.full.fill", shortText: "\(visibleCount)"),
            tint: Self.blue,
            duration: nil,
            onTap: { [weak self] in
                // Primero la gota se reabsorbe en el notch (acelera hacia él y la cápsula se abulta); la repisa
                // se abre justo cuando llega, para que la bolita nunca quede encima de la repisa abierta
                self?.lastCount = 0
                ActivityCenter.shared.remove(id: Self.activityId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                        AppState.shared.activeTab = .shelf
                        AppState.shared.mode = .shelf
                    }
                }
            }
        )
        ActivityCenter.shared.publish(activity)
    }
}
