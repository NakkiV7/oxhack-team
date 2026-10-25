import Foundation
import Security

@MainActor
protocol SecondaryCameraSecretStore {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

@MainActor
struct SecondaryCameraKeychainStore: SecondaryCameraSecretStore {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.spottr.secondary-camera",
        kSecAttrAccount as String: "pairing",
        kSecAttrSynchronizable as String: false
    ]
    func read() throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, value in value } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecondaryCameraError.configuration }
        return data
    }
    func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil) == errSecSuccess else {
                throw SecondaryCameraError.configuration
            }
        } else if status != errSecSuccess { throw SecondaryCameraError.configuration }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecondaryCameraError.configuration }
    }
}

@MainActor
enum SecondaryCameraSettings {
    struct Connection {
        let configuration: SecondaryCameraConfig
        let token: String
    }
    private struct Pairing: Codable {
        let url: String
        let certificateSHA256: String
        let token: String
    }
    static func connection(store: (any SecondaryCameraSecretStore)? = nil) throws -> Connection? {
        guard let data = try (store ?? SecondaryCameraKeychainStore()).read() else { return nil }
        guard let pairing = try? JSONDecoder().decode(Pairing.self, from: data) else { throw SecondaryCameraError.configuration }
        let configuration = try SecondaryCameraConfig(url: pairing.url, certificateSHA256: pairing.certificateSHA256)
        try SecondaryCameraConfig.validateAccessToken(pairing.token)
        return Connection(configuration: configuration, token: pairing.token)
    }
    static func save(url: String, certificateSHA256: String, token: String,
                     store: (any SecondaryCameraSecretStore)? = nil) throws {
        let configuration = try SecondaryCameraConfig(url: url, certificateSHA256: certificateSHA256)
        try SecondaryCameraConfig.validateAccessToken(token)
        let pairing = Pairing(url: configuration.baseURL.absoluteString, certificateSHA256: configuration.certificateSHA256, token: token)
        try (store ?? SecondaryCameraKeychainStore()).write(JSONEncoder().encode(pairing))
    }
    static func forget(store: (any SecondaryCameraSecretStore)? = nil) throws {
        try (store ?? SecondaryCameraKeychainStore()).remove()
    }
    static func client(store: (any SecondaryCameraSecretStore)? = nil) throws -> SecondaryCameraClient {
        guard let connection = try connection(store: store) else { throw SecondaryCameraError.configuration }
        return try SecondaryCameraClient(configuration: connection.configuration, token: connection.token)
    }
}
