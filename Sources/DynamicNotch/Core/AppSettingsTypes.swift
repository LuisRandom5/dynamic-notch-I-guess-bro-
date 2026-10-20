import AppKit
import SwiftUI
import Combine

// Opciones de los ajustes de AppState (pickers de la ventana de Ajustes)
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

/// Texto de los mensajes en los avisos (WhatsApp, Mensajes), como "Mostrar vistas previas" del iPhone
public enum MessagePreviewPrivacy: String, CaseIterable, Identifiable {
    case always
    case hideWhileRecording
    case never

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .always: return "Mostrar siempre"
        case .hideWhileRecording: return "Ocultar al grabar la pantalla"
        case .never: return "Ocultar siempre"
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
