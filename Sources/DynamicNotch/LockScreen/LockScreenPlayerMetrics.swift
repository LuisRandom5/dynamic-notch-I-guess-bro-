import SwiftUI

/// Constantes y proporciones oficiales del Reproductor en Pantalla de Bloqueo estilo Apple HIG / macOS Tahoe.
public struct LockScreenPlayerMetrics {
    // MARK: - Presentación Compacta (Horizontal)
    public static let compactCardWidth: CGFloat = 460
    public static let compactCardHeight: CGFloat = 136
    public static let compactCardHeightWithVolume: CGFloat = 168
    public static let compactCardCornerRadius: CGFloat = 24
    public static let compactPadding: CGFloat = 14
    
    // Carátula cuadrada 1:1 en modo compacto
    public static let compactArtworkSize: CGFloat = 108
    public static let compactArtworkCornerRadius: CGFloat = 16
    
    // MARK: - Presentación Vertical Hero (Estilo iOS Lockscreen / Hero)
    public static let heroArtworkSize: CGFloat = 220
    public static let heroArtworkCornerRadius: CGFloat = 20
    public static let heroThumbnailSize: CGFloat = 52
    public static let heroThumbnailCornerRadius: CGFloat = 12
    
    public static let heroCardWidth: CGFloat = 410
    public static let heroCardHeight: CGFloat = 124
    public static let heroCardHeightWithVolume: CGFloat = 156
    public static let heroCardCornerRadius: CGFloat = 24
    public static let heroSpacing: CGFloat = 16
    public static let heroPanelWidth: CGFloat = 440
    public static let heroPanelHeight: CGFloat = 410
    public static let heroPanelHeightWithVolume: CGFloat = 450
    
    // MARK: - Compatibilidad con Métricas Previas
    public static var cardWidth: CGFloat { compactCardWidth }
    public static var cardHeightCompact: CGFloat { compactCardHeight }
    public static var cardHeightWithVolume: CGFloat { compactCardHeightWithVolume }
    public static var cardCornerRadius: CGFloat { compactCardCornerRadius }
    public static var cardPadding: CGFloat { compactPadding }
    public static var artworkSize: CGFloat { compactArtworkSize }
    public static var artworkCornerRadius: CGFloat { compactArtworkCornerRadius }
    public static let rightColumnWidth: CGFloat = 306
    
    // MARK: - Movimiento de Carátula al Pausar / Reproducir (Apple Music)
    public static let pausedScale: CGFloat = 0.90
    public static let playingScale: CGFloat = 1.0
    public static let pauseSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    
    // MARK: - Tipografía Nativa Apple SF Pro
    public static let titleFontSize: CGFloat = 14.5
    public static let artistFontSize: CGFloat = 12.5
    public static let timeFontSize: CGFloat = 11.0
    public static let titleFontWeight: Font.Weight = .bold
    public static let artistFontWeight: Font.Weight = .medium
    public static let artistOpacity: Double = 0.65
    public static let timeOpacity: Double = 0.55
    
    // MARK: - Icono de la Fuente
    public static let appIconSize: CGFloat = 18
    public static let appIconCornerRadius: CGFloat = 5
    public static let appIconOpacity: Double = 0.90
    
    // MARK: - Barra de Progreso Scrubber
    public static let progressBarHeightResting: CGFloat = 3.5
    public static let progressBarHeightHovered: CGFloat = 6.0
    public static let progressFillOpacity: Double = 0.95
    public static let progressTrackOpacity: Double = 0.22
    public static let progressHoverSpring = Animation.spring(response: 0.24, dampingFraction: 0.82)
    
    // MARK: - Controles Multimedia (Glifos limpios estilo Apple Control Center)
    public static let skipButtonWidth: CGFloat = 28
    public static let playPauseButtonWidth: CGFloat = 38
    public static let controlsSpacing: CGFloat = 28
    public static let buttonPressedScale: CGFloat = 0.90
    
    // MARK: - Posición Vertical por Defecto
    public static let defaultTopPositionRatio: CGFloat = 0.52
    
    // MARK: - Sombra Externa (Silueta continua, nunca ventana)
    public static let cardShadowRadius: CGFloat = 22
    public static let cardShadowY: CGFloat = 10
    public static let cardShadowOpacity: Double = 0.35
    public static let artworkShadowRadius: CGFloat = 16
    public static let artworkShadowY: CGFloat = 6
    public static let artworkShadowOpacity: Double = 0.28
    
    // MARK: - Capa de Atenuación y Resplandor Ambiental
    public static let uniformDimmingOpacityDefault: Double = 0.20
    public static let ambientHaloOpacity: Double = 0.38
}
