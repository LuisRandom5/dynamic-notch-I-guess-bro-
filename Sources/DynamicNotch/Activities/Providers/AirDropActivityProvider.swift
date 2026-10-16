import SwiftUI

// MARK: - AirDropActivityProvider (Transferencia en Progreso -> Completado Expandido - Imagen 2)
public final class AirDropActivityProvider: ObservableObject {
    public static let shared = AirDropActivityProvider()
    
    @Published public private(set) var isTransferring: Bool = false
    @Published public private(set) var progress: Double = 0.0
    private var transferTimer: Timer?
    
    public init() {}
    
    /// Inicia una transferencia simulada de AirDrop con progreso en tiempo real
    public func startSimulatedTransfer(fileName: String = "Proyecto Final.zip", sender: String = "iPhone de Luis") {
        transferTimer?.invalidate()
        isTransferring = true
        progress = 0.0
        
        publishTransferActivity(progress: 0.0)
        
        let totalSteps = 24
        let stepDuration = 0.10 // 2.4s en total
        var currentStep = 0
        
        transferTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            currentStep += 1
            let newProgress = min(1.0, Double(currentStep) / Double(totalSteps))
            self.progress = newProgress
            self.publishTransferActivity(progress: newProgress)
            
            if currentStep >= totalSteps {
                timer.invalidate()
                self.isTransferring = false
                
                // Al terminar: se agranda automáticamente a la tarjeta de éxito que le gustó al usuario
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.publishCompletedCard(fileName: fileName, sender: sender)
                }
            }
        }
    }
    
    /// Publica la fase compacta en progreso (Alas del notch: AirDrop a la izquierda, Anillo azul a la derecha)
    public func publishTransferActivity(progress: Double) {
        let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
        
        // Icono de AirDrop con ondas concéntricas en azul a la izquierda (Imagen 2)
        let leading = AnyView(
            AirDropIconView(size: 18, color: blue)
        )
        
        // Anillo circular con arco azul de progreso a la derecha (Imagen 2)
        let trailing = AnyView(
            ZStack {
                // Pista de fondo circular oscura
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 2.2)
                    .frame(width: 17, height: 17)
                
                // Arco de progreso azul que se va completando
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.04, progress)))
                    .stroke(
                        blue,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 17, height: 17)
                    .animation(.linear(duration: 0.10), value: progress)
            }
        )
        
        let activity = LiveActivity(
            id: "airdrop_live",
            priority: 88,
            style: .pill,
            leading: leading,
            center: nil,
            trailing: trailing,
            tint: blue,
            duration: 0.8 // Se mantiene viva mientras el timer la refresca
        )
        
        ActivityCenter.shared.publish(activity)
    }
    
    /// Al terminar la transferencia: muestra la tarjeta expandida (.card) con checkmark verde
    public func publishCompletedCard(fileName: String, sender: String, fileSize: String? = nil, fileURL: URL? = nil) {
        let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
        
        let leading = AnyView(
            ZStack {
                Circle()
                    .fill(blue.opacity(0.20))
                    .frame(width: 46, height: 46)
                
                AirDropIconView(size: 24, color: blue)
            }
        )
        
        let subtitleText = (fileSize != nil && !fileSize!.isEmpty) ? "\(fileName) (\(fileSize!))" : "\(fileName)"
        let titleText = (!sender.isEmpty && sender != "AirDrop") ? "AirDrop de \(sender)" : "AirDrop recibido"
        
        let center = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .liveActivityTitle()
                Text(subtitleText)
                    .liveActivitySubtitle()
            }
        )
        
        let trailing = AnyView(
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(DesignTokens.green)
        )
        
        let activity = LiveActivity(
            id: "airdrop_live",
            priority: 90,
            style: .card,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: blue,
            duration: 4.5,
            onTap: {
                if let url = fileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    AppState.shared.expand()
                }
            }
        )
        
        ActivityCenter.shared.publish(activity)
    }
}

