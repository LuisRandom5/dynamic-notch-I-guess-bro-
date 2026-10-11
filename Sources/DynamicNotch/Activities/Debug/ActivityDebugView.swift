import SwiftUI

public struct ActivityDebugView: View {
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var debugOverlay = DebugOverlayManager.shared
    @ObservedObject var speedManager = AnimationSpeedManager.shared
    @ObservedObject var volumeInterceptor = VolumeInterceptorService.shared
    
    // Controles para Carga
    @State private var batteryPercentage: Double = 84.0
    @State private var isLowPowerMode: Bool = false
    @State private var isPluggedIn: Bool = true
    
    // Controles para SliderPill
    @State private var sliderValue: Double = 0.70
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Encabezado
                HStack {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignTokens.orange)
                    Text("Panel de Pruebas: Live Activities")
                        .font(.system(size: 18, weight: .bold))
                }
                .padding(.bottom, 4)
                
                // Actividad actual
                GroupBox("Estado Actual en la Isla") {
                    HStack {
                        if let current = center.currentActivity {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ID: \(current.id) (Prioridad: \(current.priority))")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Plantilla: \(current.style.rawValue.capitalized)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Descartar") {
                                center.remove(id: current.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Text("No hay ninguna Live Activity activa en este momento.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }
                
                // 1) CHARGING (Pill)
                GroupBox("1. Actividad Charging (Plantilla: .pill)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Porcentaje:")
                            Spacer()
                            Text("\(Int(batteryPercentage))%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        
                        Slider(value: $batteryPercentage, in: 0...100, step: 1)
                        
                        HStack(spacing: 20) {
                            Toggle("Modo Bajo Consumo", isOn: $isLowPowerMode)
                            Toggle("Conectado AC", isOn: $isPluggedIn)
                        }
                        
                        Button(action: {
                            ChargingActivityProvider.shared.publishChargingActivity(
                                percentage: Int(batteryPercentage),
                                isLowPower: isLowPowerMode,
                                isPluggedIn: isPluggedIn
                            )
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("Disparar Actividad de Carga (3s)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.green)
                    }
                    .padding(6)
                }
                
                // 2) SLIDER PILL (BRILLO, VOLUMEN, MUTE)
                GroupBox("2. Plantilla SliderPill (Brillo, Volumen y Mute)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Button("☀️ Brillo (80%)") {
                                BrightnessService.shared.publishBrightnessActivity(0.80)
                            }
                            .buttonStyle(.bordered)
                            
                            Button("🔊 Volumen (65%)") {
                                AudioDeviceService.shared.publishVolumeActivity(volume: 0.65, isMuted: false)
                            }
                            .buttonStyle(.bordered)
                            
                            Button("🔇 Mute") {
                                AudioDeviceService.shared.publishVolumeActivity(volume: 0.65, isMuted: true)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider()
                        
                        Toggle("Ocultar HUD nativo de macOS (Volumen y Brillo)", isOn: $volumeInterceptor.suppressNativeHUD)
                            .font(.system(size: 12.5, weight: .semibold))
                        
                        HStack {
                            Text(volumeInterceptor.hasAccessibilityPermission ? "✓ Accesibilidad: Otorgada" : "⚠️ Accesibilidad: No otorgada")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(volumeInterceptor.hasAccessibilityPermission ? DesignTokens.green : DesignTokens.orange)
                            Spacer()
                            Button("Configurar...") {
                                AccessibilityOnboardingWindowController.showAlways()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(6)
                }
                
                // 3) CARD
                GroupBox("3. Plantilla Card (Radio ~40pt, Alto ~105pt)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tarjeta de notificación expandida (AirDrop, llamadas o descargas).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            SampleActivities.triggerSampleCard()
                        }) {
                            HStack {
                                Image(systemName: "airdrop")
                                Text("Disparar Tarjeta Card (4s)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.purple)
                    }
                    .padding(6)
                }
                
                // 4) INSPECCIÓN VISUAL (OVERLAY DE COMPARACIÓN PIXEL-PERFECT)
                GroupBox("4. Inspección Visual Pixel-Perfect (Modo Overlay)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("Superponer Imagen de Referencia", isOn: $debugOverlay.isOverlayActive)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("Atajo: ⌘⇧O")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Opacidad de Superposición:")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int(debugOverlay.opacity * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        
                        Slider(value: $debugOverlay.opacity, in: 0.0...1.0, step: 0.05)
                        
                        HStack {
                            Button("Cargar Captura de Referencia...") {
                                debugOverlay.chooseImageFile()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            if !debugOverlay.imagePath.isEmpty {
                                Text("📄 \(debugOverlay.imagePath)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Button(action: {
                            AppState.shared.expand()
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text("Abrir Reproductor Expandido para Comparar")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.blue)
                    }
                    .padding(6)
                }
                
                // 5) VELOCIDAD DE ANIMACIÓN (DEBUG MULTIPLIER / CÁMARA LENTA)
                GroupBox("5. Velocidad de Animación (Modo Cámara Lenta)") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("Cámara Lenta (0.2x)", isOn: Binding(
                                get: { speedManager.isSlowMotion },
                                set: { _ in speedManager.toggleSlowMotion() }
                            ))
                            .font(.system(size: 13, weight: .semibold))
                            
                            Spacer()
                            
                            Text("Atajo: ⌘⇧S")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Multiplicador Global:")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.1fx", speedManager.speedMultiplier))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { speedManager.speedMultiplier },
                                set: { speedManager.setSpeed($0) }
                            ),
                            in: 0.1...1.5,
                            step: 0.1
                        )
                    }
                    .padding(6)
                }
                
                // Cola de prioridades
                GroupBox("Cola de Actividades (\(center.activeActivities.count))") {
                    if center.activeActivities.isEmpty {
                        Text("Cola vacía.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(center.activeActivities) { act in
                                HStack {
                                    Text("• \(act.id) (Prio: \(act.priority))")
                                        .font(.system(size: 12, design: .monospaced))
                                    Spacer()
                                    Button("Quitar") {
                                        center.remove(id: act.id)
                                    }
                                    .font(.system(size: 11))
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 680)
    }
}
