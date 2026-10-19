import AppKit

/// Geometría de la superficie donde vive la isla: el notch físico de la MacBook o, en pantallas sin notch,
/// una isla que el app dibuja por su cuenta. Todo lo que dibuja o posiciona la isla parte de aquí, así el
/// mismo código sirve para las dos (ver PLAN_ISLA_DINAMICA.md, sección 4).
///
/// Coordenadas de pantalla de AppKit (origen abajo a la izquierda).
public struct SurfaceGeometry: Equatable {
    public enum Kind: String, Equatable {
        /// Notch físico detectado por `auxiliaryTopLeftArea/RightArea`
        case physicalNotch
        /// Pantalla sin notch: forma de notch colgando del borde superior (comportamiento actual)
        case virtualNotch
        /// Pantalla sin notch: cápsula flotante separada del borde, como la Isla Dinámica del iPhone (Fase B)
        case floatingIsland
    }

    public var kind: Kind
    /// Marco completo de la pantalla que la contiene
    public var screenBounds: CGRect
    /// Forma en reposo (el notch o la cápsula sin actividad)
    public var notchBoundsInScreen: CGRect
    /// Ancho central que el contenido debe dejar libre (la cámara). En una isla sin cámara puede ser 0
    public var cameraCutoutWidth: CGFloat
    /// Separación entre el borde superior de la pantalla y la superficie (0 = cuelga del borde)
    public var topInset: CGFloat

    public init(kind: Kind, screenBounds: CGRect, notchBoundsInScreen: CGRect, cameraCutoutWidth: CGFloat, topInset: CGFloat) {
        self.kind = kind
        self.screenBounds = screenBounds
        self.notchBoundsInScreen = notchBoundsInScreen
        self.cameraCutoutWidth = cameraCutoutWidth
        self.topInset = topInset
    }

    // MARK: Atajos (los mismos nombres que tenía NotchGeometry)

    public var hasPhysicalNotch: Bool { kind == .physicalNotch }
    public var width: CGFloat { notchBoundsInScreen.width }
    public var height: CGFloat { notchBoundsInScreen.height }
    public var centerX: CGFloat { notchBoundsInScreen.midX }
    /// Cuelga del borde superior (notch físico o virtual): esquinas de arriba rectas
    public var hangsFromTopEdge: Bool { topInset == 0 }

    // MARK: Construcción

    /// Margen subpixel para abrazar el bisel del notch físico
    public static let physicalNotchPadding = CGSize(width: 3, height: 1)
    /// Tamaño del notch virtual en pantallas sin notch (comportamiento previo)
    public static let virtualNotchSize = CGSize(width: 180, height: 32)

    /// Notch físico a partir de las zonas auxiliares que reporta `NSScreen`. `nil` si no hay notch.
    public static func physicalNotch(screenFrame: CGRect, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?) -> SurfaceGeometry? {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
              left.width > 0, right.width > 0 else { return nil }
        let baseWidth = right.minX - left.maxX
        let baseHeight = screenFrame.maxY - left.minY
        guard baseWidth > 0, baseHeight > 0 else { return nil }
        let pad = physicalNotchPadding
        let width = baseWidth + pad.width
        let height = baseHeight + pad.height
        let bounds = CGRect(x: left.maxX - pad.width / 2, y: left.minY - pad.height, width: width, height: height)
        return SurfaceGeometry(kind: .physicalNotch, screenBounds: screenFrame, notchBoundsInScreen: bounds,
                               cameraCutoutWidth: width, topInset: 0)
    }

    /// Notch dibujado por el app en una pantalla sin notch, centrado y colgando del borde superior
    public static func virtualNotch(screenFrame: CGRect, size: CGSize = virtualNotchSize) -> SurfaceGeometry {
        let bounds = CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                            width: size.width, height: size.height)
        return SurfaceGeometry(kind: .virtualNotch, screenBounds: screenFrame, notchBoundsInScreen: bounds,
                               cameraCutoutWidth: size.width, topInset: 0)
    }

    /// Cápsula flotante tipo iPhone, separada `topInset` del borde superior. Sin cámara: el hueco central es
    /// opcional (`cameraCutoutWidth`), por defecto se respeta para que se vea igual que en el iPhone.
    public static func floatingIsland(screenFrame: CGRect, size: CGSize, topInset: CGFloat, cameraCutoutWidth: CGFloat? = nil) -> SurfaceGeometry {
        let bounds = CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - topInset - size.height,
                            width: size.width, height: size.height)
        return SurfaceGeometry(kind: .floatingIsland, screenBounds: screenFrame, notchBoundsInScreen: bounds,
                               cameraCutoutWidth: cameraCutoutWidth ?? size.width, topInset: max(0, topInset))
    }

    /// Antes de conocer las pantallas
    public static let fallback = virtualNotch(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))

    /// Elige la superficie: la primera pantalla con notch físico; si ninguna lo tiene, un notch virtual en la
    /// pantalla preferida. Devuelve también el índice de la pantalla elegida.
    public static func resolve(screens: [(frame: CGRect, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?)],
                               preferredIndex: Int?) -> (geometry: SurfaceGeometry, screenIndex: Int?) {
        for (index, screen) in screens.enumerated() {
            if let notch = physicalNotch(screenFrame: screen.frame, auxiliaryTopLeft: screen.auxiliaryTopLeft,
                                         auxiliaryTopRight: screen.auxiliaryTopRight) {
                return (notch, index)
            }
        }
        let index = preferredIndex.flatMap { screens.indices.contains($0) ? $0 : nil } ?? (screens.isEmpty ? nil : 0)
        guard let index else { return (fallback, nil) }
        return (virtualNotch(screenFrame: screens[index].frame), index)
    }
}

/// Nombre histórico: el notch es un caso de superficie
public typealias NotchGeometry = SurfaceGeometry
