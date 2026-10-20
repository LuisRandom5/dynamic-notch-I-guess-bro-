import Foundation

/// Qué compilación es: la de desarrollo (con demostraciones, paneles de prueba, Animation Studio, cámara lenta y
/// rutas /debug) o la beta para probadores, sin nada de eso. `./scripts/build_app.sh --beta` compila con `-DBETA`.
public enum BuildFlavor {
    #if BETA
    public static let isBeta = true
    #else
    public static let isBeta = false
    #endif

    /// Herramientas de desarrollo a la vista (menús de prueba, paneles, laboratorios, disparadores de prueba)
    public static var hasDeveloperTools: Bool { !isBeta }
}
