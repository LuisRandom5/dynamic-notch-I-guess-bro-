import SwiftUI
import IOKit.ps

public final class ChargingActivityProvider: ActivityProvider, ObservableObject {
    public static let shared = ChargingActivityProvider()
    
    public let providerId: String = "charging"
    
    private var runLoopSource: CFRunLoopSource?
    private var previousIsPluggedIn: Bool?
    private var hasBattery: Bool = false
    
    public init() {
        checkBatteryAvailability()
    }
    
    public func start() {
        guard hasBattery else { return }
        updateBatteryState(isInitial: true)
    }
    
    public func stop() {
    }
    
    private func checkBatteryAvailability() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            self.hasBattery = false
            return
        }
        self.hasBattery = true
    }
    
    public func updateBatteryState(isInitial: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let powerState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let isPluggedIn = powerState == kIOPSACPowerValue
            let percentage = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : current
            let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            
            let wasPluggedIn = self.previousIsPluggedIn
            self.previousIsPluggedIn = isPluggedIn
            
            if !isInitial, let wasPluggedIn = wasPluggedIn {
                // Se detectó conexión a corriente AC
                if !wasPluggedIn && isPluggedIn {
                    publishChargingActivity(percentage: percentage, isLowPower: isLowPower, isPluggedIn: true)
                } else if isPluggedIn && ActivityCenter.shared.currentActivity?.id == providerId {
                    // Si ya está visible y cambió el porcentaje, actualizar en sitio
                    publishChargingActivity(percentage: percentage, isLowPower: isLowPower, isPluggedIn: true)
                }
            }
            break
        }
    }
    
    public func publishChargingActivity(percentage: Int, isLowPower: Bool, isPluggedIn: Bool) {
        // Color por estado: verde normal, amarillo si Low Power Mode, rojo si <=10% y sin cargar
        let tintColor: Color
        if !isPluggedIn && percentage <= 10 {
            tintColor = DesignTokens.red
        } else if isLowPower {
            tintColor = DesignTokens.yellow
        } else {
            tintColor = DesignTokens.green
        }
        
        // Icono circular a la izquierda idéntico a la plantilla Card de AirDrop
        let leadingView = AnyView(
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.18))
                    .frame(width: 46, height: 46)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(tintColor)
            }
        )
        
        // Textos centrales alineados idénticos a AirDrop
        let centerView = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text(isPluggedIn ? "Cargando" : "Batería")
                    .liveActivityTitle()
                Text(isPluggedIn ? "Adaptador de corriente conectado" : "\(percentage)% restante")
                    .liveActivitySubtitle()
            }
        )
        
        // Batería animada con porcentaje a la derecha
        let trailingView = AnyView(
            ChargingTrailingView(
                percentage: percentage,
                tintColor: tintColor
            )
        )
        
        // Proteger contra interferencia del brillo automático de macOS al conectar el cargador
        BrightnessService.shared.suppressAutoBrightnessSlider(duration: 3.5)
        
        // Actividad con plantilla .card (390 x 105 pt, radio 40 pt) con prioridad 100 para no ser pisada
        let activity = LiveActivity(
            id: providerId,
            priority: 100,
            style: .card,
            leading: leadingView,
            center: centerView,
            trailing: trailingView,
            tint: tintColor,
            duration: 3.5,
            onTap: {
                AppState.shared.expand()
            }
        )
        
        ActivityCenter.shared.publish(activity)
    }
    
    public func publishLowBatteryActivity(percentage: Int) {
        let tintColor = DesignTokens.red
        
        let leadingView = AnyView(
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.18))
                    .frame(width: 46, height: 46)
                
                Image(systemName: "battery.25")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(tintColor)
            }
        )
        
        let centerView = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text("Batería baja")
                    .liveActivityTitle()
                Text("\(percentage)% restante • Conecta el adaptador")
                    .liveActivitySubtitle()
            }
        )
        
        let trailingView = AnyView(
            ChargingTrailingView(
                percentage: percentage,
                tintColor: tintColor,
                showBolt: false
            )
        )
        
        let activity = LiveActivity(
            id: "low_battery",
            priority: 95,
            style: .card,
            leading: leadingView,
            center: centerView,
            trailing: trailingView,
            tint: tintColor,
            duration: 4.5,
            onTap: {
                AppState.shared.expand()
            }
        )
        
        ActivityCenter.shared.publish(activity)
        AppState.shared.hapticService.triggerAlert()
    }
}

// MARK: - Charging Trailing View (Glyph + Smooth Spring Battery Fill)
public struct ChargingTrailingView: View {
    public let percentage: Int
    public let tintColor: Color
    public var showBolt: Bool = true
    
    @State private var animatedFill: CGFloat = 0.0
    
    public init(percentage: Int, tintColor: Color, showBolt: Bool = true) {
        self.percentage = percentage
        self.tintColor = tintColor
        self.showBolt = showBolt
    }
    
    public var body: some View {
        HStack(spacing: 7) {
            // Número en semibold con diseño redondeado nativo
            Text("\(percentage)%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tintColor)
            
            // Glifo de batería horizontal con rayo
            HStack(spacing: 1.5) {
                // Cuerpo de la batería
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(tintColor.opacity(0.85), lineWidth: 1.2)
                        .frame(width: 25, height: 13)
                    
                    // Relleno animado proporcional con spring elástico
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                        .fill(tintColor)
                        .frame(width: max(2, 21.0 * animatedFill), height: 9.5)
                        .padding(.leading, 2)
                    
                    if showBolt {
                        // Pequeño rayo centrado
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.black.opacity(0.85))
                            .frame(width: 25, height: 13)
                    }
                }
                
                // Borne / pezón de la batería
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tintColor.opacity(0.85))
                    .frame(width: 1.8, height: 5)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: percentage) { _, _ in
            startAnimation()
        }
    }
    
    private func startAnimation() {
        animatedFill = 0.0
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            animatedFill = CGFloat(min(100, max(0, percentage))) / 100.0
        }
        AppState.shared.hapticService.triggerSnap()
    }
}
