import SwiftUI

// MARK: - AirDropActivityProvider (Transferencia en Progreso -> Completado)
public final class AirDropActivityProvider: ObservableObject {
    public static let shared = AirDropActivityProvider()

    public static let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
    private static let activityId = "airdrop_live"
    /// Ancho de las alas: en progreso y, más amplias, al confirmar el envío
    private static let progressExtraWidth: CGFloat = 150
    private static let resultExtraWidth: CGFloat = 220

    @Published public private(set) var isTransferring: Bool = false
    @Published public private(set) var progress: Double = 0.0
    private var transferTimer: Timer?
    private var safetyTimer: Timer?
    private var activeDirection: AirDropTransferMonitor.Direction?
    /// Último momento en que se mostró la tarjeta de "recibido" (para no duplicarla)
    private var lastReceivedCardAt: Date = .distantPast

    public init() {}

    // MARK: - Transferencias reales (AirDropTransferMonitor)

    /// Empieza un envío o una recepción: alas con el icono de AirDrop y un anillo que avanza
    /// (sharingd no publica el porcentaje real, así que el anillo avanza de forma estimada).
    public func beginTransfer(_ direction: AirDropTransferMonitor.Direction) {
        activeDirection = direction
        isTransferring = true
        AppState.shared.hapticService.triggerSnap()
        publishTransferActivity(progress: 0, startedAt: Date())

        // Seguridad: si nunca llega el resultado, retirar las alas
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            guard let self = self, self.isTransferring else { return }
            self.isTransferring = false
            ActivityCenter.shared.dismissWithAnimation(id: Self.activityId)
        }
    }

    public func finishTransfer(_ direction: AirDropTransferMonitor.Direction, success: Bool) {
        safetyTimer?.invalidate()
        isTransferring = false
        activeDirection = nil

        switch (direction, success) {
        case (.sending, _):
            // Envío: sin tarjeta. Las alas se ensanchan con la palomita (o la X) y el notch vuelve a su estado
            publishSendResult(success: success)
        case (.receiving, true):
            // Si AirDropObserverService ya mostró la tarjeta del archivo, no volver a poner las alas encima
            // (antes se quedaban trabadas con el anillo lleno: nada las reemplazaba ni las retiraba)
            guard Date().timeIntervalSince(lastReceivedCardAt) >= 4 else { return }
            // El anillo se completa al instante y se busca el archivo (hasta 2 s) para que la tarjeta abra
            // exactamente su ubicación
            publishTransferActivity(progress: 1.0)
            locateReceivedFile(attempt: 0)
        case (.receiving, false):
            publishSendResult(success: false, title: "No se recibió")
        }
    }

    private func locateReceivedFile(attempt: Int) {
        // AirDropObserverService ya pudo mostrar la tarjeta con el archivo
        if Date().timeIntervalSince(lastReceivedCardAt) < 4 { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = AirDropObserverService.shared.findRecentlyReceivedFile()
            DispatchQueue.main.async {
                guard let self = self, Date().timeIntervalSince(self.lastReceivedCardAt) >= 4 else { return }
                if let found = found {
                    DNDLogger.log("AirDropActivityProvider: archivo recibido en \(found.url.path)")
                    self.publishCompletedCard(
                        fileName: found.url.lastPathComponent,
                        sender: "AirDrop",
                        fileSize: ByteCountFormatter.string(fromByteCount: found.size, countStyle: .file),
                        fileURL: found.url
                    )
                } else if attempt < 8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.locateReceivedFile(attempt: attempt + 1) }
                } else {
                    // No llegó a Descargas ni al Escritorio (p. ej. se guardó en Fotos): no fingir una ubicación
                    DNDLogger.log("AirDropActivityProvider: archivo recibido no encontrado en Descargas/Escritorio")
                    self.publishCompletedCard(fileName: "Guardado por AirDrop", sender: "AirDrop", fileURL: nil, opensPhotos: true)
                }
            }
        }
    }
    
    /// Inicia una transferencia simulada (menú de pruebas)
    public func startSimulatedTransfer(fileName: String = "Proyecto Final.zip", sender: String = "iPhone de Luis") {
        transferTimer?.invalidate()
        beginTransfer(.receiving)
        transferTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            self?.isTransferring = false
            self?.publishCompletedCard(fileName: fileName, sender: sender)
        }
    }

    // MARK: - Vistas

    /// Fase en progreso (alas: AirDrop a la izquierda, anillo azul a la derecha)
    public func publishTransferActivity(progress: Double, startedAt: Date = Date()) {
        let blue = Self.blue
        let leading = AnyView(AirDropIconView(size: 18, color: blue))
        let trailing = AnyView(AirDropProgressRing(startedAt: startedAt, fixedProgress: progress > 0 ? progress : nil))

        let activity = LiveActivity(
            id: Self.activityId,
            priority: 88,
            style: .pill,
            leading: leading,
            center: nil,
            trailing: trailing,
            tint: blue,
            // En curso la retira el resultado (o el safetyTimer); ya completa, se retira sola por si nada la reemplaza
            duration: progress >= 1 ? 4.0 : nil,
            customExpandedWidth: ScreenService.shared.currentGeometry.width + Self.progressExtraWidth
        )
        ActivityCenter.shared.publish(activity)
    }

    /// Resultado del envío: alas más anchas con un círculo verde y palomita (o rojo con X), y se retira sola
    private func publishSendResult(success: Bool, title: String? = nil) {
        let blue = Self.blue
        let leading = AnyView(AirDropIconView(size: 18, color: blue))
        let trailing = AnyView(AirDropResultMark(success: success))
        if success {
            AppState.shared.hapticService.triggerExpand()
        }
        let activity = LiveActivity(
            id: Self.activityId,
            priority: 90,
            style: .pill,
            title: title ?? (success ? "Enviado" : "No se envió"),
            leading: leading,
            center: nil,
            trailing: trailing,
            tint: success ? DesignTokens.green : .red,
            // ~2.4 s visible + la animación de cierre ≈ 3 s y el notch vuelve a como estaba
            duration: 2.4,
            customExpandedWidth: ScreenService.shared.currentGeometry.width + Self.resultExtraWidth
        )
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            ActivityCenter.shared.publish(activity)
        }
    }

    /// Tarjeta de "recibido": al tocarla abre la ubicación del archivo en Finder
    public func publishCompletedCard(fileName: String, sender: String, fileSize: String? = nil, fileURL: URL? = nil, opensPhotos: Bool = false) {
        lastReceivedCardAt = Date()
        let blue = Self.blue

        let leading = AnyView(
            ZStack {
                Circle()
                    .fill(blue.opacity(0.20))
                    .frame(width: 46, height: 46)
                AirDropIconView(size: 24, color: blue)
            }
        )

        let subtitleText = (fileSize?.isEmpty == false) ? "\(fileName) (\(fileSize!))" : fileName
        let titleText = (!sender.isEmpty && sender != "AirDrop") ? "AirDrop de \(sender)" : "AirDrop recibido"

        let center = AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .liveActivityTitle()
                Text(subtitleText)
                    .liveActivitySubtitle()
                if fileURL != nil || opensPhotos {
                    Text(fileURL != nil ? "Toca para ver en Finder" : "Toca para abrir Fotos")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(blue.opacity(0.95))
                }
            }
        )

        let trailing = AnyView(
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(DesignTokens.green)
        )

        let activity = LiveActivity(
            id: Self.activityId,
            priority: 90,
            style: .card,
            leading: leading,
            center: center,
            trailing: trailing,
            tint: blue,
            duration: 5.0,
            onTap: {
                if let url = fileURL {
                    // Abre Finder con el archivo seleccionado
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else if opensPhotos, let photos = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
                    NSWorkspace.shared.openApplication(at: photos, configuration: NSWorkspace.OpenConfiguration())
                }
                ActivityCenter.shared.dismissWithAnimation(id: Self.activityId)
            }
        )
        ActivityCenter.shared.publish(activity)
    }
}

// MARK: - Piezas visuales

/// Anillo azul de progreso. Sin porcentaje real disponible, avanza de forma estimada y nunca llega al
/// 100% por sí solo (el resultado real lo cierra).
private struct AirDropProgressRing: View {
    let startedAt: Date
    let fixedProgress: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: fixedProgress != nil)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = fixedProgress ?? min(0.92, 1 - exp(-elapsed / 1.6))
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.04, progress)))
                    .stroke(AirDropActivityProvider.blue, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Al terminar, el anillo se llena suave en vez de saltar
                    .animation(.easeOut(duration: 0.35), value: fixedProgress)
            }
            .frame(width: 17, height: 17)
        }
    }
}

/// Círculo verde con palomita que se dibuja (o rojo con X si falló). Minimalista.
private struct AirDropResultMark: View {
    let success: Bool
    @State private var drawn = false

    var body: some View {
        let color = success ? DesignTokens.green : Color.red
        ZStack {
            Circle()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: success ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(color)
                .scaleEffect(drawn ? 1 : 0.3)
                .opacity(drawn ? 1 : 0)
        }
        .frame(width: 19, height: 19)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { drawn = true }
        }
    }
}
