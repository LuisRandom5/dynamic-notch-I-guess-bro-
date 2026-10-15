import SwiftUI

public struct ActivityDebugView: View {
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var debugOverlay = DebugOverlayManager.shared
    @ObservedObject var speedManager = AnimationSpeedManager.shared
    @ObservedObject var volumeInterceptor = VolumeInterceptorService.shared
    @ObservedObject var glassManager = GlassClearManager.shared
    @ObservedObject var contactService = ContactLookupService.shared
    
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
                
                // MARK: - BISECCIÓN DE CAPAS: LIQUID GLASS REALMENTE TRANSPARENTE
                GroupBox("Bisección de Capas: Liquid Glass Transparente") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Activa o apaga capas individualmente para diagnosticar opacidad indeseada:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        // a) Franja del notch físico
                        Toggle(isOn: $glassManager.showNotchFusionStrip) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("a) Franja negra del notch (~34pt + degradado ~10pt)")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Fusiona el notch físico con el widget arriba sin oscurecer el resto.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // b) Tinte del cristal
                        HStack {
                            Toggle(isOn: $glassManager.showGlassTint) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("b) Tinte blanco del cristal (0% a 4%)")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("Apagado = Glass.clear puro. Encendido = tinte sutil.")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if glassManager.showGlassTint {
                                Slider(
                                    value: Binding(
                                        get: { glassManager.glassTintOpacity * 100 },
                                        set: { glassManager.glassTintOpacity = $0 / 100.0 }
                                    ),
                                    in: 0...4,
                                    step: 0.5
                                )
                                .frame(width: 80)
                                Text("\(String(format: "%.1f", glassManager.glassTintOpacity * 100))%")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                        
                        // c) Sombra exterior
                        Toggle(isOn: $glassManager.showCardShadow) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("c) Sombra exterior de la tarjeta (máscara inversa)")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Apagado = sin sombra para eliminar manchas fantasma. Encendido = sólo fuera.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // d) Forma base o NSVisualEffectView bajo el cristal (¡EL CULPABLE LECHOSO!)
                        Toggle(isOn: $glassManager.showBaseFill) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("d) Base lechosa / NSVisualEffectView bajo cristal")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("(¡CULPABLE IDENTIFICADO!)")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.red)
                                }
                                Text("Si se activa, añade material fullScreenUI que vuelve lechoso el fondo.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // e) Borde especular
                        Toggle(isOn: $glassManager.showSpecularBorder) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("e) Borde especular diagonal 1 pt")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Trazo con degradado (blanco 40% arriba → 5% centro → 18% abajo).")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // f) Fondo de ventana transparente
                        Toggle(isOn: $glassManager.enableTransparentWindowBackground) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("f) NSPanel y NSHostingView transparentes")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("isOpaque = false, backgroundColor = .clear, alphaValue = 1.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // g) Scrim local tras textos
                        Toggle(isOn: $glassManager.showLocalTextScrim) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("g) Scrim local detrás de textos")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Atenuación suave 18% sólo tras títulos y artistas, nunca en toda la tarjeta.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Slider Transparencia (0% a 35%)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Atenuación Uniforme (Slider Transparencia):")
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text("\(Int(round(glassManager.uniformScrimOpacity * 100)))%")
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            }
                            Slider(
                                value: Binding(
                                    get: { glassManager.uniformScrimOpacity * 100 },
                                    set: { glassManager.uniformScrimOpacity = $0 / 100.0 }
                                ),
                                in: 0...35,
                                step: 1
                            )
                        }
                        
                        HStack {
                            Button("Restablecer a Configuración Óptima (Paso 2)") {
                                glassManager.showNotchFusionStrip = true
                                glassManager.showGlassTint = false
                                glassManager.glassTintOpacity = 0.0
                                glassManager.showCardShadow = false
                                glassManager.showBaseFill = false
                                glassManager.showSpecularBorder = true
                                glassManager.enableTransparentWindowBackground = true
                                glassManager.showLocalTextScrim = true
                                glassManager.uniformScrimOpacity = 0.10
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.blue)
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                }
                
                // 0) LLAMADA ACTIVA CON AUDIO REACTIVO Y CONTACTOS
                GroupBox("Llamada en Curso (FaceTime / Celular / Discord)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: {
                                CallActivityProvider.shared.startIncomingCall(name: "FaceTime Audio", handle: "Mamá", isSimulation: true)
                            }) {
                                HStack {
                                    Image(systemName: "phone.badge.plus")
                                    Text("Llamada Entrante")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.green)
                            
                            Button(action: {
                                // Probar con un contacto real que tenga foto o monograma de la libreta
                                if let contact = ContactLookupService.shared.fetchFirstContactWithPhoto() {
                                    CallActivityProvider.shared.startIncomingCall(
                                        name: "Llamada celular de iPhone",
                                        handle: contact.name,
                                        avatar: contact.avatar,
                                        isSimulation: true
                                    )
                                } else {
                                    let sampleMonogram = ContactLookupService.shared.generateMonogramAvatar(for: "Luis Ángel", initials: "LA")
                                    CallActivityProvider.shared.startIncomingCall(
                                        name: "Llamada celular de iPhone",
                                        handle: "Luis Ángel",
                                        avatar: sampleMonogram,
                                        isSimulation: true
                                    )
                                }
                            }) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("Probar con Foto")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.blue)
                            
                            Button(action: {
                                CallActivityProvider.shared.startCall(name: "FaceTime Audio", handle: "Mamá", asCard: false, isSimulation: true)
                            }) {
                                HStack {
                                    Image(systemName: "phone.fill")
                                    Text("Píldora Activa")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                CallActivityProvider.shared.startCall(name: "FaceTime Audio", handle: "Mamá", asCard: true, isSimulation: true)
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.inset.filled")
                                    Text("Tarjeta Activa")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            if CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall {
                                Button("Colgar") {
                                    CallActivityProvider.shared.endCall()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                ContactLookupService.shared.requestAccess { _ in
                                    ContactLookupService.shared.checkCurrentStatus()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.crop.circle")
                                    Text("Solicitar Permiso")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text("Ajustes del Sistema")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Text(contactService.isAuthorized ? "✅ Contactos autorizados" : "⚠️ Contactos pendientes de permiso")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(contactService.isAuthorized ? DesignTokens.green : DesignTokens.orange)
                        }
                        
                        Text("Integración con TUCallCenter (FaceTime/Celular), Discord y Contactos del sistema con fotos reales y monogramas.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
                            AirDropActivityProvider.shared.startSimulatedTransfer()
                        }) {
                            HStack {
                                Image(systemName: "airdrop")
                                Text("Simular AirDrop (Alas en Progreso → Expansión)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.blue)
                        
                        Button(action: {
                            SampleActivities.triggerSampleCard()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Disparar Tarjeta Card Directa (4s)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(6)
                }
                
                // NOTIFICACIONES DINÁMICAS (WHATSAPP, MENSAJES Y ALERTAS)
                GroupBox("Notificaciones Dinámicas (WhatsApp y Quick Reply)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            NotificationActivityProvider.shared.showNotification(
                                title: "Mamá",
                                message: "¿A qué hora llegas a cenar? Te guardé comida caliente.",
                                appIcon: "message.fill",
                                appName: "WhatsApp Web",
                                tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                                enableQuickReply: true,
                                duration: 15.0
                            )
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.message.fill")
                                Text("WhatsApp Web con Swipe Down (Quick Reply)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.15, green: 0.78, blue: 0.45))
                        
                        Button(action: {
                            let contact = ContactLookupService.shared.fetchFirstContactWithPhoto()
                            let contactName = contact?.name ?? "Carlos"
                            let contactAvatar = contact?.avatar ?? ContactLookupService.shared.generateMonogramAvatar(for: "Carlos", initials: "CA")
                            
                            NotificationActivityProvider.shared.showNotification(
                                title: contactName,
                                message: "¡Bro! ¿Ya viste cómo quedó el reproductor y las llamadas? 🚀",
                                avatar: contactAvatar,
                                appIcon: "message.fill",
                                appName: "WhatsApp Web",
                                tint: Color(red: 0.15, green: 0.78, blue: 0.45),
                                enableQuickReply: true,
                                duration: 15.0
                            )
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("WhatsApp Web con Foto Real y Quick Reply")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: 12)
                        }) {
                            HStack {
                                Image(systemName: "battery.25")
                                Text("Alerta de Batería Baja (12%)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.red)
                    }
                    .padding(6)
                }
                
                // TEMPORIZADORES (MINUTKA)
                GroupBox("Temporizadores Estilo Dynamic Island (Minutka)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: {
                                TimerActivityProvider.shared.startTimer(duration: 30, title: "Minutka", asCard: false)
                            }) {
                                HStack {
                                    Image(systemName: "timer")
                                    Text("Píldora (30s)")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.orange)
                            
                            Button(action: {
                                TimerActivityProvider.shared.startTimer(duration: 30, title: "Minutka", asCard: true)
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.inset.filled")
                                    Text("Tarjeta Card (30s)")
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            if TimerActivityProvider.shared.isRunning {
                                Button("Cancelar") {
                                    TimerActivityProvider.shared.cancelTimer()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(6)
                }
                
                // AIRPODS 3D ANIMATION DEMO
                GroupBox("Animación AirPods 3D (SceneKit)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            let details = BluetoothAudioService.shared.queryConnectedAirPods()
                            let name = details?.deviceName ?? "AirPods de Luis Angel"
                            let bat = details?.primaryBattery ?? 45
                            AirPodsActivityProvider.shared.publishAirPodsActivity(
                                name: name,
                                batteryLevel: bat,
                                leftPercent: details?.leftBattery,
                                rightPercent: details?.rightBattery,
                                casePercent: details?.caseBattery,
                                duration: 4.5
                            )
                        }) {
                            HStack {
                                Image(systemName: "airpodsmax")
                                Text("Disparar Animación 3D de AirPods (con datos reales)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.cyan)
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
        .onAppear {
            contactService.checkCurrentStatus()
        }
    }
}
