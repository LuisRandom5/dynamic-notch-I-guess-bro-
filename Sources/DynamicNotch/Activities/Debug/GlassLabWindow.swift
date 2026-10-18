import AppKit
import SwiftUI

/// Laboratorio de Liquid Glass: 5 variantes lado a lado en un panel configurado igual que el del notch
/// (sin borde, no activante, fondo transparente, nivel de barra de estado). Sirve para comparar con capturas
/// qué técnica se ve como vidrio real sobre el escritorio. Abrir con `curl -X POST 127.0.0.1:48123/glasslab`.
public final class GlassLabWindow {
    public static let shared = GlassLabWindow()
    private var panel: GlassLabPanel?

    private init() {}

    public func toggle() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show()
    }

    public func show() {
        guard #available(macOS 26.0, *) else { return }
        let screen = ScreenService.shared.targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 1060, height: 300)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        let panel = self.panel ?? GlassLabPanel(contentRect: NSRect(origin: origin, size: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true

        // 5 columnas: 3 en SwiftUI y 2 en AppKit (NSGlassEffectView), cada una con el mismo contenido encima
        let columnWidth: CGFloat = 200
        let gap: CGFloat = 10
        for index in 0..<5 {
            let frame = NSRect(x: CGFloat(index) * (columnWidth + gap) + 5, y: 40, width: columnWidth, height: 220)
            let variant = GlassLabVariant(rawValue: index)!
            root.addSubview(variant.makeView(frame: frame))

            let label = NSTextField(labelWithString: variant.title)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: frame.minX, y: 8, width: columnWidth, height: 28)
            label.maximumNumberOfLines = 2
            label.wantsLayer = true
            label.shadow = {
                let s = NSShadow()
                s.shadowColor = .black
                s.shadowBlurRadius = 3
                return s
            }()
            root.addSubview(label)
        }

        panel.contentView = root
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

/// Mismo tipo de ventana que NotchPanel, para que la prueba sea representativa.
final class GlassLabPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }

    @objc func _hasActiveAppearance() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { orderOut(nil) } else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        // Doble clic cierra el laboratorio
        if event.clickCount == 2 { orderOut(nil) } else { super.mouseDown(with: event) }
    }
}

@available(macOS 26.0, *)
enum GlassLabVariant: Int {
    case current, swiftUIRegular, swiftUIClear, appKitRegular, appKitClear

    var title: String {
        switch self {
        case .current: return "1 · Antes (negro detrás + tinte)"
        case .swiftUIRegular: return "2 · SwiftUI regular, sin tinte"
        case .swiftUIClear: return "3 · SwiftUI clear, sin tinte"
        case .appKitRegular: return "4 · AppKit NSGlassEffectView regular"
        case .appKitClear: return "5 · AppKit NSGlassEffectView clear"
        }
    }

    func makeView(frame: NSRect) -> NSView {
        switch self {
        case .current, .swiftUIRegular, .swiftUIClear:
            let host = NSHostingView(rootView: GlassLabSwiftUICard(variant: self))
            host.frame = frame
            return host
        case .appKitRegular, .appKitClear:
            let glass = NSGlassEffectView(frame: frame)
            glass.style = self == .appKitRegular ? .regular : .clear
            glass.cornerRadius = 28
            let content = NSHostingView(rootView: GlassLabContent())
            content.frame = NSRect(origin: .zero, size: frame.size)
            glass.contentView = content
            return glass
        }
    }
}

@available(macOS 26.0, *)
private struct GlassLabSwiftUICard: View {
    let variant: GlassLabVariant

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            switch variant {
            case .current:
                // Réplica de la técnica anterior del notch: negro detrás + vidrio teñido de negro
                shape.fill(Color.black.opacity(0.30))
                Color.clear.glassEffect(Glass.regular.tint(Color.black.opacity(0.25)), in: shape)
            case .swiftUIClear:
                Color.clear.glassEffect(Glass.clear, in: shape)
            default:
                Color.clear.glassEffect(Glass.regular, in: shape)
            }
            GlassLabContent()
        }
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .key)
    }
}

/// Contenido típico del notch encima del vidrio, para juzgar legibilidad.
private struct GlassLabContent: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
            Text("Blinding Lights")
                .font(.system(size: 15, weight: .bold))
            Text("The Weeknd")
                .font(.system(size: 12))
                .opacity(0.7)
            HStack(spacing: 18) {
                Image(systemName: "backward.fill")
                Image(systemName: "pause.fill").font(.system(size: 20))
                Image(systemName: "forward.fill")
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
