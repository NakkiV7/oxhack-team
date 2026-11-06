import Foundation
import Security
import AuthenticationServices
import LocalAuthentication
import UIKit

struct StoredAccountCredential: Codable {
    var session: NativeAccountSession
    let privateKey: Data
    var refreshRequestID: UUID?
    var refreshStartedAt: Date?
    var locallySignedOut = false
    var lastTrustedVerification: Date?
}
@MainActor protocol AccountCredentialStorage {
    func load() throws -> StoredAccountCredential?
    func save(_ value: StoredAccountCredential) throws
    func clear() throws
}
@MainActor final class SecureAccountCredentials: AccountCredentialStorage {
    private let service = "com.omarchoudhry.spottr.native-account-v1"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "active-device", kSecAttrSynchronizable as String: false] }
    func load() throws -> StoredAccountCredential? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AccountFailure.keychain(status) }
        return try AccountJSON.decoder().decode(StoredAccountCredential.self, from: data)
    }
    func save(_ value: StoredAccountCredential) throws {
        let data = try AccountJSON.encoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let inserted = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw AccountFailure.keychain(inserted) }
            return
        }
        guard status == errSecSuccess else { throw AccountFailure.keychain(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountFailure.keychain(status) }
    }
}

@MainActor protocol NativeAccountAuthorization {
    func apple(nonce: String) async throws -> AppleIdentityResult
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential
    func guardian() async throws
}

@MainActor final class AuthenticationServicesAccountAuthorization: NSObject, NativeAccountAuthorization, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?
    private var anchor: UIWindow?

    func apple(nonce: String) async throws -> AppleIdentityResult {
        let request = ASAuthorizationAppleIDProvider().createRequest(); request.nonce = nonce
        let result = try await perform(request)
        guard let credential = result.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
              let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }),
              !token.isEmpty, !code.isEmpty else { throw AccountFailure.invalidResponse }
        return AppleIdentityResult(identityToken: token, authorizationCode: code)
    }
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential {
        guard options.rp.id == AccountClient.rpID, options.authenticatorSelection?.userVerification == "required",
              let challenge = Data(base64URL: options.challenge), !challenge.isEmpty,
              let userID = Data(base64URL: options.user.id), !userID.isEmpty else { throw AccountFailure.invalidResponse }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: AccountClient.rpID)
            .createCredentialRegistrationRequest(challenge: challenge, name: options.user.name, userID: userID)
        request.userVerificationPreference = .required
        request.displayName = options.user.displayName
        let result = try await perform(request)
        guard let credential = result.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = credential.rawAttestationObject, !attestation.isEmpty,
              !credential.credentialID.isEmpty, !credential.rawClientDataJSON.isEmpty else { throw AccountFailure.invalidResponse }
        return RegistrationCredential(id: credential.credentialID.base64URL, rawId: credential.credentialID.base64URL,
                                      response: .init(clientDataJSON: credential.rawClientDataJSON.base64URL, attestationObject: attestation.base64URL))
    }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential {
        guard options.rpId == AccountClient.rpID, options.userVerification == "required",
              let challenge = Data(base64URL: options.challenge), !challenge.isEmpty else { throw AccountFailure.invalidResponse }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: AccountClient.rpID).createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        let result = try await perform(request)
        guard let credential = result.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion,
              !credential.userID.isEmpty, credential.rawAuthenticatorData.count >= 37,
              credential.rawAuthenticatorData[32] & 0x04 != 0 else { throw AccountFailure.invalidResponse }
        return AssertionCredential(id: credential.credentialID.base64URL, rawId: credential.credentialID.base64URL,
            response: .init(clientDataJSON: credential.rawClientDataJSON.base64URL, authenticatorData: credential.rawAuthenticatorData.base64URL,
                            signature: credential.signature.base64URL, userHandle: credential.userID.base64URL))
    }
    func guardian() async throws {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil),
              try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock guardian controls for this training profile.") else { throw AccountFailure.cancelled }
    }
    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        guard continuation == nil else { throw AccountFailure.busy }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw AccountFailure.cancelled }
        anchor = window
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller; controller.delegate = self; controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor! }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) { complete(.success(authorization)) }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { complete(.failure(error)) }
    private func complete(_ result: Result<ASAuthorization, Error>) {
        let pending = continuation; continuation = nil; controller = nil; anchor = nil; pending?.resume(with: result)
    }
}
