import CryptoKit
import Foundation
import Security

// MARK: - ConnectLife (Hisense, Gorenje, ASKO)
// Cliente de la nube de ConnectLife, la de la app del mismo nombre. No es una API pública: es la misma que usa la
// app, tal como la documentó la librería `connectlife` de Python (github.com/oyvindwe/connectlife), que también
// usa la integración de Home Assistant. Flujo: Gigya (correo y contraseña) → JWT → código OAuth → token de acceso;
// después cada petición al gateway va firmada (SHA-256 de los parámetros, cifrado con su llave pública RSA).
//
// Comandos (`update`): como en la app, se manda una propiedad o un comando por petición, con su valor como texto
// (p. ej. SET_REFRIGERATOR_TEMPERATURE = "5"); los nombres salen de los mapas de connectlife-ha.

public struct ConnectLifeAppliance: Equatable {
    public let deviceId: String
    public let puid: String
    public let nickname: String
    public let typeCode: String
    public let featureCode: String
    /// Modelo, p. ej. "WDSE1214-MVB005-000"
    public let featureName: String
    public let isOnline: Bool
    /// Todo lo que reporta el aparato, tal cual (los valores llegan como texto o número)
    public let status: [String: String]
}

public enum ConnectLifeError: LocalizedError, Equatable {
    case invalidCredentials
    /// La cuenta tiene que aceptar los términos nuevos en la app antes de poder entrar
    case termsNotAccepted
    case network(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return L("El correo o la contraseña no son correctos.")
        case .termsNotAccepted: return L("Abre la app ConnectLife y acepta los términos nuevos; luego vuelve a intentarlo.")
        case .network(let detail): return L("No se pudo conectar con ConnectLife.") + " (\(detail))"
        case .unexpected(let detail): return L("ConnectLife respondió algo inesperado.") + " (\(detail))"
        }
    }
}

public actor ConnectLifeClient {
    /// Direcciones del servicio (se pueden apuntar al servidor de prueba de la librería de Python)
    public struct Endpoints {
        var login: URL
        var jwt: URL
        var authorize: URL
        var token: URL
        var redirectURI: String
        var deviceList: URL
        var update: URL

        public static let production = Endpoints(
            login: URL(string: "https://accounts.eu1.gigya.com/accounts.login")!,
            jwt: URL(string: "https://accounts.eu1.gigya.com/accounts.getJWT")!,
            authorize: URL(string: "https://oauth.hijuconn.com/oauth/authorize")!,
            token: URL(string: "https://oauth.hijuconn.com/oauth/token")!,
            redirectURI: "https://api.connectlife.io/swagger/oauth2-redirect.html",
            deviceList: URL(string: "https://clife-eu-gateway.hijuconn.com/clife-svc/pu/get_device_status_list")!,
            update: URL(string: "https://clife-eu-gateway.hijuconn.com/device/pu/property/set")!
        )

        public static func testServer(_ base: String) -> Endpoints {
            Endpoints(
                login: URL(string: "\(base)/accounts.login")!,
                jwt: URL(string: "\(base)/accounts.getJWT")!,
                authorize: URL(string: "\(base)/oauth/authorize")!,
                token: URL(string: "\(base)/oauth/token")!,
                redirectURI: "\(base)/swagger/oauth2-redirect.html",
                deviceList: URL(string: "\(base)/clife-svc/pu/get_device_status_list")!,
                update: URL(string: "\(base)/device/pu/property/set")!
            )
        }
    }

    // Identidad de la app ConnectLife (públicas: vienen dentro de la app)
    private static let gigyaAPIKey = "4_yhTWQmHFpZkQZDSV1uV-_A"
    private static let oauthClientId = "5065059336212"
    private static let oauthClientSecret = "07swfKgvJhC3ydOUS9YV_SwVz0i4LKqlOLGNUukYHVMsJRF1b-iWeUGcNlXyYCeK"
    static let gatewayAppId = "47110565134383"
    static let gatewayAppSecret = "yOzhz6junYno-nmULM3Wr7PU_dpSZN22ZdluvVWZ4uW5ZwwG8fIGCHTbrhcnU-iv"
    static let gatewaySignSuffix = "D9519A4B756946F081B7BB5B5E8D1197"
    private static let gatewayPublicKeyBase64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyyWrNG6q475HIHu7sMVu" +
        "vHof6vlgPeixmxa4EL/UsvVvHPz33NnWoQetQqit9TBNzUjMXw0KlY9PXM4iqHUU" +
        "U+dSyNDq1jZWIiJ2C2FccppswJtIKL3NRMFvT9PFh6NlP/4FUcQKojgKFbF7Kacc" +
        "JPKYHlwaO7qgoIjLxAHlSOXGpucJcOkPzT2EqsSVnW8sn8kenvNmghXDayhgxsh6" +
        "AyxK4kehJplEnmX/iYCfNoFXknGcLqFWYccgBz3fybvx30C/0IgU1980L8QsUAv5" +
        "esZmN8ugnbRgLRxKRlkQQLxQAiZMZdKTAx665YflT3YMHJvEFE8c2XFgoxHzSMc4" +
        "BwIDAQAB"
    private static let gigyaPendingRegistration = 206001
    private static let gatewayInvalidAccessToken = 100026
    private static let gatewayRandStrCheckFailed = 101005

    private let username: String
    private let password: String
    private let endpoints: Endpoints
    private let session: URLSession

    private var accessToken: String?
    private var accessTokenExpires: Date?
    private var refreshToken: String?

    public init(username: String, password: String, endpoints: Endpoints = .production) {
        self.username = username
        self.password = password
        self.endpoints = endpoints
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Entra desde cero (para comprobar la cuenta al conectarla en Ajustes)
    public func login() async throws {
        accessToken = nil
        accessTokenExpires = nil
        refreshToken = nil
        try await fullLogin()
    }

    public func appliances() async throws -> [ConnectLifeAppliance] {
        try await ensureAccessToken()
        let response = try await gateway(endpoints.deviceList, post: false, payload: [:], properties: nil,
                                          retryOnReauth: true, retryOnRandStr: true)
        guard let list = response["deviceList"] as? [[String: Any]] else {
            throw ConnectLifeError.unexpected("sin deviceList")
        }
        return list.compactMap(Self.parseAppliance)
    }

    /// Manda un comando a un aparato. El gateway responde en cuanto lo recibe; el aparato lo aplica después y su
    /// nuevo estado llega en una consulta posterior.
    public func update(puid: String, properties: [String: String]) async throws {
        try await ensureAccessToken()
        _ = try await gateway(endpoints.update, post: true, payload: ["puid": puid], properties: properties,
                              retryOnReauth: true, retryOnRandStr: true)
    }

    // MARK: - Token

    private func ensureAccessToken() async throws {
        if let expires = accessTokenExpires, accessToken != nil, expires > Date() { return }
        if accessToken != nil, let refresh = refreshToken {
            do {
                let body = try await postForm(endpoints.token, [
                    "client_id": Self.oauthClientId,
                    "client_secret": Self.oauthClientSecret,
                    "redirect_uri": endpoints.redirectURI,
                    "grant_type": "refresh_token",
                    "refresh_token": refresh,
                ])
                try storeToken(body)
                return
            } catch {
                DNDLogger.log("ConnectLife: no se pudo renovar el token, entrando de nuevo: \(error.localizedDescription)")
            }
        }
        try await fullLogin()
    }

    private func fullLogin() async throws {
        let login = try await postForm(endpoints.login, [
            "loginID": username,
            "password": password,
            "APIKey": Self.gigyaAPIKey,
        ])
        let errorCode = (login["errorCode"] as? Int) ?? 0
        if errorCode != 0 || login["errorMessage"] != nil {
            if errorCode == Self.gigyaPendingRegistration { throw ConnectLifeError.termsNotAccepted }
            DNDLogger.log("ConnectLife: inicio de sesión rechazado (\(errorCode)) \(login["errorMessage"] ?? "")")
            throw ConnectLifeError.invalidCredentials
        }
        guard let uid = login["UID"] as? String,
              let sessionInfo = login["sessionInfo"] as? [String: Any],
              let loginToken = sessionInfo["cookieValue"] as? String else {
            throw ConnectLifeError.unexpected("login sin UID")
        }

        let jwt = try await postForm(endpoints.jwt, ["APIKey": Self.gigyaAPIKey, "login_token": loginToken])
        guard let idToken = jwt["id_token"] as? String else { throw ConnectLifeError.unexpected("sin id_token") }

        let authorize = try await postJSON(endpoints.authorize, [
            "client_id": Self.oauthClientId,
            "redirect_uri": endpoints.redirectURI,
            "idToken": idToken,
            "response_type": "code",
            "thirdType": "CDC",
            "thirdClientId": uid,
        ])
        guard let code = authorize["code"] as? String else { throw ConnectLifeError.unexpected("sin código OAuth") }

        let token = try await postForm(endpoints.token, [
            "client_id": Self.oauthClientId,
            "client_secret": Self.oauthClientSecret,
            "redirect_uri": endpoints.redirectURI,
            "grant_type": "authorization_code",
            "code": code,
        ])
        try storeToken(token)
    }

    private func storeToken(_ body: [String: Any]) throws {
        guard let token = body["access_token"] as? String else { throw ConnectLifeError.unexpected("sin access_token") }
        let expiresIn = (body["expires_in"] as? Double) ?? Double("\(body["expires_in"] ?? "")") ?? 3600
        accessToken = token
        // Se renueva 90 s antes de que venza
        accessTokenExpires = Date().addingTimeInterval(expiresIn - 90)
        if let refresh = body["refresh_token"] as? String { refreshToken = refresh }
    }

    // MARK: - Gateway

    /// GET (parámetros en la URL) o POST (JSON). `properties` viaja como objeto en el cuerpo y se firma como JSON
    /// compacto, igual que en la librería de Python.
    private func gateway(_ url: URL, post: Bool, payload: [String: String], properties: [String: String]?,
                         retryOnReauth: Bool, retryOnRandStr: Bool) async throws -> [String: Any] {
        guard let accessToken else { throw ConnectLifeError.unexpected("sin token") }
        var signedPayload = payload
        if let properties { signedPayload["properties"] = try Self.compactJSON(properties) }
        let params = try Self.signedGatewayParameters(accessToken: accessToken, payload: signedPayload)
        var request: URLRequest
        if post {
            var body: [String: Any] = params
            if let properties { body["properties"] = properties }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.percentEncodedQuery = Self.formEncode(params)
            request = URLRequest(url: components.url!)
        }
        request.setValue("connectlife/0.14.0", forHTTPHeaderField: "User-Agent")
        let body = try await send(request)

        guard let response = body["response"] as? [String: Any] else {
            throw ConnectLifeError.unexpected("gateway sin response")
        }
        let resultCode = response["resultCode"].map { "\($0)" } ?? "0"
        if resultCode == "0" { return response }

        let errorCode = (response["errorCode"] as? Int) ?? Int("\(response["errorCode"] ?? "")") ?? -1
        if retryOnReauth && errorCode == Self.gatewayInvalidAccessToken {
            DNDLogger.log("ConnectLife: el gateway rechazó el token, entrando de nuevo")
            try await login()
            return try await gateway(url, post: post, payload: payload, properties: properties,
                                     retryOnReauth: false, retryOnRandStr: retryOnRandStr)
        }
        if retryOnRandStr && errorCode == Self.gatewayRandStrCheckFailed {
            return try await gateway(url, post: post, payload: payload, properties: properties,
                                     retryOnReauth: retryOnReauth, retryOnRandStr: false)
        }
        throw ConnectLifeError.unexpected("gateway \(errorCode): \(response["errorDesc"] ?? "")")
    }

    /// Parámetros comunes del gateway más la firma (`sign`)
    static func signedGatewayParameters(accessToken: String, payload: [String: String],
                                        timestamp: String? = nil, randStr: String? = nil) throws -> [String: String] {
        var params: [String: String] = [
            "accessToken": accessToken,
            "appId": gatewayAppId,
            "appSecret": gatewayAppSecret,
            "languageId": "12",
            // Nonce por petición: el gateway rechaza los repetidos
            "randStr": randStr ?? randomHex(bytes: 16),
            "timeStamp": timestamp ?? String(Int(Date().timeIntervalSince1970 * 1000)),
            "timezone": "1.0",
            "version": "5.0",
        ]
        params.merge(payload) { _, new in new }
        params["sign"] = try sign(signingString(params))
        return params
    }

    /// Como `json.dumps(valor, separators=(",", ":"))` de Python para un diccionario de texto
    static func compactJSON(_ object: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// `clave=valor` ordenados por clave, unidos con `&`, más el sufijo fijo
    static func signingString(_ params: [String: String]) -> String {
        params.keys.filter { $0 != "sign" }.sorted()
            .map { "\($0)=\(params[$0]!)" }
            .joined(separator: "&") + gatewaySignSuffix
    }

    private static func sign(_ text: String) throws -> String {
        let digest = Data(SHA256.hash(data: Data(text.utf8)))
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(try publicKey(), .rsaEncryptionPKCS1, digest as CFData, &error) else {
            throw ConnectLifeError.unexpected("firma: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        return (encrypted as Data).base64EncodedString()
    }

    private static var cachedKey: SecKey?

    private static func publicKey() throws -> SecKey {
        if let cachedKey { return cachedKey }
        var der = Data(base64Encoded: gatewayPublicKeyBase64)!
        // Security quiere la llave RSA "pelona" (PKCS#1): se quita la cabecera SubjectPublicKeyInfo de 24 bytes
        let spkiHeader = Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                               0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00])
        if der.starts(with: spkiHeader) { der = der.dropFirst(spkiHeader.count) }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, &error) else {
            throw ConnectLifeError.unexpected("llave: \(error?.takeRetainedValue().localizedDescription ?? "?")")
        }
        cachedKey = key
        return key
    }

    private static func randomHex(bytes: Int) -> String {
        (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: - HTTP

    private func postForm(_ url: URL, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try await send(request)
    }

    private func postJSON(_ url: URL, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConnectLifeError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 || status == 403 { throw ConnectLifeError.invalidCredentials }
            throw ConnectLifeError.network("HTTP \(status) en \(request.url?.path ?? "")")
        }
        // A veces llega con un Content-Type equivocado: se lee como JSON de todas formas
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectLifeError.unexpected("respuesta que no es JSON en \(request.url?.path ?? "")")
        }
        return object
    }

    /// Codificación estricta: `+`, `/` y `=` de la firma en base64 tienen que viajar escapados
    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.keys.sorted().map { key in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = fields[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? fields[key]!
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    static func parseAppliance(_ raw: [String: Any]) -> ConnectLifeAppliance? {
        guard let deviceId = raw["deviceId"].map({ "\($0)" }) else { return nil }
        var status: [String: String] = [:]
        for (key, value) in (raw["statusList"] as? [String: Any]) ?? [:] {
            status[key] = "\(value)"
        }
        // offlineState: 1 = en línea (la app lo muestra conectado), 0 = sin conexión
        let offline = Int("\(raw["offlineState"] ?? 1)") ?? 1
        return ConnectLifeAppliance(
            deviceId: deviceId,
            puid: raw["puid"].map { "\($0)" } ?? "",
            nickname: (raw["deviceNickName"] as? String) ?? "",
            typeCode: raw["deviceTypeCode"].map { "\($0)" } ?? "",
            featureCode: raw["deviceFeatureCode"].map { "\($0)" } ?? "",
            featureName: (raw["deviceFeatureName"] as? String) ?? "",
            isOnline: offline != 0,
            status: status
        )
    }
}
