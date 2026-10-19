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
        resolve(screens: screens, placement: .automatic, mainIndex: preferredIndex, cursorIndex: nil, islandStyle: .hanging)
    }

    /// En qué pantalla vive la isla
    public enum ScreenPlacement: String, CaseIterable, Equatable, Identifiable {
        public var id: String { rawValue }
        /// La pantalla con notch; si no hay, la principal
        case automatic
        /// La primera pantalla sin notch (p. ej. el monitor externo); si no hay, como automática
        case withoutNotch
        /// La pantalla donde está el cursor (la isla la sigue)
        case followCursor
    }

    /// Cómo se ve la isla en una pantalla sin notch
    public enum IslandStyle: String, CaseIterable, Equatable, Identifiable {
        public var id: String { rawValue }
        /// Cápsula separada del borde, como la Isla Dinámica del iPhone
        case floating
        /// Pegada al borde superior, con la forma del notch
        case hanging
    }

    /// Tamaño en reposo de la isla flotante: proporción del iPhone (126 × 37 pt) al alto del notch del Mac
    public static let floatingIslandSize = CGSize(width: 126, height: 32)
    /// Separación de la isla flotante y el borde superior
    public static let floatingIslandTopInset: CGFloat = 6

    /// Superficie según la preferencia del usuario:
    /// - automatic: notch físico si existe (en cualquier pantalla); si no, la pantalla principal
    /// - withoutNotch: la primera pantalla sin notch; si todas tienen, como automatic
    /// - followCursor: la pantalla del cursor (con notch → notch; sin notch → isla)
    /// En una pantalla sin notch se dibuja una isla flotante o un notch virtual según `islandStyle`.
    /// Tamaño y separación de la isla flotante en la pantalla `i` (por defecto, proporción del iPhone)
    public typealias IslandMetricsProvider = (_ screenIndex: Int) -> (size: CGSize, topInset: CGFloat)

    /// Isla del alto de la barra de menús: queda dentro de ella y no tapa las ventanas de abajo
    public static func menuBarIslandMetrics(menuBarHeight: CGFloat) -> (size: CGSize, topInset: CGFloat) {
        let bar = menuBarHeight > 0 ? menuBarHeight : 24
        let height = max(20, bar - 2)
        // Proporción de la isla flotante (126 × 32)
        let width = (height * floatingIslandSize.width / floatingIslandSize.height).rounded()
        return (CGSize(width: width, height: height), max(0, (bar - height) / 2))
    }

    public static func resolve(screens: [(frame: CGRect, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?)],
                               placement: ScreenPlacement, mainIndex: Int?, cursorIndex: Int?,
                               islandStyle: IslandStyle,
                               islandMetrics: IslandMetricsProvider? = nil) -> (geometry: SurfaceGeometry, screenIndex: Int?) {
        guard !screens.isEmpty else { return (fallback, nil) }
        func notch(at i: Int) -> SurfaceGeometry? {
            physicalNotch(screenFrame: screens[i].frame, auxiliaryTopLeft: screens[i].auxiliaryTopLeft,
                          auxiliaryTopRight: screens[i].auxiliaryTopRight)
        }
        func island(at i: Int) -> SurfaceGeometry {
            switch islandStyle {
            case .floating:
                let metrics = islandMetrics?(i) ?? (size: floatingIslandSize, topInset: floatingIslandTopInset)
                return floatingIsland(screenFrame: screens[i].frame, size: metrics.size, topInset: metrics.topInset)
            case .hanging:
                return virtualNotch(screenFrame: screens[i].frame)
            }
        }
        func surface(at i: Int) -> (SurfaceGeometry, Int?) { (notch(at: i) ?? island(at: i), i) }
        let main = mainIndex.flatMap { screens.indices.contains($0) ? $0 : nil } ?? 0

        switch placement {
        case .followCursor:
            if let cursor = cursorIndex, screens.indices.contains(cursor) { return surface(at: cursor) }
        case .withoutNotch:
            if let plain = screens.indices.first(where: { notch(at: $0) == nil }) { return surface(at: plain) }
        case .automatic:
            break
        }
        if let withNotch = screens.indices.first(where: { notch(at: $0) != nil }) { return surface(at: withNotch) }
        return surface(at: main)
    }
}

/// Nombre histórico: el notch es un caso de superficie
public typealias NotchGeometry = SurfaceGeometry
