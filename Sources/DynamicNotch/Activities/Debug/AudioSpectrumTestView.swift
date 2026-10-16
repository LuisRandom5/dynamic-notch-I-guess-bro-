import SwiftUI
import AppKit

public final class AudioSpectrumTestWindowController: NSWindowController {
    public static let shared = AudioSpectrumTestWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 620, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dynamic Notch - Monitor de Audio Real & Overscroll"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AudioSpectrumTestView())
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

public struct AudioSpectrumTestView: View {
    @ObservedObject var engine = AudioSpectrumEngine.shared
    
    // Sliders de Audio
    @State private var attack: Double = SpectrumMetrics.attackMs
    @State private var release: Double = SpectrumMetrics.releaseMs
    @State private var noiseGate: Double = Double(SpectrumMetrics.noiseGateDB)
    @State private var gain: Double = Double(SpectrumMetrics.gainMultiplier)
    @State private var btDelay: Double = SpectrumMetrics.bluetoothDelayMs
    
    // Sliders de Overscroll
    @State private var maxStretch: Double = Double(OverscrollMetrics.maxStretch)
    @State private var resistanceC: Double = Double(OverscrollMetrics.resistanceC)
    @State private var contentFollow: Double = Double(OverscrollMetrics.contentFollow)
    @State private var speedMultiplier: Double = OverscrollMetrics.speedMultiplier
    @State private var shapeResponse: Double = OverscrollMetrics.shapeSpringResponse
    @State private var shapeDamping: Double = OverscrollMetrics.shapeSpringDamping
    @State private var contentResponse: Double = OverscrollMetrics.contentSpringResponse
    @State private var contentDamping: Double = OverscrollMetrics.contentSpringDamping
    
    // Live metering a 60 fps
    @State private var liveLevels: [Float] = [0, 0, 0, 0, 0, 0]
    @State private var peakHolds: [Float] = [0, 0, 0, 0, 0, 0]
    @State private var peakDecibels: Float = -60.0
    @State private var smoothedPercentages: [Double] = [0, 0, 0, 0, 0, 0]
    @State private var displayPercentages: [Int] = [0, 0, 0, 0, 0, 0]
    @State private var lastTextUpdate: Date = Date.distantPast
    @State private var testTimer: Timer? = nil
    
    // Interactive test pill
    @State private var testDragX: CGFloat = 0
    @State private var testStretch: CGFloat = 0
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monitor de Audio en Tiempo Real & FFT")
                            .font(.system(size: 18, weight: .bold))
                        Text(engine.isRealAudioActive
                             ? "Audio Digital del Sistema Activo (Process Tap CoreAudio 64-bit) • FFT 1024 pts • Cero Micrófono"
                             : (engine.isSimulatedMode ? "Modo Simulado Psicoacústico Activo" : "Modo Automático (activa Tap Digital o reproduce música)"))
                            .font(.system(size: 11.5))
                            .foregroundColor(engine.isRealAudioActive ? .green : (engine.isSimulatedMode ? .purple : .orange))
                    }
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            engine.isSimulatedMode.toggle()
                        }) {
                            Text(engine.isSimulatedMode ? "Modo: Simulación Forzada" : "Modo: Automático / Sistema")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(engine.isSimulatedMode ? .purple : .blue)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill((!engine.isSilent || MusicService.shared.currentTrack.isPlaying || engine.isSimulatedMode) ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                            Text(String(format: "%.1f dBFS", peakDecibels))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // MARK: - VISUALIZADOR DE 6 BARRAS EN VIVO CON PEAK HOLD Y UMBRAL DE NOISE GATE
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1. Espectro de 6 Bandas Logarítmicas (Con Retención de Picos)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        HStack(spacing: 6) {
                            Text("Presets:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            ForEach(SpectrumResponsePreset.allCases) { preset in
                                Button(preset.title) {
                                    SpectrumMetrics.applyPreset(preset)
                                    attack = SpectrumMetrics.attackMs
                                    release = SpectrumMetrics.releaseMs
                                    noiseGate = Double(SpectrumMetrics.noiseGateDB)
                                    gain = Double(SpectrumMetrics.gainMultiplier)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    HStack(alignment: .bottom, spacing: 18) {
                        ForEach(0..<6, id: \.self) { i in
                            VStack(spacing: 8) {
                                // Porcentaje legible con amortiguación EMA profesional
                                Text("\(i < displayPercentages.count ? displayPercentages[i] : 0)%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                // Barra vertical con resorte balístico fluido + indicador Peak Hold
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 30, height: 115)
                                    
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            LinearGradient(
                                                colors: [PlayerMetrics.visualizerTopGradient, PlayerMetrics.visualizerBottomGradient],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 30, height: max(6, CGFloat(liveLevels[i]) * 115))
                                        .animation(.spring(response: 0.18, dampingFraction: 0.80), value: liveLevels[i])
                                    
                                    // Línea de Peak Hold
                                    Capsule()
                                        .fill(Color.white.opacity(0.85))
                                        .frame(width: 24, height: 2.5)
                                        .offset(y: -min(112, max(6, CGFloat(peakHolds[i]) * 115)))
                                }
                                
                                // Etiqueta de frecuencia
                                Text(SpectrumMetrics.bands[i].label)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("\(Int(SpectrumMetrics.bands[i].low))-\(Int(SpectrumMetrics.bands[i].high))Hz")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black.opacity(0.22))
                    .cornerRadius(12)
                }
                
                Divider()
                
                // MARK: - CONTROLES DEL AUDIO Y ENVELOPE (PERSISTENTES)
                VStack(alignment: .leading, spacing: 14) {
                    Text("2. Parámetros del Análisis de Audio (Guardados Automáticamente)")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Group {
                        sliderRow(title: "Ataque (Attack)", value: $attack, range: 5...60, unit: "ms") {
                            SpectrumMetrics.attackMs = $0
                        }
                        sliderRow(title: "Caída (Release)", value: $release, range: 40...350, unit: "ms") {
                            SpectrumMetrics.releaseMs = $0
                        }
                        sliderRow(title: "Noise Gate (Umbral)", value: $noiseGate, range: -75...(-25), unit: "dB") {
                            SpectrumMetrics.noiseGateDB = Float($0)
                        }
                        sliderRow(title: "Ganancia Perceptual", value: $gain, range: 0.5...2.5, unit: "x") {
                            SpectrumMetrics.gainMultiplier = Float($0)
                        }
                        sliderRow(title: "Retardo Bluetooth (AirPods)", value: $btDelay, range: 0...350, unit: "ms") {
                            SpectrumMetrics.bluetoothDelayMs = $0
                        }
                    }
                    
                    Toggle("Captura Digital del Sistema (CoreAudio Process Tap 64-bit)", isOn: $engine.enableSystemAudioTap)
                        .font(.system(size: 12, weight: .medium))
                    
                    Toggle("Captura Acústica por Micrófono (Muestra el punto naranja en macOS)", isOn: Binding(
                        get: { engine.enableMicrophoneCapture },
                        set: { engine.toggleMicrophoneCapture($0) }
                    ))
                    .font(.system(size: 12))
                    
                    Toggle("Forzar Modo Simulado de Prueba", isOn: $engine.isSimulatedMode)
                        .font(.system(size: 12))
                }
                
                Divider()
                
                // MARK: - CONTROLES DE OVERSCROLL ELÁSTICO
                VStack(alignment: .leading, spacing: 14) {
                    Text("3. Parámetros de Overscroll Elástico (OverscrollMetrics)")
                        .font(.system(size: 13, weight: .semibold))
                    
                    sliderRow(title: "Estiramiento Máximo (maxStretch)", value: $maxStretch, range: 20...80, unit: "pt") {
                        OverscrollMetrics.maxStretch = CGFloat($0)
                    }
                    sliderRow(title: "Resistencia (c)", value: $resistanceC, range: 0.2...1.2, unit: "") {
                        OverscrollMetrics.resistanceC = CGFloat($0)
                    }
                    sliderRow(title: "Seguimiento Contenido (contentFollow)", value: $contentFollow, range: 0.4...0.95, unit: "") {
                        OverscrollMetrics.contentFollow = CGFloat($0)
                    }
                    sliderRow(title: "Velocidad de Animación (Cámara Lenta)", value: $speedMultiplier, range: 0.2...1.5, unit: "x") {
                        OverscrollMetrics.speedMultiplier = $0
                    }
                    sliderRow(title: "Resorte Forma (Response)", value: $shapeResponse, range: 0.2...0.8, unit: "s") {
                        OverscrollMetrics.shapeSpringResponse = $0
                    }
                    sliderRow(title: "Amortiguación Forma (Damping)", value: $shapeDamping, range: 0.3...0.9, unit: "") {
                        OverscrollMetrics.shapeSpringDamping = $0
                    }
                    sliderRow(title: "Resorte Contenido (Response)", value: $contentResponse, range: 0.2...0.9, unit: "s") {
                        OverscrollMetrics.contentSpringResponse = $0
                    }
                    sliderRow(title: "Amortiguación Contenido (Damping)", value: $contentDamping, range: 0.3...0.9, unit: "") {
                        OverscrollMetrics.contentSpringDamping = $0
                    }
                    
                    // Zona interactiva de prueba de overscroll
                    VStack(alignment: .center, spacing: 10) {
                        Text("Prueba de Gesto en Vivo (Arrastra a los lados):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            // Fondo con ElasticPillShape
                            ElasticPillShape(topRadius: 28, bottomRadius: 28, stretch: testStretch)
                                .fill(Color.black)
                                .overlay(
                                    ElasticPillShape(topRadius: 28, bottomRadius: 28, stretch: testStretch)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .frame(width: 260, height: 70)
                            
                            // Contenido con desfase y escala
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.pink)
                                    .frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Canción de Prueba")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Artista Demo")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                AudioVisualizer(isPlaying: true)
                            }
                            .padding(.horizontal, 16)
                            .frame(width: 260, height: 70)
                            .offset(x: testStretch * CGFloat(contentFollow))
                            .scaleEffect(
                                x: 1.0 + (abs(testStretch) / CGFloat(maxStretch)) * 0.03,
                                y: 1.0,
                                anchor: testStretch >= 0 ? .leading : .trailing
                            )
                        }
                        .frame(width: 380, height: 90)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    testDragX = val.translation.width
                                    testStretch = OverscrollMetrics.calculateStretch(for: testDragX)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: shapeResponse * speedMultiplier, dampingFraction: shapeDamping)) {
                                        testStretch = 0
                                    }
                                    testDragX = 0
                                }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 580, minHeight: 700)
        .onAppear {
            testTimer?.invalidate()
            testTimer = Timer.scheduledTimer(withTimeInterval: 0.032, repeats: true) { _ in
                let levels = engine.getMagnitudes()
                if levels.count == 6 {
                    liveLevels = levels
                    
                    for i in 0..<6 {
                        if levels[i] > peakHolds[i] {
                            peakHolds[i] = levels[i]
                        } else {
                            peakHolds[i] = max(0, peakHolds[i] - 0.008)
                        }
                        smoothedPercentages[i] += (Double(levels[i] * 100.0) - smoothedPercentages[i]) * 0.24
                    }
                    
                    if Date().timeIntervalSince(lastTextUpdate) > 0.20 {
                        lastTextUpdate = Date()
                        displayPercentages = smoothedPercentages.map { Int(round($0)) }
                        peakDecibels = engine.getPeakDecibels()
                    }
                }
            }
        }
        .onDisappear {
            testTimer?.invalidate()
            testTimer = nil
        }
    }
    
    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .frame(width: 220, alignment: .leading)
            Slider(value: value, in: range) { _ in
                onChange(value.wrappedValue)
            }
            Text("\(String(format: range.upperBound > 10 ? "%.0f" : "%.2f", value.wrappedValue)) \(unit)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }
}
