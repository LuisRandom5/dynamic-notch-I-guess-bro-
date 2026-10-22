import AppKit
import SwiftUI

// MARK: - Panel de la barra de menús
// Lo que sale al hacer clic en el icono de Dynamic Notch: un panel como los del Centro de Control, pegado a la barra,
// con los interruptores más usados en mosaicos y abajo los accesos (Ajustes, Permisos, Salir).

public final class StatusPanelController: NSObject {
    public static let shared = StatusPanelController()

    private var panel: NSPanel?
    private var monitors: [Any] = []
    /// Para no reabrirlo con el mismo clic que lo cerró (el clic en el icono también llega al monitor global)
    private var closedAt = Date.distantPast

    public var isOpen: Bool { panel?.isVisible ?? false }

    public func toggle(below anchor: NSRect) {
        if isOpen {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.25 {
            open(below: anchor)
        }
    }

    public func open(below anchor: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: StatusPanelView(close: { [weak self] in self?.close() }))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // Pegado a la barra (como el Centro de Control) y sin salirse de la pantalla
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = StatusPanelView.shadowMargin
        let x = min(max(anchor.minX - 10 - margin, visible.minX + 6 - margin), visible.maxX - size.width - 6 + margin)
        let y = visible.maxY - 5 - size.height + margin
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    public func close() {
        guard let panel, panel.isVisible else { return }
        closedAt = Date()
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Sin sombra de ventana (salía la del rectángulo en las esquinas): la dibuja la vista, con margen
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        // Clic fuera (en otra app o en el escritorio) cierra, como un menú
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(global) }
        // Escape cierra; un clic en otra ventana de la app también
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel {
                self.close()
            }
            return event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

/// Panel sin borde que sí recibe el teclado (Escape)
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Contenido

struct StatusPanelView: View {
    /// Margen transparente alrededor del panel para que quepa su sombra
    static let shadowMargin: CGFloat = 24
    let close: () -> Void
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var interceptor = VolumeInterceptorService.shared

    private var isOpen: Bool { appState.mode == .expanded || appState.mode == .shelf }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !interceptor.hasAccessibilityPermission {
                Button {
                    close()
                    WelcomeWindowController.showAlways()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Falta un permiso")).font(.system(size: 12.5, weight: .semibold))
                            Text(L("Sin Accesibilidad no salen el volumen ni el brillo."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(L("Arreglar")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    ToggleTile(icon: "speaker.wave.2.fill", title: "Volumen en la isla",
                               isOn: Binding(get: { interceptor.suppressNativeHUD }, set: { interceptor.suppressNativeHUD = $0 }))
                    ToggleTile(icon: "music.note", title: "Música junto al notch", isOn: $appState.showCompactWhenPlaying)
                }
                GridRow {
                    ToggleTile(icon: "cursorarrow.rays", title: "Abrir al acercar", isOn: $appState.expandOnHover)
                    ToggleTile(icon: "hand.tap.fill", title: "Vibración", isOn: Binding(
                        get: { appState.enableHaptics },
                        set: { appState.enableHaptics = $0; HapticService.shared.isEnabled = $0 }))
                }
            }

            ActionTile(icon: isOpen ? "chevron.up" : "chevron.down",
                       title: isOpen ? "Cerrar la isla" : "Abrir la isla") {
                close()
                if isOpen { appState.collapse() } else { appState.expand() }
            }

            if NSScreen.screens.count > 1 {
                HStack {
                    Text(L("La isla se ve en")).font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $appState.islandScreenPlacement) {
                        Text(L("El notch")).tag(SurfaceGeometry.ScreenPlacement.automatic)
                        Text(L("El monitor")).tag(SurfaceGeometry.ScreenPlacement.withoutNotch)
                        Text(L("Donde esté el puntero")).tag(SurfaceGeometry.ScreenPlacement.followCursor)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
            }

            VStack(spacing: 0) {
                PanelRow(icon: "gearshape", title: "Ajustes…") {
                    close()
                    SettingsWindowController.shared.show()
                }
                PanelRow(icon: "lock.shield", title: "Permisos…") {
                    close()
                    WelcomeWindowController.showAlways()
                }
                if BuildFlavor.isBeta {
                    PanelRow(icon: "envelope", title: "Enviar comentarios…") {
                        close()
                        FeedbackService.exportDiagnostics()
                    }
                }
                if BuildFlavor.hasDeveloperTools {
                    PanelRow(icon: "hammer", title: "Herramientas de desarrollo", trailing: "chevron.right") {
                        close()
                        let location = NSEvent.mouseLocation
                        DispatchQueue.main.async {
                            StatusItemManager.shared.developerMenu().popUp(positioning: nil, at: location, in: nil)
                        }
                    }
                }
                Divider().padding(.vertical, 4).padding(.horizontal, 8)
                PanelRow(icon: "power", title: "Salir de Dynamic Notch") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(PanelBackground())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(Self.shadowMargin)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("Dynamic Notch").font(.system(size: 13, weight: .semibold))
                Text(versionText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return L("Versión") + " " + version
    }
}

/// Mosaico redondo como los del Centro de Control: el círculo se pinta de azul cuando está encendido
private struct ToggleTile: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.12)))
                Text(L(title))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? L("Encendido") : L("Apagado"))
    }
}

private struct ActionTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
                Text(L(title)).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Fila de menú: se resalta al pasar el puntero, como en los menús de macOS
private struct PanelRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(hovering ? Color.white : Color.secondary)
                Text(L(title)).font(.system(size: 13))
                Spacer()
                if let trailing {
                    Image(systemName: trailing).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Fondo del panel: vidrio como el Centro de Control (macOS 26+) o material oscuro antes
private struct PanelBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .clipShape(shape)
                .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}
