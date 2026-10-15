import SwiftUI

public struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var volumeInterceptor = VolumeInterceptorService.shared
    
    @State private var selectedTab: SettingsTab = .appearance
    
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance = "Apariencia"
        case gestures = "Gestos"
        case shelf = "Drag & Drop"
        case media = "Multimedia"
        case system = "Sistema"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .appearance: return "sparkles"
            case .gestures: return "hand.tap"
            case .shelf: return "tray.and.arrow.down.fill"
            case .media: return "play.circle"
            case .system: return "gearshape"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header con pestañas estilo macOS Sequoia
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Capsule().fill(Color.white.opacity(0.18))
                                : Capsule().fill(Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color.black.opacity(0.35))
            
            Divider()
                .opacity(0.2)
            
            // Contenido de la pestaña
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .appearance:
                        appearanceSection
                    case .gestures:
                        gesturesSection
                    case .shelf:
                        shelfSection
                    case .media:
                        mediaSection
                    case .system:
                        systemSection
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 560, height: 480)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow, state: .active))
    }
    
    // MARK: - Sección Apariencia
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Estilo Visual del Notch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
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
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 44, height: 12)
                                )
                            
                            if appState.appearanceMode == .pureOLED {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignTokens.blue, lineWidth: 2.5)
                            }
                        }
                        
                        Text("Negro Puro OLED")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(appState.appearanceMode == .pureOLED ? .white : .white.opacity(0.65))
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
                                        colors: [Color.white.opacity(0.20), Color.black.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 70)
                                .overlay(
                                    Capsule()
                                        .fill(Color.white.opacity(0.25))
                                        .frame(width: 44, height: 12)
                                )
                            
                            if appState.appearanceMode == .darkGlass {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignTokens.blue, lineWidth: 2.5)
                            }
                        }
                        
                        Text("Cristal Oscuro")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(appState.appearanceMode == .darkGlass ? .white : .white.opacity(0.65))
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
                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 70)
                                .overlay(
                                    Capsule()
                                        .fill(Color.white.opacity(0.40))
                                        .frame(width: 44, height: 12)
                                )
                            
                            if appState.appearanceMode == .clearGlass {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignTokens.blue, lineWidth: 2.5)
                            }
                        }
                        
                        Text("Cristal Claro")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(appState.appearanceMode == .clearGlass ? .white : .white.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            
            if appState.appearanceMode == .darkGlass {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacidad del Tinte Oscuro")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(round(appState.glassDarknessOpacity * 100)))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // Rango exacto de 30% a 90% (DEFAULT ~55%)
                    Slider(
                        value: Binding(
                            get: { Double(round(appState.glassDarknessOpacity * 100)) },
                            set: { appState.glassDarknessOpacity = min(0.90, max(0.30, $0 / 100.0)) }
                        ),
                        in: 30...90,
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
                                .foregroundColor(.white.opacity(0.85))
                            Text("Atenuación uniforme: 0% totalmente claro, 10% default, 35% máxima legibilidad.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                        Text("\(Int(round(GlassClearManager.shared.uniformScrimOpacity * 100)))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                    }
                    
                    Slider(
                        value: Binding(
                            get: { round(GlassClearManager.shared.uniformScrimOpacity * 100) },
                            set: { GlassClearManager.shared.uniformScrimOpacity = min(0.35, max(0.0, $0 / 100.0)) }
                        ),
                        in: 0...35,
                        step: 1
                    )
                    .tint(DesignTokens.blue)
                    
                    HStack {
                        Toggle(isOn: Binding(
                            get: { GlassClearManager.shared.enableAutoWallpaperLuminance },
                            set: { GlassClearManager.shared.enableAutoWallpaperLuminance = $0 }
                        )) {
                            Text("Adaptar al fondo de pantalla")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.80))
                        }
                        .toggleStyle(.checkbox)
                        
                        Spacer()
                        
                        if GlassClearManager.shared.enableAutoWallpaperLuminance {
                            Text("Luminosidad: \(Int(round(GlassClearManager.shared.detectedWallpaperLuminance * 100)))%")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Botón para abrir el panel de bisección
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
                            .foregroundColor(.white)
                        Text("Por accesibilidad del sistema, el efecto Liquid Glass se desactiva y cae automáticamente al modo Negro Puro OLED.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.70))
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
                            .foregroundColor(.white)
                        Text("macOS tiene configurado un color de acento o modo tintado en Ajustes. El cristal adoptará un leve tinte por decisión del sistema.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.70))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
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
                title: "Expandir al pasar el cursor (Hover)",
                subtitle: "Despliega automáticamente el Notch al acercar el cursor a la cámara",
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
                        .foregroundColor(.white)
                }
                Text("Arrastra cualquier archivo desde Finder o el escritorio hacia el Notch para custodiarlos temporalmente, transferirlos entre ventanas o mantener tu pantalla limpia.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.65))
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            
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
                                    .foregroundColor(.white.opacity(0.85))
                                Text("Radio en puntos para despertar el Notch al arrastrar")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.50))
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
                                .foregroundColor(.white.opacity(0.40))
                            Spacer()
                            Text("Estándar (175 pt)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.40))
                            Spacer()
                            Text("Amplia (260 pt)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.40))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
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
                            .foregroundColor(.white)
                        Text("\(appState.shelfItems.count) \(appState.shelfItems.count == 1 ? "archivo custodiado" : "archivos custodiados") • \(ShelfStorageService.shared.totalStashedSizeString())")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.60))
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
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            
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
                            .foregroundColor(.white)
                        Text("Monitorea coordenadas, proximidad euclidiana y eventos de NSPasteboard.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Sección Multimedia
    private var mediaSection: some View {
        VStack(spacing: 12) {
            ToggleRow(
                title: "Mostrar mini píldora durante la reproducción",
                subtitle: "Muestra la carátula y el visualizador animado junto al Notch mientras escuchas música",
                isOn: $appState.showCompactWhenPlaying
            )
            
            ToggleRow(
                title: "Animación de AirPods",
                subtitle: "Muestra la animación y el estado de batería al conectar auriculares Bluetooth o AirPods",
                isOn: $appState.enableAirPodsAnimation
            )
            
            ToggleRow(
                title: "Captura de Audio del Sistema (Process Tap)",
                subtitle: "Lee el audio del sistema vía CoreAudio. Al apagarlo, el visualizador usa simulación rítmica inteligente y el punto morado de macOS desaparece por completo.",
                isOn: Binding(
                    get: { AudioSpectrumEngine.shared.enableSystemAudioTap },
                    set: { AudioSpectrumEngine.shared.enableSystemAudioTap = $0 }
                )
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Compatibilidad Universal Activa")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("Detecta automáticamente videos de YouTube, Spotify, Apple Music, Safari, Google Chrome, Arc, Brave, VLC y más.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            
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
                        Text("Monitor de Audio Real & Espectro 6 Bandas")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Visualiza y calibra las 6 bandas logarítmicas con balística profesional.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Sección Sistema
    private var systemSection: some View {
        VStack(spacing: 12) {
            ToggleRow(
                title: "Ocultar HUD nativo de macOS",
                subtitle: "Reemplaza los cuadros grises flotantes de volumen y brillo de macOS por las animaciones en el Notch",
                isOn: Binding(
                    get: { volumeInterceptor.suppressNativeHUD },
                    set: { volumeInterceptor.suppressNativeHUD = $0 }
                )
            )
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: volumeInterceptor.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(volumeInterceptor.hasAccessibilityPermission ? .green : .orange)
                        .font(.system(size: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(volumeInterceptor.hasAccessibilityPermission ? "Permisos de Accesibilidad Concedidos" : "Permisos de Accesibilidad Requeridos")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(volumeInterceptor.hasAccessibilityPermission ? "Dynamic Notch tiene acceso completo para ocultar el HUD nativo." : "Permite a la aplicación interceptar las teclas de volumen y brillo.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
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
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            
            HStack {
                Text("Dynamic Notch para macOS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Versión 1.0.0")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
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
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
