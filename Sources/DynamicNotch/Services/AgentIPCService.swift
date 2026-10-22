import Foundation
import SwiftUI
import Network
import AppKit

/// Servicio de Comunicación Inter-Procesos (IPC) local para Dynamic Notch.
/// Expone un servidor HTTP nativo y ligero en `127.0.0.1:48123` para interactuar
/// con herramientas de IA (Antigravity), scripts CLI, terminales y suites de compilación.
public final class AgentIPCService {
    public static let shared = AgentIPCService()
    
    public let port: UInt16 = 48123
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.luisrandom.DynamicNotch.AgentIPC", qos: .userInitiated)
    
    private struct PendingRequest {
        let activityId: String
        let connection: NWConnection
        let timeoutWorkItem: DispatchWorkItem?
    }
    
    private var pendingRequests: [String: PendingRequest] = [:]
    private var isRunning: Bool = false
    private var liveSessionSteps: [AgentLiveStep] = []
    private var lastFileDiff: AgentFileDiff? = nil
    private var persistentProgress: Double = 0.0
    
    private init() {
        setupActivityProviderCallbacks()
    }
    
    private func setupActivityProviderCallbacks() {
        AgentActivityProvider.shared.onResponseSubmitted = { [weak self] activityId, actionId, textReply in
            self?.queue.async {
                self?.handleUserDecision(activityId: activityId, actionId: actionId, textReply: textReply)
            }
        }
        
        AgentActivityProvider.shared.onActivityDismissed = { [weak self] activityId in
            self?.queue.async {
                self?.handleActivityDismissed(activityId: activityId)
            }
        }
    }
    
    // MARK: - Lifecycle
    
    public func start() {
        queue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isStopped = false
            self.startServer()
        }
    }
    
    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isStopped = true
            guard self.isRunning else { return }
            self.listener?.cancel()
            self.listener = nil
            self.isRunning = false
            
            // Cancelar y cerrar todas las conexiones pendientes
            for (_, req) in self.pendingRequests {
                req.timeoutWorkItem?.cancel()
                self.sendHTTPResponse(
                    connection: req.connection,
                    statusCode: 503,
                    statusText: "Service Unavailable",
                    jsonObject: ["status": "cancelled", "reason": "server_stopped"]
                )
            }
            self.pendingRequests.removeAll()
            DNDLogger.log("AgentIPCService: Servidor detenido.")
        }
    }
    
    /// Arranques fallidos seguidos (p. ej. el puerto sigue ocupado por la instancia anterior al relanzar)
    private var failedStarts = 0
    /// Detenido a propósito: los reintentos no lo vuelven a abrir
    private var isStopped = false

    /// Sin reintento, un puerto ocupado al arrancar dejaba a Claude y a los agentes sin canal hasta reiniciar la app
    private func retryAfterFailure() {
        listener?.cancel()
        listener = nil
        failedStarts += 1
        let delay: TimeInterval = failedStarts <= 5 ? 2 : 10
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isStopped, !self.isRunning, self.listener == nil else { return }
            DNDLogger.log("AgentIPCService: reintentando abrir el puerto (intento \(self.failedStarts + 1))")
            self.startServer()
        }
    }

    private func startServer() {
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            guard let nwPort = NWEndpoint.Port(rawValue: self.port) else {
                DNDLogger.log("AgentIPCService: Puerto inválido: \(self.port)")
                return
            }
            
            let listener = try NWListener(using: params, on: nwPort)
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.failedStarts = 0
                    DNDLogger.log("AgentIPCService: Escuchando activamente en 127.0.0.1:\(self?.port ?? 48123)")
                case .failed(let error):
                    DNDLogger.log("AgentIPCService error: \(error.localizedDescription)")
                    self?.isRunning = false
                    self?.retryAfterFailure()
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
            
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            DNDLogger.log("AgentIPCService: Falló al inicializar listener: \(error.localizedDescription)")
            retryAfterFailure()
        }
    }
    
    // MARK: - Manejo de Conexiones Entrantes
    
    private func handleNewConnection(_ connection: NWConnection) {
        // Enforce strictly local loopback
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = "\(host)"
            let isLocal = hostStr.contains("127.0.0.1") || hostStr.contains("::1") || hostStr.contains("localhost")
            if !isLocal {
                DNDLogger.log("AgentIPCService: Rechazada conexión no local desde: \(hostStr)")
                connection.cancel()
                return
            }
        }
        
        connection.start(queue: queue)
        readRequestData(connection: connection, accumulatedData: Data())
    }
    
    private func readRequestData(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                DNDLogger.log("AgentIPCService receive error: \(error)")
                connection.cancel()
                return
            }
            
            var currentData = accumulatedData
            if let data = data, !data.isEmpty {
                currentData.append(data)
            }
            
            // Buscar fin de encabezados HTTP
            guard let headerEndRange = currentData.range(of: Data("\r\n\r\n".utf8)) ?? currentData.range(of: Data("\n\n".utf8)) else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.readRequestData(connection: connection, accumulatedData: currentData)
                }
                return
            }
            
            let headerData = currentData.subdata(in: 0..<headerEndRange.lowerBound)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            let lines = headerString.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard let requestLine = lines.first else {
                connection.cancel()
                return
            }
            
            let parts = requestLine.components(separatedBy: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }
            
            let method = parts[0].uppercased()
            let rawPath = parts[1]
            let path = rawPath.components(separatedBy: "?").first ?? rawPath
            
            // Determinar Content-Length si existe
            var contentLength = 0
            for line in lines {
                let lower = line.lowercased()
                if lower.hasPrefix("content-length:") {
                    let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                    contentLength = Int(valStr) ?? 0
                    break
                }
            }
            
            let bodyStartIndex = headerEndRange.upperBound
            let bodyDataLength = currentData.count - bodyStartIndex
            
            if bodyDataLength < contentLength && !isComplete {
                // Esperar a recibir el resto del body
                self.readRequestData(connection: connection, accumulatedData: currentData)
                return
            }
            
            let bodyData = currentData.subdata(in: bodyStartIndex..<min(bodyStartIndex + contentLength, currentData.count))
            guard Self.isTrustedLocalClient(headerLines: lines.dropFirst()) else {
                DNDLogger.log("AgentIPCService: petición rechazada (viene de un navegador o de otro host): \(method) \(path)")
                self.sendHTTPResponse(connection: connection, statusCode: 403, statusText: "Forbidden",
                                      jsonObject: ["error": "Sólo acepta programas locales (no páginas web)"])
                return
            }
            if !BuildFlavor.hasDeveloperTools, path.hasPrefix("/debug/") || path == "/glasslab" {
                self.sendHTTPResponse(connection: connection, statusCode: 404, statusText: "Not Found", jsonObject: ["error": "not found"])
                return
            }
            self.routeRequest(method: method, path: path, bodyData: bodyData, connection: connection)
        }
    }
    
    /// Sólo programas de esta Mac (scripts, hooks, `dynamicnotch`): una página web abierta en el navegador podría
    /// mandar peticiones a 127.0.0.1 y leer o mostrar cosas en la isla. Los navegadores siempre agregan `Origin` o
    /// `Sec-Fetch-*` (las herramientas de línea de comandos no), y `Host` distinto de localhost delata un DNS rebinding.
    static func isTrustedLocalClient<S: Sequence>(headerLines: S) -> Bool where S.Element == String {
        for line in headerLines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
            if name == "origin" || name.hasPrefix("sec-fetch-") { return false }
            if name == "host" {
                let host = value.split(separator: ":").first.map(String.init) ?? value
                if !["127.0.0.1", "localhost", "[::1]"].contains(host) { return false }
            }
        }
        return true
    }

    // MARK: - Enrutamiento de Peticiones HTTP
    
    private func routeRequest(method: String, path: String, bodyData: Data, connection: NWConnection) {
        DNDLogger.log("AgentIPCService: Request \(method) \(path)")
        
        // Sin CORS: las páginas web no pueden usar este servidor (ver isTrustedLocalClient)
        if method == "OPTIONS" {
            sendHTTPResponse(connection: connection, statusCode: 403, statusText: "Forbidden", jsonObject: [:])
            return
        }
        
        switch (method, path) {
        case ("GET", "/status"), ("GET", "/health"), ("GET", "/ping"):
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: [
                    "status": "ok",
                    "app": "Dynamic Notch",
                    "version": "1.0",
                    "notchMode": "\(AppState.shared.mode)",
                    "agentActive": AgentActivityProvider.shared.isActive,
                    "currentActivity": ActivityCenter.shared.currentActivity?.id ?? "none",
                    "activeActivities": ActivityCenter.shared.activeActivities.map { "\($0.id): \($0.priority)" }
                ]
            )
            
        case ("POST", "/notify"):
            handleNotifyRequest(bodyData: bodyData, connection: connection)
            
        case ("POST", "/progress"):
            handleProgressRequest(bodyData: bodyData, connection: connection)
            
        case ("GET", "/debug/hit"):
            // Diagnóstico del hit-test: zona del notch y zonas reportadas por las bolitas
            var info: [String: Any] = [:]
            DispatchQueue.main.sync {
                info = NotchWindowManager.shared.hitTestDebugInfo()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)
            
        case ("GET", "/debug/activities"):
            // Diagnóstico: actividades activas, principal y bolitas
            var info: [String: Any] = [:]
            DispatchQueue.main.sync {
                let center = ActivityCenter.shared
                info = [
                    "mode": "\(AppState.shared.mode)",
                    "current": center.currentActivity?.id ?? "nil",
                    "secondary": center.secondaryActivities.map(\.id),
                    "active": center.activeActivities.map(\.id),
                    "expanded": center.expandedActivity?.id ?? "nil",
                    "fusing": center.fusingActivityId ?? "nil",
                    "stale": Array(center.staleActivityIds).sorted(),
                    "departing": center.departingSatellites.map(\.activity.id)
                ]
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)
            
        case ("POST", "/debug/render-bubble"):
            // Diagnóstico visual: renderiza cuadros del nacimiento de una bolita (modo negro) a /tmp
            DispatchQueue.main.async {
                BubbleFrameRenderer.renderSequence()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/render-notices"):
            // Diagnóstico visual: dibuja los avisos (WhatsApp, carga, batería baja) en /tmp/dn_notices.png
            DispatchQueue.main.async {
                NoticeRenderer.render()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/tap-shelf"):
            // Diagnóstico: simula el toque en la bolita de la repisa
            DispatchQueue.main.async {
                ActivityCenter.shared.activeActivities.first { $0.id == ShelfActivityProvider.activityId }?.onTap?()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("GET", "/debug/hitches"), ("POST", "/debug/hitches"):
            // Diagnóstico de rendimiento: cuadros lentos recientes (POST además reinicia el conteo)
            var info: [String: Any] = [:]
            let reset = method == "POST"
            DispatchQueue.main.sync {
                info = FrameHitchMonitor.shared.report(reset: reset)
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)
            
        case ("POST", "/debug/drop-invite"):
            // Diagnóstico: muestra la tarjeta de "suelta aquí" 4 s (para medir su zona activa con /debug/hit)
            DispatchQueue.main.async {
                withAnimation { AppState.shared.isDropInvitationActive = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { AppState.shared.isDropInvitationActive = false }
                }
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/studio-snapshot"):
            DispatchQueue.main.async { AnimationStudioWindow.shared.snapshot() }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/settings-snapshot"):
            let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
            let tabName = json["tab"] as? String ?? "Apariencia"
            DispatchQueue.main.async {
                let tab = SettingsView.SettingsTab(rawValue: tabName) ?? .general
                SettingsWindowController.shared.snapshot(tab: tab, to: "/tmp/dn_settings.png")
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/studio"):
            // Abre el Animation Studio de las bolitas
            DispatchQueue.main.async { AnimationStudioWindow.shared.show() }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/toggle-notch"):
            // Diagnóstico: abre o cierra el reproductor como si el usuario lo hiciera
            DispatchQueue.main.async {
                if AppState.shared.mode == .expanded || AppState.shared.mode == .shelf {
                    AppState.shared.collapse()
                } else {
                    AppState.shared.expand()
                }
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/cycle"):
            // Diagnóstico: como el swipe a lo ancho sobre el notch ({"forward": false} para regresar)
            let forward = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any])?["forward"] as? Bool ?? true
            DispatchQueue.main.async {
                ActivityCenter.shared.cycleActivities(forward: forward)
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/expand"):
            // Diagnóstico: expande la tarjeta de una actividad como mantener presionada su bolita ({"id": "..."})
            let targetId = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any])?["id"] as? String
            DispatchQueue.main.async {
                let center = ActivityCenter.shared
                if let id = targetId, let activity = center.activeActivities.first(where: { $0.id == id }) {
                    center.initiateFusion(for: activity)
                } else if center.expandedActivity != nil {
                    center.collapseExpandedActivity()
                }
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/sample-activity"):
            // Diagnóstico: una descarga de ejemplo sin tarjeta propia (usa la plantilla expandida por defecto).
            // {"progress": 0.4, "subtitle": "...", "remove": true}
            let json = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                if json["remove"] as? Bool == true {
                    ActivityCenter.shared.end(id: "sample_download", dismissAfter: 0)
                    return
                }
                let progress = json["progress"] as? Double ?? 0.4
                ActivityCenter.shared.publish(LiveActivity(
                    id: "sample_download",
                    kind: .download,
                    style: .pill,
                    title: "Descargando",
                    subtitle: json["subtitle"] as? String ?? "macOS 27.1.ipsw · \(Int(progress * 8)) de 8 GB",
                    progress: progress,
                    bolitaVariant: .progressRing(progress: progress, strokeColor: DesignTokens.blue, iconName: "arrow.down"),
                    tint: DesignTokens.blue,
                    onTap: { NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) }
                ))
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/debug/appearance"):
            // Diagnóstico: cambia el estilo del notch en vivo ({"mode": "oled" | "darkGlass" | "clearGlass"})
            let mode = (((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any])?["mode"] as? String)
                .flatMap(NotchAppearanceMode.init(rawValue:))
            if let mode {
                DispatchQueue.main.async { AppState.shared.appearanceMode = mode }
            }
            sendHTTPResponse(connection: connection, statusCode: mode == nil ? 400 : 200, statusText: mode == nil ? "Bad Request" : "OK",
                             jsonObject: ["status": mode == nil ? "modo inválido" : "ok"])
            
        case ("POST", "/debug/feedback-archive"):
            // Diagnóstico: arma el .zip de "Enviar comentarios" en /tmp (sin la alerta) y dice dónde quedó
            DispatchQueue.main.async {
                let result: [String: Any]
                do { result = ["path": try FeedbackService.writeArchive(in: URL(fileURLWithPath: "/tmp")).path] }
                catch { result = ["error": error.localizedDescription] }
                self.sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: result)
            }

        case ("POST", "/debug/settings-bare"):
            let tabName = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any])?["tab"] as? String ?? "General"
            DispatchQueue.main.async {
                SettingsWindowController.shared.snapshotBare(tab: SettingsView.SettingsTab(rawValue: tabName) ?? .general, to: "/tmp/dn_settings_bare.png")
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])

        case ("POST", "/debug/render-welcome"):
            // Diagnóstico: la ventana de bienvenida y permisos en /tmp/dn_welcome.png
            DispatchQueue.main.async { WelcomeWindowController.snapshot(to: "/tmp/dn_welcome.png") }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])

        case ("POST", "/debug/speed"):
            // Diagnóstico: cámara lenta de las transformaciones ({"speed": 0.2} … 1.0) para revisarlas cuadro a cuadro
            let speed = (((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any])?["speed"] as? Double) ?? 1.0
            DispatchQueue.main.async { AnimationSpeedManager.shared.setSpeed(speed) }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])

        case ("GET", "/debug/fullscreen"):
            var info: [String: Any] = [:]
            DispatchQueue.main.sync { info = FullScreenMediaMonitor.shared.debugSnapshot() }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)
            
        case ("POST", "/debug/island"):
            // Diagnóstico de la Fase B: {"ignoreNotch": true} trata todas las pantallas como si no tuvieran notch
            // (para ver la isla en la MacBook); {"style": "floating"|"hanging"}, {"placement": "..."}
            let json = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                if let ignore = json["ignoreNotch"] as? Bool {
                    UserDefaults.standard.set(ignore, forKey: "debugIslandIgnoreNotch")
                }
                if let style = (json["style"] as? String).flatMap(SurfaceGeometry.IslandStyle.init(rawValue:)) {
                    AppState.shared.islandStyle = style
                }
                if let placement = (json["placement"] as? String).flatMap(SurfaceGeometry.ScreenPlacement.init(rawValue:)) {
                    AppState.shared.islandScreenPlacement = placement
                }
                if let rest = json["visibleAtRest"] as? Bool {
                    AppState.shared.islandVisibleAtRest = rest
                }
                ScreenService.shared.updateScreenGeometry()
            }
            let g = DispatchQueue.main.sync { ScreenService.shared.currentGeometry }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: [
                "kind": g.kind.rawValue, "bounds": "\(g.notchBoundsInScreen)", "topInset": g.topInset
            ])
            
        case ("POST", "/debug/airpods-model"):
            // Diagnóstico: {"productId": "0x200a", "maxColor": "blue"} y muestra la animación de esos AirPods
            let json = ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                if let color = (json["maxColor"] as? String).flatMap(AirPodsMaxColor.init(rawValue:)) {
                    AppState.shared.airPodsMaxColor = color
                }
                if let pid = json["productId"] as? String {
                    BluetoothAudioService.shared.simulateModel(productId: pid)
                }
                if json["show"] as? Bool ?? true {
                    AirPodsActivityProvider.shared.publishAirPodsActivity(name: "AirPods de prueba", batteryLevel: 80,
                                                                          leftPercent: 80, rightPercent: 70, casePercent: 45)
                }
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK",
                             jsonObject: ["identity": AirPodsAssetService.currentIdentity.map { "\($0.product)-\($0.variant)" } ?? "-"])

        case ("GET", "/debug/airpods-ble"):
            // Diagnóstico: escucha 8 s el aviso Bluetooth de los AirPods y devuelve la última lectura
            AirPodsBLEMonitor.shared.scan(for: 8)
            let reading = DispatchQueue.main.sync { AirPodsBLEMonitor.shared.latest }
            var info: [String: Any] = ["scanning": true]
            DispatchQueue.main.sync {
                info["bluetooth"] = AirPodsBLEMonitor.shared.stateDescription
                info["appleTypes"] = AirPodsBLEMonitor.shared.appleTypesSeen.map { String(format: "0x%02x:%d", $0.key, $0.value) }.sorted()
            }
            if let r = reading {
                info["productId"] = r.productIdHex
                info["color"] = Int(r.color)
                info["left"] = r.left ?? -1
                info["right"] = r.right ?? -1
                info["case"] = r.caseLevel ?? -1
                info["charging"] = [r.leftCharging, r.rightCharging, r.caseCharging]
                info["rssi"] = r.rssi
                info["raw"] = r.raw
                info["age"] = Date().timeIntervalSince(r.at)
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)

        case ("GET", "/debug/whatsapp"):
            let rows = WhatsAppWebObserverService.shared.debugRows()
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["rows": rows])
            
        case ("GET", "/debug/audio"):
            // Diagnóstico de las barras: captura real, relevo procedural y niveles
            var info: [String: Any] = [:]
            DispatchQueue.main.sync {
                info = AudioSpectrumEngine.shared.debugSnapshot()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: info)
            
        case ("POST", "/glasslab"), ("GET", "/glasslab"):
            // Abre/cierra el laboratorio de Liquid Glass (comparativa de 5 variantes)
            DispatchQueue.main.async {
                GlassLabWindow.shared.toggle()
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/claude/usage"):
            // Uso de la suscripción desde scripts/claude_statusline.py
            let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                ClaudeActivityProvider.shared.handleUsage(json: json)
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/claude"):
            // Reportes de scripts/claude_notch_hook.py (Claude Code)
            let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                ClaudeActivityProvider.shared.handle(json: json)
            }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK", jsonObject: ["status": "ok"])
            
        case ("POST", "/tokens"), ("POST", "/credits"):
            handleTokensRequest(bodyData: bodyData, connection: connection)
            
        case ("GET", "/tokens"), ("GET", "/credits"):
            let quotaList = AICreditsService.shared.quotas.map { q in
                [
                    "id": q.id,
                    "name": q.name,
                    "model": q.modelName,
                    "remainingPercent": q.remainingPercent,
                    "usedRequests": q.usedRequests,
                    "totalRequests": q.totalRequests,
                    "resetTime": q.resetTimeString,
                    "totalTokensUsed": q.totalTokensUsed
                ] as [String: Any]
            }
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: [
                    "status": "ok",
                    "quotas": quotaList,
                    "sessionInputTokens": AICreditsService.shared.sessionInputTokens,
                    "sessionOutputTokens": AICreditsService.shared.sessionOutputTokens
                ]
            )
            
        case ("POST", "/fuse"):
            DispatchQueue.main.async {
                if let act = ActivityCenter.shared.secondaryActivities.first ?? ActivityCenter.shared.activeActivities.first {
                    ActivityCenter.shared.initiateFusion(for: act, fromSide: .right)
                }
            }
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "action": "fusing"]
            )
            
        case ("POST", "/collapse"):
            DispatchQueue.main.async {
                ActivityCenter.shared.collapseExpandedActivity()
            }
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "action": "collapsed"]
            )
            
        case ("POST", "/canvas"), ("GET", "/canvas"):
            DispatchQueue.main.async {
                AmbientCanvasWindowManager.shared.toggleCanvas()
            }
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: [
                    "status": "ok",
                    "toggled": true
                ]
            )
            
        case ("POST", "/ask"), ("POST", "/perm"), ("POST", "/permission"), ("POST", "/authorize"):
            handleAskRequest(bodyData: bodyData, connection: connection)
            
        case ("POST", "/activity"):
            // API pública v1 (docs/API.md): iniciar, actualizar o terminar una actividad propia
            let request: PublicActivityAPI.Request
            do {
                request = try PublicActivityAPI.parse(bodyData)
            } catch {
                sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request",
                                 jsonObject: ["error": "\(error)", "version": PublicActivityAPI.version])
                return
            }
            let outcome = DispatchQueue.main.sync { PublicActivityAPI.apply(request) }
            switch outcome {
            case .started, .updated, .ended:
                let name = outcome == .started ? "started" : (outcome == .updated ? "updated" : "ended")
                sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK",
                                 jsonObject: ["status": name, "id": request.id, "version": PublicActivityAPI.version])
            case .notFound:
                sendHTTPResponse(connection: connection, statusCode: 404, statusText: "Not Found",
                                 jsonObject: ["error": "No hay una actividad con ese id", "id": request.id])
            case .tooMany:
                sendHTTPResponse(connection: connection, statusCode: 429, statusText: "Too Many Requests",
                                 jsonObject: ["error": "Máximo \(PublicActivityAPI.maxActive) actividades de la API a la vez"])
            }

        case ("GET", "/activity"):
            let items = DispatchQueue.main.sync { PublicActivityAPI.activeSummary() }
            sendHTTPResponse(connection: connection, statusCode: 200, statusText: "OK",
                             jsonObject: ["activities": items, "version": PublicActivityAPI.version])

        case ("POST", "/timer"):
            handleTimerRequest(bodyData: bodyData, connection: connection)
            
        case ("POST", "/call"):
            handleCallRequest(bodyData: bodyData, connection: connection)
            
        default:
            sendHTTPResponse(
                connection: connection,
                statusCode: 404,
                statusText: "Not Found",
                jsonObject: ["error": "Ruta no encontrada", "path": path]
            )
        }
    }
    
    // MARK: - Handlers de Notificación y Permisos
    
    private func handleNotifyRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendHTTPResponse(
                connection: connection,
                statusCode: 400,
                statusText: "Bad Request",
                jsonObject: ["error": "JSON inválido en el cuerpo de la petición"]
            )
            return
        }
        
        let title = json["title"] as? String ?? "Antigravity"
        let subtitle = json["subtitle"] as? String ?? "Notificación"
        let message = json["message"] as? String ?? ""
        let duration = json["duration"] as? Double ?? 5.0
        
        AgentActivityProvider.shared.showInteraction(
            type: .notification,
            title: title,
            subtitle: subtitle,
            message: message,
            command: nil,
            options: [AgentActionOption(id: "ok", label: "Entendido", isPrimary: true)],
            enableTextReply: false,
            duration: duration
        )
        
        sendHTTPResponse(
            connection: connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "ok",
                "delivered": true,
                "title": title,
                "message": message
            ]
        )
    }
    
    private func handleProgressRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendHTTPResponse(
                connection: connection,
                statusCode: 400,
                statusText: "Bad Request",
                jsonObject: ["error": "JSON inválido en el cuerpo de la petición"]
            )
            return
        }
        
        let event = json["event"] as? String ?? "step"
        if event == "start" || event == "session_start" {
            persistentProgress = 0.10
            liveSessionSteps = []
            lastFileDiff = nil
        }
        
        if event == "dismiss" || event == "finish_dismiss" || event == "stop" || event == "cancel" {
            AgentActivityProvider.shared.dismissProgress()
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "dismissed": true]
            )
            return
        }
        
        if event == "expand" || json["action"] as? String == "expand" {
            AgentActivityProvider.shared.expandProgressHUD()
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "expanded": true]
            )
            return
        }
        
        if event == "collapse" || json["action"] as? String == "collapse" {
            AgentActivityProvider.shared.collapseProgressHUD()
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "collapsed": true]
            )
            return
        }
        
        if event == "toggle" || json["action"] as? String == "toggle" {
            AgentActivityProvider.shared.toggleProgressHUD()
            sendHTTPResponse(
                connection: connection,
                statusCode: 200,
                statusText: "OK",
                jsonObject: ["status": "ok", "toggled": true]
            )
            return
        }
        
        let agentName = json["agent"] as? String ?? "Antigravity"
        let taskName = json["task"] as? String ?? "Desarrollo en curso"
        let isCompleted = (event == "finish" || event == "completed" || (json["completed"] as? Bool ?? false))
        
        // Parsear lista de pasos reales o acumular incrementalmente
        var steps: [AgentLiveStep] = []
        if let rawSteps = json["steps"] as? [[String: Any]], !rawSteps.isEmpty {
            for s in rawSteps {
                let title = s["title"] as? String ?? ""
                let isComp = s["completed"] as? Bool ?? false
                let isAct = s["active"] as? Bool ?? false
                steps.append(AgentLiveStep(title: title, isCompleted: isComp, isActive: isAct))
            }
            liveSessionSteps = steps
        } else if let rawCompleted = json["completedSteps"] as? [String], !rawCompleted.isEmpty {
            for c in rawCompleted {
                steps.append(AgentLiveStep(title: c, isCompleted: true, isActive: false))
            }
            if let currentStep = json["step"] as? String, !currentStep.isEmpty {
                steps.append(AgentLiveStep(title: currentStep, isCompleted: isCompleted, isActive: !isCompleted))
            }
            liveSessionSteps = steps
        } else if let currentStep = json["step"] as? String, !currentStep.isEmpty {
            // Acumulación progresiva real
            var updated = liveSessionSteps.map { s in
                AgentLiveStep(id: s.id, title: s.title, isCompleted: true, isActive: false)
            }
            if isCompleted {
                updated.append(AgentLiveStep(title: currentStep, isCompleted: true, isActive: false))
            } else {
                updated.append(AgentLiveStep(title: currentStep, isCompleted: false, isActive: true))
            }
            if updated.count > 6 {
                updated = Array(updated.suffix(6))
            }
            steps = updated
            liveSessionSteps = updated
        } else {
            if isCompleted {
                steps = liveSessionSteps.map { AgentLiveStep(id: $0.id, title: $0.title, isCompleted: true, isActive: false) }
            } else {
                steps = liveSessionSteps
            }
        }
        
        if steps.isEmpty {
            steps = [
                AgentLiveStep(title: "Dynamic Notch", isCompleted: isCompleted, isActive: !isCompleted)
            ]
        }
        
        // Parsear archivo y métricas de diffs reales
        var fileDiff: AgentFileDiff? = nil
        let filename = json["file"] as? String ?? json["filename"] as? String
        let add = json["added"] as? Int ?? json["additions"] as? Int ?? (json["diff"] as? [String: Any])?["added"] as? Int ?? 0
        let del = json["deleted"] as? Int ?? json["deletions"] as? Int ?? (json["diff"] as? [String: Any])?["deleted"] as? Int ?? 0
        let statusText = json["status"] as? String ?? (isCompleted ? "Completado" : "Trabajando...")
        let explicitProgress = json["progress"] as? Double
        let rawProgress: Double
        if let exp = explicitProgress {
            rawProgress = max(0.04, min(1.0, exp))
        } else if isCompleted {
            rawProgress = 1.0
        } else if !steps.isEmpty {
            let completedCount = steps.filter { $0.isCompleted }.count
            let total = steps.count
            let base = Double(completedCount) / Double(total)
            let activeBonus = steps.contains(where: { $0.isActive }) ? (0.5 / Double(total)) : 0.0
            rawProgress = max(0.08, min(0.95, base + activeBonus))
        } else {
            rawProgress = 0.12
        }
        
        let progress: Double
        if isCompleted {
            persistentProgress = 1.0
            progress = 1.0
        } else {
            // Monotónico: Jamás regresa a 0 durante una tarea en curso
            persistentProgress = max(persistentProgress, rawProgress)
            progress = persistentProgress
        }
        
        let remainingTimeText = json["remaining_text"] as? String
            ?? json["timeRemaining"] as? String
            ?? (json["remaining"] as? Int).map { "~ \($0)s" }
        
        if let fname = filename, !fname.isEmpty {
            fileDiff = AgentFileDiff(
                filename: fname,
                additions: add,
                deletions: del,
                statusText: statusText,
                progress: progress
            )
            lastFileDiff = fileDiff
        } else if let last = lastFileDiff {
            fileDiff = AgentFileDiff(
                filename: last.filename,
                additions: add > 0 ? add : last.additions,
                deletions: del > 0 ? del : last.deletions,
                statusText: statusText,
                progress: progress
            )
        } else {
            fileDiff = AgentFileDiff(
                filename: "Sources/DynamicNotch",
                additions: add,
                deletions: del,
                statusText: statusText,
                progress: progress
            )
        }
        
        let payload = AgentLiveProgressPayload(
            agentName: agentName,
            taskName: taskName,
            steps: steps,
            fileDiff: fileDiff,
            isCompleted: isCompleted,
            progress: progress,
            remainingTimeText: remainingTimeText
        )
        
        // Registrar consumo de tokens real en AICreditsService si viene en el payload
        if let tokensDict = json["tokens"] as? [String: Any] {
            let inTok = tokensDict["input"] as? Int ?? tokensDict["inputTokens"] as? Int ?? 0
            let outTok = tokensDict["output"] as? Int ?? tokensDict["outputTokens"] as? Int ?? 0
            AICreditsService.shared.recordTokens(providerId: agentName, inputTokens: inTok, outputTokens: outTok, isNewRequest: false)
        } else if let used = json["tokensUsed"] as? Int {
            AICreditsService.shared.recordTokens(providerId: agentName, inputTokens: Int(Double(used) * 0.75), outputTokens: Int(Double(used) * 0.25), isNewRequest: false)
        } else {
            // Estimación orgánica basada en diffs para mantener el pulso real de tokens
            let addedLines = fileDiff?.additions ?? 0
            let deletedLines = fileDiff?.deletions ?? 0
            let estimatedTokens = max(35, (addedLines + deletedLines) * 14)
            AICreditsService.shared.recordTokens(providerId: agentName, inputTokens: estimatedTokens, outputTokens: max(15, estimatedTokens / 4), isNewRequest: false)
        }
        
        AgentActivityProvider.shared.showProgress(payload: payload)
        
        sendHTTPResponse(
            connection: connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "ok",
                "agent": agentName,
                "task": taskName,
                "completed": isCompleted
            ]
        )
    }
    
    // MARK: - Manejo de Tokens y Cuotas de IA
    
    private func handleTokensRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendHTTPResponse(
                connection: connection,
                statusCode: 400,
                statusText: "Bad Request",
                jsonObject: ["error": "JSON inválido en el cuerpo de la petición"]
            )
            return
        }
        
        let provider = json["provider"] as? String ?? json["agent"] as? String ?? "antigravity"
        let inTok = json["input"] as? Int ?? json["inputTokens"] as? Int ?? json["input_tokens"] as? Int ?? 0
        let outTok = json["output"] as? Int ?? json["outputTokens"] as? Int ?? json["output_tokens"] as? Int ?? 0
        let isReq = json["request"] as? Bool ?? json["isNewRequest"] as? Bool ?? json["is_new_request"] as? Bool ?? true
        
        AICreditsService.shared.recordTokens(providerId: provider, inputTokens: inTok, outputTokens: outTok, isNewRequest: isReq)
        
        sendHTTPResponse(
            connection: connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "ok",
                "provider": provider,
                "inputTokens": inTok,
                "outputTokens": outTok,
                "totalRecorded": inTok + outTok
            ]
        )
    }
    
    // MARK: - Manejo de Temporizador y Llamadas por IPC
    
    private func handleTimerRequest(bodyData: Data, connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
        
        let action = json["action"] as? String ?? "start"
        let duration = json["duration"] as? TimeInterval ?? 60.0
        let title = json["title"] as? String ?? "Temporizador"
        let asCard = json["card"] as? Bool ?? false
        
        DispatchQueue.main.async {
            switch action.lowercased() {
            case "start":
                TimerActivityProvider.shared.startTimer(duration: duration, title: title, asCard: asCard)
            case "pause", "resume", "toggle":
                TimerActivityProvider.shared.togglePauseResume()
            case "cancel", "stop":
                TimerActivityProvider.shared.cancelTimer()
            case "lap":
                TimerActivityProvider.shared.recordLap()
            case "stopwatch":
                TimerActivityProvider.shared.startStopwatch(asCard: asCard)
            default:
                TimerActivityProvider.shared.startTimer(duration: duration, title: title, asCard: asCard)
            }
        }
        
        sendHTTPResponse(
            connection: connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "ok",
                "action": action,
                "duration": duration,
                "title": title
            ]
        )
    }
    
    private func handleCallRequest(bodyData: Data, connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
        
        let action = json["action"] as? String ?? "start"
        let name = json["name"] as? String ?? "FaceTime Audio"
        let handle = json["handle"] as? String ?? "Mamá"
        let asCard = json["card"] as? Bool ?? false
        
        DispatchQueue.main.async {
            switch action.lowercased() {
            case "incoming":
                CallActivityProvider.shared.startIncomingCall(name: name, handle: handle, isSimulation: true)
            case "start":
                CallActivityProvider.shared.startCall(name: name, handle: handle, asCard: asCard, isSimulation: true)
            case "end", "hangup", "decline":
                CallActivityProvider.shared.endCall()
            case "answer":
                CallActivityProvider.shared.answerCall()
            default:
                CallActivityProvider.shared.startCall(name: name, handle: handle, asCard: asCard, isSimulation: true)
            }
        }
        
        sendHTTPResponse(
            connection: connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "ok",
                "action": action,
                "name": name,
                "handle": handle
            ]
        )
    }
    
    private func handleAskRequest(bodyData: Data, connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
        
        let rawType = json["type"] as? String ?? "permission"
        let type: AgentInteractionType
        switch rawType.lowercased() {
        case "notification": type = .notification
        case "question": type = .question
        default: type = .permission
        }
        
        let title = json["title"] as? String ?? (type == .permission ? "Permiso Requerido" : "Antigravity")
        let subtitle = json["subtitle"] as? String ?? (type == .permission ? "Ejecución de Comando" : "Consulta")
        let message = json["message"] as? String ?? ""
        let command = json["command"] as? String
        let enableTextReply = json["enableTextReply"] as? Bool ?? true
        let timeoutSeconds = json["timeout"] as? Double ?? 180.0
        
        var customOptions: [AgentActionOption]? = nil
        if let rawOpts = json["options"] as? [[String: Any]] {
            customOptions = rawOpts.compactMap { opt in
                guard let id = opt["id"] as? String, let label = opt["label"] as? String else { return nil }
                let isPrimary = opt["isPrimary"] as? Bool ?? false
                let isDestructive = opt["isDestructive"] as? Bool ?? false
                return AgentActionOption(id: id, label: label, isPrimary: isPrimary, isDestructive: isDestructive)
            }
        }
        
        // Desplegar la actividad en el Notch y obtener su ID único
        let activityId = AgentActivityProvider.shared.showInteraction(
            type: type,
            title: title,
            subtitle: subtitle,
            message: message,
            command: command,
            options: customOptions,
            enableTextReply: enableTextReply,
            duration: nil
        )
        
        // Timeout de seguridad para no dejar la petición colgada si el usuario no responde
        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self = self, connection != nil else { return }
            self.queue.async {
                if let req = self.pendingRequests.removeValue(forKey: activityId) {
                    DNDLogger.log("AgentIPCService: Solicitud id=\(activityId) expiró por timeout")
                    self.sendHTTPResponse(
                        connection: req.connection,
                        statusCode: 408,
                        statusText: "Request Timeout",
                        jsonObject: [
                            "status": "timeout",
                            "action": "timeout",
                            "decision": "deny",
                            "reason": "Timeout esperando autorización en Dynamic Notch",
                            "reply": NSNull(),
                            "activityId": activityId
                        ]
                    )
                    DispatchQueue.main.async {
                        AgentActivityProvider.shared.dismissActivity()
                    }
                }
            }
        }
        
        queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
        
        let pending = PendingRequest(
            activityId: activityId,
            connection: connection,
            timeoutWorkItem: timeoutWorkItem
        )
        self.pendingRequests[activityId] = pending
        DNDLogger.log("AgentIPCService: Solicitud id=\(activityId) en espera de decisión del usuario")
    }
    
    // MARK: - Resolución de Decisiones del Usuario
    
    private func handleUserDecision(activityId: String, actionId: String, textReply: String?) {
        guard let req = pendingRequests.removeValue(forKey: activityId) else { return }
        req.timeoutWorkItem?.cancel()
        
        var responseJson: [String: Any] = [
            "status": "ok",
            "action": actionId,
            "decision": actionId,
            "activityId": activityId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let reply = textReply, !reply.isEmpty {
            responseJson["reply"] = reply
        } else {
            responseJson["reply"] = NSNull()
        }
        
        DNDLogger.log("AgentIPCService: Respondiendo HTTP para id=\(activityId) -> action=\(actionId), reply=\(textReply ?? "nil")")
        sendHTTPResponse(
            connection: req.connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: responseJson
        )
    }
    
    private func handleActivityDismissed(activityId: String) {
        guard let req = pendingRequests.removeValue(forKey: activityId) else { return }
        req.timeoutWorkItem?.cancel()
        
        DNDLogger.log("AgentIPCService: Actividad id=\(activityId) descartada por el usuario")
        sendHTTPResponse(
            connection: req.connection,
            statusCode: 200,
            statusText: "OK",
            jsonObject: [
                "status": "dismissed",
                "action": "dismiss",
                "decision": "deny",
                "reason": "Descartado por el usuario en Dynamic Notch",
                "reply": NSNull(),
                "activityId": activityId
            ]
        )
    }
    
    // MARK: - HTTP Helpers
    
    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, statusText: String, jsonObject: [String: Any]) {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]) else {
            connection.cancel()
            return
        }
        
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        
        var responseData = Data(headers.utf8)
        responseData.append(bodyData)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
