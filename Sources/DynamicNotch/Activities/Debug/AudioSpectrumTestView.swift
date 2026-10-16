import SwiftUI
import AppKit

public final class AudioSpectrumTestWindowController: NSWindowController {
    public static let shared = AudioSpectrumTestWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 720, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dynamic Notch - Calibración & Diagnóstico de Audio (Dynamic Island)"
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
    @ObservedObject var generator = AudioSignalGenerator.shared
    
    // Sliders de Audio y DSP
    @State private var attack: Double = SpectrumMetrics.attackMs
    @State private var release: Double = SpectrumMetrics.releaseMs
    @State private var noiseGate: Double = Double(SpectrumMetrics.noiseGateDB)
    @State private var gain: Double = Double(SpectrumMetrics.gainMultiplier)
    @State private var btDelay: Double = SpectrumMetrics.bluetoothDelayMs
    @State private var spatialDiffusion: Double = Double(SpectrumMetrics.spatialDiffusion)
    @State private var organicAmount: Double = SpectrumMetrics.organicAmount
    @State private var generatorVolume: Double = Double(AudioSignalGenerator.shared.volume)
    
    // Sliders de Overscroll
    @State private var maxStretch: Double = Double(OverscrollMetrics.maxStretch)
    @State private var resistanceC: Double = Double(OverscrollMetrics.resistanceC)
    @State private var contentFollow: Double = Double(OverscrollMetrics.contentFollow)
    @State private var speedMultiplier: Double = OverscrollMetrics.speedMultiplier
    @State private var shapeResponse: Double = OverscrollMetrics.shapeSpringResponse
    @State private var shapeDamping: Double = OverscrollMetrics.shapeSpringDamping
    
    // Live metering y diagnóstico
    @State private var liveLevels: [Float] = [0, 0, 0, 0, 0, 0]
    @State private var peakHolds: [Float] = [0, 0, 0, 0, 0, 0]
    @State private var peakDecibels: Float = -60.0
    @State private var displayPercentages: [Int] = [0, 0, 0, 0, 0, 0]
    @State private var diagnosticsList: [BandDiagnostics] = []
    @State private var testTimer: Timer? = nil
    @State private var csvExportURL: URL? = nil
    @State private var showExportAlert: Bool = false
    
    // Vista interactiva de overscroll
    @State private var testDragX: CGFloat = 0
    @State private var testStretch: CGFloat = 0
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                Divider()
                
                // PASO 6: Vista previa a tamaño real (6 barras ~3.5 pt)
                realSizePreviewSection
                
                Divider()
                
                // VISUALIZADOR DE 6 BARRAS CON PEAK HOLD
                mainVisualizerSection
                
                Divider()
                
                // PASO 1: Diagnóstico de 4 Etapas (Raw, Weighted, Normalized, Smoothed)
                multiStageInspectionSection
                
                Divider()
                
                // PASO 1: Tabla de Estadísticas de 60s (p10, p50, p90, max, % > 90%, saturación)
                diagnosticsTableSection
                
                Divider()
                
                // PASO 6: Generador de Señales de Prueba
                signalGeneratorSection
                
                Divider()
                
                // CONTROLES DE PARÁMETROS DEL AUDIO (DSP, Ponderación, Orgánico)
                audioControlsSection
                
                Divider()
                
                // CONTROLES DE OVERSCROLL ELÁSTICO
                overscrollControlsSection
            }
            .padding(20)
        }
        .frame(minWidth: 680, minHeight: 780)
        .onAppear {
            startLiveTimer()
        }
        .onDisappear {
            testTimer?.invalidate()
            testTimer = nil
        }
        .alert(isPresented: $showExportAlert) {
            Alert(
                title: Text("Telemetría Exportada"),
                message: Text("Se guardó el archivo CSV en:\n\(csvExportURL?.path ?? "")"),
                primaryButton: .default(Text("Abrir en Finder")) {
                    if let url = csvExportURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                },
                secondaryButton: .cancel(Text("OK"))
            )
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monitor de Audio en Tiempo Real & FFT Multirresolución")
                    .font(.system(size: 18, weight: .bold))
                Text(engine.isRealAudioActive
                     ? "Audio Digital del Sistema Activo (Process Tap CoreAudio 64-bit) • FFT 4096 pts • Cero Micrófono"
                     : (engine.isSimulatedMode ? "Modo Simulado Psicoacústico Activo" : "Modo Automático (activa Tap Digital o reproduce música)"))
                    .font(.system(size: 11.5))
                    .foregroundColor(engine.isRealAudioActive ? .green : (engine.isSimulatedMode ? .purple : .orange))
            }
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: {
                    engine.isSimulatedMode.toggle()
                }) {
                    Text(engine.isSimulatedMode ? "Modo: Simulación" : "Modo: Sistema Real")
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
    }
    
    // MARK: - PASO 6: Vista previa a tamaño real (6 barras ~3.5 pt)
    private var realSizePreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vista Previa a Tamaño Real (Dynamic Island / Notch)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Escala 1:1 nativa (6 barras de 3.5 pt)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 24) {
                // Cápsula negra Dynamic Island compacta
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.22, blue: 0.45))
                    
                    Text("Canción en Reproducción")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 6 barras estilo Dynamic Island tamaño real
                    HStack(alignment: .center, spacing: 2.2) {
                        ForEach(0..<6, id: \.self) { i in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.98, green: 0.22, blue: 0.45), Color(red: 0.98, green: 0.55, blue: 0.20)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(
                                    width: 3.5,
                                    height: max(3.5, CGFloat(liveLevels[i]) * 18.0)
                                )
                        }
                    }
                    .frame(height: 18)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 280, height: 36)
                .background(Color.black)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                
                // Alerta de Saturación de Bandas Altas
                if engine.highBandsSaturating {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Bandas altas saturando (>22% sobre el 90%)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.14))
                    .cornerRadius(8)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Respuesta balanceada y calibrada")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Visualizador de 6 Barras Grandes con Peak Hold
    private var mainVisualizerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Espectro de 6 Bandas (FFT 4096 multirresolución)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Text("Presets:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    ForEach(SpectrumResponsePreset.allCases) { preset in
                        Button(preset.shortTitle) {
                            SpectrumMetrics.applyPreset(preset)
                            attack = SpectrumMetrics.attackMs
                            release = SpectrumMetrics.releaseMs
                            noiseGate = Double(SpectrumMetrics.noiseGateDB)
                            gain = Double(SpectrumMetrics.gainMultiplier)
                            spatialDiffusion = Double(SpectrumMetrics.spatialDiffusion)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(SpectrumMetrics.activePreset == preset ? .blue : .secondary)
                    }
                }
            }
            
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: 8) {
                        Text("\(i < displayPercentages.count ? displayPercentages[i] : 0)%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(liveLevels[i] > 0.90 ? .orange : .secondary)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 32, height: 120)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [PlayerMetrics.visualizerTopGradient, PlayerMetrics.visualizerBottomGradient],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 32, height: max(6, CGFloat(liveLevels[i]) * 120))
                                .animation(.spring(response: 0.16, dampingFraction: 0.82), value: liveLevels[i])
                            
                            // Línea de Peak Hold
                            Capsule()
                                .fill(Color.white.opacity(0.90))
                                .frame(width: 26, height: 2.5)
                                .offset(y: -min(116, max(6, CGFloat(peakHolds[i]) * 120)))
                        }
                        
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
            .background(Color.black.opacity(0.24))
            .cornerRadius(12)
        }
    }
    
    // MARK: - PASO 1: Diagnóstico de 4 Etapas
    private var multiStageInspectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Inspección de las 4 Etapas del Pipeline DSP")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("1. Raw → 2. Weighted (Ruido Rosa) → 3. Normalized (Tanh) → 4. Smoothed")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                stageColumn(title: "1. Energía Bruta (Raw)", values: engine.stageRaw, color: .gray)
                stageColumn(title: "2. Ponderada (Pink)", values: engine.stageWeighted, color: .orange)
                stageColumn(title: "3. Normalizada (Tanh)", values: engine.stageNormalized, color: .blue)
                stageColumn(title: "4. Suavizada (Final)", values: engine.stageSmoothed, color: .green)
            }
            .padding(12)
            .background(Color.black.opacity(0.18))
            .cornerRadius(10)
        }
    }
    
    @ViewBuilder
    private func stageColumn(title: String, values: [Float], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<6, id: \.self) { i in
                    let val = i < values.count ? values[i] : 0.0
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 14, height: 60)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: 14, height: max(2, CGFloat(val) * 60))
                        }
                        Text("\(i)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - PASO 1: Tabla de Estadísticas de 60s
    private var diagnosticsTableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Registro Histórico de 60 Segundos & Percentiles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: {
                    if let url = engine.exportTelemetryToCSV() {
                        csvExportURL = url
                        showExportAlert = true
                    }
                }) {
                    Label("Exportar CSV", systemImage: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            VStack(spacing: 0) {
                // Encabezados
                HStack {
                    Text("Banda").frame(width: 85, alignment: .leading)
                    Text("Rango").frame(width: 90, alignment: .leading)
                    Text("p10").frame(width: 50, alignment: .trailing)
                    Text("p50 (Mediana)").frame(width: 90, alignment: .trailing)
                    Text("p90").frame(width: 50, alignment: .trailing)
                    Text("Máx").frame(width: 50, alignment: .trailing)
                    Text("% > 90%").frame(width: 70, alignment: .trailing)
                    Text("Estado").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.06))
                
                // Filas
                ForEach(diagnosticsList) { diag in
                    HStack {
                        Text(diag.label).frame(width: 85, alignment: .leading).font(.system(size: 10.5, weight: .semibold))
                        Text(diag.freqRange).frame(width: 90, alignment: .leading).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", diag.p10 * 100)).frame(width: 50, alignment: .trailing).font(.system(size: 10, design: .monospaced))
                        Text(String(format: "%.0f%%", diag.p50 * 100)).frame(width: 90, alignment: .trailing).font(.system(size: 10, weight: .medium, design: .monospaced))
                        Text(String(format: "%.0f%%", diag.p90 * 100)).frame(width: 50, alignment: .trailing).font(.system(size: 10, design: .monospaced))
                        Text(String(format: "%.0f%%", diag.maxVal * 100)).frame(width: 50, alignment: .trailing).font(.system(size: 10, design: .monospaced))
                        Text(String(format: "%.1f%%", diag.percentAbove90)).frame(width: 70, alignment: .trailing).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(diag.percentAbove90 > 20.0 ? .orange : .primary)
                        
                        HStack(spacing: 4) {
                            if diag.isSaturating {
                                Text("SATURANDO")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            } else {
                                Text("OK")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.85))
                                    .cornerRadius(4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(diag.id % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
                }
            }
            .background(Color.black.opacity(0.20))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }
    
    // MARK: - PASO 6: Generador de Señales de Prueba
    private var signalGeneratorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generador de Señales de Calibración (Paso 6)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if generator.activeSignal != .off {
                    Text("Generando: \(generator.activeSignal.title)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            
            HStack(spacing: 8) {
                ForEach([
                    SignalGeneratorType.pinkNoise,
                    SignalGeneratorType.sineSweep,
                    SignalGeneratorType.tone1kHz,
                    SignalGeneratorType.metronome120,
                    SignalGeneratorType.silence3s
                ], id: \.self) { sig in
                    Button(action: {
                        if generator.activeSignal == sig {
                            generator.setSignal(.off)
                        } else {
                            generator.setSignal(sig)
                        }
                    }) {
                        Text(sig.title)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(generator.activeSignal == sig ? .green : .secondary)
                }
                
                Button(action: { generator.setSignal(.off) }) {
                    Text("Detener")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            HStack(spacing: 16) {
                sliderRow(title: "Volumen Generador", value: $generatorVolume, range: 0.1...1.0, unit: "") {
                    generator.volume = Float($0)
                }
                
                Toggle("Incluir mi audio en Process Tap", isOn: Binding(
                    get: { SpectrumMetrics.includeAppAudioInTap },
                    set: { SpectrumMetrics.includeAppAudioInTap = $0 }
                ))
                .font(.system(size: 11.5))
            }
        }
    }
    
    // MARK: - Controles de Audio y DSP
    private var audioControlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parámetros del Motor de Audio & DSP (Persistentes)")
                .font(.system(size: 13, weight: .semibold))
            
            Group {
                sliderRow(title: "Ataque (Attack)", value: $attack, range: 5...50, unit: "ms") {
                    SpectrumMetrics.attackMs = $0
                }
                sliderRow(title: "Caída (Release)", value: $release, range: 40...350, unit: "ms") {
                    SpectrumMetrics.releaseMs = $0
                }
                sliderRow(title: "Noise Gate (Apertura)", value: $noiseGate, range: -70...(-30), unit: "dB") {
                    SpectrumMetrics.noiseGateDB = Float($0)
                }
                sliderRow(title: "Ganancia Perceptual", value: $gain, range: 0.5...2.5, unit: "x") {
                    SpectrumMetrics.gainMultiplier = Float($0)
                }
                sliderRow(title: "Difusión Espacial", value: $spatialDiffusion, range: 0.0...0.30, unit: "") {
                    SpectrumMetrics.spatialDiffusion = Float($0)
                }
                sliderRow(title: "Modo Orgánico Híbrido (Paso 5)", value: $organicAmount, range: 0.0...1.0, unit: "") {
                    SpectrumMetrics.organicAmount = $0
                }
                sliderRow(title: "Retardo Bluetooth (AirPods)", value: $btDelay, range: 0...350, unit: "ms") {
                    SpectrumMetrics.bluetoothDelayMs = $0
                }
            }
            
            Toggle("Captura Digital del Sistema (CoreAudio Process Tap 64-bit)", isOn: $engine.enableSystemAudioTap)
                .font(.system(size: 12, weight: .medium))
            
            Toggle("Captura Acústica por Micrófono", isOn: Binding(
                get: { engine.enableMicrophoneCapture },
                set: { engine.toggleMicrophoneCapture($0) }
            ))
            .font(.system(size: 12))
            
            Toggle("Forzar Modo Simulado de Prueba", isOn: $engine.isSimulatedMode)
                .font(.system(size: 12))
        }
    }
    
    // MARK: - Controles de Overscroll Elástico
    private var overscrollControlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parámetros de Overscroll Elástico")
                .font(.system(size: 13, weight: .semibold))
            
            sliderRow(title: "Estiramiento Máximo (maxStretch)", value: $maxStretch, range: 20...80, unit: "pt") {
                OverscrollMetrics.maxStretch = CGFloat($0)
            }
            sliderRow(title: "Resistencia (c)", value: $resistanceC, range: 0.2...1.2, unit: "") {
                OverscrollMetrics.resistanceC = CGFloat($0)
            }
            sliderRow(title: "Seguimiento Contenido", value: $contentFollow, range: 0.4...0.95, unit: "") {
                OverscrollMetrics.contentFollow = CGFloat($0)
            }
            sliderRow(title: "Velocidad de Animación", value: $speedMultiplier, range: 0.2...1.5, unit: "x") {
                OverscrollMetrics.speedMultiplier = $0
            }
            
            // Zona interactiva de prueba
            VStack(alignment: .center, spacing: 10) {
                Text("Prueba de Gesto en Vivo (Arrastra a los lados):")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ZStack {
                    ElasticPillShape(topRadius: 28, bottomRadius: 28, stretch: testStretch)
                        .fill(Color.black)
                        .overlay(
                            ElasticPillShape(topRadius: 28, bottomRadius: 28, stretch: testStretch)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 260, height: 70)
                    
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
                            withAnimation(.spring(response: shapeResponse, dampingFraction: shapeDamping)) {
                                testStretch = 0
                                testDragX = 0
                            }
                        }
                )
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black.opacity(0.18))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Timer en Vivo (60 fps)
    private func startLiveTimer() {
        testTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
            let levels = engine.getMagnitudes()
            let peak = engine.getPeakDecibels()
            self.liveLevels = levels
            self.peakDecibels = peak
            
            for i in 0..<6 {
                let lvl = levels[i]
                if lvl > self.peakHolds[i] {
                    self.peakHolds[i] = lvl
                } else {
                    self.peakHolds[i] = max(0.0, self.peakHolds[i] - 0.012)
                }
                self.displayPercentages[i] = Int(round(lvl * 100))
            }
            
            // Actualizar tabla de diagnóstico cada ~300ms
            self.diagnosticsList = engine.computeDiagnostics()
        }
    }
    
    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 190, alignment: .leading)
            Slider(value: value, in: range) {
                Text(title)
            }
            .onChange(of: value.wrappedValue) { _, newVal in
                onChange(newVal)
            }
            Text(String(format: "%.1f %@", value.wrappedValue, unit))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
        }
    }
}
