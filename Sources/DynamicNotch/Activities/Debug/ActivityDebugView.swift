import SwiftUI

public struct ActivityDebugView: View {
    @ObservedObject var center = ActivityCenter.shared
    @ObservedObject var debugOverlay = DebugOverlayManager.shared
    @ObservedObject var speedManager = AnimationSpeedManager.shared
    @ObservedObject var volumeInterceptor = VolumeInterceptorService.shared
    @ObservedObject var glassManager = GlassClearManager.shared
    @ObservedObject var contactService = ContactLookupService.shared
    @ObservedObject var appState = AppState.shared
    
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
                                if center.expandedActivity?.id == current.id {
                                    center.collapseExpandedActivity()
                                }
                                if current.id == "live_timer" || current.id == "sim_timer" {
                                    TimerActivityProvider.shared.cancelTimer()
                                }
                                if current.id == AgentActivityProvider.shared.progressActivityId {
                                    AgentActivityProvider.shared.dismissProgress()
                                }
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
                
                // MARK: - SISTEMA COMPLETO DE LIVE ACTIVITIES, BOLITAS Y FUSIÓN LÍQUIDA
                GroupBox("Sistema de Live Activities, Bolitas y Fusión Líquida") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Modos de Presentación
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Modo de Presentación:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Picker("", selection: $appState.multiActivityMode) {
                                ForEach(MultiActivityPresentationMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Ubicación de las Bolitas
                        HStack {
                            Text("Ubicación Bolitas:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Picker("", selection: $appState.satelliteLocation) {
                                ForEach(SatelliteLocationPreference.allCases) { loc in
                                    Text(loc.title).tag(loc)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }
                        
                        // Tamaño de las Bolitas
                        HStack {
                            Text("Tamaño de Bolitas:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Picker("", selection: $appState.bolitaDiameter) {
                                Text("Mini (24 pt)").tag(CGFloat(24.0))
                                Text("Apple Nativa (26 pt)").tag(CGFloat(26.0))
                                Text("Mediana (28 pt)").tag(CGFloat(28.0))
                                Text("Original (32 pt)").tag(CGFloat(32.0))
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }
                        
                        // Máximo de Bolitas Visibles
                        HStack {
                            Text("Máx. Bolitas Visibles:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Stepper("\(appState.maxSatelliteBolitas) bolitas", value: $appState.maxSatelliteBolitas, in: 1...4)
                                .font(.system(size: 11, weight: .bold))
                        }
                        
                        // Multiplicador de Velocidad de Animación (0.2x para inspeccionar la fusión)
                        HStack {
                            Text("Inspección de Fusión:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Button(speedManager.speedMultiplier < 0.5 ? "Cámara Lenta (0.2x) 🐢" : "Velocidad Normal (1.0x) ⚡️") {
                                if speedManager.speedMultiplier < 0.5 {
                                    speedManager.speedMultiplier = 1.0
                                } else {
                                    speedManager.speedMultiplier = 0.2
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(speedManager.speedMultiplier < 0.5 ? .purple : .secondary)
                        }
                        
                        Divider()
                        
                        // Lanzador de 5 Actividades Simuladas
                        Text("Actividades Simuladas Individuales:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Button("📞 Llamada (Verde)") {
                                    launchCallActivity()
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                                
                                Button("⏱ Temporizador (15m)") {
                                    launchTimerActivity()
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }
                            
                            HStack(spacing: 6) {
                                Button("✨ Antigravity AI (Morado)") {
                                    launchAIActivity()
                                }
                                .buttonStyle(.bordered)
                                .tint(.purple)
                                
                                Button("🔴 Grabación (Roja)") {
                                    launchRecordingActivity()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            
                            Button("🌐 VPN WireGuard (Azul)") {
                                launchVPNActivity()
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                        
                        Divider()
                        
                        // Pruebas avanzadas
                        VStack(spacing: 6) {
                            Button("🚀 Iniciar las 5 Actividades (+N Desbordamiento)") {
                                launchAllFiveActivities()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            
                            HStack(spacing: 6) {
                                Button("⚡️ Simular Temporizador Urgente") {
                                    launchTimerActivity(isUrgent: true)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                
                                Button("🗑 Descartar Todas") {
                                    center.collapseExpandedActivity()
                                    TimerActivityProvider.shared.cancelTimer()
                                    AgentActivityProvider.shared.dismissProgress()
                                    for act in center.activeActivities {
                                        center.remove(id: act.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(8)
                }
                
                // MARK: - PASO 1: CONFIRMACIÓN DE CRISTAL NATIVO Y SUPERFICIES
                GroupBox("Superficies y API Activa de Cristal (Paso 1)") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Píldora del Notch:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text(AppState.shared.effectiveAppearanceMode == .pureOLED ? "Color.black (OLED Puro)" : ".glassEffect(.regular) + .darkAqua Nativo")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppState.shared.effectiveAppearanceMode == .pureOLED ? .secondary : .cyan)
                        }
                        HStack {
                            Text("Tarjetas Expandidas:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text(".glassEffect(.regular) Nativo (Glass.regular)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        HStack {
                            Text("Pantalla de Bloqueo:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text("NSGlassEffectView (AppKit)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                        HStack {
                            Text("Ventana de Ajustes:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text("NSVisualEffectView (.underWindowBackground)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $glassManager.showRefractionTestPattern) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Patrón de Prueba de Refracción (Franjas + Texto)")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Proyecta franjas diagonales de alto contraste y texto detrás de la píldora para verificar refracción óptica y brillo especular.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
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
                        
                        // Slider Transparencia (Mínimo 18% a 45%)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Atenuación Uniforme (Mínimo 18% garantizado):")
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                                Text("\(Int(round(glassManager.uniformScrimOpacity * 100)))%")
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            }
                            Slider(
                                value: Binding(
                                    get: { max(18.0, glassManager.uniformScrimOpacity * 100) },
                                    set: { glassManager.uniformScrimOpacity = max(0.18, $0 / 100.0) }
                                ),
                                in: 18...45,
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
                        VStack(spacing: 8) {
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
                                    if let contact = ContactLookupService.shared.fetchFirstContactWithPhoto() {
                                        CallActivityProvider.shared.startIncomingCall(
                                            name: "Llamada celular de iPhone",
                                            handle: contact.name,
                                            avatar: contact.avatar,
                                            isSimulation: true
                                        )
                                    } else {
                                        let sampleMonogram = ContactLookupService.shared.generateMonogramAvatar(for: "Ana García", initials: "AG")
                                        CallActivityProvider.shared.startIncomingCall(
                                            name: "Llamada celular de iPhone",
                                            handle: "Ana García",
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
                                
                                if CallActivityProvider.shared.isCallActive || CallActivityProvider.shared.isIncomingCall {
                                    Button("Colgar") {
                                        CallActivityProvider.shared.endCall()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 8) {
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
                                
                                Spacer()
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
                            
                            Spacer()
                        }
                        
                        Text(contactService.isAuthorized ? "✅ Contactos autorizados" : "⚠️ Contactos pendientes de permiso")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(contactService.isAuthorized ? DesignTokens.green : DesignTokens.orange)
                        
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
                                duration: 5.5
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
                                duration: 5.5
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
                
                // AIRPODS WING ANIMATION DEMO
                GroupBox("Animación de AirPods (Alas del Notch)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: {
                                let details = BluetoothAudioService.shared.queryConnectedAirPods()
                                let name = details?.deviceName ?? "AirPods"
                                let bat = details?.primaryBattery ?? 85
                                AirPodsActivityProvider.shared.publishAirPodsActivity(
                                    name: name,
                                    batteryLevel: bat,
                                    leftPercent: details?.leftBattery,
                                    rightPercent: details?.rightBattery,
                                    casePercent: details?.caseBattery,
                                    duration: 13.0
                                )
                            }) {
                                HStack {
                                    Image(systemName: "airpods")
                                    Text("Disparar Animación de AirPods en el Notch (13s)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.green)
                            
                            if center.currentActivity?.id == AirPodsActivityProvider.shared.providerId || center.activeActivities.contains(where: { $0.id == AirPodsActivityProvider.shared.providerId }) {
                                Button("Cerrar") {
                                    center.remove(id: AirPodsActivityProvider.shared.providerId)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(6)
                }
                
                // 4) INSPECCIÓN VISUAL (OVERLAY DE COMPARACIÓN PIXEL-PERFECT)
                // Cada modelo y color con su animación oficial (sin tocar los AirPods conectados)
                AirPodsAnimationTestBench()

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
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .onAppear {
            contactService.checkCurrentStatus()
        }
    }
    
    // MARK: - Métodos de Simulación de Live Activities y Fusión
    
    private func launchTimerActivity(isUrgent: Bool = false) {
        let duration: TimeInterval = isUrgent ? 60 : 900
        TimerActivityProvider.shared.startTimer(duration: duration, title: "Temporizador", asCard: isUrgent)
    }
    
    private func launchCallActivity() {
        let call = LiveActivity(
            id: "sim_call",
            kind: .call,
            priority: 900,
            style: .pill,
            state: .active,
            title: "FaceTime Audio",
            subtitle: "Mamá • 08:32",
            leading: AnyView(
                HStack(spacing: 5) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.green)
                    Text("08:32")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            ),
            trailing: AnyView(
                Image(systemName: "waveform")
                    .foregroundColor(.green)
            ),
            bolitaVariant: .color(bgColor: Color(red: 0.18, green: 0.80, blue: 0.44), fgColor: .white, iconName: "phone.fill"),
            expandedView: AnyView(
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mamá")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text("FaceTime Audio • 08:32")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            center.collapseExpandedActivity()
                            center.remove(id: "sim_call")
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Colgar llamada")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 36) // Despeje holgado para el notch físico de la Mac
                .padding(.bottom, 18)
            ),
            customExpandedWidth: 420,
            customExpandedHeight: 114
        )
        center.publish(call)
    }
    
    private func launchRecordingActivity() {
        let rec = LiveActivity(
            id: "sim_rec",
            kind: .recording,
            priority: 880,
            style: .pill,
            state: .active,
            title: "Grabación de Pantalla",
            subtitle: "01:45",
            leading: AnyView(
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("REC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                }
            ),
            trailing: AnyView(
                Text("01:45")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            ),
            bolitaVariant: .color(bgColor: Color(red: 0.95, green: 0.26, blue: 0.21), fgColor: .white, iconName: "record.circle"),
            expandedView: AnyView(
                HStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grabación de Pantalla Activa")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Duración: 01:45 • Pantalla Integrada")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        center.collapseExpandedActivity()
                        center.remove(id: "sim_rec")
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 36, height: 36)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Detener grabación")
                }
                .padding(.horizontal, 22)
                .padding(.top, 36) // Despeje holgado para el notch físico de la Mac
                .padding(.bottom, 18)
            ),
            customExpandedWidth: 420,
            customExpandedHeight: 112
        )
        center.publish(rec)
    }
    
    private func launchVPNActivity() {
        let vpn = LiveActivity(
            id: "sim_vpn",
            kind: .vpn,
            priority: 650,
            style: .pill,
            state: .active,
            title: "VPN WireGuard",
            subtitle: "Zurich, CH",
            leading: AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.blue)
                    Text("VPN")
                        .font(.system(size: 11, weight: .bold))
                }
            ),
            trailing: AnyView(
                Text("ON")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue)
            ),
            bolitaVariant: .color(bgColor: Color(red: 0.15, green: 0.55, blue: 0.98), fgColor: .white, iconName: "network"),
            expandedView: AnyView(
                HStack {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VPN Conectada")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Servidor: Zurich (WireGuard) • 42 ms")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        center.collapseExpandedActivity()
                        center.remove(id: "sim_vpn")
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: "power")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Desconectar VPN")
                }
                .padding(.horizontal, 22)
                .padding(.top, 36) // Despeje holgado para el notch físico de la Mac
                .padding(.bottom, 18)
            ),
            customExpandedWidth: 420,
            customExpandedHeight: 112
        )
        center.publish(vpn)
    }
    
    private func launchAIActivity() {
        let steps = [
            AgentLiveStep(title: "Read NotchContainerView.swift", isCompleted: true),
            AgentLiveStep(title: "Edit NotchBolitaView.swift", isCompleted: true),
            AgentLiveStep(title: "Morphing Fusion Transition", isCompleted: false, isActive: true),
            AgentLiveStep(title: "Build and Validate", isCompleted: false)
        ]
        let diff = AgentFileDiff(
            filename: "NotchBolitaView.swift",
            additions: 84,
            deletions: 12,
            statusText: "Morphing...",
            progress: 0.68
        )
        let payload = AgentLiveProgressPayload(
            agentName: "Antigravity",
            taskName: "Live Activities & Bolitas",
            steps: steps,
            fileDiff: diff,
            isCompleted: false
        )
        AgentActivityProvider.shared.showProgress(payload: payload)
    }
    
    private func launchAllFiveActivities() {
        launchCallActivity()
        launchTimerActivity()
        launchAIActivity()
        launchRecordingActivity()
        launchVPNActivity()
    }
}
