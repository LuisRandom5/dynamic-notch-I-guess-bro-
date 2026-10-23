import Combine
import Foundation
import Security

// MARK: - Casa
// Estado de los aparatos de la casa (por ahora los de ConnectLife: la lavasecadora y el refri). Pregunta a la nube
// cada 30 s mientras la lavadora está en un ciclo y cada minuto cuando todo está quieto, para no saturar la cuenta
// (la API no es pública). El correo va en UserDefaults y la contraseña en el Llavero.
//
// Controles: el cambio se ve al instante (se encima sobre lo último que reportó el aparato) y se confirma en las
// consultas siguientes; si en 90 s el aparato no lo refleja, se quita y se avisa. Los botones de temperatura
// esperan a que dejes de tocarlos para mandar sólo el valor final.
@MainActor
public final class HomeStore: ObservableObject {
    public static let shared = HomeStore()

    public enum ConnectionState: Equatable {
        case notConfigured
        case connecting
        case connected
        /// Hay cuenta pero la última consulta falló (se reintenta sola, salvo si la contraseña ya no sirve)
        case failed(String)
    }

    @Published public private(set) var account: String?
    @Published public private(set) var connection: ConnectionState = .notConfigured
    @Published public private(set) var snapshot = HomeSnapshot()
    /// Aviso corto para la tarjeta ("No se aplicó…"); se borra solo
    @Published public private(set) var controlMessage: String?
    /// Abrir Casa directo en los controles del refri (al tocar su aviso)
    @Published public var showsFridgeControls = false
    /// Hay cambios mandados que el aparato aún no confirma
    @Published public private(set) var pendingKeys: Set<String> = []

    public var isConfigured: Bool { account != nil }
    public var washer: WasherStatus? { snapshot.washers.first }
    public var fridge: FridgeStatus? { snapshot.fridges.first }

    static let activeInterval: TimeInterval = 30
    static let idleInterval: TimeInterval = 60
    private static let accountKey = "homeConnectLifeAccount"
    /// Para probar contra el servidor de prueba de la librería de Python (`defaults write … homeConnectLifeTestServer http://127.0.0.1:8080`)
    private static let testServerKey = "homeConnectLifeTestServer"

    private var client: ConnectLifeClient?
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// Lo último que reportó la nube, sin los cambios pendientes encima
    private var lastAppliances: [ConnectLifeAppliance] = []
    private var pending: [String: PendingChange] = [:]
    private var sendTasks: [String: Task<Void, Never>] = [:]
    private var messageTask: Task<Void, Never>?

    struct PendingChange {
        let puid: String
        let statusKey: String
        let value: String
        let title: String
        var sentAt: Date
    }

    /// Tiempo que se espera a que el aparato refleje un cambio
    static let confirmTimeout: TimeInterval = 90

    private init() {
        account = UserDefaults.standard.string(forKey: Self.accountKey)
    }

    // MARK: - Ciclo de vida

    public func start() {
        guard let account, let password = HomeKeychain.password(for: account) else {
            connection = .notConfigured
            return
        }
        client = makeClient(account: account, password: password)
        startPolling()
    }

    /// Comprueba la cuenta y, si sirve, la guarda y empieza a consultar. Devuelve el error para mostrarlo en Ajustes.
    public func connect(email: String, password: String) async -> String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else { return L("Escribe el correo y la contraseña.") }
        let previousConnection = connection
        connection = .connecting
        let candidate = makeClient(account: email, password: password)
        do {
            try await candidate.login()
            let appliances = try await candidate.appliances()
            HomeKeychain.save(password: password, for: email)
            if let old = account, old != email { HomeKeychain.delete(for: old) }
            UserDefaults.standard.set(email, forKey: Self.accountKey)
            account = email
            client = candidate
            lastAppliances = appliances
            apply(HomeSnapshot(appliances: appliances))
            DNDLogger.log("Casa: cuenta conectada, \(appliances.count) aparato(s)")
            startPolling()
            return nil
        } catch {
            // La cuenta anterior (si había) sigue como estaba
            connection = account == nil ? .notConfigured : previousConnection
            return error.localizedDescription
        }
    }

    public func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        if let account { HomeKeychain.delete(for: account) }
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        account = nil
        client = nil
        connection = .notConfigured
        sendTasks.values.forEach { $0.cancel() }
        sendTasks = [:]
        pending = [:]
        pendingKeys = []
        lastAppliances = []
        apply(HomeSnapshot())
    }

    public func refreshNow() {
        guard client != nil else { return }
        startPolling()
    }

    // MARK: - Consultas

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = await self.poll()
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    /// Una consulta; devuelve cuánto esperar para la siguiente
    private func poll() async -> TimeInterval {
        guard let client else { return Self.idleInterval }
        if snapshot.isEmpty { connection = .connecting }
        do {
            let appliances = try await client.appliances()
            consecutiveFailures = 0
            logChanges(from: lastAppliances, to: appliances)
            lastAppliances = appliances
            reconcilePending(with: appliances)
            apply(HomeSnapshot(appliances: withPendingChanges(appliances)))
        } catch ConnectLifeError.invalidCredentials {
            // La contraseña cambió: no se insiste (bloquearía la cuenta)
            connection = .failed(ConnectLifeError.invalidCredentials.localizedDescription)
            pollTask?.cancel()
            return Self.idleInterval
        } catch {
            // La reemplazó otra consulta (Actualizar, un comando recién mandado): no es una falla
            if Task.isCancelled { return Self.idleInterval }
            consecutiveFailures += 1
            connection = .failed(error.localizedDescription)
            DNDLogger.log("Casa: falló la consulta (\(consecutiveFailures)): \(error.localizedDescription)")
            // 1, 2, 4… minutos, hasta 10
            return min(600, 60 * pow(2, Double(min(consecutiveFailures - 1, 4))))
        }
        let watching = (washer?.isCycleActive ?? false) || HomeActivityProvider.shared.wantsFastPolling || !pending.isEmpty
        return watching ? Self.activeInterval : Self.idleInterval
    }

    // MARK: - Controles

    public func setFridge(_ control: FridgeControl) {
        guard let fridge, let client, fridge.isOnline else { return }
        let key = fridge.puid + "|" + control.statusKey
        pending[key] = PendingChange(puid: fridge.puid, statusKey: control.statusKey, value: control.statusValue,
                                     title: control.title, sentAt: Date())
        pendingKeys = Set(pending.keys)
        apply(HomeSnapshot(appliances: withPendingChanges(lastAppliances)))

        let isStepper: Bool
        switch control {
        case .fridgeTemperature, .freezerTemperature: isStepper = true
        default: isStepper = false
        }
        sendTasks[key]?.cancel()
        sendTasks[key] = Task { [weak self] in
            // −/+ seguidos: sólo se manda el último valor
            if isStepper {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if Task.isCancelled { return }
            }
            let command = control.command
            do {
                try await client.update(puid: fridge.puid, properties: [command.name: command.value])
                DNDLogger.log("Casa: mandado \(command.name)=\(command.value)")
                guard let self else { return }
                self.pending[key]?.sentAt = Date()
                // El aparato tarda unos segundos en reportarlo
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { self.refreshNow() }
            } catch {
                guard let self, !Task.isCancelled else { return }
                DNDLogger.log("Casa: falló \(command.name): \(error.localizedDescription)")
                self.pending[key] = nil
                self.pendingKeys = Set(self.pending.keys)
                self.apply(HomeSnapshot(appliances: self.withPendingChanges(self.lastAppliances)))
                if case ConnectLifeError.network = error {
                    self.showMessage(L("Sin conexión: no se cambió"))
                } else {
                    self.showMessage(L("ConnectLife no aceptó el cambio"))
                }
            }
        }
    }

    /// Quita lo que el aparato ya confirmó y lo que nunca reflejó (avisando)
    private func reconcilePending(with appliances: [ConnectLifeAppliance]) {
        guard !pending.isEmpty else { return }
        let now = Date()
        for (key, change) in pending {
            let reported = appliances.first { $0.puid == change.puid }?.status[change.statusKey]
            if reported.map({ Self.sameValue($0, change.value) }) ?? false {
                pending[key] = nil
            } else if now.timeIntervalSince(change.sentAt) > Self.confirmTimeout {
                pending[key] = nil
                DNDLogger.log("Casa: \(change.statusKey) no llegó a \(change.value) (reporta \(reported ?? "nada"))")
                showMessage(String(format: L("El aparato no aplicó: %@"), change.title))
            }
        }
        pendingKeys = Set(pending.keys)
    }

    private func withPendingChanges(_ appliances: [ConnectLifeAppliance]) -> [ConnectLifeAppliance] {
        guard !pending.isEmpty else { return appliances }
        return appliances.map { appliance in
            var status = appliance.status
            for change in pending.values where change.puid == appliance.puid {
                status[change.statusKey] = change.value
            }
            return ConnectLifeAppliance(deviceId: appliance.deviceId, puid: appliance.puid, nickname: appliance.nickname,
                                        typeCode: appliance.typeCode, featureCode: appliance.featureCode,
                                        featureName: appliance.featureName, isOnline: appliance.isOnline, status: status)
        }
    }

    /// Qué cambió desde la consulta anterior (para saber qué manda cada aparato y cuándo; p. ej. al abrir la puerta)
    private func logChanges(from old: [ConnectLifeAppliance], to new: [ConnectLifeAppliance]) {
        guard !old.isEmpty else { return }
        for appliance in new {
            guard let before = old.first(where: { $0.puid == appliance.puid }) else { continue }
            let changed = appliance.status.keys.sorted().filter { before.status[$0] != appliance.status[$0] }
            if before.isOnline != appliance.isOnline {
                DNDLogger.log("Casa: \(appliance.nickname) \(appliance.isOnline ? "en línea" : "sin conexión")")
            }
            guard !changed.isEmpty else { continue }
            let text = changed.prefix(20).map { "\($0) \(before.status[$0] ?? "∅")→\(appliance.status[$0] ?? "∅")" }
                .joined(separator: ", ")
            DNDLogger.log("Casa: \(appliance.nickname) cambió \(text)\(changed.count > 20 ? " (+\(changed.count - 20))" : "")")
        }
    }

    /// "5" y "5.0" son lo mismo
    nonisolated static func sameValue(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if let x = Double(a), let y = Double(b) { return x == y }
        return false
    }

    private func showMessage(_ text: String) {
        controlMessage = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.controlMessage = nil }
        }
    }

    private func apply(_ new: HomeSnapshot) {
        let previous = snapshot
        snapshot = new
        if isConfigured { connection = .connected }
        HomeActivityProvider.shared.update(previous: previous, current: new)
    }

    private func makeClient(account: String, password: String) -> ConnectLifeClient {
        if let server = UserDefaults.standard.string(forKey: Self.testServerKey), !server.isEmpty {
            DNDLogger.log("Casa: usando el servidor de prueba \(server)")
            return ConnectLifeClient(username: account, password: password, endpoints: .testServer(server))
        }
        return ConnectLifeClient(username: account, password: password)
    }
}

// MARK: - Llavero

enum HomeKeychain {
    private static let service = "com.luisrandom.DynamicNotch.connectlife"

    static func password(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(password: String, for account: String) {
        delete(for: account)
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: "Dynamic Notch — ConnectLife",
            kSecValueData: Data(password.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { DNDLogger.log("Casa: no se pudo guardar en el Llavero (\(status))") }
    }

    static func delete(for account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
