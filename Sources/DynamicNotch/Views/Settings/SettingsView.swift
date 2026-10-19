import SwiftUI

public struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var volumeInterceptor = VolumeInterceptorService.shared
    @ObservedObject var spectrumEngine = AudioSpectrumEngine.shared
    @ObservedObject var whatsAppObserver = WhatsAppWebObserverService.shared
    @ObservedObject var messagesObserver = MessagesObserverService.shared
    @ObservedObject var callDetector = CallDetectorService.shared
    @ObservedObject var timerProvider = TimerActivityProvider.shared
    @ObservedObject var lockScreenBridge = LockScreenSkyLightBridge.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    
    /// Pestaña con la que se abre (diagnóstico: /debug/settings-snapshot la cambia)
    public static var initialTab: SettingsTab = .appearance
    @State private var selectedTab: SettingsTab = SettingsView.initialTab
    @State private var noiseGateDB: Double = Double(SpectrumMetrics.noiseGateDB)
    
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance = "Apariencia"
        case gestures = "Gestos"
        case activities = "Actividades"
        case shelf = "Drag & Drop"
        case media = "Multimedia"
        case miniApps = "Mini-Apps"
        case system = "Sistema"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .appearance: return "sparkles"
            case .gestures: return "hand.tap"
            case .activities: return "circle.grid.2x1.fill"
            case .shelf: return "tray.and.arrow.down.fill"
            case .media: return "play.circle"
            case .miniApps: return "square.grid.2x2.fill"
            case .system: return "gearshape"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header con pestañas estilo macOS Sequoia
            HStack(spacing: 5) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Capsule().fill(Color.primary.opacity(0.12))
                                : Capsule().fill(Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.70))
            
            Divider()
                .opacity(0.4)
            
            // Contenido de la pestaña
            ScrollView {
                VStack(spacing: 18) {
                    switch selectedTab {
                    case .appearance:
                        appearanceSection
                        appearanceExtras
                    case .gestures:
                        gesturesSection
                        gesturesExtras
                    case .activities:
                        activitiesSection
                    case .shelf:
                        shelfSection
                    case .media:
                        mediaSection
                        ToggleRow(
                            title: "Barras al tempo de la canción con audio protegido",
                            subtitle: "macOS entrega silencio con contenido protegido (Apple Music, Safari con DRM). En ese caso las barras laten al BPM real de la canción, calculado con su avance de iTunes.",
                            isOn: $appState.tempoFallbackEnabled
                        )
                    case .miniApps:
                        miniAppsSection
                    case .system:
                        ToggleRow(
                            title: "Reemplazar los avisos nativos de AirDrop",
                            subtitle: "Cierra el aviso de macOS y la ventana de Descargas que se abre sola; el notch muestra su propia animación de envío y recepción.",
                            isOn: $appState.airDropReplacesNative
                        )
                        systemSection
                    }
                }
                .padding(24)
            }
        }
        // 7 pestañas: ancho suficiente para leer sus nombres completos
        .frame(width: 800, height: 560)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow, state: .active))
    }
    
    // MARK: - Sección Apariencia
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Estilo Visual del Notch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                        Text("Reducción de transparencia activa")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignTokens.orange)
                    }
                }
                
                HStack(spacing: 12) {
                    // Opción 1: Negro Puro OLED
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            appState.appearanceMode = .pureOLED
                        }
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black)
                                    .frame(height: 70)
                                    .overlay(
                                        Capsule()
                                            .fill(Color.white.opacity(0.18))
                                            .frame(width: 44, height: 12)
                                    )
                                
                                if appState.appearanceMode == .pureOLED {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DesignTokens.blue, lineWidth: 2.5)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                            }
                            
                            VStack(spacing: 1) {
                                Text("Negro Puro OLED")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(appState.appearanceMode == .pureOLED ? .primary : .secondary)
                                Text("(Fundido con cámara)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    // Opción 2: Cristal Oscuro (Dark Glass - Por Defecto)
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            appState.appearanceMode = .darkGlass
                        }
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.black.opacity(0.75), Color.black.opacity(0.92)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 70)
                                    .overlay(
                                        Capsule()
                                            .fill(Color.white.opacity(0.35))
                                            .frame(width: 44, height: 12)
                                    )
                                
                                if appState.appearanceMode == .darkGlass {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DesignTokens.blue, lineWidth: 2.5)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                            }
                            
                            VStack(spacing: 1) {
                                Text("Cristal Oscuro")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(appState.appearanceMode == .darkGlass ? .primary : .secondary)
                                Text("(Por defecto • Alto contraste)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    // Opción 3: Cristal Claro (Clear Glass)
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            appState.appearanceMode = .clearGlass
                        }
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 70)
                                    .overlay(
                                        Capsule()
                                            .fill(Color.black.opacity(0.20))
                                            .frame(width: 44, height: 12)
                                    )
                                
                                if appState.appearanceMode == .clearGlass {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DesignTokens.blue, lineWidth: 2.5)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                            }
                            
                            VStack(spacing: 1) {
                                Text("Cristal Claro")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(appState.appearanceMode == .clearGlass ? .primary : .secondary)
                                Text("(Opcional • Fondos oscuros)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                
                if appState.appearanceMode == .clearGlass {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Aviso: Pensado para fondos oscuros o de foto. En páginas web o fondos completamente blancos puede reducir el contraste de lectura.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }
                
                if appState.appearanceMode == .darkGlass {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Opacidad del Tinte Oscuro")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("Modula el tinte de Glass.regular: 0% (cristal oscuro adaptativo puro) hasta 85% (cristal profundo).")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            RollingNumberView(
                                value: Int(round(appState.glassDarknessOpacity * 100)),
                                suffix: "%",
                                font: .system(size: 12, weight: .bold, design: .rounded),
                                color: .primary
                            )
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(round(appState.glassDarknessOpacity * 100)) },
                                set: { appState.glassDarknessOpacity = min(0.85, max(0.0, $0 / 100.0)) }
                            ),
                            in: 0...85,
                            step: 1
                        )
                        .tint(DesignTokens.blue)
                    }
                    .padding(.top, 4)
                }
                
                if appState.appearanceMode == .clearGlass {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Atenuación Mínima (Slider Transparencia)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("0% = Glass.clear nativo 100% puro sin velo oscuro; sube hasta 45% para añadir contraste en fondos muy blancos.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            RollingNumberView(
                                value: Int(round(GlassClearManager.shared.uniformScrimOpacity * 100)),
                                suffix: "%",
                                font: .system(size: 12, weight: .bold, design: .rounded),
                                color: .primary
                            )
                        }
                        
                        Slider(
                            value: Binding(
                                get: { max(0.0, round(GlassClearManager.shared.uniformScrimOpacity * 100)) },
                                set: { GlassClearManager.shared.uniformScrimOpacity = min(0.45, max(0.0, $0 / 100.0)) }
                            ),
                            in: 0...45,
                            step: 1
                        )
                        .tint(DesignTokens.blue)
                        
                        HStack {
                            Toggle(isOn: Binding(
                                get: { GlassClearManager.shared.enableAutoWallpaperLuminance },
                                set: { GlassClearManager.shared.enableAutoWallpaperLuminance = $0 }
                            )) {
                                Text("Adaptar al fondo de pantalla (solo sube atenuación en fondos claros)")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.primary)
                            }
                            .toggleStyle(.checkbox)
                            
                            Spacer()
                            
                            if GlassClearManager.shared.enableAutoWallpaperLuminance {
                                Text("Luminosidad: \(Int(round(GlassClearManager.shared.detectedWallpaperLuminance * 100)))%")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: {
                            ActivityDebugWindow.shared.show()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Abrir Bisección de Capas y Debug")
                            }
                            .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .padding(.top, 4)
                }
                
                // Avisos del Sistema
                if GlassClearManager.shared.isReduceTransparencyActive {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("«Reducir transparencia» está activo en macOS")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Por accesibilidad del sistema, el efecto Liquid Glass se desactiva y cae automáticamente al modo Negro Puro OLED.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
                }
                
                if GlassClearManager.shared.isSystemLiquidGlassTinted {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Liquid Glass Tintado por el Sistema")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.primary)
                            Text("macOS tiene configurado un color de acento o modo tintado en Ajustes. El cristal adoptará un leve tinte por decisión del sistema.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15)))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Nueva Tarjeta: Comportamiento de Expansión y Sombra en Hover
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.blue)
                    Text("Expansión y Sombra al Pasar el Cursor (Hover)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Toggle("", isOn: $appState.enableHoverExpansion)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                
                Text("Al posar el cursor sobre el Notch, la píldora se expande suavemente con una sombra profunda y constante mientras el cursor permanece encima, volviendo a su tamaño original al salir.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if appState.enableHoverExpansion {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Escala de crecimiento en Hover")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("+\(String(format: "%.1f", (appState.hoverScaleAmount - 1.0) * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(DesignTokens.blue)
                        }
                        Slider(value: $appState.hoverScaleAmount, in: 1.01...1.08, step: 0.005)
                            .tint(DesignTokens.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Profundidad de sombra flotante")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            RollingNumberView(
                                value: Int(round(appState.hoverShadowIntensity * 100)),
                                suffix: "%",
                                font: .system(size: 12, weight: .bold, design: .rounded),
                                color: DesignTokens.blue
                            )
                        }
                        Slider(value: $appState.hoverShadowIntensity, in: 0.20...1.0, step: 0.05)
                            .tint(DesignTokens.blue)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Sección Gestos
    private var gesturesSection: some View {
        VStack(spacing: 12) {
            ToggleRow(
                title: "Deslizar con 2 dedos en Trackpad",
                subtitle: "Cambia rápidamente entre el reproductor y la bandeja de archivos con un swipe horizontal",
                isOn: $appState.enableTrackpadSwipe
            )
            
            ToggleRow(
                title: "Expandir automáticamente al acercar el cursor",
                subtitle: "Despliega el panel completo del Notch sin hacer clic al acercar el cursor a la cámara",
                isOn: $appState.expandOnHover
            )
            
            ToggleRow(
                title: "Vibración Háptica en Trackpad",
                subtitle: "Siente un clic físico de confirmación al arrastrar archivos, cambiar canciones o interactuar",
                isOn: $appState.enableHaptics
            )
            
            ToggleRow(
                title: "Sonido inmersivo al regular volumen",
                subtitle: "Reproduce el sonido clásico de macOS con retroalimentación instantánea",
                isOn: $appState.enableSoundFeedback
            )
            
            ToggleRow(
                title: "Contraer al salir el cursor",
                subtitle: "Regresa al modo compacto o reposo cuando el cursor abandona el área del Notch",
                isOn: $appState.autoCollapseOnHoverExit
            )
        }
    }
    
    // MARK: - Sección Drag & Drop (Repisa Inteligente)
    private var shelfSection: some View {
        VStack(spacing: 16) {
            // Hero Card descriptiva
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.blue)
                    Text("Repisa y Drag & Drop Inteligente")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.primary)
                }
                Text("Arrastra cualquier archivo desde Finder o el escritorio hacia el Notch para custodiarlos temporalmente, transferirlos entre ventanas o mantener tu pantalla limpia.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Grupo 1: Detección Magnética por Proximidad
            VStack(alignment: .leading, spacing: 12) {
                ToggleRow(
                    title: "Apertura magnética al acercar archivos",
                    subtitle: "Despliega automáticamente una tarjeta de invitación cuando arrastras archivos cerca del Notch",
                    isOn: $appState.enableDropInvitation
                )
                
                if appState.enableDropInvitation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Distancia de atracción magnética")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("Radio en puntos para despertar el Notch al arrastrar")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(Int(appState.dropInvitationDistance)) pt")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(DesignTokens.blue)
                        }
                        
                        Slider(
                            value: $appState.dropInvitationDistance,
                            in: 80...260,
                            step: 5
                        )
                        .tint(DesignTokens.blue)
                        
                        HStack {
                            Text("Cercana (80 pt)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                            Spacer()
                            Text("Estándar (175 pt)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                            Spacer()
                            Text("Amplia (260 pt)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
            
            // Grupo 2: Opciones de Gestión de Archivos
            VStack(spacing: 12) {
                ToggleRow(
                    title: "Mover archivos a la repisa (Limpiar escritorio)",
                    subtitle: "Al soltar archivos en el Notch, desaparecen del escritorio y se custodian en la repisa. Puedes devolverlos con 1 clic",
                    isOn: $appState.moveFilesToShelf
                )
                
                ToggleRow(
                    title: "Abrir la repisa automáticamente al soltar",
                    subtitle: "Despliega la pestaña de archivos en el Notch de inmediato al recibir un drop exitoso",
                    isOn: $appState.autoOpenShelfOnDrop
                )
                
                ToggleRow(
                    title: "Mostrar contador en el Notch en reposo",
                    subtitle: "Muestra una discreta insignia junto a la cámara cuando hay archivos en custodia",
                    isOn: $appState.showShelfBadgeInNotch
                )
                
                ToggleRow(
                    title: "Vibración háptica en Drag & Drop",
                    subtitle: "Emite un clic táctil en el Trackpad al capturar, mover o devolver archivos a su origen",
                    isOn: $appState.enableShelfHaptics
                )
            }
            
            // Grupo 3: Almacenamiento y Acciones Rápidas
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Estado del Almacenamiento")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(appState.shelfItems.count) \(appState.shelfItems.count == 1 ? "archivo custodiado" : "archivos custodiados") • \(ShelfStorageService.shared.totalStashedSizeString())")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button(action: {
                        ShelfStorageService.shared.selectAndAddFiles()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Añadir...")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack(spacing: 8) {
                    Button(action: {
                        ShelfStorageService.shared.openStashFolderInFinder()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("Abrir en Finder")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    
                    if !appState.shelfItems.isEmpty {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                                appState.restoreAllShelfItemsToOrigin()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Devolver todo al origen")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                                appState.emptyShelfToTrash()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Vaciar")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red.opacity(0.85))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Grupo 4: Diagnóstico y Sonda en Tiempo Real
            Button(action: {
                DragProbeDebugWindowController.shared.toggleWindow()
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(
                                colors: [DesignTokens.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sonda de Detección Drag & Drop en Vivo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Monitorea coordenadas, proximidad euclidiana y eventos de NSPasteboard (0% CPU en reposo).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Sección Multimedia
    private var mediaSection: some View {
        VStack(spacing: 14) {
            ToggleRow(
                title: "Mostrar mini píldora durante la reproducción",
                subtitle: "Muestra la carátula y el visualizador animado junto al Notch mientras escuchas música",
                isOn: $appState.showCompactWhenPlaying
            )
            
            ToggleRow(
                title: "Animación 3D de AirPods",
                subtitle: "Muestra la animación PBR de estudio y el estado de batería al conectar AirPods",
                isOn: $appState.enableAirPodsAnimation
            )
            
            ToggleRow(
                title: "Barras que siguen la música",
                subtitle: "Escucha el audio del sistema sólo mientras reproduces música o video, para que las barras sigan el sonido real. Mientras tanto macOS muestra el indicador morado; al pausar se apaga. No se graba ni se guarda nada, y el micrófono nunca se usa. Apagado: animación sin audio.",
                isOn: Binding(
                    get: { spectrumEngine.realAudioBarsEnabled },
                    set: { spectrumEngine.setRealAudioBarsEnabled($0) }
                )
            )
            
            visualizerStyleAndCalibrationCard
            
            // Acceso al Monitor de Audio en Tiempo Real
            Button(action: {
                AudioSpectrumTestWindowController.shared.show()
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(
                                colors: [PlayerMetrics.visualizerTopGradient, PlayerMetrics.visualizerBottomGradient],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abrir Laboratorio de Espectro FFT (6 y 10 Bandas)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Visualiza picos dBFS, Peak Hold y calibra ganancia, ataque y caída por banda.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            lockScreenViabilityCard
        }
    }
    
    private var lockScreenViabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 15, weight: .bold))
                Text("Pantalla de Bloqueo: Viabilidad SkyLight (Paso 0)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                if lockScreenBridge.isSupported {
                    Text("SkyLight SPIs ✅")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                } else {
                    Text("Kill Switch ❌")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                }
            }
            
            ToggleRow(
                title: "Reproductor en Pantalla de Bloqueo",
                subtitle: "Muestra controles y carátula grande bajo el reloj de macOS al bloquear",
                isOn: $appState.enableLockScreenPlayer
            )
            
            if appState.enableLockScreenPlayer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diseño del Reproductor")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Picker("", selection: $appState.lockScreenStyle) {
                        Text("Hero (iOS)").tag(AppState.LockScreenStyle.heroWidget)
                        Text("Compacta").tag(AppState.LockScreenStyle.compactCard)
                        Text("Ambient Canvas").tag(AppState.LockScreenStyle.ambientCanvas)
                    }
                    .pickerStyle(.segmented)
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            AmbientCanvasWindowManager.shared.toggleCanvas()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "music.quarternote.3")
                                Text("Canvas Música (Imagen 1)")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: {
                            AgentActivityProvider.shared.showProgress(payload: AgentLiveProgressPayload())
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text("Monitor IA Notch (Imagen 2)")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modo de Renderizado Liquid Glass (Paso 3)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Picker("", selection: $appState.lockScreenRenderMode) {
                        ForEach(AppState.LockScreenRenderMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 4)
                
                ToggleRow(
                    title: "Ocultar detalles por privacidad",
                    subtitle: "Oculta la carátula y los nombres de canciones en la pantalla bloqueada",
                    isOn: $appState.lockScreenHideMediaDetails
                )
                
                ToggleRow(
                    title: "Halo ambiental de carátula",
                    subtitle: "Proyecta un resplandor atmosférico suave con el color dominante de la canción",
                    isOn: $appState.lockScreenShowArtworkHalo
                )
                
                ToggleRow(
                    title: "Control de volumen",
                    subtitle: "Muestra un deslizador interactivo de volumen en la tarjeta de bloqueo",
                    isOn: $appState.lockScreenShowVolumeSlider
                )
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Ajuste vertical bajo el reloj")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int(appState.lockScreenVerticalOffset)) pt")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    Slider(value: Binding(
                        get: { Double(appState.lockScreenVerticalOffset) },
                        set: { appState.lockScreenVerticalOffset = CGFloat($0) }
                    ), in: -200.0...200.0, step: 5.0)
                    .tint(.cyan)
                }
                .padding(.horizontal, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Tiempo visible tras pausar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(appState.lockScreenPauseTimeoutSeconds) s")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    Slider(value: Binding(
                        get: { Double(appState.lockScreenPauseTimeoutSeconds) },
                        set: { appState.lockScreenPauseTimeoutSeconds = Int($0) }
                    ), in: 5.0...60.0, step: 5.0)
                    .tint(.cyan)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Atenuación uniforme de fondo")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        RollingNumberView(
                            value: Int(round(appState.lockScreenDimmingOpacity * 100)),
                            suffix: "%",
                            font: .system(size: 12, weight: .bold, design: .monospaced),
                            color: .cyan
                        )
                    }
                    Slider(value: $appState.lockScreenDimmingOpacity, in: 0.10...0.35, step: 0.01)
                    .tint(.cyan)
                }
                .padding(.horizontal, 4)
                
                ToggleRow(
                    title: "Modo Debug de contornos",
                    subtitle: "Dibuja contornos de colores en ventana, silueta y capas para comprobar la geometría",
                    isOn: $appState.lockScreenDebugOutlines
                )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnóstico:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(lockScreenBridge.diagnosticStatus)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.9))
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            
            HStack(spacing: 10) {
                // Botón de prueba en pantalla de bloqueo con cuenta atrás
                if lockScreenManager.testCountdownSeconds > 0 {
                    Button(action: {
                        lockScreenManager.cancelArmedTest()
                    }) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Bloquea en \(lockScreenManager.testCountdownSeconds)s (⌘⌃Q) • Cancelar")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.yellow)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        lockScreenManager.startCountdownAndArmLockScreenTest(seconds: 4)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.circle.fill")
                            Text("Probar en pantalla de bloqueo (⌘⌃Q)")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(Color.cyan.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
                
                // Previsualizar reproductor en escritorio
                Button(action: {
                    if lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode {
                        lockScreenManager.hidePlayerPanelPreview()
                    } else {
                        lockScreenManager.showPlayerPanelPreview(duration: 10)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode ? "eye.slash" : "eye")
                        Text(lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode ? "Cerrar previsualización" : "Previsualizar reproductor (10 s)")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                
                if lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode {
                    Button(action: {
                        lockScreenManager.hidePlayerPanelPreview()
                    }) {
                        Text("Ocultar")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var visualizerStyleAndCalibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.pink)
                Text("Estilo y Respuesta del Visualizador de Audio")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Paleta de color de las barras")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(VisualizerColorStyle.allCases) { style in
                        visualizerStyleButton(for: style)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Preset de balística FFT")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(SpectrumResponsePreset.allCases) { preset in
                        spectrumPresetButton(for: preset)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Umbral de Silencio (Noise Gate)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(Int(noiseGateDB)) dBFS")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                Slider(
                    value: Binding(
                        get: { noiseGateDB },
                        set: { newVal in
                            noiseGateDB = newVal
                            SpectrumMetrics.noiseGateDB = Float(newVal)
                        }
                    ),
                    in: -65...(-30),
                    step: 1
                )
                .tint(.cyan)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func visualizerStyleButton(for style: VisualizerColorStyle) -> some View {
        let isSelected = appState.visualizerColorStyle == style
        let fillOpacity: Double = isSelected ? 0.32 : 0.45
        let fillColor: Color = isSelected ? DesignTokens.blue.opacity(fillOpacity) : Color(NSColor.controlBackgroundColor).opacity(fillOpacity)
        let strokeColor: Color = isSelected ? DesignTokens.blue : Color.primary.opacity(0.10)
        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appState.visualizerColorStyle = style
            }
        }) {
            Text(style.title)
                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fillColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(strokeColor, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    private func spectrumPresetButton(for preset: SpectrumResponsePreset) -> some View {
        Button(action: {
            SpectrumMetrics.applyPreset(preset)
            noiseGateDB = Double(SpectrumMetrics.noiseGateDB)
            appState.hapticService.triggerSnap()
        }) {
            VStack(spacing: 2) {
                Text(preset.shortTitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(preset.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sección Banco de Mini-Apps
    private var miniAppsSection: some View {
        VStack(spacing: 16) {
            // Descripción del Banco de Mini-Apps
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DesignTokens.orange)
                    Text("Banco de Mini-Apps del Notch")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.primary)
                }
                Text("Las Mini-Apps se ejecutan como overlays instantáneos dentro del Notch y como Live Activities en el Dynamic Island, manteniendo la navegación principal del Notch minimalista de solo 2 páginas (Música y Bandeja).")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Accesos rápidos fijados en la esquina superior derecha del Notch
            VStack(spacing: 10) {
                ToggleRow(
                    title: "Fijar icono de Cronómetro / Temporizador en el Notch",
                    subtitle: "Muestra un botón de acceso rápido en la esquina superior derecha del reproductor",
                    isOn: $appState.pinTimerMiniAppInNotch
                )
                
                ToggleRow(
                    title: "Fijar icono del Monitor de Audio FFT en el Notch",
                    subtitle: "Permite abrir el analizador de espectro de 10 bandas en vivo con 1 clic desde el Notch",
                    isOn: $appState.pinAudioMonitorMiniAppInNotch
                )
            }
            
            // Tarjeta Mini-App 1: Cronómetro & Temporizador Pomodoro
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.orange.opacity(0.22))
                            .frame(width: 34, height: 34)
                        Image(systemName: timerProvider.mode.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(DesignTokens.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cronómetro & Temporizador Pomodoro")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Text(timerProvider.hasActiveSession ? "En curso: \(timerProvider.formattedDuration) (\(timerProvider.mode.title))" : "Cuenta atrás con presets rápidos y cronómetro con registro de vueltas")
                            .font(.system(size: 11))
                            .foregroundColor(timerProvider.hasActiveSession ? DesignTokens.orange : .secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.openWithMiniApp(.timer)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("Abrir en Notch")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.orange)
                    .controlSize(.small)
                }
                
                // Lanzadores rápidos desde Ajustes
                HStack(spacing: 8) {
                    Button("1 min") { timerProvider.startTimer(duration: 60, title: "Temporizador 1m", asCard: false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("5 min") { timerProvider.startTimer(duration: 300, title: "Temporizador 5m", asCard: false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("15 min") { timerProvider.startTimer(duration: 900, title: "Temporizador 15m", asCard: false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("25m Pomodoro 🍅") { timerProvider.startTimer(duration: 1500, title: "Pomodoro 25m", asCard: false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Iniciar Cronómetro") { timerProvider.startStopwatch(asCard: false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    
                    if timerProvider.hasActiveSession {
                        Spacer()
                        Button(timerProvider.isRunning ? "Pausar" : "Reanudar") {
                            timerProvider.togglePauseResume()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Detener") {
                            timerProvider.cancelTimer()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Tarjeta Mini-App 2: Monitor de Audio FFT en Tiempo Real
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.cyan.opacity(0.20))
                            .frame(width: 34, height: 34)
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitor de Audio FFT en Tiempo Real")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Analizador de 10 bandas con indicadores Peak Hold, lectura dBFS y presets de respuesta.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.openWithMiniApp(.audioMonitor)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("Abrir en Notch")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)
                }
                
                HStack(spacing: 8) {
                    Text("Respuesta rápida:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    ForEach(SpectrumResponsePreset.allCases) { preset in
                        Button(preset.shortTitle) {
                            SpectrumMetrics.applyPreset(preset)
                            noiseGateDB = Double(SpectrumMetrics.noiseGateDB)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Spacer()
                    
                    Button("Ventana de Calibración...") {
                        AudioSpectrumTestWindowController.shared.show()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Sección Sistema
    private var systemSection: some View {
        VStack(spacing: 14) {
            ToggleRow(
                title: "Ocultar HUD nativo de macOS",
                subtitle: "Reemplaza los cuadros grises flotantes de volumen y brillo de macOS por las animaciones en el Notch",
                isOn: Binding(
                    get: { volumeInterceptor.suppressNativeHUD },
                    set: { volumeInterceptor.suppressNativeHUD = $0 }
                )
            )
            
            // Nueva Sección: Rendimiento y Observadores en Segundo Plano
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.green)
                    Text("Rendimiento y Observadores en Segundo Plano")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                ToggleRow(
                    title: "Detector de Llamadas (FaceTime, Celular, WhatsApp, Discord)",
                    subtitle: "Detecta llamadas entrantes para contestar/rechazar desde el Notch y llamadas activas con onda de voz reactiva y sonido al mutear.",
                    isOn: $callDetector.isEnabled
                )
                
                if callDetector.isEnabled {
                    Button(action: {
                        CallActivityProvider.shared.startIncomingCall(
                            name: "FaceTime Audio",
                            handle: "Mamá",
                            isSimulation: true
                        )
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Probar llamada entrante en el Notch")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                
                ToggleRow(
                    title: "Observador de Mensajes de WhatsApp Web",
                    subtitle: "Detecta mensajes entrantes en pestañas de WhatsApp Web usando AppleScript precompilado en caché.",
                    isOn: $whatsAppObserver.isEnabled
                )
                
                if whatsAppObserver.isEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Intervalo de consulta de WhatsApp Web")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: "%.1f s", whatsAppObserver.pollInterval))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(DesignTokens.blue)
                        }
                        Slider(value: $whatsAppObserver.pollInterval, in: 0.5...5.0, step: 0.25)
                            .tint(DesignTokens.blue)
                    }
                    .padding(.horizontal, 8)
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            whatsAppObserver.simulateTestNotification()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "message.fill")
                                Text("Probar Notificación de WhatsApp")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(red: 0.15, green: 0.78, blue: 0.45).opacity(0.85)))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            whatsAppObserver.activateWhatsAppWeb()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Ir a WhatsApp")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                }
                
                // Observador de iMessage / Mensajes
                ToggleRow(
                    title: "Observador de iMessage / Mensajes",
                    subtitle: "Detecta notificaciones de iMessage y SMS entrantes con Quick Reply nativo en el Dynamic Notch.",
                    isOn: $messagesObserver.isEnabled
                )
                
                if messagesObserver.isEnabled {
                    HStack(spacing: 10) {
                        Button(action: {
                            messagesObserver.simulateTestNotification()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "message.fill")
                                Text("Probar Notificación de iMessage")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(red: 0.18, green: 0.52, blue: 0.98).opacity(0.90)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("Optimizaciones activas: Sonda Drag & Drop bajo demanda (0% CPU en reposo) • Caché IPC diferencial de carátulas • Escena 3D con suspensión automática de GPU.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: volumeInterceptor.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(volumeInterceptor.hasAccessibilityPermission ? .green : .orange)
                        .font(.system(size: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(volumeInterceptor.hasAccessibilityPermission ? "Permisos de Accesibilidad Concedidos" : "Permisos de Accesibilidad Requeridos")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(volumeInterceptor.hasAccessibilityPermission ? "Dynamic Notch tiene acceso completo para ocultar el HUD nativo." : "Permite a la aplicación interceptar las teclas de volumen y brillo.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !volumeInterceptor.hasAccessibilityPermission {
                        Button("Configurar...") {
                            AccessibilityOnboardingWindowController.showIfNeeded()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            HStack {
                Text("Dynamic Notch para macOS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Versión \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }
}

// MARK: - Ajustes nuevos (Actividades, extras de Apariencia y Gestos)

extension SettingsView {
    var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroupTitle("Bolitas", systemImage: "circle.grid.2x1.fill")
            SliderRow(
                title: "Tamaño de las bolitas",
                subtitle: "0 = automático (el alto de la cápsula del notch, como el iPhone).",
                value: Binding(get: { Double(appState.bolitaDiameter) }, set: { appState.bolitaDiameter = CGFloat($0) }),
                range: 0...44, step: 1,
                display: { $0 < 1 ? "Auto" : "\(Int($0)) pt" }
            )
            SliderRow(
                title: "Separación del notch",
                subtitle: "Espacio entre la cápsula y la bolita.",
                value: Binding(get: { Double(appState.bolitaGap) }, set: { appState.bolitaGap = CGFloat($0) }),
                range: 4...20, step: 1,
                display: { "\(Int($0)) pt" }
            )
            ToggleRow(
                title: "Segunda bolita a la izquierda",
                subtitle: "Como la Isla Dinámica: hasta 3 actividades a la vista, una en el notch y una bolita a cada lado. Apagado: las dos bolitas a la derecha.",
                isOn: $appState.bubblesOnBothSides
            )
            ToggleRow(
                title: "Mínima pegada con varias actividades",
                subtitle: "Si hay bolitas, la música se reduce a su carátula junto a la cámara, como el iPhone. Apagado: conserva sus dos alas.",
                isOn: $appState.minimalAttachedEnabled
            )
            PickerRow(
                title: "Clic en una bolita",
                subtitle: "Mantener presionado siempre la expande. \"Traerla al notch\" la pone en el lugar principal; las que sólo viven como bolita (Claude, la repisa) se expanden.",
                selection: $appState.bubbleTapAction,
                label: { $0.title }
            )
            SliderRow(
                title: "Tiempo para mantener presionado",
                subtitle: "Cuánto hay que mantener presionada una bolita para expandirla.",
                value: $appState.bubbleHoldDuration,
                range: 0.2...0.8, step: 0.05,
                display: { String(format: "%.2f s", $0) }
            )
            ToggleRow(
                title: "La bolita se encoge al pasar por el notch",
                subtitle: "Cuando el cursor está sobre el notch, sólo crece el notch; la bolita se queda y se hace un poco más pequeña.",
                isOn: $appState.bubbleShrinksOnNotchHover
            )
            Button {
                AnimationStudioWindow.shared.show()
            } label: {
                Label("Ajustar la animación en Animation Studio…", systemImage: "film.stack")
            }
            
            SettingsGroupTitle("Integraciones del sistema", systemImage: "switch.2")
            ToggleRow(
                title: "Bloq Mayús",
                subtitle: "Aviso breve al activarlo o desactivarlo, como el interruptor de silencio del iPhone.",
                isOn: $appState.capsLockIndicatorEnabled
            )
            ToggleRow(
                title: "Conexión y VPN",
                subtitle: "Aviso al perder o recuperar internet y al conectar o desconectar una VPN de túnel completo.",
                isOn: $appState.networkIndicatorEnabled
            )
            ToggleRow(
                title: "Cámara y micrófono en uso",
                subtitle: "Bolita verde (cámara) o naranja (micrófono) mientras alguna app los usa. Sólo se consulta si están en uso; Dynamic Notch nunca los abre.",
                isOn: $appState.privacyIndicatorEnabled
            )
            ToggleRow(
                title: "Descargas",
                subtitle: "Bolita con el progreso de lo que se descarga en la carpeta Descargas (Safari y apps que publican su progreso).",
                isOn: $appState.downloadsActivityEnabled
            )
            
            SettingsGroupTitle("Comportamiento de la Isla Dinámica", systemImage: "sparkles.rectangle.stack")
            ToggleRow(
                title: "Alertas",
                subtitle: "Una actualización importante (p. ej. Claude terminó una tarea larga) expande la actividad un momento y regresa sola.",
                isOn: $appState.liveActivityAlertsEnabled
            )
            if appState.liveActivityAlertsEnabled {
                SliderRow(
                    title: "Duración de las alertas",
                    subtitle: "Si el cursor está encima, la alerta se queda hasta que se vaya.",
                    value: $appState.liveActivityAlertDuration,
                    range: 2...8, step: 0.5,
                    display: { String(format: "%.1f s", $0) }
                )
                ToggleRow(
                    title: "Las alertas suenan",
                    subtitle: "Un sonido breve cuando la alerta lo pide (p. ej. Claude terminó o necesita permiso). Nunca más de una alerta cada 30 s por actividad.",
                    isOn: $appState.liveActivityAlertSound
                )
            }
            SliderRow(
                title: "Resumen al terminar",
                subtitle: "Cuánto se queda una actividad terminada (anillo completo) antes de reabsorberse. Las actividades se terminan solas a las 8 h, y las que dejan de actualizarse se ven atenuadas.",
                value: $appState.liveActivityEndSummaryDuration,
                range: 0...60, step: 5,
                display: { $0 < 1 ? "Al instante" : "\(Int($0)) s" }
            )
            SliderRow(
                title: "Pausa tras volumen o brillo",
                subtitle: "Tiempo con el notch limpio antes de que regrese el reproductor u otra actividad.",
                value: $appState.hudReturnDelay,
                range: 0...6, step: 0.5,
                display: { String(format: "%.1f s", $0) }
            )
            ToggleRow(
                title: "Ocultar el notch en pantalla completa",
                subtitle: "Mientras ves un video o música a pantalla completa, el notch desaparece hasta que salgas.",
                isOn: $appState.hideNotchInFullScreen
            )
            ToggleRow(
                title: "El temporizador cede el notch a la música",
                subtitle: "Con música sonando, el temporizador sigue como bolita en vivo.",
                isOn: $appState.timerYieldsToMusic
            )
        }
    }
    
    var appearanceExtras: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroupTitle("Detalles de la Isla", systemImage: "circle.dashed")
            ToggleRow(
                title: "Keyline en modo oscuro",
                subtitle: "Con el Mac en modo oscuro y el notch en negro, un borde fino del color de lo que se muestra.",
                isOn: $appState.keylineEnabled
            )
            ToggleRow(
                title: "Alas de cristal en el notch cerrado",
                subtitle: "En los modos de cristal, los lados del notch con actividad son Liquid Glass; el centro sigue negro detrás de la cámara.",
                isOn: $appState.glassWingsEnabled
            )
            ToggleRow(
                title: "Cristal Oscuro se adapta a fondos claros",
                subtitle: "Sobre ventanas o fondos claros usa el vidrio regular, que se lee mejor (como \"Con tinte\" de iOS).",
                isOn: $appState.adaptGlassToBrightBackdrop
            )
        }
    }
    
    var gesturesExtras: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroupTitle("Transiciones", systemImage: "hand.draw")
            ToggleRow(
                title: "Cerrar siguiendo los dedos",
                subtitle: "Al deslizar hacia arriba, el reproductor, la repisa o una tarjeta se recogen con tus dedos y se decide al soltar.",
                isOn: $appState.interactiveCloseEnabled
            )
            if appState.interactiveCloseEnabled {
                SliderRow(
                    title: "Recorrido para cerrar",
                    subtitle: "Qué tanto hay que deslizar antes de soltar para que se cierre (un deslizamiento rápido siempre cierra).",
                    value: $appState.interactiveCloseThreshold,
                    range: 0.15...0.7, step: 0.05,
                    display: { "\(Int($0 * 100)) %" }
                )
            }
            ToggleRow(
                title: "Desenfoque al transformarse",
                subtitle: "El contenido del notch se desenfoca un instante mientras cambia de forma, como en la Isla Dinámica.",
                isOn: $appState.morphBlurEnabled
            )
            ToggleRow(
                title: "Deslizar a lo ancho recorre las actividades",
                subtitle: "Con dos o más actividades entre bolitas y cola, deslizar de lado sobre el notch cerrado las va pasando, como la Isla Dinámica.",
                isOn: $appState.swipeCyclesActivities
            )
            ToggleRow(
                title: "Deslizar de lado para esconder la música",
                subtitle: "Sobre el notch cerrado, deslizar de lado esconde las alas de la música; otro deslizamiento o una canción nueva las regresa.",
                isOn: $appState.swipeToMinimizeMusic
            )
        }
    }
}

private struct SettingsGroupTitle: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.blue)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
        }
        .padding(.top, 6)
    }
}

private struct SliderRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(display(value))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(DesignTokens.blue)
                    .monospacedDigit()
            }
            // Continuo (sin marcas); el valor se redondea al paso indicado
            Slider(value: Binding(
                get: { value },
                set: { value = step > 0 ? (($0 / step).rounded() * step) : $0 }
            ), in: range)
                .tint(DesignTokens.blue)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Fila con un selector segmentado (mismo estilo que ToggleRow)
private struct PickerRow<Value: Hashable & Identifiable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    let subtitle: String
    @Binding var selection: Value
    var label: (Value) -> String = { "\($0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $selection) {
                ForEach(Value.allCases) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

