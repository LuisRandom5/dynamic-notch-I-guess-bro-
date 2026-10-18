import SwiftUI
import AppKit
import Combine

// MARK: - Animation Studio (versión ligera)
//
// Herramienta de diseño para el morfeo líquido de las bolitas:
// - Escenario con la animación REAL (LiquidSatelliteModifier + LiquidContour) ampliada.
// - Línea de tiempo propia: el resorte se simula paso a paso, así que se puede reproducir, pausar, cambiar
//   la velocidad (hasta 0.1×), avanzar cuadro a cuadro y arrastrar a cualquier instante.
// - Parámetros en vivo (LiquidMotionTuning): son los mismos que lee la animación de la app.
// - Vista de geometría: contorno sin material, formas del extremo del notch y de la gota, y fase activa.
// Abrir: menú de la barra → "Animation Studio", o POST 127.0.0.1:48123/debug/studio.

public final class AnimationStudioWindow {
    public static let shared = AnimationStudioWindow()
    private var window: NSWindow?

    public func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Animation Studio · Bolitas"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AnimationStudioView())
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Captura de la propia ventana (dibujada por la app, sin grabación de pantalla) para revisar el Studio
    public func snapshot(to path: String = "/tmp/dn_studio.png") {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Integrador de resorte con reloj propio (pausable y con velocidad variable)
final class StudioPlayback: ObservableObject {
    enum Direction { case emerge, absorb }

    @Published var raw: CGFloat = 1
    @Published var isPlaying = false
    @Published var speed: Double = 0.25
    @Published var direction: Direction = .emerge
    @Published var elapsed: Double = 0

    private var velocity: CGFloat = 0
    private var timer: AnyCancellable?
    private var lastTick: CFTimeInterval = 0

    func play(_ direction: Direction) {
        self.direction = direction
        raw = direction == .emerge ? 1 : 0
        velocity = 0
        elapsed = 0
        resume()
    }

    func resume() {
        guard !isPlaying else { return }
        isPlaying = true
        lastTick = CACurrentMediaTime()
        timer = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
    }

    func pause() {
        isPlaying = false
        timer = nil
    }

    func scrub(to value: CGFloat) {
        pause()
        raw = value
        velocity = 0
    }

    func step(_ delta: CGFloat) { scrub(to: max(-0.12, min(1, raw + delta))) }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, now - lastTick) * speed
        lastTick = now
        elapsed += dt
        let t = LiquidMotionTuning.v
        let response = direction == .emerge ? t.emergeResponse : t.absorbResponse
        let damping = direction == .emerge ? t.emergeDamping : t.absorbDamping
        let target: CGFloat = direction == .emerge ? 0 : 1
        // Resorte de SwiftUI: rigidez (2π/response)², amortiguamiento 4πζ/response
        let stiffness = pow(2 * .pi / max(0.05, response), 2)
        let friction = 4 * .pi * damping / max(0.05, response)
        let substeps = 8
        let h = CGFloat(dt) / CGFloat(substeps)
        for _ in 0..<substeps {
            let accel = -CGFloat(stiffness) * (raw - target) - CGFloat(friction) * velocity
            velocity += accel * h
            raw += velocity * h
        }
        if abs(raw - target) < 0.0004 && abs(velocity) < 0.002 {
            raw = target
            pause()
        }
    }
}

struct AnimationStudioView: View {
    @StateObject private var playback = StudioPlayback()
    @ObservedObject private var tuning = LiquidMotionTuning.shared

    @State private var showGeometry = true
    @State private var showMaterial = true
    @State private var glassMode = false
    @State private var zoom: CGFloat = 3.2

    // Escenario con las medidas reales del notch
    private var notchWidth: CGFloat { max(180, ScreenService.shared.currentGeometry.width + NotchTuning.compactWingsExtraWidth) }
    private var notchHeight: CGFloat { max(30, ScreenService.shared.currentGeometry.height) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                stage
                Divider()
                timeline
                    .padding(14)
            }
            Divider()
            parameters
                .frame(width: 300)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Escenario

    private var stage: some View {
        let d = notchHeight
        let restingX = notchWidth / 2 + AppState.shared.bolitaGap + d / 2
        let notchEndX = notchWidth / 2 - d / 2
        return ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.62), Color(red: 0.32, green: 0.18, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .top) {
                if showMaterial {
                    RoundedRectangle(cornerRadius: d / 2, style: .continuous)
                        .fill(glassMode ? Color.white.opacity(0.18) : Color.black)
                        .frame(width: notchWidth, height: d)
                    StudioBubble(diameter: d, glass: glassMode)
                        .modifier(LiquidSatelliteModifier(
                            merge: playback.raw,
                            restingX: restingX,
                            notchEndX: notchEndX,
                            notchRadius: d / 2,
                            bubbleDiameter: d,
                            offsetY: 0,
                            showsBridge: true,
                            isGlass: glassMode
                        ))
                }
                if showGeometry {
                    StudioGeometryOverlay(raw: playback.raw, restingX: restingX, notchEndX: notchEndX, notchWidth: notchWidth, diameter: d)
                }
            }
            .frame(width: notchWidth + 2 * (d * 2 + 30), height: d * 3, alignment: .top)
            // Centrado en el extremo del notch, donde ocurre todo (la gota y su lugar de reposo)
            .offset(x: -(notchEndX + restingX) / 2)
            .scaleEffect(zoom)
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Línea de tiempo

    private var timeline: some View {
        let profile = LiquidDropProfile(raw: playback.raw, tuning: tuning.values)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { playback.play(.emerge) } label: { Label("Salir", systemImage: "arrow.right.circle") }
                Button { playback.play(.absorb) } label: { Label("Regresar", systemImage: "arrow.left.circle") }
                Button { playback.isPlaying ? playback.pause() : playback.resume() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { playback.step(0.01) } label: { Image(systemName: "backward.frame.fill") }
                    .help("Hacia el notch (m + 0.01)")
                Button { playback.step(-0.01) } label: { Image(systemName: "forward.frame.fill") }
                    .help("Hacia afuera (m − 0.01)")
                Divider().frame(height: 18)
                Text("Velocidad")
                Picker("", selection: $playback.speed) {
                    Text("0.1×").tag(0.1)
                    Text("0.25×").tag(0.25)
                    Text("0.5×").tag(0.5)
                    Text("1×").tag(1.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            HStack {
                Text("Fuera").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(1 - playback.raw) },
                    set: { playback.scrub(to: CGFloat(1 - $0)) }
                ), in: 0...1.12)
                Text("En reposo").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Text(String(format: "m %.3f", playback.raw)).monospacedDigit()
                Text(profile.phase).bold()
                Text(String(format: "ancho %.2f · alto %.2f", profile.scaleX, profile.scaleY)).monospacedDigit()
                Text(String(format: "t %.2f s", playback.elapsed)).monospacedDigit()
                Spacer()
                Toggle("Geometría", isOn: $showGeometry)
                Toggle("Material", isOn: $showMaterial)
                Toggle("Cristal", isOn: $glassMode)
            }
            .font(.system(size: 12))
            HStack {
                Text("Zoom")
                Slider(value: $zoom, in: 1...5).frame(width: 160)
                Spacer()
                Button("Exportar cuadros…") {
                    BubbleFrameRenderer.renderSequence()
                    NSWorkspace.shared.selectFile("/tmp/dn_bubble_frames.png", inFileViewerRootedAtPath: "/tmp")
                }
            }
            .font(.system(size: 12))
        }
    }

    // MARK: Parámetros en vivo

    private var parameters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Parámetros en vivo").font(.headline)
                Text("Son los que usa la animación real de la app: los cambios se aplican al instante.")
                    .font(.caption).foregroundStyle(.secondary)
                group("Forma") {
                    param("Unión (cuello)", \.blend, 3...24, "%.1f pt")
                    param("Tramo de nacimiento", \.birthSpan, 0.05...0.5, "%.2f")
                    param("Alto mínimo al salir", \.minHeight, 0.2...1, "%.2f")
                    param("Alargamiento del óvalo", \.elongation, 0...1.2, "%.2f")
                    param("Tensión antes del corte", \.tension, 0...0.25, "%.2f")
                    param("Temblor al soltarse", \.wobble, 0...0.25, "%.2f")
                }
                group("Resorte al salir") {
                    param("Duración (response)", \.emergeResponse, 0.2...2.5, "%.2f s")
                    param("Amortiguamiento", \.emergeDamping, 0.3...1, "%.2f")
                }
                group("Resorte al regresar") {
                    param("Duración (response)", \.absorbResponse, 0.2...2.5, "%.2f s")
                    param("Amortiguamiento", \.absorbDamping, 0.3...1, "%.2f")
                }
                group("Reacción de la isla") {
                    param("Ensanche al salir", \.widenImpulse, 0...16, "%.0f pt")
                    param("Abultamiento al recibir", \.absorbBulge, 0...16, "%.0f pt")
                }
                Button("Restablecer valores de fábrica") { tuning.reset() }
            }
            .padding(16)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }

    private func param(_ title: String, _ key: WritableKeyPath<LiquidMotionTuning.Values, Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11.5))
                Spacer()
                Text(String(format: format, tuning.values[keyPath: key])).font(.system(size: 11.5)).monospacedDigit()
            }
            Slider(value: Binding(
                get: { tuning.values[keyPath: key] },
                set: { tuning.values[keyPath: key] = $0 }
            ), in: range)
        }
    }
}

/// Bolita de prueba (negro o cristal) con el mismo comportamiento de relevo que la real
private struct StudioBubble: View {
    let diameter: CGFloat
    let glass: Bool
    @Environment(\.liquidBubbleGlassSuppressed) private var drawnByDroplet

    var body: some View {
        ZStack {
            if glass {
                if !drawnByDroplet {
                    if #available(macOS 26.0, *) {
                        Color.black.opacity(0.22).clipShape(Circle())
                            .glassEffect(Glass.clear, in: Circle())
                    } else {
                        Circle().fill(Color.black.opacity(0.4))
                    }
                }
            } else {
                Circle().fill(Color.black)
            }
            Circle()
                .stroke(Color.orange.opacity(0.28), lineWidth: diameter * 0.075)
                .frame(width: diameter * 0.58, height: diameter * 0.58)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: diameter * 0.24, weight: .semibold))
                .foregroundColor(.orange)
        }
        .frame(width: diameter, height: diameter)
        .environment(\.colorScheme, .dark)
    }
}

/// Geometría sin material: contorno, cápsula del extremo del notch, elipse de la gota y la cápsula completa
private struct StudioGeometryOverlay: View {
    let raw: CGFloat
    let restingX: CGFloat
    let notchEndX: CGFloat
    let notchWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        let r = diameter / 2
        let profile = LiquidDropProfile(raw: raw)
        let x = restingX + (notchEndX - restingX) * profile.travel
        let geometry = LiquidDropGeometry(
            notchCenterOffset: CGPoint(x: notchEndX - x, y: 0),
            notchRadius: r, bubbleRadius: r,
            scaleX: profile.scaleX, scaleY: profile.scaleY,
            notchIsLeading: notchEndX < restingX
        )
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, dash: [3, 2]))
                .frame(width: notchWidth, height: diameter)
            ZStack {
                let full = LiquidContour.path(
                    pillRect: geometry.pillRect, drop: geometry.dropRect,
                    in: CGRect(origin: .zero, size: CGSize(width: geometry.size, height: geometry.size))
                )
                full.stroke(Color.cyan, lineWidth: 0.7)
                Path(roundedRect: geometry.pillRect, cornerRadius: r).stroke(Color.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 0.4, dash: [2, 2]))
                Path(ellipseIn: geometry.dropRect).stroke(Color.pink.opacity(0.8), style: StrokeStyle(lineWidth: 0.4, dash: [2, 2]))
                Path(ellipseIn: CGRect(x: geometry.size / 2 - 0.8, y: geometry.size / 2 - 0.8, width: 1.6, height: 1.6)).fill(Color.pink)
            }
            .frame(width: geometry.size, height: geometry.size)
            .frame(width: diameter, height: diameter)
            .offset(x: x)
        }
        .allowsHitTesting(false)
    }
}
