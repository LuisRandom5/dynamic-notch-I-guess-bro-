import AppKit
import SwiftUI
import Combine

public enum NotchAppearanceMode: String, CaseIterable, Identifiable {
    case pureOLED = "oled"
    case darkGlass = "darkGlass"
    case clearGlass = "clearGlass"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pureOLED: return "Negro Puro OLED"
        case .darkGlass: return "Cristal Oscuro"
        case .clearGlass: return "Cristal Claro"
        }
    }
}

public enum VisualizerColorStyle: String, CaseIterable, Identifiable {
    case adaptive = "adaptive"
    case vibrant = "vibrant"
    case pureWhite = "pureWhite"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .adaptive: return "Adaptativo (Carátula)"
        case .vibrant: return "Vibrante (Apple Music)"
        case .pureWhite: return "Blanco Minimalista"
        }
    }
}

public enum MiniAppKind: String, CaseIterable, Identifiable {
    case timer = "timer"
    case audioMonitor = "audioMonitor"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .timer: return "Cronómetro y Temporizador"
        case .audioMonitor: return "Monitor de Audio FFT"
        }
    }
    public var icon: String {
        switch self {
        case .timer: return "timer"
        case .audioMonitor: return "waveform.badge.magnifyingglass"
        }
    }
}

/// Modos de presentación para Live Activities múltiples:
/// - Modo A (Personalizado Dynamic Notch): Cápsula principal compacta flanqueada por bolitas satélite desprendidas.
/// - Modo B (Inspirado en iOS HIG): Dos presentaciones mínimas (una adyacente al notch y una separada).
public enum MultiActivityPresentationMode: String, CaseIterable, Identifiable {
    case modeA = "modeA"
    case modeB = "modeB"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .modeA: return "Modo A: Compacta + Bolitas Satélite"
        case .modeB: return "Modo B: Inspirado en iOS (2 Mínimas)"
        }
    }
}

/// Clic en una bolita. iPhone: tocar abre la app; en los modelos con varias actividades, tocar una la trae
public enum BubbleTapAction: String, CaseIterable, Identifiable {
    case openApp
    case bringToNotch
    case expand

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openApp: return "Abrir su app"
        case .bringToNotch: return "Traerla al notch"
        case .expand: return "Expandir"
        }
    }
}

public enum SatelliteLocationPreference: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case bothSides = "bothSides"
    case rightOnly = "rightOnly"
    case bottomRow = "bottomRow"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Automática (Espacio libre)"
        case .bothSides: return "Ambos lados (Izquierda y Derecha)"
        case .rightOnly: return "Solo derecha"
        case .bottomRow: return "Fila inferior"
        }
    }
}

public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Notch State
    @Published public var mode: NotchMode = .idle
    @Published public var activeTab: NotchTab = .music
    @Published public var activeAlert: NotchAlert?
    @Published public var isHovered: Bool = false
    @Published public var shelfItems: [ShelfItem] = [] {
        didSet {
            if shelfItems.isEmpty && activeTab == .shelf && mode != .shelf {
                activeTab = .music
            }
        }
    }
    @Published public var isShelfDragTargeted: Bool = false
    @Published public var isDropInvitationActive: Bool = false {
        // La zona activa de la ventana debe crecer con la tarjeta de "suelta aquí": si no, sólo se podía
        // soltar en un cuadro del tamaño del notch cerrado, al centro
        didSet {
            guard oldValue != isDropInvitationActive else { return }
            DispatchQueue.main.async { NotchWindowManager.shared.updateHitAreaForCurrentState() }
        }
    }
    @Published public var isDropSuccessAnimating: Bool = false
    @Published public var trackpadDragOffset: CGFloat = 0
    @Published public var trackpadDragOffsetY: CGFloat = 0
    @Published public var isHoldingBareNotch: Bool = false
    @Published public var activeMiniAppOverlay: MiniAppKind? = nil
    
    // Elastic Overscroll State (Forma vs Contenido)
    @Published public var overscrollOffset: CGFloat = 0           // Estiramiento asimétrico de la cápsula negra (pt)
    @Published public var contentOverscrollOffset: CGFloat = 0    // Desplazamiento orgánico con desfase del contenido (pt)
    @Published public var verticalOverscrollOffset: CGFloat = 0   // Estiramiento elástico hacia abajo (anclado arriba al notch)
    @Published public var contentVerticalOverscrollOffset: CGFloat = 0 // Desplazamiento vertical orgánico del contenido
    @Published public var isOverscrolling: Bool = false
    /// Desenfoque mantenido por un gesto del trackpad en curso (0…1): sigue el recorrido de los dedos y se
    /// queda al máximo desde que el gesto dispara el cambio hasta que el usuario levanta los dedos
    @Published public var gestureBlurHold: CGFloat = 0
    /// Cierre interactivo (0…1): el reproductor/repisa/tarjeta se encoge hacia el notch siguiendo los dedos
    @Published public var interactiveCollapseProgress: CGFloat = 0
    /// Como en la Isla Dinámica: deslizar de lado sobre el notch cerrado esconde la actividad de música
    /// (queda el notch limpio); otro deslizamiento, o el cambio de canción, la regresa
    @Published public var isCompactMinimized: Bool = false

    // MARK: - Ajustes de comportamiento (pestañas Actividades, Gestos, Apariencia…)
    /// La bolita se encoge cuando el cursor pasa por el notch
    @Published public var bubbleShrinksOnNotchHover: Bool = UserDefaults.standard.object(forKey: "bubbleShrinksOnNotchHover") != nil
        ? UserDefaults.standard.bool(forKey: "bubbleShrinksOnNotchHover") : true {
        didSet { UserDefaults.standard.set(bubbleShrinksOnNotchHover, forKey: "bubbleShrinksOnNotchHover") }
    }
    /// Con varias actividades la del notch pasa a "mínima pegada" (sólo su lado izquierdo, junto a la cámara),
    /// como la Isla Dinámica del iPhone
    /// Apagado por defecto: el usuario prefiere conservar las barras de la música junto a las bolitas
    @Published public var minimalAttachedEnabled: Bool = UserDefaults.standard.bool(forKey: "minimalAttachedEnabledV2") {
        didSet { UserDefaults.standard.set(minimalAttachedEnabled, forKey: "minimalAttachedEnabledV2") }
    }
    /// La segunda bolita va a la izquierda (como el iPhone); apagado, las dos a la derecha
    public var bubblesOnBothSides: Bool {
        get { satelliteLocation != .rightOnly }
        set { satelliteLocation = newValue ? .automatic : .rightOnly }
    }
    /// Qué hace un clic en una bolita (mantener presionado siempre la expande)
    @Published public var bubbleTapAction: BubbleTapAction = {
        if let raw = UserDefaults.standard.string(forKey: "bubbleTapAction"), let action = BubbleTapAction(rawValue: raw) {
            return action
        }
        // Migración del ajuste anterior (encendido = abrir la app; apagado = expandir)
        if UserDefaults.standard.object(forKey: "bubbleTapOpensApp") != nil, !UserDefaults.standard.bool(forKey: "bubbleTapOpensApp") {
            return .expand
        }
        return .openApp
    }() {
        didSet { UserDefaults.standard.set(bubbleTapAction.rawValue, forKey: "bubbleTapAction") }
    }
    /// Las alertas de actividades también suenan (si la actualización lo pide)
    @Published public var liveActivityAlertSound: Bool = UserDefaults.standard.object(forKey: "liveActivityAlertSound") != nil
        ? UserDefaults.standard.bool(forKey: "liveActivityAlertSound") : true {
        didSet { UserDefaults.standard.set(liveActivityAlertSound, forKey: "liveActivityAlertSound") }
    }
    /// Cuánto se queda una actividad terminada mostrando su resumen antes de irse (Claude, agentes)
    @Published public var liveActivityEndSummaryDuration: Double = UserDefaults.standard.object(forKey: "liveActivityEndSummaryDuration") != nil
        ? UserDefaults.standard.double(forKey: "liveActivityEndSummaryDuration") : 15 {
        didSet { UserDefaults.standard.set(liveActivityEndSummaryDuration, forKey: "liveActivityEndSummaryDuration") }
    }
    // MARK: Isla en pantallas sin notch (Fase B)
    /// En qué pantalla vive la isla (ver SurfaceGeometry.ScreenPlacement)
    @Published public var islandScreenPlacement: SurfaceGeometry.ScreenPlacement =
        SurfaceGeometry.ScreenPlacement(rawValue: UserDefaults.standard.string(forKey: "islandScreenPlacement") ?? "") ?? .automatic {
        didSet {
            UserDefaults.standard.set(islandScreenPlacement.rawValue, forKey: "islandScreenPlacement")
            ScreenService.shared.updateScreenGeometry()
        }
    }
    /// En una pantalla sin notch: cápsula flotante (iPhone) o notch virtual pegado al borde
    @Published public var islandStyle: SurfaceGeometry.IslandStyle =
        SurfaceGeometry.IslandStyle(rawValue: UserDefaults.standard.string(forKey: "islandStyle") ?? "") ?? .floating {
        didSet {
            UserDefaults.standard.set(islandStyle.rawValue, forKey: "islandStyle")
            ScreenService.shared.updateScreenGeometry()
        }
    }
    /// La isla flotante se ve en reposo (como el iPhone) o sólo cuando hay algo
    @Published public var islandVisibleAtRest: Bool = UserDefaults.standard.object(forKey: "islandVisibleAtRest") != nil
        ? UserDefaults.standard.bool(forKey: "islandVisibleAtRest") : true {
        didSet { UserDefaults.standard.set(islandVisibleAtRest, forKey: "islandVisibleAtRest") }
    }
    
    // MARK: Integraciones del sistema (A-6)
    /// Aviso breve al activar o desactivar Bloq Mayús (como el interruptor de silencio del iPhone)
    @Published public var capsLockIndicatorEnabled: Bool = UserDefaults.standard.object(forKey: "capsLockIndicatorEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "capsLockIndicatorEnabled") : true {
        didSet { UserDefaults.standard.set(capsLockIndicatorEnabled, forKey: "capsLockIndicatorEnabled") }
    }
    /// Aviso al perder o recuperar internet y al conectar o desconectar una VPN
    @Published public var networkIndicatorEnabled: Bool = UserDefaults.standard.object(forKey: "networkIndicatorEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "networkIndicatorEnabled") : true {
        didSet { UserDefaults.standard.set(networkIndicatorEnabled, forKey: "networkIndicatorEnabled") }
    }
    /// Bolita mientras alguna app usa la cámara o el micrófono (sólo se consulta el estado; nunca se abren)
    @Published public var privacyIndicatorEnabled: Bool = UserDefaults.standard.object(forKey: "privacyIndicatorEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "privacyIndicatorEnabled") : true {
        didSet { UserDefaults.standard.set(privacyIndicatorEnabled, forKey: "privacyIndicatorEnabled") }
    }
    /// Bolita con el progreso de las descargas (Safari y apps que publican su progreso en Descargas)
    @Published public var downloadsActivityEnabled: Bool = UserDefaults.standard.object(forKey: "downloadsActivityEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "downloadsActivityEnabled") : true {
        didSet { UserDefaults.standard.set(downloadsActivityEnabled, forKey: "downloadsActivityEnabled") }
    }
    
    /// Swipe a lo ancho sobre el notch cerrado recorre las actividades (con 2 o más entre bolitas y cola)
    @Published public var swipeCyclesActivities: Bool = UserDefaults.standard.object(forKey: "swipeCyclesActivities") != nil
        ? UserDefaults.standard.bool(forKey: "swipeCyclesActivities") : true {
        didSet { UserDefaults.standard.set(swipeCyclesActivities, forKey: "swipeCyclesActivities") }
    }
    /// Segundos para \"mantener presionado\" una bolita
    @Published public var bubbleHoldDuration: Double = UserDefaults.standard.object(forKey: "bubbleHoldDuration") != nil
        ? UserDefaults.standard.double(forKey: "bubbleHoldDuration") : 0.35 {
        didSet { UserDefaults.standard.set(bubbleHoldDuration, forKey: "bubbleHoldDuration") }
    }
    /// Alertas: una actualización importante expande la actividad un momento
    @Published public var liveActivityAlertsEnabled: Bool = UserDefaults.standard.object(forKey: "liveActivityAlertsEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "liveActivityAlertsEnabled") : true {
        didSet { UserDefaults.standard.set(liveActivityAlertsEnabled, forKey: "liveActivityAlertsEnabled") }
    }
    /// Segundos que se queda abierta una alerta
    @Published public var liveActivityAlertDuration: Double = UserDefaults.standard.object(forKey: "liveActivityAlertDuration") != nil
        ? UserDefaults.standard.double(forKey: "liveActivityAlertDuration") : 4.0 {
        didSet { UserDefaults.standard.set(liveActivityAlertDuration, forKey: "liveActivityAlertDuration") }
    }
    /// Segundos de notch limpio tras el HUD de volumen/brillo
    @Published public var hudReturnDelay: Double = UserDefaults.standard.object(forKey: "hudReturnDelay") != nil
        ? UserDefaults.standard.double(forKey: "hudReturnDelay") : 3.0 {
        didSet { UserDefaults.standard.set(hudReturnDelay, forKey: "hudReturnDelay") }
    }
    /// Ocultar el notch mientras se ve algo a pantalla completa
    @Published public var hideNotchInFullScreen: Bool = UserDefaults.standard.object(forKey: "hideNotchInFullScreen") != nil
        ? UserDefaults.standard.bool(forKey: "hideNotchInFullScreen") : true {
        didSet { UserDefaults.standard.set(hideNotchInFullScreen, forKey: "hideNotchInFullScreen") }
    }
    /// El temporizador cede el notch a la música y sigue como bolita
    @Published public var timerYieldsToMusic: Bool = UserDefaults.standard.object(forKey: "timerYieldsToMusic") != nil
        ? UserDefaults.standard.bool(forKey: "timerYieldsToMusic") : true {
        didSet { UserDefaults.standard.set(timerYieldsToMusic, forKey: "timerYieldsToMusic") }
    }
    /// Deslizar de lado sobre el notch cerrado esconde la música
    @Published public var swipeToMinimizeMusic: Bool = UserDefaults.standard.object(forKey: "swipeToMinimizeMusic") != nil
        ? UserDefaults.standard.bool(forKey: "swipeToMinimizeMusic") : true {
        didSet { UserDefaults.standard.set(swipeToMinimizeMusic, forKey: "swipeToMinimizeMusic") }
    }
    /// Cerrar siguiendo los dedos al deslizar hacia arriba
    @Published public var interactiveCloseEnabled: Bool = UserDefaults.standard.object(forKey: "interactiveCloseEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "interactiveCloseEnabled") : true {
        didSet { UserDefaults.standard.set(interactiveCloseEnabled, forKey: "interactiveCloseEnabled") }
    }
    /// Recorrido mínimo (0…1) para que el cierre interactivo se complete
    @Published public var interactiveCloseThreshold: Double = UserDefaults.standard.object(forKey: "interactiveCloseThreshold") != nil
        ? UserDefaults.standard.double(forKey: "interactiveCloseThreshold") : 0.30 {
        didSet { UserDefaults.standard.set(interactiveCloseThreshold, forKey: "interactiveCloseThreshold") }
    }
    /// Desenfoque del contenido mientras el notch se transforma
    @Published public var morphBlurEnabled: Bool = UserDefaults.standard.object(forKey: "morphBlurEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "morphBlurEnabled") : true {
        didSet { UserDefaults.standard.set(morphBlurEnabled, forKey: "morphBlurEnabled") }
    }
    /// Borde fino de color en modo oscuro (keyline)
    @Published public var keylineEnabled: Bool = UserDefaults.standard.object(forKey: "keylineEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "keylineEnabled") : true {
        didSet { UserDefaults.standard.set(keylineEnabled, forKey: "keylineEnabled") }
    }
    /// Alas de cristal en el notch cerrado con actividad
    @Published public var glassWingsEnabled: Bool = UserDefaults.standard.object(forKey: "glassWingsEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "glassWingsEnabled") : true {
        didSet { UserDefaults.standard.set(glassWingsEnabled, forKey: "glassWingsEnabled") }
    }
    /// Cristal Oscuro: vidrio regular sobre fondos claros
    @Published public var adaptGlassToBrightBackdrop: Bool = UserDefaults.standard.object(forKey: "adaptGlassToBrightBackdrop") != nil
        ? UserDefaults.standard.bool(forKey: "adaptGlassToBrightBackdrop") : true {
        didSet { UserDefaults.standard.set(adaptGlassToBrightBackdrop, forKey: "adaptGlassToBrightBackdrop") }
    }
    /// Barras al tempo de la canción cuando el audio está protegido
    @Published public var tempoFallbackEnabled: Bool = UserDefaults.standard.object(forKey: "tempoFallbackEnabled") != nil
        ? UserDefaults.standard.bool(forKey: "tempoFallbackEnabled") : true {
        didSet { UserDefaults.standard.set(tempoFallbackEnabled, forKey: "tempoFallbackEnabled") }
    }
    /// AirDrop: cerrar el aviso nativo y la ventana de Descargas que abre macOS (la animación propia se queda)
    @Published public var airDropReplacesNative: Bool = UserDefaults.standard.object(forKey: "airDropReplacesNative") != nil
        ? UserDefaults.standard.bool(forKey: "airDropReplacesNative") : true {
        didSet { UserDefaults.standard.set(airDropReplacesNative, forKey: "airDropReplacesNative") }
    }

    
    // Volume HUD State
    @Published public var isVolumeHUDActive: Bool = false
    @Published public var currentVolume: Float = 0.5
    @Published public var isVolumeMuted: Bool = false
    private var volumeDismissTimer: Timer?
    
    // Hover Sustained Expansion State (reemplaza los antiguos "espasmos" por expansión continua con sombra fija)
    @Published public var heartbeatScaleX: CGFloat = 1.0
    @Published public var heartbeatScaleY: CGFloat = 1.0
    @Published public var heartbeatShadowOpacity: Double = 0.0
    
    // Settings
    @Published public var expandOnHover: Bool = UserDefaults.standard.object(forKey: "expandOnHover") != nil
        ? UserDefaults.standard.bool(forKey: "expandOnHover")
        : false {
        didSet { UserDefaults.standard.set(expandOnHover, forKey: "expandOnHover") }
    }
    @Published public var enableHoverExpansion: Bool = UserDefaults.standard.object(forKey: "enableHoverExpansion") != nil
        ? UserDefaults.standard.bool(forKey: "enableHoverExpansion")
        : true {
        didSet {
            UserDefaults.standard.set(enableHoverExpansion, forKey: "enableHoverExpansion")
            if !enableHoverExpansion {
                setHoverState(false)
            }
        }
    }
    @Published public var hoverScaleAmount: Double = UserDefaults.standard.object(forKey: "hoverScaleAmount") != nil
        ? UserDefaults.standard.double(forKey: "hoverScaleAmount")
        : 1.045 {
        didSet { UserDefaults.standard.set(hoverScaleAmount, forKey: "hoverScaleAmount") }
    }
    @Published public var hoverShadowIntensity: Double = UserDefaults.standard.object(forKey: "hoverShadowIntensity") != nil
        ? UserDefaults.standard.double(forKey: "hoverShadowIntensity")
        : 0.52 {
        didSet { UserDefaults.standard.set(hoverShadowIntensity, forKey: "hoverShadowIntensity") }
    }
    @Published public var enableHaptics: Bool = UserDefaults.standard.object(forKey: "enableHaptics") != nil
        ? UserDefaults.standard.bool(forKey: "enableHaptics")
        : true {
        didSet { UserDefaults.standard.set(enableHaptics, forKey: "enableHaptics") }
    }
    @Published public var enableSoundFeedback: Bool = UserDefaults.standard.object(forKey: "enableSoundFeedback") != nil
        ? UserDefaults.standard.bool(forKey: "enableSoundFeedback")
        : true {
        didSet { UserDefaults.standard.set(enableSoundFeedback, forKey: "enableSoundFeedback") }
    }
    @Published public var showCompactWhenPlaying: Bool = UserDefaults.standard.object(forKey: "showCompactWhenPlaying") != nil
        ? UserDefaults.standard.bool(forKey: "showCompactWhenPlaying")
        : true {
        didSet {
            UserDefaults.standard.set(showCompactWhenPlaying, forKey: "showCompactWhenPlaying")
            reconcileCompactMode()
        }
    }
    @Published public var autoCollapseOnHoverExit: Bool = UserDefaults.standard.object(forKey: "autoCollapseOnHoverExit") != nil
        ? UserDefaults.standard.bool(forKey: "autoCollapseOnHoverExit")
        : true {
        didSet { UserDefaults.standard.set(autoCollapseOnHoverExit, forKey: "autoCollapseOnHoverExit") }
    }
    @Published public var isPlayerDetailExpanded: Bool = false
    
    // Mini-Apps Quick Access Pins
    @Published public var pinTimerMiniAppInNotch: Bool = UserDefaults.standard.object(forKey: "pinTimerMiniAppInNotch") != nil
        ? UserDefaults.standard.bool(forKey: "pinTimerMiniAppInNotch")
        : true {
        didSet { UserDefaults.standard.set(pinTimerMiniAppInNotch, forKey: "pinTimerMiniAppInNotch") }
    }
    @Published public var pinAudioMonitorMiniAppInNotch: Bool = UserDefaults.standard.object(forKey: "pinAudioMonitorMiniAppInNotch") != nil
        ? UserDefaults.standard.bool(forKey: "pinAudioMonitorMiniAppInNotch")
        : false {
        didSet { UserDefaults.standard.set(pinAudioMonitorMiniAppInNotch, forKey: "pinAudioMonitorMiniAppInNotch") }
    }
    
    // MARK: - Live Activities & Bolitas Settings
    @Published public var multiActivityMode: MultiActivityPresentationMode = {
        if let raw = UserDefaults.standard.string(forKey: "multiActivityMode"),
           let mode = MultiActivityPresentationMode(rawValue: raw) {
            return mode
        }
        return .modeA // Modo A por defecto (prioridad del proyecto)
    }() {
        didSet {
            UserDefaults.standard.set(multiActivityMode.rawValue, forKey: "multiActivityMode")
            ActivityCenter.shared.recalculateRoles()
        }
    }
    
    @Published public var satelliteLocation: SatelliteLocationPreference = {
        if let raw = UserDefaults.standard.string(forKey: "satelliteLocation"),
           let loc = SatelliteLocationPreference(rawValue: raw) {
            return loc
        }
        return .automatic
    }() {
        didSet {
            UserDefaults.standard.set(satelliteLocation.rawValue, forKey: "satelliteLocation")
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    @Published public var maxSatelliteBolitas: Int = {
        let val = UserDefaults.standard.integer(forKey: "maxSatelliteBolitas")
        return val > 0 ? val : 2 // 2 por defecto
    }() {
        didSet {
            UserDefaults.standard.set(maxSatelliteBolitas, forKey: "maxSatelliteBolitas")
            ActivityCenter.shared.recalculateRoles()
        }
    }
    
    @Published public var bolitaDiameter: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "bolitaDiameter")
        // 0 = automático: mismo alto que la cápsula del notch, como las bolitas de la Isla Dinámica del iPhone
        // (los tamaños fijos anteriores se migran a automático)
        return (saved > 0 && ![23.0, 26.0, 28.0, 36.0].contains(saved)) ? CGFloat(saved) : 0
    }() {
        didSet {
            UserDefaults.standard.set(Double(bolitaDiameter), forKey: "bolitaDiameter")
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    /// Diámetro real de las bolitas: el elegido, o el alto del notch en automático
    public var effectiveBolitaDiameter: CGFloat {
        bolitaDiameter > 0 ? bolitaDiameter : max(24, ScreenService.shared.currentGeometry.height)
    }
    
    @Published public var bolitaGap: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "bolitaGap")
        // 11 pt entre los bordes geométricos de la cápsula y la bolita (la sombra no cuenta)
        return (saved > 0 && saved != 8.0 && saved != 6.0) ? CGFloat(saved) : 11.0
    }() {
        didSet {
            UserDefaults.standard.set(Double(bolitaGap), forKey: "bolitaGap")
            NotchWindowManager.shared.updateHitAreaForCurrentState()
        }
    }
    
    // Visualizer Style Setting
    @Published public var visualizerColorStyle: VisualizerColorStyle = {
        if let saved = UserDefaults.standard.string(forKey: "visualizerColorStyle"),
           let style = VisualizerColorStyle(rawValue: saved) {
            return style
        }
        return .adaptive
    }() {
        didSet { UserDefaults.standard.set(visualizerColorStyle.rawValue, forKey: "visualizerColorStyle") }
    }
    
    @Published public var enableDragDropShelf: Bool = UserDefaults.standard.object(forKey: "enableDragDropShelf") != nil
        ? UserDefaults.standard.bool(forKey: "enableDragDropShelf")
        : true {
        didSet { UserDefaults.standard.set(enableDragDropShelf, forKey: "enableDragDropShelf") }
    }
    
    // MARK: - Modos de Apariencia & Liquid Glass Nativo (macOS 26+)
    @Published public var appearanceMode: NotchAppearanceMode = {
        if let saved = UserDefaults.standard.string(forKey: "notchAppearanceMode"),
           let mode = NotchAppearanceMode(rawValue: saved) {
            return mode
        }
        return .darkGlass // Por defecto: Cristal Oscuro ("Glass.regular" con apariencia oscura forzada)
    }() {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "notchAppearanceMode")
            DispatchQueue.main.async {
                NotchWindowManager.shared.panel?.appearance = NSAppearance(named: .darkAqua) // siempre oscura: el vidrio clear en apariencia clara se ve esmerilado
            }
        }
    }
    
    /// Modo efectivo considerando preferencias de accesibilidad del sistema
    public var effectiveAppearanceMode: NotchAppearanceMode {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ||
           NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return .pureOLED
        }
        return appearanceMode
    }
    
    public var isLiquidGlassEnabled: Bool {
        get { effectiveAppearanceMode != .pureOLED }
        set {
            guard newValue != (effectiveAppearanceMode != .pureOLED) else { return }
            if !newValue {
                appearanceMode = .pureOLED
            } else if appearanceMode == .pureOLED {
                appearanceMode = .darkGlass
            }
        }
    }
    
    // Opacidad de tinte en Cristal Oscuro: rango 0%-85%, DEFAULT 38% (0.38) para preservar profundidad óptica de Glass.regular
    @Published public var glassDarknessOpacity: Double = UserDefaults.standard.object(forKey: "glassDarknessOpacityV2") != nil
        ? max(0.0, min(0.85, UserDefaults.standard.double(forKey: "glassDarknessOpacityV2")))
        : 0.38 {
        didSet {
            let clamped = max(0.0, min(0.85, glassDarknessOpacity))
            UserDefaults.standard.set(clamped, forKey: "glassDarknessOpacityV2")
            UserDefaults.standard.set(clamped, forKey: "glassDarknessOpacity")
        }
    }
    @Published public var enableTrackpadSwipe: Bool = UserDefaults.standard.object(forKey: "enableTrackpadSwipe") != nil ? UserDefaults.standard.bool(forKey: "enableTrackpadSwipe") : true {
        didSet { UserDefaults.standard.set(enableTrackpadSwipe, forKey: "enableTrackpadSwipe") }
    }
    @Published public var enableAirPodsAnimation: Bool = UserDefaults.standard.object(forKey: "enableAirPodsAnimation") != nil ? UserDefaults.standard.bool(forKey: "enableAirPodsAnimation") : true {
        didSet { UserDefaults.standard.set(enableAirPodsAnimation, forKey: "enableAirPodsAnimation") }
    }
    
    // MARK: - Lock Screen Player Settings (Paso 0 - Paso 5)
    public enum LockScreenStyle: String, CaseIterable, Identifiable {
        case heroWidget = "heroWidget" // Carátula Hero + Cápsula Flotante (Referencia / iOS Widget)
        case compactCard = "compactCard" // Tarjeta Horizontal Unificada (macOS)
        case ambientCanvas = "ambientCanvas" // Canvas Inmersivo con Letras Sincronizadas (Imagen 1)
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .heroWidget: return "Hero Widget (iOS)"
            case .compactCard: return "Tarjeta Compacta (macOS)"
            case .ambientCanvas: return "Canvas Inmersivo con Letras (Imagen 1)"
            }
        }
    }
    
    @Published public var isAmbientCanvasOpen: Bool = false
    /// Pantalla bloqueada: el reproductor está en pantalla completa (transitorio; al bloquear arranca según
    /// `lockScreenStyle`)
    @Published public var isLockScreenFullscreen: Bool = false
    
    public enum LockScreenRenderMode: String, CaseIterable, Identifiable {
        case pureOLED = "pureOLED" // 0. 100% Negro Puro OLED (#000000 opaco absoluto)
        case nativeGlass = "nativeGlass" // 1. Liquid Glass nativo (.glassEffect macOS 26+)
        case visualEffect = "visualEffect" // 2. NSVisualEffectView behind-window
        case privateBlur = "privateBlur" // 3. CGSSetWindowBackgroundBlurRadius
        case solidDark = "solidDark" // 4. Translúcido oscuro sólido (fallback)
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .pureOLED: return "Negro Puro OLED 100% (#000000)"
            case .nativeGlass: return "Liquid Glass Nativo (macOS 26+)"
            case .visualEffect: return "NSVisualEffectView (Detrás de Ventana)"
            case .privateBlur: return "CoreGraphics Blur (CGSSetWindowBackgroundBlurRadius)"
            case .solidDark: return "Sólido Oscuro Translúcido"
            }
        }
    }
    
    @Published public var lockScreenRenderMode: LockScreenRenderMode = {
        if let raw = UserDefaults.standard.string(forKey: "lockScreenRenderMode"),
           let mode = LockScreenRenderMode(rawValue: raw) {
            return mode
        }
        return .nativeGlass
    }() {
        didSet {
            UserDefaults.standard.set(lockScreenRenderMode.rawValue, forKey: "lockScreenRenderMode")
            print("🎨 [AppState] LockScreenRenderMode actualizado a: \(lockScreenRenderMode.rawValue) (\(lockScreenRenderMode.displayName))")
        }
    }
    
    @Published public var isLockScreenArtworkExpanded: Bool = UserDefaults.standard.object(forKey: "isLockScreenArtworkExpanded") != nil
        ? UserDefaults.standard.bool(forKey: "isLockScreenArtworkExpanded")
        : false {
        didSet { UserDefaults.standard.set(isLockScreenArtworkExpanded, forKey: "isLockScreenArtworkExpanded") }
    }
    
    @Published public var lockScreenStyle: LockScreenStyle = {
        if let raw = UserDefaults.standard.string(forKey: "lockScreenStyle"),
           let style = LockScreenStyle(rawValue: raw) {
            return style
        }
        return .heroWidget
    }() {
        didSet { UserDefaults.standard.set(lockScreenStyle.rawValue, forKey: "lockScreenStyle") }
    }
    
    @Published public var isLockScreenTestArmed: Bool = false
    @Published public var enableLockScreenPlayer: Bool = UserDefaults.standard.object(forKey: "enableLockScreenPlayer") != nil
        ? UserDefaults.standard.bool(forKey: "enableLockScreenPlayer")
        : true {
        didSet { UserDefaults.standard.set(enableLockScreenPlayer, forKey: "enableLockScreenPlayer") }
    }
    @Published public var lockScreenPauseTimeoutSeconds: Int = UserDefaults.standard.object(forKey: "lockScreenPauseTimeoutSeconds") != nil
        ? UserDefaults.standard.integer(forKey: "lockScreenPauseTimeoutSeconds")
        : 30 {
        didSet { UserDefaults.standard.set(lockScreenPauseTimeoutSeconds, forKey: "lockScreenPauseTimeoutSeconds") }
    }
    @Published public var lockScreenVerticalOffset: CGFloat = UserDefaults.standard.object(forKey: "lockScreenVerticalOffset") != nil
        ? CGFloat(UserDefaults.standard.double(forKey: "lockScreenVerticalOffset"))
        : 0.0 {
        didSet { UserDefaults.standard.set(Double(lockScreenVerticalOffset), forKey: "lockScreenVerticalOffset") }
    }
    @Published public var lockScreenShowArtworkHalo: Bool = UserDefaults.standard.object(forKey: "lockScreenShowArtworkHalo") != nil
        ? UserDefaults.standard.bool(forKey: "lockScreenShowArtworkHalo")
        : false {
        didSet { UserDefaults.standard.set(lockScreenShowArtworkHalo, forKey: "lockScreenShowArtworkHalo") }
    }
    @Published public var lockScreenShowVolumeSlider: Bool = UserDefaults.standard.object(forKey: "lockScreenShowVolumeSlider") != nil
        ? UserDefaults.standard.bool(forKey: "lockScreenShowVolumeSlider")
        : false {
        didSet { UserDefaults.standard.set(lockScreenShowVolumeSlider, forKey: "lockScreenShowVolumeSlider") }
    }
    @Published public var lockScreenDimmingOpacity: Double = UserDefaults.standard.object(forKey: "lockScreenDimmingOpacity") != nil
        ? UserDefaults.standard.double(forKey: "lockScreenDimmingOpacity")
        : 0.22 {
        didSet { UserDefaults.standard.set(lockScreenDimmingOpacity, forKey: "lockScreenDimmingOpacity") }
    }
    @Published public var lockScreenDebugOutlines: Bool = UserDefaults.standard.object(forKey: "lockScreenDebugOutlines") != nil
        ? UserDefaults.standard.bool(forKey: "lockScreenDebugOutlines")
        : false {
        didSet { UserDefaults.standard.set(lockScreenDebugOutlines, forKey: "lockScreenDebugOutlines") }
    }
    @Published public var lockScreenHideMediaDetails: Bool = UserDefaults.standard.object(forKey: "lockScreenHideMediaDetails") != nil
        ? UserDefaults.standard.bool(forKey: "lockScreenHideMediaDetails")
        : false {
        didSet { UserDefaults.standard.set(lockScreenHideMediaDetails, forKey: "lockScreenHideMediaDetails") }
    }
    @Published public var hasPromptedLockScreenPrivacy: Bool = UserDefaults.standard.object(forKey: "hasPromptedLockScreenPrivacy") != nil
        ? UserDefaults.standard.bool(forKey: "hasPromptedLockScreenPrivacy")
        : false {
        didSet { UserDefaults.standard.set(hasPromptedLockScreenPrivacy, forKey: "hasPromptedLockScreenPrivacy") }
    }
    @Published public var lockScreenShowOnAllDisplays: Bool = UserDefaults.standard.object(forKey: "lockScreenShowOnAllDisplays") != nil
        ? UserDefaults.standard.bool(forKey: "lockScreenShowOnAllDisplays")
        : false {
        didSet { UserDefaults.standard.set(lockScreenShowOnAllDisplays, forKey: "lockScreenShowOnAllDisplays") }
    }

    // Drag & Drop / Shelf Settings
    @Published public var moveFilesToShelf: Bool = UserDefaults.standard.object(forKey: "moveFilesToShelf") != nil
        ? UserDefaults.standard.bool(forKey: "moveFilesToShelf")
        : true {
        didSet { UserDefaults.standard.set(moveFilesToShelf, forKey: "moveFilesToShelf") }
    }
    @Published public var isDropErrorAnimating: Bool = false
    @Published public var dropErrorMessage: String = ""
    @Published public var lastDroppedCount: Int = 0
    @Published public var enableDropInvitation: Bool = UserDefaults.standard.object(forKey: "enableDropInvitation") != nil
        ? UserDefaults.standard.bool(forKey: "enableDropInvitation")
        : true {
        didSet { UserDefaults.standard.set(enableDropInvitation, forKey: "enableDropInvitation") }
    }
    @Published public var dropInvitationDistance: Double = UserDefaults.standard.object(forKey: "dropInvitationDistance") != nil
        ? UserDefaults.standard.double(forKey: "dropInvitationDistance")
        : 175.0 {
        didSet { UserDefaults.standard.set(dropInvitationDistance, forKey: "dropInvitationDistance") }
    }
    @Published public var autoOpenShelfOnDrop: Bool = UserDefaults.standard.object(forKey: "autoOpenShelfOnDrop") != nil
        ? UserDefaults.standard.bool(forKey: "autoOpenShelfOnDrop")
        : true {
        didSet { UserDefaults.standard.set(autoOpenShelfOnDrop, forKey: "autoOpenShelfOnDrop") }
    }
    @Published public var enableShelfHaptics: Bool = UserDefaults.standard.object(forKey: "enableShelfHaptics") != nil
        ? UserDefaults.standard.bool(forKey: "enableShelfHaptics")
        : true {
        didSet { UserDefaults.standard.set(enableShelfHaptics, forKey: "enableShelfHaptics") }
    }
    @Published public var showShelfBadgeInNotch: Bool = UserDefaults.standard.object(forKey: "showShelfBadgeInNotch") != nil
        ? UserDefaults.standard.bool(forKey: "showShelfBadgeInNotch")
        : true {
        didSet { UserDefaults.standard.set(showShelfBadgeInNotch, forKey: "showShelfBadgeInNotch") }
    }
    
    /// Archivo de la repisa actualmente en proceso de ser arrastrado hacia afuera (Drag-Out)
    @Published public var activeDragOutItem: ShelfItem? = nil
    
    // Services
    public let screenService = ScreenService.shared
    public let musicService = MusicService.shared
    public let batteryService = BatteryService.shared
    public let hapticService = HapticService.shared
    public let audioService = AudioDeviceService.shared
    
    public var requestCollapse: (() -> Void)?
    private var musicPauseDismissTimer: Timer?
    private var alertDismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public var shouldShowCompact: Bool {
        // La repisa ya no abre las alas: se muestra como bolita (ShelfActivityProvider)
        return (musicService.hasActiveMusic || musicPauseDismissTimer != nil) && showCompactWhenPlaying
    }
    
    /// Reconcilia de forma segura el modo compacto cuando cambia la música, la bandeja o se cierra una actividad
    public func reconcileCompactMode() {
        guard mode != .expanded && mode != .shelf else { return }
        if shouldShowCompact {
            if mode == .idle {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    mode = .compact
                }
            }
        } else {
            if mode == .compact {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    mode = .idle
                }
            }
        }
    }
    
    private init() {
        setupSubscriptions()
        self.shelfItems = ShelfStorageService.shared.loadExistingStashedItems()
    }
    
    private func setupSubscriptions() {
        // Battery MagSafe connection listener -> Publicar actividad de carga dedicada (sin forzar reproductor de música)
        batteryService.onPowerConnected = { percentage in
            ChargingActivityProvider.shared.publishChargingActivity(
                percentage: percentage,
                isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isPluggedIn: true
            )
        }
        
        // Alerta de Batería Baja automática estilo Apple Card / Dynamic Island
        batteryService.onLowBattery = { percentage in
            ChargingActivityProvider.shared.publishLowBatteryActivity(percentage: percentage)
        }
        
        // Volume change listener
        audioService.onVolumeChanged = { [weak self] volume, isMuted in
            self?.handleVolumeChanged(volume: volume, isMuted: isMuted)
        }
        
        // Music changes con retención de 30 segundos al pausar
        musicService.$hasActiveMusic
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                print("[AppState] hasActiveMusic: \(isPlaying), current mode: \(self.mode)")
                if isPlaying {
                    // Cancela cualquier timer de colapso pendiente
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = nil
                    self.reconcileCompactMode()
                } else {
                    // Al pausar: retener el minirreproductor durante 30 segundos antes de colapsar
                    self.musicPauseDismissTimer?.invalidate()
                    self.musicPauseDismissTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self = self, !self.musicService.hasActiveMusic else { return }
                            self.musicPauseDismissTimer = nil
                            if self.mode == .compact || self.mode == .idle {
                                self.reconcileCompactMode()
                            } else if self.mode == .expanded && !self.isHovered {
                                self.collapse()
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func handleVolumeChanged(volume: Float, isMuted: Bool) {
        self.currentVolume = volume
        self.isVolumeMuted = isMuted
        self.isVolumeHUDActive = false
    }
    
    /// Expansión suave y continua tipo Dynamic Island real con sombra fija mientras el cursor permanece sobre el Notch
    public func setHoverState(_ hovering: Bool) {
        if hovering && enableHoverExpansion && mode != .expanded && mode != .shelf {
            let targetX = CGFloat(max(1.01, min(1.09, hoverScaleAmount)))
            let targetY = CGFloat(1.0 + (hoverScaleAmount - 1.0) * 0.72)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                heartbeatScaleX = targetX
                heartbeatScaleY = targetY
                heartbeatShadowOpacity = hoverShadowIntensity
            }
        } else {
            // Ya en reposo: no publicar nada (evita reevaluar todas las vistas sin motivo)
            guard heartbeatScaleX != 1.0 || heartbeatScaleY != 1.0 || heartbeatShadowOpacity != 0.0 else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                heartbeatScaleX = 1.0
                heartbeatScaleY = 1.0
                heartbeatShadowOpacity = 0.0
            }
        }
    }
    
    public func triggerHeartbeat() {
        setHoverState(true)
    }
    
    public func triggerAlert(_ type: AlertType, duration: TimeInterval = 4.0) {
        let alert = NotchAlert(type: type)
        self.activeAlert = alert
        self.activeTab = .alerts
        
        if mode != .expanded {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                self.mode = .expanded
            }
            hapticService.triggerExpand()
        }
        
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.collapse()
            self.activeAlert = nil
        }
    }
    
    public func handleMouseEnter() {
        guard !isHovered else { return }
        self.isHovered = true
        if expandOnHover {
            if mode == .idle || mode == .compact {
                withAnimation(.spring(response: 0.68, dampingFraction: 0.76)) {
                    if !self.shelfItems.isEmpty && !self.musicService.hasActiveMusic {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    } else {
                        self.mode = .expanded
                        self.activeTab = .music
                    }
                }
                hapticService.triggerExpand()
            }
        } else {
            setHoverState(true)
        }
    }
    
    public func handleMouseLeave() {
        self.isHovered = false
        setHoverState(false)
        if expandOnHover {
            if mode == .expanded && activeAlert == nil {
                collapse()
            }
        }
    }
    
    public func collapse() {
        // Asignar sólo si cambia: cada asignación a un @Published (aunque sea el mismo valor) hace que TODAS
        // las vistas que observan AppState se reevalúen, y eso en el primer cuadro del cierre lo congelaba
        if overscrollOffset != 0 { overscrollOffset = 0 }
        if contentOverscrollOffset != 0 { contentOverscrollOffset = 0 }
        if verticalOverscrollOffset != 0 { verticalOverscrollOffset = 0 }
        if contentVerticalOverscrollOffset != 0 { contentVerticalOverscrollOffset = 0 }
        if activeMiniAppOverlay != nil { activeMiniAppOverlay = nil }
        setHoverState(false)
        if (shelfItems.isEmpty || musicService.hasActiveMusic) && activeTab != .music {
            activeTab = .music
        }
        
        if let requestCollapse = requestCollapse {
            requestCollapse()
        } else {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeCloseResponse,
                dampingFraction: ExitAnimationMetrics.shapeCloseDamping
            )
            withAnimation(springAnim) {
                mode = shouldShowCompact ? .compact : .idle
                hapticService.triggerSnap()
            }
        }
    }
    
    public func expand() {
        guard mode != .expanded && mode != .shelf else { return }
        overscrollOffset = 0
        contentOverscrollOffset = 0
        verticalOverscrollOffset = 0
        contentVerticalOverscrollOffset = 0
        isPlayerDetailExpanded = false
        setHoverState(false)
        if shelfItems.isEmpty {
            activeTab = .music
        }
        
        let springAnim = AnimationSpeedManager.shared.spring(
            response: ExitAnimationMetrics.shapeOpenResponse,
            dampingFraction: ExitAnimationMetrics.shapeOpenDamping
        )
        withAnimation(springAnim) {
            mode = (activeTab == .shelf && !shelfItems.isEmpty) ? .shelf : .expanded
            hapticService.triggerExpand()
        }
    }
    
    public func openWithMiniApp(_ miniApp: MiniAppKind) {
        activeMiniAppOverlay = miniApp
        activeTab = .music
        if mode != .expanded {
            let springAnim = AnimationSpeedManager.shared.spring(
                response: ExitAnimationMetrics.shapeOpenResponse,
                dampingFraction: ExitAnimationMetrics.shapeOpenDamping
            )
            withAnimation(springAnim) {
                mode = .expanded
            }
            hapticService.triggerExpand()
        }
    }
    
    public func toggleExpand() {
        if mode == .expanded || mode == .shelf {
            collapse()
        } else {
            expand()
        }
    }
    
    public func addShelfFile(url: URL) {
        guard !shelfItems.contains(where: { $0.url.path == url.path || $0.originalURL?.path == url.path }) else {
            mode = .shelf
            activeTab = .shelf
            return
        }
        let item = ShelfStorageService.shared.stashFile(from: url, shouldMove: moveFilesToShelf)
        shelfItems.append(item)
        mode = .shelf
        activeTab = .shelf
        hapticService.triggerDrop()
    }
    
    public var onDropSuccess: (() -> Void)?
    public var onDropError: ((String) -> Void)?
    
    public func triggerDropError(message: String) {
        isDropErrorAnimating = true
        dropErrorMessage = message
        hapticService.triggerSnap()
        onDropError?(message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
                self.isDropErrorAnimating = false
            }
        }
    }
    
    public func triggerDropSuccess(urls: [URL]) {
        DNDLogger.log("AppState.triggerDropSuccess called with \(urls.count) urls")
        isDropSuccessAnimating = true
        isDropErrorAnimating = false
        var addedAny = false
        var newBatch: [ShelfItem] = []
        
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("File already exists in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("Stashed item: \(item.name), destination: \(item.url.path), isStashed: \(item.isStashed)")
        }
        
        self.lastDroppedCount = newBatch.isEmpty ? urls.count : newBatch.count
        
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        
        if addedAny && enableShelfHaptics {
            hapticService.triggerDrop()
        }
        onDropSuccess?()
        
        // Retención de confirmación de 0.65 s para disfrutar la animación de éxito antes de retraerse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self = self else { return }
            let needsHold = self.mode == .compact && self.musicService.hasActiveMusic
            if needsHold {
                self.isHoldingBareNotch = true
            }
            withAnimation(.spring(response: ExitAnimationMetrics.cardDismissResponse, dampingFraction: ExitAnimationMetrics.cardDismissDamping)) {
                self.isDropInvitationActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isDropSuccessAnimating = false
                if addedAny || self.autoOpenShelfOnDrop || !self.shelfItems.isEmpty {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
                        self.mode = .shelf
                        self.activeTab = .shelf
                    }
                    if self.enableShelfHaptics {
                        self.hapticService.triggerSnap()
                    }
                } else if needsHold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard !self.isDropInvitationActive && ActivityCenter.shared.currentActivity == nil else {
                            self.isHoldingBareNotch = false
                            return
                        }
                        withAnimation(AnimationSpeedManager.shared.spring(response: 0.44, dampingFraction: 0.82)) {
                            self.isHoldingBareNotch = false
                        }
                    }
                }
            }
        }
    }
    
    public func addShelfFiles(urls: [URL]) {
        DNDLogger.log("AppState.addShelfFiles called with \(urls.count) urls")
        var addedAny = false
        var newBatch: [ShelfItem] = []
        for url in urls {
            let canonical = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            // Limpiar registros antiguos cuyo archivo ya no exista en la repisa
            shelfItems.removeAll { item in
                if item.url.path == canonical.path || item.originalURL?.path == canonical.path {
                    return !FileManager.default.fileExists(atPath: item.url.path)
                }
                return false
            }
            guard !shelfItems.contains(where: { $0.url.path == canonical.path || $0.originalURL?.path == canonical.path }) else {
                DNDLogger.log("addShelfFiles: file already in shelf: \(canonical.lastPathComponent)")
                continue
            }
            let item = ShelfStorageService.shared.stashFile(from: canonical, shouldMove: moveFilesToShelf)
            shelfItems.append(item)
            newBatch.append(item)
            addedAny = true
            DNDLogger.log("addShelfFiles stashed: \(item.name) at \(item.url.path)")
        }
        if !newBatch.isEmpty {
            ShelfStorageService.shared.recordBatch(newBatch)
        }
        if addedAny {
            if enableShelfHaptics {
                hapticService.triggerDrop()
            }
            if mode != .shelf {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                    mode = .shelf
                    activeTab = .shelf
                }
            }
        } else if !shelfItems.isEmpty && mode != .shelf {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.84)) {
                mode = .shelf
                activeTab = .shelf
            }
        }
    }
    
    public func removeShelfItem(_ item: ShelfItem, moveToTrash: Bool = true) {
        if moveToTrash && item.isStashed {
            ShelfStorageService.shared.moveToTrash(item: item)
        }
        shelfItems.removeAll(where: { $0.id == item.id || $0.url.path == item.url.path })
    }
    
    public func restoreShelfItemToOrigin(_ item: ShelfItem) {
        if ShelfStorageService.shared.restoreToOrigin(item: item) {
            shelfItems.removeAll(where: { $0.id == item.id })
            hapticService.triggerSnap()
        }
    }
    
    public func restoreAllShelfItemsToOrigin() {
        var toRemove: [UUID] = []
        for item in shelfItems {
            if ShelfStorageService.shared.restoreToOrigin(item: item) {
                toRemove.append(item.id)
            }
        }
        shelfItems.removeAll(where: { toRemove.contains($0.id) })
        hapticService.triggerSnap()
    }
    
    public func emptyShelfToTrash() {
        for item in shelfItems {
            if item.isStashed {
                ShelfStorageService.shared.moveToTrash(item: item)
            }
        }
        shelfItems.removeAll()
        hapticService.triggerSnap()
    }
    
    public func undoLastDrop() {
        let restored = ShelfStorageService.shared.undoLastBatch(from: &shelfItems)
        if !restored.isEmpty {
            hapticService.triggerSnap()
        }
    }
}
