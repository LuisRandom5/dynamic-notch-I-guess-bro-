import SwiftUI
import AppKit

public struct MarqueeText: View {
    public var text: String
    public var font: Font
    public var fontSize: CGFloat
    public var fontWeight: Font.Weight
    public var color: Color
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false
    
    public init(
        _ text: String,
        fontSize: CGFloat = 17,
        fontWeight: Font.Weight = .regular,
        color: Color = .white
    ) {
        self.text = text
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.font = .system(size: fontSize, weight: fontWeight)
        self.color = color
    }
    
    private var isOverflowing: Bool {
        textWidth > containerWidth && containerWidth > 0
    }
    
    public var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .preference(key: TextWidthPreferenceKey.self, value: textGeo.size.width)
                        }
                    )
                    .offset(x: offset)
            }
            .frame(width: availableWidth, alignment: .leading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: isOverflowing ? .clear : .white, location: 0.0),
                        .init(color: .white, location: isOverflowing ? 0.05 : 0.0),
                        .init(color: .white, location: isOverflowing ? 0.95 : 1.0),
                        .init(color: isOverflowing ? .clear : .white, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onPreferenceChange(TextWidthPreferenceKey.self) { width in
                self.textWidth = width
                self.containerWidth = availableWidth
                restartAnimation(availableWidth: availableWidth, textWidth: width)
            }
            .onChange(of: text) { _, newText in
                restartAnimation(availableWidth: availableWidth, textWidth: textWidth)
            }
        }
        .frame(height: fontSize + 5)
    }
    
    private func restartAnimation(availableWidth: CGFloat, textWidth: CGFloat) {
        offset = 0
        isAnimating = false
        
        guard textWidth > availableWidth && availableWidth > 0 else { return }
        
        let overflow = textWidth - availableWidth + 18
        let duration = Double(overflow) / 22.0 // Velocidad suave tipo marquesina
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard self.textWidth > availableWidth else { return }
            withAnimation(Animation.easeInOut(duration: duration)) {
                self.offset = -overflow
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
                withAnimation(Animation.easeInOut(duration: 0.8)) {
                    self.offset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.restartAnimation(availableWidth: availableWidth, textWidth: textWidth)
                }
            }
        }
    }
}

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
