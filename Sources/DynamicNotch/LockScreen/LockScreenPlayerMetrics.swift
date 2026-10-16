import SwiftUI

/// Constantes y proporciones oficiales del Reproductor en Pantalla de Bloqueo estilo Apple Music / macOS Tahoe.
public struct LockScreenPlayerMetrics {
    // MARK: - Dimensiones de la Tarjeta
    public static let cardWidth: CGFloat = 520
    public static let cardHeightCompact: CGFloat = 164
    public static let cardHeightWithVolume: CGFloat = 208
    public static let cardCornerRadius: CGFloat = 34
    public static let cardPadding: CGFloat = 18
    
    // MARK: - Carátula Concéntrica (34 - 18 = 16)
    public static let artworkSize: CGFloat = 128
    public static let artworkCornerRadius: CGFloat = 16
    public static let artworkShadowRadius: CGFloat = 12
    public static let artworkShadowY: CGFloat = 4
    public static let artworkShadowOpacity: Double = 0.25
    
    // MARK: - Movimiento de Carátula al Pausar / Reproducir (Apple Music)
    public static let pausedScale: CGFloat = 0.88
    public static let playingScale: CGFloat = 1.0
    public static let pauseSpring = Animation.spring(response: 0.40, dampingFraction: 0.75)
    
    // MARK: - Columna Derecha
    public static let rightColumnWidth: CGFloat = 338
    
    // MARK: - Tipografía SF Pro idéntica al reproductor desbloqueado (PlayerMetrics)
    public static let titleFontSize: CGFloat = PlayerMetrics.titleFontSize       // 14.5
    public static let artistFontSize: CGFloat = PlayerMetrics.artistFontSize     // 12.5
    public static let timeFontSize: CGFloat = PlayerMetrics.timeFontSize         // 12.0
    public static let titleFontWeight: Font.Weight = .bold
    public static let artistFontWeight: Font.Weight = .medium
    public static let artistOpacity: Double = PlayerMetrics.artistOpacity        // 0.60
    public static let timeOpacity: Double = PlayerMetrics.timeOpacity            // 0.55
    
    // MARK: - Icono de la Fuente (Esquina Superior Derecha, sin texto)
    public static let appIconSize: CGFloat = 22
    public static let appIconCornerRadius: CGFloat = 6
    public static let appIconOpacity: Double = 0.85
    
    // MARK: - Barra de Progreso
    public static let progressBarHeightResting: CGFloat = 4
    public static let progressBarHeightHovered: CGFloat = 8
    public static let progressFillOpacity: Double = 0.90
    public static let progressTrackOpacity: Double = 0.28
    public static let progressHoverSpring = Animation.spring(response: 0.28, dampingFraction: 0.75)
    
    // MARK: - Controles Multimedia (Solo glifos sin círculo)
    public static let skipButtonWidth: CGFloat = 28
    public static let playPauseButtonWidth: CGFloat = 40
    public static let controlsSpacing: CGFloat = 28
    public static let buttonPressedScale: CGFloat = 0.92
    
    // MARK: - Posición Vertical por Defecto
    /// Borde superior a ~52% de la altura de pantalla medida desde arriba:
    /// Ubicado más abajo según preferencia del usuario.
    public static let defaultTopPositionRatio: CGFloat = 0.52
    
    // MARK: - Sombra Externa de la Tarjeta (Solo sobre silueta RoundedRectangle, nunca ventana)
    public static let cardShadowRadius: CGFloat = 30
    public static let cardShadowY: CGFloat = 12
    public static let cardShadowOpacity: Double = 0.36
    
    // MARK: - Capa de Atenuación Uniforme (Normaliza fondos con manchas oscuras o claras)
    public static let uniformDimmingOpacityDefault: Double = 0.22
    public static let ambientHaloOpacity: Double = 0.12
    
    // MARK: - Dimensiones Hero Widget (Estilo iOS / Referencia del Usuario)
    public static let heroArtworkSize: CGFloat = 240
    public static let heroArtworkCornerRadius: CGFloat = 24
    public static let heroThumbnailSize: CGFloat = 54
    public static let heroThumbnailCornerRadius: CGFloat = 12
    public static let heroCardWidth: CGFloat = 410
    public static let heroCardHeight: CGFloat = 120
    public static let heroCardHeightWithVolume: CGFloat = 158
    public static let heroCardCornerRadius: CGFloat = 26
    public static let heroSpacing: CGFloat = 16
    public static let heroPanelWidth: CGFloat = 450
    public static let heroPanelHeight: CGFloat = 430
    public static let heroPanelHeightWithVolume: CGFloat = 470
}

