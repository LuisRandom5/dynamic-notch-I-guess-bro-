import Foundation

/// Texto en el idioma de la Mac: busca la traducción en `Resources/<idioma>.lproj/Localizable.strings` y, si no
/// hay, deja el español original. Los `Text("literal")` de SwiftUI ya se traducen solos; esto es para los textos
/// que llegan como `String` (filas de Ajustes, menú de la barra, avisos armados en código).
@inline(__always)
func L(_ spanish: String) -> String {
    NSLocalizedString(spanish, bundle: .main, comment: "")
}
