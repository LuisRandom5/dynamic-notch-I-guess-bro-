import SwiftUI

// MARK: - PlayerMetrics (Constantes para el Reproductor Expandido Idéntico al iPhone)
public struct PlayerMetrics {
    // MARK: - Forma y Fondo (Dimensiones holgadas y confortables: 456 x 196 pt, radio 50)
    public static let cardWidth: CGFloat = 456               // Aumentado a 456 pt para amplio margen lateral y que ningún icono roce las esquinas
    public static let cardHeight: CGFloat = 196              // Aumentado a 196 pt para dar altura respirable a las 3 filas
    public static let detailCardHeight: CGFloat = 264        // Altura extendida estilo mini reproductor Apple Music
    public static let cornerRadius: CGFloat = 50             // Curva continua ultra-suave
    public static let paddingInternal: CGFloat = 24          // 24 pt de padding interno para que la carátula y el visualizador respiren
    public static let topContentPadding: CGFloat = 36        // Espacio superior holgado bajo el notch de la Mac
    
    // Degradado vertical del fondo (#000000 arriba -> #0B0B0B abajo desde 65%)
    public static let backgroundTopColor = Color.black
    public static let backgroundBottomColor = Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0B / 255.0)
    public static let backgroundShiftLocation: CGFloat = 0.65
    
    // Borde de 1 pt (blanco 0% arriba -> blanco 10% abajo)
    public static let borderWidth: CGFloat = 1.0
    public static let borderTopOpacity: Double = 0.0
    public static let borderMidOpacity: Double = 0.02
    public static let borderBottomOpacity: Double = 0.10
    
    // Sombra multicapa cinematográfica estilo Apple
    public static let shadowRadius: CGFloat = 36
    public static let shadowY: CGFloat = 12
    public static let shadowOpacity: Double = 0.55
    
    // MARK: - Fila 1: Carátula, Texto y Visualizador
    public static let artworkSize: CGFloat = 46
    public static let artworkCornerRadius: CGFloat = 11
    public static let artworkToTextSpacing: CGFloat = 12
    
    public static let titleFontSize: CGFloat = 14.5
    public static let artistFontSize: CGFloat = 12.5
    public static let artistOpacity: Double = 0.60
    public static let titleToArtistSpacing: CGFloat = 2.0
    
    // Visualizador de Audio (AudioVisualizer - Barritas finas, elegantes y perfectamente centradas)
    public static let visualizerBarCount: Int = 6
    public static let visualizerBarWidth: CGFloat = 2.0
    public static let visualizerBarSpacing: CGFloat = 1.8
    public static let visualizerMinHeight: CGFloat = 2.4
    public static let visualizerMaxHeight: CGFloat = 13.0
    public static let visualizerPausedDotSize: CGFloat = 2.4
    public static let visualizerTopGradient = Color(red: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0) // #8B5CF6 Violeta
    public static let visualizerBottomGradient = Color(red: 0xD9 / 255.0, green: 0x46 / 255.0, blue: 0xEF / 255.0) // #D946EF Magenta/Rosa
    
    // MARK: - Fila 2: Progreso
    public static let row1ToRow2Spacing: CGFloat = 12
    public static let timeFontSize: CGFloat = 12.0
    public static let timeOpacity: Double = 0.55
    public static let timeWidth: CGFloat = 46                // Suficiente espacio para "-1:46" sin elipsis "-1:..."
    public static let timeToBarSpacing: CGFloat = 8
    
    public static let progressBarHeight: CGFloat = 4.5
    public static let progressBarHoverHeight: CGFloat = 6.5
    public static let progressBarFillColor = Color(red: 0xE8 / 255.0, green: 0xE8 / 255.0, blue: 0xE8 / 255.0) // #E8E8E8
    public static let progressBarTrackColor = Color.white.opacity(0.20) // blanco al 20%
    
    // MARK: - Fila 3: Controles
    public static let row2ToRow3Spacing: CGFloat = 14
    public static let controlsCenterSpacing: CGFloat = 58
    
    public static let skipButtonWidth: CGFloat = 22
    public static let skipButtonHeight: CGFloat = 14
    
    // Play / Pausa
    public static let playPauseWidth: CGFloat = 22
    public static let playPauseHeight: CGFloat = 20
    public static let pauseBarWidth: CGFloat = 5.5
    public static let pauseBarHeight: CGFloat = 18
    public static let pauseBarRadius: CGFloat = 1.8
    public static let pauseBarSpacing: CGFloat = 2.6
    public static let playIconSize: CGFloat = 19
    
    // Botones Laterales (Shuffle & AirPlay)
    public static let sideButtonWidth: CGFloat = 22
    public static let sideButtonColor = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0) // #8E8E93
    public static let buttonPressScale: CGFloat = 0.90
    
    public static let bottomPadding: CGFloat = 22
}
