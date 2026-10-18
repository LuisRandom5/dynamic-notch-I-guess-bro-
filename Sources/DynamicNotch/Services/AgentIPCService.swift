import Foundation
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
            self.startServer()
        }
    }
    
    public func stop() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
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
                    DNDLogger.log("AgentIPCService: Escuchando activamente en 127.0.0.1:\(self?.port ?? 48123)")
                case .failed(let error):
                    DNDLogger.log("AgentIPCService error: \(error.localizedDescription)")
                    self?.isRunning = false
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
            self.routeRequest(method: method, path: path, bodyData: bodyData, connection: connection)
        }
    }
    
    // MARK: - Enrutamiento de Peticiones HTTP
    
    private func routeRequest(method: String, path: String, bodyData: Data, connection: NWConnection) {
        DNDLogger.log("AgentIPCService: Request \(method) \(path)")
        
        // Soporte CORS preflight
        if method == "OPTIONS" {
            sendCORSPreflightResponse(connection: connection)
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
            
        case ("POST", "/glasslab"), ("GET", "/glasslab"):
            // Abre/cierra el laboratorio de Liquid Glass (comparativa de 5 variantes)
            DispatchQueue.main.async {
                GlassLabWindow.shared.toggle()
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
            "Access-Control-Allow-Origin: *",
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
    
    private func sendCORSPreflightResponse(connection: NWConnection) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Access-Control-Max-Age: 86400",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        
        connection.send(content: Data(headers.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
