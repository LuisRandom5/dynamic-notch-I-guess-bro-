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
        
        // Initial state query
        updateBatteryState(isInitial: true)
        
        // Setup IOKit runloop observer
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx = ctx else { return }
            let provider = Unmanaged<ChargingActivityProvider>.fromOpaque(ctx).takeUnretainedValue()
            provider.updateBatteryState(isInitial: false)
        }
        
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = source
        }
    }
    
    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
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
        
        // Actividad con plantilla .card (390 x 105 pt, radio 40 pt)
        let activity = LiveActivity(
            id: providerId,
            priority: 80,
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
}

// MARK: - Charging Trailing View (Glyph + Count Up Animation)
public struct ChargingTrailingView: View {
    public let percentage: Int
    public let tintColor: Color
    
    @State private var animatedPercentage: Int = 0
    @State private var animatedFill: CGFloat = 0.0
    
    public init(percentage: Int, tintColor: Color) {
        self.percentage = percentage
        self.tintColor = tintColor
    }
    
    public var body: some View {
        HStack(spacing: 7) {
            // Número en semibold con conteo hacia arriba
            Text("\(animatedPercentage)%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tintColor)
                .contentTransition(.numericText())
            
            // Glifo de batería horizontal con rayo
            HStack(spacing: 1.5) {
                // Cuerpo de la batería
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(tintColor.opacity(0.85), lineWidth: 1.2)
                        .frame(width: 25, height: 13)
                    
                    // Relleno animado proporcional de 0 a 100%
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                        .fill(tintColor)
                        .frame(width: max(2, 21.0 * animatedFill), height: 9.5)
                        .padding(.leading, 2)
                    
                    // Pequeño rayo centrado
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.black.opacity(0.85))
                        .frame(width: 25, height: 13)
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
        animatedPercentage = 0
        
        // Animación suave de relleno en 0.6s
        withAnimation(.easeOut(duration: 0.6)) {
            animatedFill = CGFloat(min(100, max(0, percentage))) / 100.0
        }
        
        // Conteo del número hacia arriba
        let steps = 15
        let stepDuration = 0.6 / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * stepDuration)) {
                self.animatedPercentage = Int((Double(self.percentage) / Double(steps)) * Double(i))
            }
        }
    }
}
