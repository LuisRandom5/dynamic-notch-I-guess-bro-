import AppKit
import SwiftUI

// MARK: - Banco de pruebas
// Cada aviso y actividad de la isla a un clic, ordenados como Ajustes: barra lateral por tema y tarjetas con su
// icono, su nombre y una línea de qué hace. Sólo en la compilación de desarrollo; se abre desde el menú de la barra.
// El panel viejo (vidrio, capas, modos de presentación) sigue en "Herramientas".
public final class TestBenchWindow {
    public static let shared = TestBenchWindow()
    private var window: NSWindow?

    private init() {}

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Banco de pruebas"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TestBenchView().environmentObject(AppState.shared))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum BenchCategory: String, CaseIterable, Identifiable {
    case notices = "Avisos"
    case system = "Batería y sistema"
    case home = "Casa y tele"
    case activities = "Actividades"
    case music = "Música"
    case airpods = "AirPods"
    case tools = "Herramientas"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notices: return "bell.badge.fill"
        case .system: return "battery.75percent"
        case .home: return "house.fill"
        case .activities: return "circle.grid.2x1.fill"
        case .music: return "music.note"
        case .airpods: return "airpods"
        case .tools: return "hammer.fill"
        }
    }

    var color: Color {
        switch self {
        case .notices: return .red
        case .system: return .green
        case .home: return .teal
        case .activities: return .purple
        case .music: return .pink
        case .airpods: return Color(white: 0.45)
        case .tools: return .brown
        }
    }

    var blurb: String {
        switch self {
        case .notices: return "Mensajes, llamadas, reuniones y AirDrop, como llegarían de verdad."
        case .system: return "Carga, batería y los HUD de volumen y brillo."
        case .home: return "Cada aviso de la lavadora y el refri, en la isla y en la tele. Mientras dura (45 s) se ignoran los datos reales."
        case .activities: return "Temporizadores, agentes y varias actividades a la vez para ver las bolitas."
        case .music: return "Una canción de ejemplo y el canvas a pantalla completa."
        case .airpods: return "La animación al conectarlos y cada modelo y color oficial."
        case .tools: return "Ventanas de diagnóstico: vidrio y capas, bolitas, espectro y arrastre."
        }
    }
}

private struct BenchItem: Identifiable {
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let action: () -> Void
    var id: String { title }
}

struct TestBenchView: View {
    @State private var category: BenchCategory = .notices

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(category)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(BenchCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.color.gradient))
                        Text(item.rawValue)
                            .font(.system(size: 13))
                            .foregroundStyle(item == category ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(item == category ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                Self.dismissAll()
            } label: {
                Label("Quitar todo de la isla", systemImage: "xmark.circle")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 40)
        .padding(.bottom, 12)
        .frame(width: 210)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(category.color.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(category.rawValue)
                    .font(.system(size: 22, weight: .bold))
                Text(category.blurb)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .notices: grid(Self.notices)
        case .system: grid(Self.system)
        case .home: HomeBenchSection()
        case .activities: grid(Self.activities)
        case .music: grid(Self.music)
        case .airpods:
            grid(Self.airpods)
            AirPodsAnimationTestBench()
        case .tools: grid(Self.tools)
        }
    }

    fileprivate func grid(_ items: [BenchItem], title: String? = nil) -> some View {
        BenchGrid(items: items, title: title)
    }

    // MARK: - Pruebas

    private static let notices: [BenchItem] = [
        BenchItem(title: "WhatsApp", detail: "Mensaje con respuesta rápida", icon: "message.fill", color: .green) {
            WhatsAppWebObserverService.shared.simulateTestNotification()
        },
        BenchItem(title: "Foto", detail: "WhatsApp con una foto", icon: "photo.fill", color: .green) {
            WhatsAppWebObserverService.shared.simulateTestNotification(message: WhatsAppMessagePreview.describe("Foto"))
        },
        BenchItem(title: "Otro contacto", detail: "Para ver la cola de mensajes", icon: "person.2.fill", color: .green) {
            WhatsAppWebObserverService.shared.simulateTestNotification(sender: "Ana", message: "¿Ya viste lo que te mandé?")
        },
        BenchItem(title: "iMessage", detail: "Mensaje de la app Mensajes", icon: "bubble.left.fill", color: .blue) {
            MessagesObserverService.shared.simulateTestNotification()
        },
        BenchItem(title: "Llamada entrante", detail: "FaceTime de Mamá", icon: "phone.arrow.down.left.fill", color: .green) {
            CallActivityProvider.shared.startIncomingCall(name: "FaceTime Audio", handle: "Mamá", isSimulation: true)
        },
        BenchItem(title: "Llamada en curso", detail: "Con su contador en la isla", icon: "phone.fill", color: .green) {
            CallActivityProvider.shared.startCall(name: "FaceTime Audio", handle: "Mamá", asCard: false, isSimulation: true)
        },
        BenchItem(title: "Colgar", detail: "Termina la llamada simulada", icon: "phone.down.fill", color: .red) {
            CallActivityProvider.shared.endCall()
        },
        BenchItem(title: "Próxima reunión", detail: "En 4 minutos, con botón para unirse", icon: "video.fill", color: .blue) {
            CalendarActivityProvider.shared.showSample()
        },
        BenchItem(title: "Concentración", detail: "Se activa No molestar", icon: "moon.fill", color: .indigo) {
            SystemStatusActivityProvider.shared.simulateFocusChange(on: true)
        },
        BenchItem(title: "AirDrop", detail: "Transferencia con su progreso", icon: "airplayaudio", color: .blue) {
            AirDropActivityProvider.shared.startSimulatedTransfer()
        },
    ]

    private static let system: [BenchItem] = [
        BenchItem(title: "Cargando", detail: "Al 83 %, como el iPhone", icon: "bolt.fill", color: .green) {
            ChargingActivityProvider.shared.publishChargingActivity(percentage: 83, isLowPower: false, isPluggedIn: true)
        },
        BenchItem(title: "Carga completa", detail: "Al llegar al 100 %", icon: "battery.100percent.bolt", color: .green) {
            ChargingActivityProvider.shared.publishFullyChargedActivity()
        },
        BenchItem(title: "Batería baja", detail: "Al 10 %, con el relleno rojo", icon: "battery.25percent", color: .red) {
            ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: 10)
        },
        BenchItem(title: "Volumen", detail: "HUD al 65 %", icon: "speaker.wave.2.fill", color: .gray) {
            AudioDeviceService.shared.publishVolumeActivity(volume: 0.65, isMuted: false)
        },
        BenchItem(title: "Silencio", detail: "HUD silenciado", icon: "speaker.slash.fill", color: .gray) {
            AudioDeviceService.shared.publishVolumeActivity(volume: 0.65, isMuted: true)
        },
        BenchItem(title: "Brillo", detail: "HUD al 80 %", icon: "sun.max.fill", color: .yellow) {
            BrightnessService.shared.publishBrightnessActivity(0.80)
        },
    ]

    private static let activities: [BenchItem] = [
        BenchItem(title: "Temporizador", detail: "15 minutos, como bolita", icon: "timer", color: .orange) {
            ActivityDebugView().launchTimerActivity()
        },
        BenchItem(title: "Temporizador urgente", detail: "1 minuto, como tarjeta", icon: "alarm.fill", color: .orange) {
            ActivityDebugView().launchTimerActivity(isUrgent: true)
        },
        BenchItem(title: "Claude trabajando", detail: "Progreso de un agente", icon: "sparkles", color: .purple) {
            AgentActivityProvider.shared.showProgress(payload: AgentLiveProgressPayload())
        },
        BenchItem(title: "Agente pide permiso", detail: "Pregunta antes de un comando", icon: "hand.raised.fill", color: .purple) {
            AgentActivityProvider.shared.showInteraction(
                type: .permission, title: "Antigravity", subtitle: "Permiso requerido",
                message: "¿Deseas ejecutar el siguiente comando en la terminal?", command: "git push origin main")
        },
        BenchItem(title: "Agente de ejemplo", detail: "Actividad de IA simulada", icon: "wand.and.stars", color: .purple) {
            ActivityDebugView().launchAIActivity()
        },
        BenchItem(title: "Llamada (actividad)", detail: "Píldora verde de ejemplo", icon: "phone.circle.fill", color: .green) {
            ActivityDebugView().launchCallActivity()
        },
        BenchItem(title: "Grabación", detail: "Píldora roja de ejemplo", icon: "record.circle", color: .red) {
            ActivityDebugView().launchRecordingActivity()
        },
        BenchItem(title: "VPN", detail: "Píldora azul de ejemplo", icon: "network.badge.shield.half.filled", color: .blue) {
            ActivityDebugView().launchVPNActivity()
        },
        BenchItem(title: "Cinco a la vez", detail: "Para ver el carrusel y las bolitas", icon: "square.stack.3d.up.fill", color: .indigo) {
            ActivityDebugView().launchAllFiveActivities()
        },
    ]

    private static let music: [BenchItem] = [
        BenchItem(title: "Canción de ejemplo", detail: "Starboy, sin sonido", icon: "music.note", color: .pink) {
            MusicService.shared.setDemoTrack(MusicTrack(
                title: "Starboy", artist: "The Weeknd ft. Daft Punk", album: "Starboy", artwork: nil,
                isPlaying: true, playbackPosition: 14, duration: 230, appSource: "Simulado"))
        },
        BenchItem(title: "Canvas", detail: "La música a pantalla completa", icon: "rectangle.inset.filled", color: .pink) {
            AmbientCanvasWindowManager.shared.toggleCanvas()
        },
        BenchItem(title: "Pantalla bloqueada", detail: "Bloquea en 4 s para ver el reproductor", icon: "lock.fill", color: .teal) {
            LockScreenManager.shared.startCountdownAndArmLockScreenTest(seconds: 4)
        },
    ]

    private static let airpods: [BenchItem] = [
        BenchItem(title: "Conectar AirPods", detail: "La animación con tus AirPods (o unos Pro)", icon: "airpods", color: .gray) {
            let details = BluetoothAudioService.shared.queryConnectedAirPods()
            AirPodsActivityProvider.shared.publishAirPodsActivity(
                name: details?.deviceName ?? "AirPods Pro",
                batteryLevel: details?.primaryBattery ?? 100,
                leftPercent: details?.leftBattery ?? 100,
                rightPercent: details?.rightBattery ?? 100,
                casePercent: details?.caseBattery ?? 100,
                duration: 13.0)
        },
    ]

    private static let tools: [BenchItem] = [
        BenchItem(title: "Vidrio y capas", detail: "El panel avanzado de antes", icon: "square.3.layers.3d", color: .blue) {
            ActivityDebugWindow.shared.show()
        },
        BenchItem(title: "Animation Studio", detail: "Las bolitas cuadro por cuadro", icon: "film.stack", color: .orange) {
            AnimationStudioWindow.shared.show()
        },
        BenchItem(title: "Espectro FFT", detail: "Calibrar las barras de la música", icon: "waveform", color: .pink) {
            AudioSpectrumTestWindowController.shared.show()
        },
        BenchItem(title: "Arrastrar archivos", detail: "Sonda de drag & drop", icon: "hand.draw.fill", color: .cyan) {
            DragProbeDebugWindowController.shared.toggleWindow()
        },
    ]

    static func dismissAll() {
        let center = ActivityCenter.shared
        center.collapseExpandedActivity()
        TimerActivityProvider.shared.cancelTimer()
        AgentActivityProvider.shared.dismissProgress()
        CallActivityProvider.shared.endCall()
        HomeActivityProvider.shared.endSimulation()
        for activity in center.activeActivities where !activity.id.hasPrefix("home_") {
            center.remove(id: activity.id)
        }
    }
}

// MARK: - Piezas

private struct BenchGrid: View {
    let items: [BenchItem]
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10)], spacing: 10) {
                ForEach(items) { BenchTile(item: $0) }
            }
        }
    }
}

private struct BenchTile: View {
    let item: BenchItem
    @State private var isHovered = false
    @State private var flash = false

    var body: some View {
        Button {
            item.action()
            withAnimation(.easeOut(duration: 0.12)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.3)) { flash = false }
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(item.color.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(flash ? item.color.opacity(0.25)
                          : Color(NSColor.controlBackgroundColor).opacity(isHovered ? 1 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered ? 0.14 : 0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.detail)
    }
}

/// Casa: cada aviso en la isla (y en la tele si está activada) y cada tarjeta sólo en la tele
private struct HomeBenchSection: View {
    @ObservedObject private var tv = TVNotifier.shared
    @EnvironmentObject var appState: AppState

    private func color(_ simulation: HomeActivityProvider.Simulation) -> Color {
        switch simulation {
        case .washing: return .blue
        case .finished, .reminder: return .green
        case .error, .fridgeWarm: return .red
        case .fridgeDoor: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BenchGrid(items: HomeActivityProvider.Simulation.allCases.map { simulation in
                BenchItem(title: simulation.title, detail: tv.isReady ? "En la isla y en la tele" : "En la isla",
                          icon: simulation.symbol, color: color(simulation)) {
                    HomeActivityProvider.shared.simulate(simulation)
                }
            }, title: "Avisos")

            BenchGrid(items: [
                BenchItem(title: "Abrir Casa", detail: "La mini app en la isla", icon: "house.fill", color: .teal) {
                    HomeStore.shared.showsFridgeControls = false
                    appState.openWithMiniApp(.home)
                },
                BenchItem(title: "Volver a lo real", detail: "Quita lo simulado", icon: "arrow.uturn.backward", color: .gray) {
                    HomeActivityProvider.shared.endSimulation()
                },
            ])

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sólo en la tele")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $tv.corner) {
                        ForEach(TVNotifier.Corner.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if tv.isReady {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10)], spacing: 10) {
                        ForEach(HomeActivityProvider.Simulation.allCases) { simulation in
                            BenchTile(item: BenchItem(title: simulation.title, detail: tv.tvName ?? "Tele",
                                                      icon: "tv", color: color(simulation)) {
                                TVNotifier.shared.notify(HomeActivityProvider.tvNotice(for: simulation))
                            })
                        }
                    }
                    if let result = tv.lastResult {
                        Text(result)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Activa los avisos en la tele en Ajustes › Casa.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
