import SwiftUI
import AppKit

/// Herramienta de diagnóstico: dibuja la secuencia de nacimiento de una bolita (cápsula negra + gota) para
/// varios valores de fusión y la guarda como una sola imagen en /tmp/dn_bubble_frames.png.
@MainActor
enum BubbleFrameRenderer {
    static func renderSequence() {
        let merges: [CGFloat] = [1.0, 0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.26, 0.18, 0.12, 0.05, 0.0, -0.05]
        let height: CGFloat = 34
        let pillWidth: CGFloat = 200
        let diameter: CGFloat = 34
        let gap: CGFloat = 11
        let restingX = pillWidth / 2 + gap + diameter / 2
        let notchEndX = pillWidth / 2 - height / 2

        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(merges.enumerated()), id: \.offset) { _, m in
                HStack(spacing: 12) {
                    Text(String(format: "m %.2f", m))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 60, alignment: .leading)
                    ZStack(alignment: .top) {
                        Capsule().fill(Color.black).frame(width: pillWidth, height: height)
                        ZStack {
                            Circle().fill(Color.black)
                            Circle().stroke(Color.orange.opacity(0.3), lineWidth: 3).frame(width: diameter * 0.7)
                            Image(systemName: "cup.and.saucer.fill").font(.system(size: 11)).foregroundColor(.orange)
                        }
                        .frame(width: diameter, height: diameter)
                        .modifier(LiquidSatelliteModifier(
                            merge: m,
                            restingX: restingX,
                            notchEndX: notchEndX,
                            notchRadius: height / 2,
                            bubbleDiameter: diameter,
                            offsetY: 0,
                            showsBridge: true,
                            isGlass: false
                        ))
                    }
                    .frame(width: pillWidth + 2 * (gap + diameter + 20), height: height + 6, alignment: .top)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.25, green: 0.30, blue: 0.75))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "/tmp/dn_bubble_frames.png"))
        DNDLogger.log("BubbleFrameRenderer: cuadros guardados en /tmp/dn_bubble_frames.png")
    }
}
