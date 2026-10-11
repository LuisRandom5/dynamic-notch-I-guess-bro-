import SwiftUI

public enum SampleActivities {
    /// Ejemplo de plantilla SliderPill
    public static func triggerSampleSlider(value: Double = 0.75) {
        let leading = AnyView(
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        )
        
        let center = AnyView(
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(6, geo.size.width * CGFloat(value)), height: 6)
                }
            }
        )
        
        let trailing = AnyView(
            Text("\(Int(round(value * 100)))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        )
        
        let activity = LiveActivity(
            id: "sample_slider",
            priority: 50,
            style: .sliderPill,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: DesignTokens.blue,
            duration: 3.0,
            onTap: {
                AppState.shared.expand()
            }
        )
        ActivityCenter.shared.publish(activity)
    }
    
    /// Ejemplo de plantilla Card
    public static func triggerSampleCard() {
        let leading = AnyView(
            ZStack {
                Circle()
                    .fill(DesignTokens.blue.opacity(0.20))
                    .frame(width: 46, height: 46)
                
                Image(systemName: "airdrop")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DesignTokens.blue)
            }
        )
        
        let center = AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text("AirDrop recibido")
                    .liveActivityTitle()
                Text("Proyecto Final.zip (24 MB)")
                    .liveActivitySubtitle()
            }
        )
        
        let trailing = AnyView(
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(DesignTokens.green)
        )
        
        let activity = LiveActivity(
            id: "sample_card",
            priority: 60,
            style: .card,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: DesignTokens.blue,
            duration: 4.0,
            onTap: {
                AppState.shared.expand()
            }
        )
        ActivityCenter.shared.publish(activity)
    }
}
