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
    
    /// Como en el iPhone: al conectar el cargador la isla se abre a lo ancho con "Cargando" a la izquierda y la
    /// batería con su porcentaje a la derecha; verde normal, amarilla en Modo de bajo consumo
    public func publishChargingActivity(percentage: Int, isLowPower: Bool, isPluggedIn: Bool) {
        let tintColor: Color
        if !isPluggedIn && percentage <= 10 {
            tintColor = DesignTokens.red
        } else if isLowPower {
            tintColor = DesignTokens.yellow
        } else {
            tintColor = DesignTokens.green
        }
        // Protege contra el brillo automático de macOS al conectar el cargador
        BrightnessService.shared.suppressAutoBrightnessSlider(duration: 3.5)
        publishBatteryNotice(
            id: providerId,
            label: isPluggedIn ? "Cargando" : "Batería",
            labelColor: Color.white.opacity(0.92),
            percentage: percentage,
            tint: tintColor,
            kind: isPluggedIn ? .charging : .fullyCharged,
            duration: 3.2
        )
    }

    /// Como en el iPhone: "Batería baja" en rojo con la batería casi vacía
    public func publishLowBatteryActivity(percentage: Int) {
        publishBatteryNotice(
            id: "low_battery",
            label: "Batería baja",
            labelColor: DesignTokens.red,
            percentage: percentage,
            tint: DesignTokens.red,
            kind: .low,
            duration: 4.5
        )
        AppState.shared.hapticService.triggerAlert()
    }

    /// Como en el iPhone: al llegar al 100 % con el cargador conectado
    public func publishFullyChargedActivity() {
        publishBatteryNotice(
            id: providerId,
            label: "Carga completa",
            labelColor: Color.white.opacity(0.92),
            percentage: 100,
            tint: DesignTokens.green,
            kind: .fullyCharged,
            duration: 3.2
        )
    }

    /// Aviso breve en las alas de la isla (como el volumen o Bloq Mayús): entra de inmediato, todo lo demás se
    /// recoge y regresa al terminar
    private func publishBatteryNotice(id: String, label: String, labelColor: Color, percentage: Int, tint: Color,
                                      kind: BatteryNoticePillView.Kind, duration: TimeInterval) {
        let wing = BatteryNoticePillView.wingWidth(for: label)
        var notice = LiveActivity(
            id: id,
            priority: ActivityRelevance.systemStatus,
            style: .pill,
            title: label,
            // (Por si se muestra en otro lado, p. ej. la tarjeta expandida)
            leading: AnyView(
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .fixedSize()
            ),
            trailing: AnyView(ChargingTrailingView(percentage: percentage, tintColor: tint, showBolt: kind == .charging, compact: true)),
            // En la isla: la vista con la animación del iPhone (se abre a los lados como con los AirPods)
            customView: AnyView(BatteryNoticePillView(activityId: id, kind: kind, label: label, labelColor: labelColor,
                                                      percentage: percentage, tint: tint, wingWidth: wing)),
            bolitaVariant: .color(bgColor: tint.opacity(0.22), fgColor: tint, iconName: kind == .charging ? "bolt.fill" : (kind == .low ? "battery.25" : "battery.100")),
            tint: tint,
            duration: duration,
            isUrgent: true
        )
        notice.isSystemNotice = true
        notice.customExpandedWidth = ScreenService.shared.currentGeometry.width + wing * 2
        ActivityCenter.shared.publish(notice)
    }
}

// MARK: - Charging Trailing View (Glyph + Smooth Spring Battery Fill)
public struct ChargingTrailingView: View {
    public let percentage: Int
    public let tintColor: Color
    public var showBolt: Bool = true
    /// Tamaño para las alas de la isla (más chico que en la tarjeta)
    public var compact: Bool = false
    
    @State private var animatedFill: CGFloat = 0.0
    
    public init(percentage: Int, tintColor: Color, showBolt: Bool = true, compact: Bool = false) {
        self.percentage = percentage
        self.tintColor = tintColor
        self.showBolt = showBolt
        self.compact = compact
    }

    private var bodyWidth: CGFloat { compact ? 22 : 25 }
    private var bodyHeight: CGFloat { compact ? 11 : 13 }
    
    public var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            // Número en semibold con diseño redondeado nativo
            Text("\(percentage)%")
                .font(.system(size: compact ? 12.5 : 15, weight: .semibold, design: compact ? .default : .rounded))
                .monospacedDigit()
                .foregroundColor(tintColor)
            
            // Glifo de batería horizontal con rayo
            HStack(spacing: 1.5) {
                // Cuerpo de la batería
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(tintColor.opacity(0.85), lineWidth: 1.2)
                        .frame(width: bodyWidth, height: bodyHeight)
                    
                    // Relleno animado proporcional con spring elástico
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                        .fill(tintColor)
                        .frame(width: max(2, (bodyWidth - 4) * animatedFill), height: bodyHeight - 3.5)
                        .padding(.leading, 2)
                    
                    if showBolt {
                        // Pequeño rayo centrado
                        Image(systemName: "bolt.fill")
                            .font(.system(size: compact ? 7 : 8, weight: .heavy))
                            .foregroundColor(.black.opacity(0.85))
                            .frame(width: bodyWidth, height: bodyHeight)
                    }
                }
                
                // Borne / pezón de la batería
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tintColor.opacity(0.85))
                    .frame(width: 1.8, height: compact ? 4 : 5)
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
