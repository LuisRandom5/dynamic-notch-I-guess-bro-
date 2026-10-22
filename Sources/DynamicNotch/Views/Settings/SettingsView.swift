import ServiceManagement
import SwiftUI

// MARK: - Ajustes
// Como los Ajustes del Sistema de macOS: barra lateral con secciones y, a la derecha, listas agrupadas nativas.
// Cada sección empieza con una frase que explica para qué sirve; cada opción tiene un título corto y una línea en
// lenguaje sencillo. Lo fino va plegado en "Más opciones" al final de cada sección, y todo lo de desarrollo vive en
// la sección "Desarrollo", que no existe en la beta.
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
    @ObservedObject var glassManager = GlassClearManager.shared

    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var noiseGateDB: Double = Double(SpectrumMetrics.noiseGateDB)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Apariencia"
        case displays = "Pantallas sin notch"
        case music = "Música"
        case lockScreen = "Pantalla bloqueada"
        case airpods = "AirPods"
        case notifications = "Avisos"
        case activities = "Varias actividades"
        case gestures = "Gestos"
        case shelf = "Repisa de archivos"
        case extras = "Temporizador y más"
        case developer = "Desarrollo"

        public var id: String { rawValue }

        /// Las que se muestran (la de desarrollo, sólo en la compilación de desarrollo)
        static var visible: [SettingsTab] {
            allCases.filter { $0 != .developer || BuildFlavor.hasDeveloperTools }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "paintbrush.fill"
            case .displays: return "display"
            case .music: return "music.note"
            case .lockScreen: return "lock.fill"
            case .airpods: return "airpods"
            case .notifications: return "bell.badge.fill"
            case .activities: return "circle.grid.2x1.fill"
            case .gestures: return "hand.draw.fill"
            case .shelf: return "tray.and.arrow.down.fill"
            case .extras: return "timer"
            case .developer: return "hammer.fill"
            }
        }

        var color: Color {
            switch self {
            case .general: return .gray
            case .appearance: return .indigo
            case .displays: return .blue
            case .music: return .pink
            case .lockScreen: return .teal
            case .airpods: return Color(white: 0.45)
            case .notifications: return .red
            case .activities: return .purple
            case .gestures: return .orange
            case .shelf: return .cyan
            case .extras: return .orange
            case .developer: return .brown
            }
        }

        /// Una frase: para qué sirve la sección
        var blurb: String {
            switch self {
            case .general: return "Lo básico: abrir al iniciar sesión, permisos y cómo se comporta la isla."
            case .appearance: return "El color de la isla y cómo reacciona cuando pasas el puntero."
            case .displays: return "Cómo se ve la isla en monitores o Macs que no tienen notch."
            case .music: return "La canción que suena, sus barras animadas y cómo se mueven."
            case .lockScreen: return "Los controles de la música cuando tu Mac está bloqueado."
            case .airpods: return "La animación y la batería de tus AirPods cuando se conectan."
            case .notifications: return "Qué avisos aparecen en la isla: mensajes, llamadas, reuniones y cosas de tu Mac."
            case .activities: return "Cuando hay varias cosas a la vez, aparecen como bolitas junto al notch."
            case .gestures: return "Qué pasa al deslizar o acercar el puntero a la isla."
            case .shelf: return "Arrastra archivos a la isla para guardarlos un rato y usarlos después."
            case .extras: return "Temporizador, cronómetro y el medidor de audio, dentro de la isla."
            case .developer: return "Herramientas para probar y ajustar la app. No aparecen en la beta."
            }
        }
    }

    public init() {}

    public var body: some View {
        let tab = navigation.selectedTab ?? .general
        HStack(spacing: 0) {
            // Barra lateral, como los Ajustes del Sistema
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.visible) { item in
                        SidebarRow(tab: item, isSelected: item == tab) {
                            navigation.selectedTab = item
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .frame(width: 220)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeader(tab: tab)
                    content(for: tab)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(tab)
        }
        // Con tamaño ideal y elástico: la ventana manda
        .frame(minWidth: 820, idealWidth: 880, maxWidth: .infinity, minHeight: 600, idealHeight: 640, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalSection
        case .appearance: appearanceSection
        case .displays: displaysSection
        case .music: musicSection
        case .lockScreen: lockScreenSection
        case .airpods: airPodsSection
        case .notifications: notificationsSection
        case .activities: activitiesSection
        case .gestures: gesturesSection
        case .shelf: shelfSection
        case .extras: extrasSection
        case .developer: developerSection
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalSection: some View {
        SettingsGroup {
            SettingToggle("Abrir al iniciar sesión",
                          "Dynamic Notch se abre solo cuando enciendes tu Mac.",
                          isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        SettingsGroup("Permisos") {
            HStack(spacing: 10) {
                Image(systemName: volumeInterceptor.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(volumeInterceptor.hasAccessibilityPermission ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(volumeInterceptor.hasAccessibilityPermission ? L("Todo listo") : L("Falta el permiso de Accesibilidad"))
                    Text(volumeInterceptor.hasAccessibilityPermission
                         ? L("Revisa aquí qué más puede usar la app (Calendario, Contactos, Bluetooth).")
                         : L("Sin él no salen el volumen, el brillo ni los avisos de otras apps."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Revisar permisos…")) { WelcomeWindowController.showAlways() }
            }
        }

        SettingsGroup("Volumen y brillo") {
            SettingToggle("Mostrar el volumen y el brillo en la isla",
                          "En lugar del cuadro gris de macOS, el cambio se ve en la isla.",
                          isOn: Binding(get: { volumeInterceptor.suppressNativeHUD },
                                        set: { volumeInterceptor.suppressNativeHUD = $0 }))
            SettingToggle("Sonido al cambiar el volumen",
                          "El clic de macOS para saber qué tan fuerte quedó.",
                          isOn: $appState.enableSoundFeedback)
            SettingToggle("Vibración del trackpad",
                          "Un pequeño golpe en el trackpad al cambiar canción, arrastrar archivos y más.",
                          isOn: $appState.enableHaptics)
        }

        SettingsGroup("Isla") {
            SettingToggle("Ocultar en pantalla completa",
                          "Mientras ves un video o algo a pantalla completa, la isla desaparece.",
                          isOn: $appState.hideNotchInFullScreen)
        }

        SettingsGroup {
            SettingRow("Versión", nil) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            if BuildFlavor.isBeta {
                Button(L("Enviar comentarios…")) { FeedbackService.exportDiagnostics() }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = L("macOS no lo permitió. Mueve la app a la carpeta Aplicaciones e inténtalo de nuevo.")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Apariencia

    @ViewBuilder
    private var appearanceSection: some View {
        SettingsGroup("Estilo") {
            HStack(spacing: 12) {
                StyleCard(title: "Negro", detail: "Se funde con la cámara", mode: .pureOLED, selection: $appState.appearanceMode) {
                    Color.black
                }
                StyleCard(title: "Cristal oscuro", detail: "Transparente y oscuro", mode: .darkGlass, selection: $appState.appearanceMode) {
                    LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                StyleCard(title: "Cristal claro", detail: "Lo más transparente", mode: .clearGlass, selection: $appState.appearanceMode) {
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .padding(.vertical, 4)

            if glassManager.isReduceTransparencyActive {
                Notice(icon: "exclamationmark.triangle.fill", color: .orange,
                       text: "\"Reducir transparencia\" está activado en macOS, así que la isla se ve en negro.")
            }
            if appState.appearanceMode == .darkGlass {
                SettingSlider("Qué tan oscuro", "Más oscuro se lee mejor; más claro deja ver lo de atrás.",
                              value: Binding(get: { appState.glassDarknessOpacity }, set: { appState.glassDarknessOpacity = min(0.85, max(0, $0)) }),
                              range: 0...0.85, step: 0.01, minLabel: "Claro", maxLabel: "Oscuro",
                              display: { "\(Int(($0 * 100).rounded())) %" })
                SettingToggle("Más contraste sobre fondos claros",
                              "Encima de ventanas o fondos claros, el cristal se vuelve un poco más opaco para leerse mejor.",
                              isOn: $appState.adaptGlassToBrightBackdrop)
            }
            if appState.appearanceMode == .clearGlass {
                Notice(icon: "info.circle.fill", color: .blue,
                       text: "Pensado para fondos oscuros o con foto. Sobre páginas blancas puede costar leerla.")
                SettingSlider("Contraste", "Agrega un velo oscuro para que se lea mejor.",
                              value: Binding(get: { glassManager.uniformScrimOpacity }, set: { glassManager.uniformScrimOpacity = min(0.45, max(0, $0)) }),
                              range: 0...0.45, step: 0.01, minLabel: "Nada", maxLabel: "Mucho",
                              display: { "\(Int(($0 * 100).rounded())) %" })
                SettingToggle("Ajustar al fondo de pantalla",
                              "Si tu fondo de pantalla es claro, sube el contraste solo.",
                              isOn: Binding(get: { glassManager.enableAutoWallpaperLuminance },
                                            set: { glassManager.enableAutoWallpaperLuminance = $0 }))
            }
            if appState.appearanceMode != .pureOLED {
                SettingToggle("Lados de cristal con la música",
                              "Con el notch cerrado, los lados que muestran la música también son de cristal.",
                              isOn: $appState.glassWingsEnabled)
            }
            SettingToggle("Borde de color en modo oscuro",
                          "Una línea fina del color de lo que se muestra, para separar la isla del fondo oscuro.",
                          isOn: $appState.keylineEnabled)
        }

        SettingsGroup("Al pasar el puntero") {
            SettingToggle("Crecer al pasar el puntero",
                          "La isla crece un poco y proyecta sombra mientras el puntero está encima.",
                          isOn: $appState.enableHoverExpansion)
            if appState.enableHoverExpansion {
                SettingSlider("Cuánto crece", nil, value: $appState.hoverScaleAmount,
                              range: 1.01...1.08, step: 0.005, minLabel: "Poco", maxLabel: "Mucho",
                              display: { "+\(String(format: "%.1f", ($0 - 1) * 100)) %" })
                SettingSlider("Sombra", nil, value: $appState.hoverShadowIntensity,
                              range: 0.2...1, step: 0.05, minLabel: "Suave", maxLabel: "Fuerte",
                              display: { "\(Int(($0 * 100).rounded())) %" })
            }
        }

        SettingsGroup("Animaciones") {
            SettingToggle("Desenfoque al cambiar de forma",
                          "El contenido se desenfoca un instante mientras la isla cambia, como en el iPhone.",
                          isOn: $appState.morphBlurEnabled)
        }
    }

    // MARK: - Pantallas sin notch

    @ViewBuilder
    private var displaysSection: some View {
        SettingsGroup {
            SettingPicker("Dónde aparece la isla",
                          "Automática: en el notch de la MacBook (o en la pantalla principal si no tiene). Sin notch: en tu monitor externo. Sigue al puntero: en la pantalla donde estés.",
                          selection: $appState.islandScreenPlacement) { placement in
                switch placement {
                case .automatic: return "Automática"
                case .withoutNotch: return "Sin notch"
                case .followCursor: return "Sigue al puntero"
                }
            }
            SettingPicker("Forma", "Flotante: una cápsula separada del borde, como en el iPhone. Pegada: con la forma del notch.",
                          selection: $appState.islandStyle) { $0 == .floating ? "Flotante" : "Pegada al borde" }
            SettingToggle("Siempre visible",
                          "La isla se ve aunque no haya nada sonando. Apagado: sólo aparece cuando tiene algo que mostrar.",
                          isOn: $appState.islandVisibleAtRest)
        }

        SettingsGroup("Más opciones") {
            SettingToggle("Del alto de la barra de menús",
                          "La isla flotante cabe en la barra de menús. Apagado: el tamaño del iPhone, un poco más grande.",
                          isOn: $appState.islandFitsMenuBar)
            SettingSlider("Distancia al borde de arriba", "Al mínimo: automática, como en el iPhone.",
                          value: $appState.islandTopInset, range: -1...16, step: 1,
                          minLabel: "Auto", maxLabel: "Lejos",
                          display: { $0 < 0 ? L("Auto") : "\(Int($0)) pt" })
        }
    }

    // MARK: - Música

    @ViewBuilder
    private var musicSection: some View {
        SettingsGroup {
            SettingToggle("Mostrar la canción junto al notch",
                          "Mientras suena música, la portada y unas barras animadas aparecen a los lados del notch.",
                          isOn: $appState.showCompactWhenPlaying)
        }

        SettingsGroup("Barras animadas") {
            SettingToggle("Las barras siguen la música",
                          "Escuchan el sonido de tu Mac sólo mientras algo suena (macOS muestra un punto morado). No se graba nada y el micrófono nunca se usa. Apagado: se mueven solas.",
                          isOn: Binding(get: { spectrumEngine.realAudioBarsEnabled },
                                        set: { spectrumEngine.setRealAudioBarsEnabled($0) }))
            SettingToggle("Seguir el ritmo si no hay sonido",
                          "Algunas canciones protegidas no dejan escuchar su audio; entonces las barras laten al ritmo de la canción.",
                          isOn: $appState.tempoFallbackEnabled)
            SettingPicker("Color de las barras", nil, selection: $appState.visualizerColorStyle) { style in
                switch style {
                case .adaptive: return "De la portada"
                case .vibrant: return "Vivos"
                case .pureWhite: return "Blanco"
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel("Cómo se mueven", "Elige un estilo; \"Recomendado\" es el de la Isla Dinámica.")
                HStack(spacing: 6) {
                    ForEach(SpectrumResponsePreset.allCases) { preset in
                        Button(L(friendlyPresetName(preset))) {
                            SpectrumMetrics.applyPreset(preset)
                            noiseGateDB = Double(SpectrumMetrics.noiseGateDB)
                            appState.hapticService.triggerSnap()
                        }
                    }
                }
            }
        }

        SettingsGroup("Más opciones") {
            SettingSlider("Ignorar sonidos muy bajos",
                          "Por debajo de este volumen las barras se quedan quietas.",
                          value: Binding(get: { noiseGateDB }, set: { noiseGateDB = $0; SpectrumMetrics.noiseGateDB = Float($0) }),
                          range: -65 ... -30, step: 1, minLabel: "Casi todo", maxLabel: "Sólo fuerte",
                          display: { "\(Int($0)) dB" })
        }
    }

    private func friendlyPresetName(_ preset: SpectrumResponsePreset) -> String {
        switch preset {
        case .island: return "Recomendado"
        case .smooth: return "Suave"
        case .balanced: return "Normal"
        case .punchy: return "Intenso"
        }
    }

    // MARK: - Pantalla bloqueada

    @ViewBuilder
    private var lockScreenSection: some View {
        SettingsGroup {
            SettingToggle("Música en la pantalla bloqueada",
                          "Al bloquear tu Mac, debajo del reloj aparecen la portada y los controles de lo que suena.",
                          isOn: $appState.enableLockScreenPlayer)
            if !lockScreenBridge.isSupported {
                Notice(icon: "exclamationmark.triangle.fill", color: .orange,
                       text: "Esta versión de macOS no permite mostrarla en la pantalla bloqueada.")
            }
            Button(lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode ? L("Cerrar la vista previa") : L("Ver cómo se ve (10 s)")) {
                if lockScreenManager.isPanelVisible && lockScreenManager.isPreviewMode {
                    lockScreenManager.hidePlayerPanelPreview()
                } else {
                    lockScreenManager.showPlayerPanelPreview(duration: 10)
                }
            }
        }

        if appState.enableLockScreenPlayer {
            SettingsGroup("Diseño") {
                SettingPicker("Estilo", nil, selection: $appState.lockScreenStyle) { style in
                    switch style {
                    case .heroWidget: return "Grande"
                    case .compactCard: return "Compacto"
                    case .ambientCanvas: return "Con letra"
                    }
                }
                SettingToggle("Ocultar la canción",
                              "No muestra la portada ni el nombre de la canción mientras está bloqueado.",
                              isOn: $appState.lockScreenHideMediaDetails)
                SettingToggle("Brillo de color",
                              "Un resplandor suave con el color de la portada.",
                              isOn: $appState.lockScreenShowArtworkHalo)
                SettingToggle("Control de volumen",
                              "Una barra para subir o bajar el volumen sin desbloquear.",
                              isOn: $appState.lockScreenShowVolumeSlider)
            }

            SettingsGroup("Más opciones") {
                SettingSlider("Altura", "Mueve los controles más arriba o más abajo del reloj.",
                              value: Binding(get: { Double(appState.lockScreenVerticalOffset) }, set: { appState.lockScreenVerticalOffset = CGFloat($0) }),
                              range: -200...200, step: 5, minLabel: "Arriba", maxLabel: "Abajo",
                              display: { "\(Int($0)) pt" })
                SettingSlider("Tiempo visible después de pausar", nil,
                              value: Binding(get: { Double(appState.lockScreenPauseTimeoutSeconds) }, set: { appState.lockScreenPauseTimeoutSeconds = Int($0) }),
                              range: 5...60, step: 5, minLabel: "5 s", maxLabel: "1 min",
                              display: { "\(Int($0)) s" })
                SettingSlider("Oscurecer el fondo", "Para que los controles se lean mejor sobre fondos claros.",
                              value: $appState.lockScreenDimmingOpacity, range: 0.10...0.35, step: 0.01,
                              minLabel: "Poco", maxLabel: "Más",
                              display: { "\(Int(($0 * 100).rounded())) %" })
                SettingPicker("Fondo de los controles", nil, selection: $appState.lockScreenRenderMode) { mode in
                    switch mode {
                    case .pureOLED: return "Negro"
                    case .nativeGlass: return "Cristal"
                    case .visualEffect: return "Desenfocado"
                    case .privateBlur: return "Desenfoque fuerte"
                    case .solidDark: return "Oscuro"
                    }
                }
            }
        }
    }

    // MARK: - AirPods

    @ViewBuilder
    private var airPodsSection: some View {
        SettingsGroup {
            SettingToggle("Animación al conectarlos",
                          "La isla muestra tus AirPods (la animación oficial de Apple de tu modelo) y su batería. Toca la isla para ver cada auricular y el estuche.",
                          isOn: $appState.enableAirPodsAnimation)
            if appState.enableAirPodsAnimation {
                SettingPicker("Animación", "La primera vez se baja de Apple (unos MB).",
                              selection: $appState.airPodsAnimationStyle) { $0.title }
                SettingPicker("Color de tus AirPods Max", "macOS no dice el color; elígelo para ver la animación correcta. Los demás AirPods son blancos.",
                              selection: $appState.airPodsMaxColor) { $0.title }
            }
        }
    }

    // MARK: - Avisos

    @ViewBuilder
    private var notificationsSection: some View {
        SettingsGroup("Mensajes") {
            SettingToggle("WhatsApp",
                          "Avisos de WhatsApp Web (en Safari o Chrome) con quién te escribe y qué dice.",
                          isOn: $whatsAppObserver.isEnabled)
            if whatsAppObserver.isEnabled {
                if whatsAppObserver.javaScriptBlocked {
                    Notice(icon: "exclamationmark.bubble.fill", color: .orange,
                           text: "Para ver el mensaje con WhatsApp en una pestaña de fondo, activa en Safari → Ajustes → Desarrollador → \"Permitir JavaScript desde Apple Events\" (en Chrome: Ver → Desarrollador).")
                }
                Button(L("Abrir WhatsApp")) { whatsAppObserver.activateWhatsAppWeb() }
            }
            SettingToggle("Mensajes de Apple",
                          "Avisos de iMessage y SMS en la isla.",
                          isOn: $messagesObserver.isEnabled)
            SettingPicker("Mostrar el texto del mensaje",
                          "\"Ocultar al grabar la pantalla\" sólo dice \"Mensaje nuevo\" mientras grabas. En videollamadas que comparten pantalla elige \"Ocultar siempre\".",
                          selection: $appState.messagePreviewPrivacy) { $0.title }
        }

        SettingsGroup("Llamadas") {
            SettingToggle("Llamadas",
                          "Contesta o rechaza llamadas de FaceTime, del iPhone, WhatsApp o Discord desde la isla.",
                          isOn: $callDetector.isEnabled)
        }

        SettingsGroup("Calendario y descargas") {
            SettingToggle("Próxima reunión",
                          "5 minutos antes aparece una cuenta regresiva; haz clic para unirte si tiene enlace (Zoom, Meet, Teams…). Pide permiso de Calendario.",
                          isOn: $appState.calendarActivityEnabled)
            SettingToggle("Descargas",
                          "El progreso de lo que se descarga en tu carpeta Descargas.",
                          isOn: $appState.downloadsActivityEnabled)
            SettingToggle("AirDrop en la isla",
                          "Lo que envías o recibes por AirDrop se ve en la isla, en lugar de la ventana de macOS.",
                          isOn: $appState.airDropReplacesNative)
        }

        SettingsGroup("Tu Mac") {
            SettingToggle("Bloq Mayús", "Un aviso breve al activarlo o desactivarlo.",
                          isOn: $appState.capsLockIndicatorEnabled)
            SettingToggle("Concentración", "Un aviso al activar o desactivar No molestar u otra Concentración.",
                          isOn: $appState.focusIndicatorEnabled)
            SettingToggle("Internet y VPN", "Un aviso al perder o recuperar internet, o al conectar una VPN.",
                          isOn: $appState.networkIndicatorEnabled)
            SettingToggle("Cámara y micrófono en uso",
                          "Un punto verde (cámara) o naranja (micrófono) mientras alguna app los usa.",
                          isOn: $appState.privacyIndicatorEnabled)
        }

        if whatsAppObserver.isEnabled {
            SettingsGroup("Más opciones") {
                SettingSlider("Revisar WhatsApp cada", "Más seguido avisa antes; menos seguido gasta menos batería.",
                              value: $whatsAppObserver.pollInterval, range: 0.5...5, step: 0.25,
                              minLabel: "Rápido", maxLabel: "Ahorro",
                              display: { String(format: "%.1f s", $0) })
            }
        }
    }

    // MARK: - Varias actividades

    @ViewBuilder
    private var activitiesSection: some View {
        SettingsGroup {
            SettingToggle("Una bolita a cada lado",
                          "Hasta 3 cosas a la vista: una en el notch y una bolita a cada lado. Apagado: las dos bolitas a la derecha.",
                          isOn: $appState.bubblesOnBothSides)
            SettingPicker("Al hacer clic en una bolita",
                          "Si la mantienes presionada, siempre se abre.",
                          selection: $appState.bubbleTapAction) { $0.title }
            SettingToggle("Esconder la bolita de la app que estás viendo",
                          "Si ya tienes esa app a la vista, su bolita no aparece (como en el iPhone).",
                          isOn: $appState.hideActivityWhileAppVisible)
            SettingToggle("Música más chica con varias cosas",
                          "Con bolitas a la vista, la música se reduce a su portada junto a la cámara.",
                          isOn: $appState.minimalAttachedEnabled)
            SettingToggle("El temporizador le deja el lugar a la música",
                          "Con música sonando, el temporizador sigue como bolita.",
                          isOn: $appState.timerYieldsToMusic)
        }

        SettingsGroup("Alertas") {
            SettingToggle("Mostrar alertas",
                          "Cuando algo importante pasa (por ejemplo, termina una tarea), su bolita se abre un momento y vuelve sola.",
                          isOn: $appState.liveActivityAlertsEnabled)
            if appState.liveActivityAlertsEnabled {
                SettingToggle("Con sonido", "Un sonido breve cuando la alerta lo pide.",
                              isOn: $appState.liveActivityAlertSound)
                SettingSlider("Duración", "Si el puntero está encima, se queda hasta que lo quites.",
                              value: $appState.liveActivityAlertDuration, range: 2...8, step: 0.5,
                              minLabel: "2 s", maxLabel: "8 s",
                              display: { String(format: "%.1f s", $0) })
            }
        }

        SettingsGroup("Más opciones") {
            SettingSlider("Tamaño de las bolitas", "Al mínimo: automático, del alto del notch.",
                          value: Binding(get: { Double(appState.bolitaDiameter) }, set: { appState.bolitaDiameter = CGFloat($0) }),
                          range: 0...44, step: 1, minLabel: "Auto", maxLabel: "Grande",
                          display: { $0 < 1 ? L("Auto") : "\(Int($0)) pt" })
            SettingSlider("Distancia al notch", nil,
                          value: Binding(get: { Double(appState.bolitaGap) }, set: { appState.bolitaGap = CGFloat($0) }),
                          range: 4...20, step: 1, minLabel: "Cerca", maxLabel: "Lejos",
                          display: { "\(Int($0)) pt" })
            SettingToggle("La bolita se achica al pasar por el notch",
                          "Con el puntero sobre el notch, sólo crece el notch y la bolita se hace un poco más chica.",
                          isOn: $appState.bubbleShrinksOnNotchHover)
            SettingSlider("Tiempo para mantener presionado", "Cuánto hay que presionar una bolita para abrirla.",
                          value: $appState.bubbleHoldDuration, range: 0.2...0.8, step: 0.05,
                          minLabel: "Corto", maxLabel: "Largo",
                          display: { String(format: "%.2f s", $0) })
            SettingSlider("Cuánto se queda al terminar", "Lo que acaba de terminar se queda un rato antes de desaparecer.",
                          value: $appState.liveActivityEndSummaryDuration, range: 0...60, step: 5,
                          minLabel: "Nada", maxLabel: "1 min",
                          display: { $0 < 1 ? L("Al instante") : "\(Int($0)) s" })
            SettingSlider("Pausa después del volumen o el brillo",
                          "Cuánto se queda limpia la isla antes de que regrese la música.",
                          value: $appState.hudReturnDelay, range: 0...6, step: 0.5,
                          minLabel: "Nada", maxLabel: "6 s",
                          display: { String(format: "%.1f s", $0) })
        }
    }

    // MARK: - Gestos

    @ViewBuilder
    private var gesturesSection: some View {
        SettingsGroup("Puntero") {
            SettingToggle("Abrir al acercar el puntero",
                          "La isla se abre sola cuando acercas el puntero, sin hacer clic.",
                          isOn: $appState.expandOnHover)
            SettingToggle("Cerrar al alejar el puntero",
                          "La isla abierta se cierra sola cuando sacas el puntero.",
                          isOn: $appState.autoCollapseOnHoverExit)
        }

        SettingsGroup("Trackpad") {
            SettingToggle("Deslizar con dos dedos entre música y archivos",
                          "Con la isla abierta, desliza de lado para pasar del reproductor a la repisa.",
                          isOn: $appState.enableTrackpadSwipe)
            SettingToggle("Deslizar para pasar entre bolitas",
                          "Con la isla cerrada y varias cosas a la vez, desliza de lado para recorrerlas.",
                          isOn: $appState.swipeCyclesActivities)
            SettingToggle("Deslizar para esconder la música",
                          "Con la isla cerrada, desliza de lado para esconder la música; otro deslizamiento la regresa.",
                          isOn: $appState.swipeToMinimizeMusic)
            SettingToggle("Cerrar deslizando hacia arriba",
                          "Desliza hacia arriba y la isla abierta se recoge siguiendo tus dedos.",
                          isOn: $appState.interactiveCloseEnabled)
            if appState.interactiveCloseEnabled {
                SettingSlider("Cuánto deslizar para cerrar", "Un deslizamiento rápido siempre cierra.",
                              value: $appState.interactiveCloseThreshold, range: 0.15...0.7, step: 0.05,
                              minLabel: "Poco", maxLabel: "Mucho",
                              display: { "\(Int(($0 * 100).rounded())) %" })
            }
        }
    }

    // MARK: - Repisa de archivos

    @ViewBuilder
    private var shelfSection: some View {
        SettingsGroup {
            SettingRow(appState.shelfItems.isEmpty ? "La repisa está vacía" : "Archivos en la repisa",
                             appState.shelfItems.isEmpty
                                ? "Arrastra un archivo hacia el notch para guardarlo aquí."
                                : "\(appState.shelfItems.count) · \(ShelfStorageService.shared.totalStashedSizeString())") {
                HStack {
                    Button(L("Agregar…")) { ShelfStorageService.shared.selectAndAddFiles() }
                    Button(L("Ver en Finder")) { ShelfStorageService.shared.openStashFolderInFinder() }
                }
            }
            if !appState.shelfItems.isEmpty {
                HStack {
                    Button(L("Devolver todo a su lugar")) {
                        withAnimation { appState.restoreAllShelfItemsToOrigin() }
                    }
                    Button(L("Vaciar la repisa"), role: .destructive) {
                        withAnimation { appState.emptyShelfToTrash() }
                    }
                }
            }
        }

        SettingsGroup("Al arrastrar") {
            SettingToggle("Abrirse al acercar un archivo",
                          "Cuando arrastras un archivo cerca del notch, la isla se abre para recibirlo.",
                          isOn: $appState.enableDropInvitation)
            if appState.enableDropInvitation {
                SettingSlider("Qué tan cerca", nil,
                              value: $appState.dropInvitationDistance, range: 80...260, step: 5,
                              minLabel: "Cerca", maxLabel: "Lejos",
                              display: { "\(Int($0)) pt" })
            }
            SettingToggle("Quitar el archivo del escritorio",
                          "Al soltarlo en la isla se guarda en la repisa y desaparece de donde estaba. Lo puedes devolver con un clic.",
                          isOn: $appState.moveFilesToShelf)
            SettingToggle("Abrir la repisa al soltar", "Muestra los archivos en cuanto sueltas uno.",
                          isOn: $appState.autoOpenShelfOnDrop)
            SettingToggle("Mostrar cuántos archivos hay", "Un número pequeño junto al notch cuando hay archivos guardados.",
                          isOn: $appState.showShelfBadgeInNotch)
            SettingToggle("Vibración al arrastrar", "Un pequeño golpe en el trackpad al guardar o devolver archivos.",
                          isOn: $appState.enableShelfHaptics)
        }
    }

    // MARK: - Temporizador y más

    @ViewBuilder
    private var extrasSection: some View {
        SettingsGroup("Temporizador") {
            if timerProvider.hasActiveSession {
                SettingRow("En marcha", "\(timerProvider.formattedDuration) · \(timerProvider.mode.title)") {
                    HStack {
                        Button(timerProvider.isRunning ? L("Pausar") : L("Reanudar")) { timerProvider.togglePauseResume() }
                        Button(L("Detener"), role: .destructive) { timerProvider.cancelTimer() }
                    }
                }
            }
            SettingRow("Empezar un temporizador", "La cuenta regresiva se ve en la isla.") {
                HStack(spacing: 6) {
                    Button("1 min") { timerProvider.startTimer(duration: 60, title: L("Temporizador"), asCard: false) }
                    Button("5 min") { timerProvider.startTimer(duration: 300, title: L("Temporizador"), asCard: false) }
                    Button("15 min") { timerProvider.startTimer(duration: 900, title: L("Temporizador"), asCard: false) }
                    Button("25 min") { timerProvider.startTimer(duration: 1500, title: L("Pomodoro"), asCard: false) }
                }
            }
            SettingRow("Cronómetro", nil) {
                Button(L("Empezar")) { timerProvider.startStopwatch(asCard: false) }
            }
            SettingToggle("Botón del temporizador en la isla",
                          "Un acceso directo en la esquina de la isla abierta.",
                          isOn: $appState.pinTimerMiniAppInNotch)
            Button(L("Abrir el temporizador en la isla")) { appState.openWithMiniApp(.timer) }
        }

        SettingsGroup("Medidor de audio") {
            SettingToggle("Botón del medidor en la isla",
                          "Un acceso directo para ver el sonido en barras de colores mientras suena algo.",
                          isOn: $appState.pinAudioMonitorMiniAppInNotch)
            Button(L("Abrir el medidor en la isla")) { appState.openWithMiniApp(.audioMonitor) }
        }
    }

    // MARK: - Desarrollo (sólo en la compilación de desarrollo)

    @ViewBuilder
    private var developerSection: some View {
        if BuildFlavor.hasDeveloperTools {
            SettingsGroup("Ventanas de prueba") {
                Button("Panel de pruebas y bisección de capas…") { ActivityDebugWindow.shared.show() }
                Button("Animation Studio (bolitas)…") { AnimationStudioWindow.shared.show() }
                Button("Laboratorio de espectro FFT y calibración…") { AudioSpectrumTestWindowController.shared.show() }
                Button("Sonda de drag & drop…") { DragProbeDebugWindowController.shared.toggleWindow() }
            }
            SettingsGroup("Demostraciones") {
                Button("Llamada entrante") {
                    CallActivityProvider.shared.startIncomingCall(name: "FaceTime Audio", handle: "Mamá", isSimulation: true)
                }
                Button("Mensaje de WhatsApp") { whatsAppObserver.simulateTestNotification() }
                Button("Mensaje de iMessage") { messagesObserver.simulateTestNotification() }
                Button("Canvas de música en pantalla completa") { AmbientCanvasWindowManager.shared.toggleCanvas() }
                Button("Monitor de IA en la isla") { AgentActivityProvider.shared.showProgress(payload: AgentLiveProgressPayload()) }
            }
            SettingsGroup("Pantalla bloqueada") {
                Toggle("Contornos de depuración", isOn: $appState.lockScreenDebugOutlines)
                SettingRow("Diagnóstico SkyLight", nil) {
                    Text(lockScreenBridge.diagnosticStatus)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                }
                if lockScreenManager.testCountdownSeconds > 0 {
                    Button("Bloquea en \(lockScreenManager.testCountdownSeconds) s (⌘⌃Q) · Cancelar") { lockScreenManager.cancelArmedTest() }
                } else {
                    Button("Probar en la pantalla bloqueada (⌘⌃Q)") { lockScreenManager.startCountdownAndArmLockScreenTest(seconds: 4) }
                }
            }
        }
    }
}

/// Sección abierta en Ajustes; desde fuera se puede abrir una en particular (p. ej. el diagnóstico de capturas)
public final class SettingsNavigation: ObservableObject {
    public static let shared = SettingsNavigation()
    @Published public var selectedTab: SettingsView.SettingsTab? = .general
}

// MARK: - Piezas de la ventana

/// Fila de la barra lateral: icono de color y nombre; la elegida se resalta como en los Ajustes del Sistema
private struct SidebarRow: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab.color.gradient))
                Text(L(tab.rawValue))
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Encabezado de cada sección: icono grande, nombre y para qué sirve
private struct SectionHeader: View {
    let tab: SettingsView.SettingsTab

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: tab.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tab.color.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(L(tab.rawValue))
                    .font(.system(size: 20, weight: .bold))
                Text(L(tab.blurb))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Grupo de opciones: título opcional y una tarjeta con una línea fina entre cada opción
private struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(L(title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            _VariadicView.Tree(DividedRows()) { content() }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

/// Pone una línea fina entre las filas de un grupo (como las listas agrupadas de macOS)
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if child.id != children.last?.id {
                    Divider()
                }
            }
        }
    }
}

/// Título de una opción con su explicación debajo
private struct SettingLabel: View {
    let title: String
    let detail: String?

    init(_ title: String, _ detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(title))
                .font(.system(size: 13))
            if let detail {
                Text(L(detail))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Opción con algo a la derecha (botones, un valor…)
private struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, _ detail: String?, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingLabel(title, detail)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, _ detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    let detail: String?
    @Binding var value: V
    let range: ClosedRange<V>
    let step: V
    let minLabel: String
    let maxLabel: String
    let display: (V) -> String

    init(_ title: String, _ detail: String?, value: Binding<V>, range: ClosedRange<V>, step: V,
         minLabel: String, maxLabel: String, display: @escaping (V) -> String) {
        self.title = title
        self.detail = detail
        self._value = value
        self.range = range
        self.step = step
        self.minLabel = minLabel
        self.maxLabel = maxLabel
        self.display = display
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SettingLabel(title, detail)
                Spacer()
                Text(display(value))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Continuo (sin marcas); el valor se redondea al paso indicado
            Slider(value: Binding(get: { value }, set: { value = step > 0 ? (($0 / step).rounded() * step) : $0 }), in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(L(minLabel)).font(.system(size: 11)).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(L(maxLabel)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }
}

private struct SettingPicker<Value: Hashable & Identifiable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    let detail: String?
    @Binding var selection: Value
    let label: (Value) -> String

    init(_ title: String, _ detail: String?, selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.title = title
        self.detail = detail
        self._selection = selection
        self.label = label
    }

    var body: some View {
        SettingRow(title, detail) {
            Picker("", selection: $selection) {
                ForEach(Value.allCases) { value in
                    Text(L(label(value))).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// Aviso dentro de un grupo (información o advertencia)
private struct Notice: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(L(text))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tarjeta para elegir el estilo de la isla
private struct StyleCard<Fill: View>: View {
    let title: String
    let detail: String
    let mode: NotchAppearanceMode
    @Binding var selection: NotchAppearanceMode
    @ViewBuilder let fill: () -> Fill

    var body: some View {
        let selected = selection == mode
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = mode }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    fill()
                    Capsule()
                        .fill(mode == .clearGlass ? Color.black.opacity(0.22) : Color.white.opacity(0.28))
                        .frame(width: 46, height: 13)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                )
                VStack(spacing: 1) {
                    Text(L(title)).font(.system(size: 12, weight: .semibold))
                    Text(L(detail)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
