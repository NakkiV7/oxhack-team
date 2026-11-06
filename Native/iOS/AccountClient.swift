import Foundation
import CryptoKit

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}

enum AccountFailure: Error, LocalizedError {
    case configuration, invalidResponse, cancelled, busy, checkpointRequired, reauthenticate, service(Int, String), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .configuration: return "Account services are not ready in this build. Your saved local data is unchanged."
        case .cancelled: return "Authentication was cancelled."
        case .busy: return "Finish the current authentication request first."
        case .checkpointRequired: return "Choose an adult account owner or a guardian before continuing."
        case .reauthenticate: return "Sign in with your passkey and Authenticator again. Your local data is unchanged."
        case .keychain: return "Secure credentials are unavailable. Unlock this device and retry."
        case .service(let status, _): return status == 401 ? "Verification was not accepted. Retry or sign in again." : "Account services are temporarily unavailable. Try again."
        case .invalidResponse: return "The account response could not be verified. Try again."
        }
    }
}

enum AccountJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw AccountFailure.invalidResponse }
            return date
        }
        return decoder
    }
}

struct NativeAccountSession: Codable, Equatable {
    var authenticated: Bool
    let accountID: UUID
    var appAccountToken: UUID
    let deviceID: UUID
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    var backupCodes: [String]?
    var usedBackupCode: Bool?
    func validate() throws {
        guard authenticated, appAccountToken == accountID, !accessToken.isEmpty, !refreshToken.isEmpty,
              accessExpiresAt < refreshExpiresAt else { throw AccountFailure.invalidResponse }
    }
}
struct DevicePublicKey: Encodable { let kty = "EC"; let crv = "P-256"; let x: String; let y: String }
struct NativeDeviceProof: Codable {
    let challenge: String; let nonce: String; let issuedAt: String; let signature: String
    static func message(path: String, body: Data, token: String, challenge: String, nonce: String, issuedAt: String) -> Data {
        Data(["spottr-native-v1", "POST", path, Data(SHA256.hash(data: body)).base64URL,
              Data(SHA256.hash(data: Data(token.utf8))).base64URL, challenge, nonce, issuedAt].joined(separator: "\n").utf8)
    }
    static func make(path: String, body: Data, token: String, challenge: String, key: P256.Signing.PrivateKey, now: Date = .now) throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountFailure.invalidResponse }
        let nonce = Data(bytes).base64URL
        let issuedAt = ISO8601DateFormatter().string(from: now)
        let signature = try key.signature(for: message(path: path, body: body, token: token, challenge: challenge, nonce: nonce, issuedAt: issuedAt)).rawRepresentation.base64URL
        return Self(challenge: challenge, nonce: nonce, issuedAt: issuedAt, signature: signature)
    }
    static func publicKey(_ key: P256.Signing.PrivateKey) -> DevicePublicKey {
        let bytes = key.publicKey.x963Representation
        return DevicePublicKey(x: bytes[1..<33].base64URL, y: bytes[33..<65].base64URL)
    }
}

@MainActor protocol AccountTransport { func send(_ request: URLRequest) async throws -> (Data, Int) }
@MainActor final class NativeAccountTransport: NSObject, AccountTransport, URLSessionTaskDelegate {
    // Task 10 enables this only after the reviewed provider and associated-domain acceptance.
    static let providerConfigurationReady = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard Self.providerConfigurationReady else { throw AccountFailure.configuration }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 131072 else { throw AccountFailure.invalidResponse }
        return (data, response.statusCode)
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class AccountClient {
    static let origin = "https://spottr.omarchoudhry.co.uk"
    static let rpID = "spottr.omarchoudhry.co.uk"
    private let transport: any AccountTransport
    init(transport: any AccountTransport) { self.transport = transport }
    convenience init() { self.init(transport: NativeAccountTransport()) }
    func post<Body: Encodable, Reply: Decodable>(_ route: String, body: Body, credential: StoredAccountCredential? = nil, refresh: Bool = false) async throws -> Reply {
        let data = try AccountJSON.encoder().encode(body)
        guard data.count <= 32768, route.first == "/", !route.contains("?"), !route.contains("..") else { throw AccountFailure.invalidResponse }
        let path = "/api/native/v1" + route
        var request = URLRequest(url: URL(string: Self.origin + path)!)
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let credential {
            let token = refresh ? credential.session.refreshToken : credential.session.accessToken
            let challenge: SessionChallenge = try await post("/session/challenge", body: TokenRequest(token: token))
            guard challenge.expiresAt > Date() else { throw AccountFailure.reauthenticate }
            let key = try P256.Signing.PrivateKey(rawRepresentation: credential.privateKey)
            let proof = try NativeDeviceProof.make(path: path, body: data, token: token, challenge: challenge.challenge, key: key)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(String(decoding: try AccountJSON.encoder().encode(proof), as: UTF8.self), forHTTPHeaderField: "X-Spottr-Proof")
        }
        let (response, status) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            let issue = try? AccountJSON.decoder().decode(ServiceError.self, from: response)
            throw AccountFailure.service(status, issue?.error ?? "unknown")
        }
        return try AccountJSON.decoder().decode(Reply.self, from: response)
    }
}
struct EmptyRequest: Codable {}
struct TokenRequest: Encodable { let token: String }
struct SessionChallenge: Decodable { let challenge: String; let expiresAt: Date }
struct ServiceError: Decodable { let error: String }
enum IdentityPurpose: String, Codable { case enroll, recover, link }
struct IdentityStart: Decodable { let flowToken: String; let expiresAt: Date; let accepted: Bool?; let nonce: String? }
struct FlowReply: Decodable { let flowToken: String; let verified: Bool?; let needsSecondFactor: Bool? }
struct FlowRequest: Encodable { let flowToken: String }
struct EmailStart: Encodable { let email: String; let purpose: IdentityPurpose }
struct AppleStart: Encodable { let purpose: IdentityPurpose }
struct EmailVerify: Encodable { let flowToken: String; let code: String }
struct AppleVerify: Encodable { let flowToken: String; let identityToken: String; let authorizationCode: String }
struct AppleIdentityResult { let identityToken: String; let authorizationCode: String }
struct RegistrationVerify: Encodable { let flowToken: String; let credential: RegistrationCredential }
struct AssertionVerify: Encodable { let flowToken: String; let credential: AssertionCredential }
struct EnrollmentSecret: Decodable { let flowToken: String; let secret: String; let uri: String }
struct EnrollmentComplete: Encodable { let flowToken: String; let code: String; let deviceKey: DevicePublicKey }
struct MFAComplete: Encodable { let flowToken: String; let code: String?; let backupCode: String?; let deviceKey: DevicePublicKey }
struct RecoveryOptionsRequest: Encodable { let flowToken: String; let backupCode: String }
struct RegistrationOptionsReply: Decodable { let flowToken: String; let options: PasskeyCreationOptions }
struct LoginOptionsReply: Decodable { let flowToken: String; let expiresAt: Date; let options: PasskeyRequestOptions }
struct RefreshRequest: Encodable { let requestID: UUID }
struct DeleteRequest: Encodable { let confirm = "DELETE" }
struct RevocationRequest: Encodable {
    let deviceID: String
    init(deviceID: UUID) { self.deviceID = deviceID.uuidString.lowercased() }
}
struct SignedOutReply: Decodable { let signedOut: Bool }
struct DeletedReply: Decodable { let deleted: Bool; let phoneHistoryUnchanged: Bool }
struct LinkedReply: Decodable { let linked: Bool }
struct CurrentSessionReply: Decodable { let authenticated: Bool; let accountID: UUID; let appAccountToken: UUID; let deviceID: UUID; let accessExpiresAt: Date; let refreshExpiresAt: Date }
struct PasskeyCreationOptions: Decodable {
    struct RP: Decodable { let id: String?; let name: String }
    struct User: Decodable { let id: String; let name: String; let displayName: String }
    struct Selection: Decodable { let userVerification: String?; let residentKey: String? }
    let challenge: String; let rp: RP; let user: User; let authenticatorSelection: Selection?
}
struct PasskeyRequestOptions: Decodable { let challenge: String; let rpId: String?; let userVerification: String? }
struct RegistrationCredential: Encodable {
    struct Response: Encodable { let clientDataJSON: String; let attestationObject: String; let transports = ["internal"] }
    let id: String; let rawId: String; let type = "public-key"; let clientExtensionResults = EmptyRequest(); let authenticatorAttachment = "platform"; let response: Response
}
struct AssertionCredential: Encodable {
    struct Response: Encodable { let clientDataJSON: String; let authenticatorData: String; let signature: String; let userHandle: String }
    let id: String; let rawId: String; let type = "public-key"; let clientExtensionResults = EmptyRequest(); let authenticatorAttachment = "platform"; let response: Response
}
