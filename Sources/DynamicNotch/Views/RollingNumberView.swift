import SwiftUI

/// Vista animada de números cambiantes estilo Cronómetro / Odómetro (Apple Stopwatch)
/// Las cifras ruedan verticalmente hacia arriba cuando el valor aumenta, y hacia abajo cuando disminuye.
/// Incorpora `.monospacedDigit()` y transiciones nativas `.contentTransition(.numericText)`
/// para una perfecta fluidez en macOS Sonoma y versiones posteriores.
public struct RollingNumberView: View {
    public let value: Int
    public var prefix: String
    public var suffix: String
    public var font: Font
    public var color: Color
    public var alignment: Alignment
    public var animation: Animation
    
    @State private var previousValue: Int
    
    public init(
        value: Int,
        prefix: String = "",
        suffix: String = "",
        font: Font = .system(size: 13, weight: .semibold, design: .rounded),
        color: Color = .white,
        alignment: Alignment = .trailing,
        animation: Animation = .spring(response: 0.28, dampingFraction: 0.82)
    ) {
        self.value = value
        self.prefix = prefix
        self.suffix = suffix
        self.font = font
        self.color = color
        self.alignment = alignment
        self.animation = animation
        self._previousValue = State(initialValue: value)
    }
    
    private var isCountingDown: Bool {
        value < previousValue
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            if !prefix.isEmpty {
                Text(prefix)
                    .font(font)
                    .foregroundColor(color)
            }
            
            Text("\(value)")
                .font(font)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .contentTransition(.numericText(countsDown: isCountingDown))
                .animation(animation, value: value)
            
            if !suffix.isEmpty {
                Text(suffix)
                    .font(font)
                    .foregroundColor(color)
            }
        }
        .frame(alignment: alignment)
        .onChange(of: value) { oldVal, _ in
            previousValue = oldVal
        }
    }
}
