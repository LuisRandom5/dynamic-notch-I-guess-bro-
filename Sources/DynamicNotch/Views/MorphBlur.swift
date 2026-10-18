import SwiftUI

// MARK: - Desenfoque de transformación (estándar de Dynamic Notch)
//
// Como en la Isla Dinámica: mientras la forma del notch se transforma (abrir/cerrar el reproductor, la
// repisa, una tarjeta, cambiar de actividad), su CONTENIDO se desenfoca un instante y vuelve a enfocarse
// cuando la forma llega a su tamaño. Oculta el contenido "a medio acomodar" y hace que el cambio se sienta
// como una sola masa que se transforma.
//
// Uso (para todo contenido nuevo dentro del notch):
//     contenido.morphBlur(on: claveDelEstado, hold: appState.gestureBlurHold)
// La clave es cualquier valor que cambie cuando cambia lo que muestra el notch. `hold` mantiene el
// desenfoque mientras el usuario desliza en el trackpad: sigue el recorrido de los dedos y, si el gesto ya
// disparó el cambio, se queda hasta que los levanta.

public struct MorphBlurModifier<Key: Equatable>: ViewModifier {
    let key: Key
    let radius: CGFloat
    /// Desenfoque mantenido desde fuera (0…1), p. ej. por un gesto del trackpad en curso
    var hold: CGFloat = 0

    @State private var blur: CGFloat = 0
    @State private var token = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .blur(radius: reduceMotion ? 0 : max(blur, hold * radius))
            .onChange(of: key) { _, _ in
                guard !reduceMotion else { return }
                token += 1
                let current = token
                // Entra rápido (la forma empieza a moverse) y se aclara mientras la forma se asienta
                withAnimation(.easeOut(duration: 0.10)) { blur = radius }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    guard current == token else { return }
                    withAnimation(.easeOut(duration: 0.34)) { blur = 0 }
                }
            }
    }
}

public extension View {
    /// Desenfoque breve del contenido durante una transformación del notch (ver MorphBlurModifier)
    /// - hold: desenfoque mantenido (0…1) mientras dura una interacción, p. ej. `AppState.gestureBlurHold`
    func morphBlur<Key: Equatable>(on key: Key, radius: CGFloat = 14, hold: CGFloat = 0) -> some View {
        modifier(MorphBlurModifier(key: key, radius: radius, hold: hold))
    }
}
