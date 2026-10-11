import SwiftUI

// MARK: - Design Tokens (Centralized Style Guide)
public enum DesignTokens {
    // Colors
    public static let background = Color.black
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.60)
    public static let textTertiary = Color.white.opacity(0.40)
    
    // Apple HIG Semantic Palette
    public static let green = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)   // #34C759
    public static let orange = Color(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x0A / 255.0)  // #FF9F0A
    public static let red = Color(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0)     // #FF453A
    public static let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)    // #0A84FF
    public static let purple = Color(red: 0xBF / 255.0, green: 0x5A / 255.0, blue: 0xF2 / 255.0)  // #BF5AF2
    public static let yellow = Color(red: 0xFF / 255.0, green: 0xD6 / 255.0, blue: 0x0A / 255.0)  // #FFD60A
    
    // Shared Animations
    public static let activityEntrySpring = Animation.spring(response: 0.45, dampingFraction: 0.75)
    public static let activityExitSpring = Animation.spring(response: 0.40, dampingFraction: 0.80)
    public static let activityContentDelay: Double = 0.08
    public static let contentFadeOutDuration: Double = 0.09
}

// MARK: - Typography Extensions
public extension Text {
    func liveActivityTitle() -> some View {
        self.font(.system(size: 20, weight: .bold, design: .default))
            .foregroundColor(DesignTokens.textPrimary)
    }
    
    func liveActivitySubtitle() -> some View {
        self.font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(DesignTokens.textSecondary)
    }
    
    func liveActivityPillLabel() -> some View {
        self.font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(DesignTokens.textPrimary)
    }
    
    func liveActivityNumber(size: CGFloat = 15, weight: Font.Weight = .semibold, color: Color = DesignTokens.textPrimary) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
            .contentTransition(.numericText())
    }
}
