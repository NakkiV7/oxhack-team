import XCTest
import CryptoKit
@testable import Spottr

@MainActor final class AccountFlowTests: XCTestCase {
    func testRevocationSerializesCanonicalServerDeviceIDAndSignsExactRequestBody() async throws {
        let serverID = "abcdef12-3456-4789-abcd-ef1234567890"
        let deviceID = try XCTUnwrap(UUID(uuidString: serverID))
        let wire = AccountTestTransport()
        wire.replies = [Data("{\"challenge\":\"challenge\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}".utf8), Data("{\"signedOut\":true}".utf8)]
        let credential = try fixtureCredential()
        let reply: SignedOutReply = try await AccountClient(transport: wire).post("/session/revoke", body: RevocationRequest(deviceID: deviceID), credential: credential)
        XCTAssertTrue(reply.signedOut)
        let request = try XCTUnwrap(wire.requests.last)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(body, try AccountJSON.encoder().encode(["deviceID": serverID]))
        let proofData = Data(try XCTUnwrap(request.value(forHTTPHeaderField: "X-Spottr-Proof")).utf8)
        let proof = try JSONDecoder().decode(NativeDeviceProof.self, from: proofData)
        let message = NativeDeviceProof.message(path: "/api/native/v1/session/revoke", body: body, token: credential.session.accessToken, challenge: proof.challenge, nonce: proof.nonce, issuedAt: proof.issuedAt)
        let key = try P256.Signing.PrivateKey(rawRepresentation: credential.privateKey)
        XCTAssertTrue(key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: XCTUnwrap(Data(base64URL: proof.signature))), for: message))
    }

    func testDeviceProofSignsExactBodyAndTokenWithRawSignature() throws {
        let key = P256.Signing.PrivateKey()
        let body = Data("{\"requestID\":\"123\"}".utf8)
        let proof = try NativeDeviceProof.make(path: "/api/native/v1/session/refresh", body: body, token: "token", challenge: "challenge", key: key, now: Date(timeIntervalSince1970: 1800000000))
        let message = NativeDeviceProof.message(path: "/api/native/v1/session/refresh", body: body, token: "token", challenge: proof.challenge, nonce: proof.nonce, issuedAt: proof.issuedAt)
        XCTAssertTrue(key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: Data(base64URL: proof.signature)!), for: message))
        XCTAssertEqual(Data(base64URL: proof.signature)?.count, 64)
        XCTAssertEqual(Data(base64URL: proof.nonce)?.count, 32)
        XCTAssertNotEqual(message, NativeDeviceProof.message(path: "/api/native/v1/session/refresh", body: Data("{}".utf8), token: "token", challenge: proof.challenge, nonce: proof.nonce, issuedAt: proof.issuedAt))
    }

    func testPartialIdentityNeverExposesAccountAndChildCheckpointPrecedesEmail() async throws {
        let wire = AccountTestTransport()
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: AccountTestAuthorization())
        await store.startEmail(email: "guardian@example.test", purpose: .enroll)
        XCTAssertEqual(wire.requests.count, 0)
        XCTAssertNil(store.accountID)
        try store.setCheckpoint(ageYears: 12, role: .guardian)
        wire.replies = [Data("{\"flowToken\":\"pending\",\"expiresAt\":\"2030-01-01T00:00:00Z\",\"accepted\":true}".utf8)]
        await store.startEmail(email: "guardian@example.test", purpose: .enroll)
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertNil(store.accountID)
        XCTAssertFalse(String(data: wire.requests[0].httpBody!, encoding: .utf8)!.contains("age"))
    }

    func testRestoreOfflineKeepsCredentialAndConcurrentRefreshUsesOneDurableRequest() async throws {
        let wire = AccountTestTransport()
        let vault = MemoryAccountCredentials()
        let stored = try fixtureCredential()
        try vault.save(stored)
        wire.failure = URLError(.notConnectedToInternet)
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await store.restore()
        XCTAssertEqual(store.accountID, stored.session.accountID)
        XCTAssertEqual(store.state, .trustedOffline)
        XCTAssertNotNil(try vault.load())
        wire.failure = nil
        wire.replies = [Data("{\"challenge\":\"challenge\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}".utf8), try AccountJSON.encoder().encode(stored.session)]
        async let a: Void = store.refresh()
        async let b: Void = store.refresh()
        _ = await (a, b)
        XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/session/refresh") == true }.count, 1)
        XCTAssertNil(try vault.load()?.refreshRequestID)
    }

    func testInvalidCredentialsRequireAuthenticationWithoutDeletingLocalCredential() async throws {
        let wire = AccountTestTransport()
        let vault = MemoryAccountCredentials()
        try vault.save(fixtureCredential())
        wire.status = 401
        wire.replies = [Data("{\"error\":\"verification_failed\"}".utf8)]
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await store.restore()
        XCTAssertNil(store.accountID)
        XCTAssertEqual(store.state, .credentialsUnknown)
        XCTAssertNotNil(try vault.load())
    }

    func testMismatchedPurchaseAttributionAndIncompleteMFAAreRejected() throws {
        var session = try fixtureCredential().session
        session.appAccountToken = UUID()
        XCTAssertThrowsError(try session.validate())
        session.appAccountToken = session.accountID
        session.authenticated = false
        XCTAssertThrowsError(try session.validate())
    }

    func testNativePasskeyRejectsWrongRPAndMissingRequiredVerificationBeforePresentation() async throws {
        let adapter = AuthenticationServicesAccountAuthorization()
        for payload in [
            "{\"challenge\":\"YWJj\",\"rpId\":\"other.example\",\"userVerification\":\"required\"}",
            "{\"challenge\":\"YWJj\",\"rpId\":\"spottr.omarchoudhry.co.uk\",\"userVerification\":\"preferred\"}"
        ] {
            let options = try JSONDecoder().decode(PasskeyRequestOptions.self, from: Data(payload.utf8))
            do { _ = try await adapter.authenticate(options: options); XCTFail("Invalid RP/UV must fail before native presentation") }
            catch AccountFailure.invalidResponse { }
        }
    }

    func testLostRefreshResponseRetainsSameRequestIDAndExpiredRetryNeverReusesToken() async throws {
        let wire = AccountTestTransport()
        let vault = MemoryAccountCredentials()
        var stored = try fixtureCredential()
        stored.refreshRequestID = UUID(); stored.refreshStartedAt = Date().addingTimeInterval(-70)
        try vault.save(stored)
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await store.restore()
        XCTAssertEqual(wire.requests.count, 0)
        XCTAssertEqual(store.state, .credentialsUnknown)
        XCTAssertEqual(try vault.load()?.refreshRequestID, stored.refreshRequestID)
    }

    func testAppleEnrollmentMapsNonceCodePasskeyAndAuthenticatorBeforeTrust() async throws {
        let wire = AccountTestTransport()
        let vault = MemoryAccountCredentials()
        let authorization = AccountTestAuthorization()
        authorization.succeed = true
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: authorization)
        try store.setCheckpoint(ageYears: 30, role: .adultSelf)
        wire.replies = [
            Data(#"{"flowToken":"flow","expiresAt":"2030-01-01T00:00:00Z","nonce":"exact-server-nonce"}"#.utf8),
            Data(#"{"flowToken":"flow","verified":true}"#.utf8)
        ]
        await store.startApple(purpose: .enroll)
        XCTAssertEqual(authorization.appleNonce, "exact-server-nonce")
        XCTAssertNil(store.accountID)
        let appleBody = try XCTUnwrap(JSONSerialization.jsonObject(with: wire.requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(appleBody["identityToken"], "actual-native-identity-token")
        XCTAssertEqual(appleBody["authorizationCode"], "actual-native-code")
        wire.replies = [
            Data(#"{"flowToken":"flow","options":{"challenge":"YWJj","rp":{"id":"spottr.omarchoudhry.co.uk","name":"Spottr"},"user":{"id":"dXNlci1oYW5kbGU","name":"Account","displayName":"Account"},"authenticatorSelection":{"userVerification":"required","residentKey":"required"}}}"#.utf8),
            Data(#"{"flowToken":"flow","secret":"LOCALSETUPSEED","uri":"otpauth://totp/Spottr"}"#.utf8)
        ]
        await store.enrollPasskey()
        XCTAssertEqual(authorization.registrationUserID, Data("user-handle".utf8))
        XCTAssertEqual(store.step, .authenticatorSetup)
        XCTAssertNil(store.accountID)
        XCTAssertNil(try vault.load())
        let trusted = try fixtureCredential().session
        wire.replies = [try AccountJSON.encoder().encode(trusted)]
        await store.complete(code: "123456")
        XCTAssertEqual(store.accountID, trusted.accountID)
        XCTAssertEqual(store.appAccountToken, trusted.accountID)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: wire.requests.last!.httpBody!) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["flowToken", "code", "deviceKey"])
        let key = try XCTUnwrap(body["deviceKey"] as? [String: String])
        XCTAssertEqual(Set(key.keys), ["kty", "crv", "x", "y"])
        XCTAssertNil(key["d"])
    }

    func testLateOfflineRestoreCannotUndoExplicitSignOut() async throws {
        let wire = AccountTestTransport()
        wire.holdFirst = true
        wire.failure = URLError(.notConnectedToInternet)
        let vault = MemoryAccountCredentials()
        try vault.save(fixtureCredential())
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        let restore = Task { await store.restore() }
        while wire.held == nil { await Task.yield() }
        await store.signOut()
        wire.held?.resume(); wire.held = nil
        await restore.value
        XCTAssertNil(store.accountID)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(try vault.load()?.locallySignedOut, true)
    }

    func testCoordinatorKeepsDelayedSavesWithSourceProfileAndGuardianGateCannotBeSkipped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = AccountTestTransport(); wire.failure = URLError(.notConnectedToInternet)
        let vault = MemoryAccountCredentials(); try vault.save(fixtureCredential())
        let authorization = AccountTestAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: authorization)
        await account.restore()
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        coordinator.accountChanged()
        await coordinator.createProfile(name: "Adult", age: try TrainingAgeContext(ageYears: 30, guardianManaged: false))
        let adult = try XCTUnwrap(coordinator.visibleWorkspace)
        await coordinator.createProfile(name: "Junior", age: try TrainingAgeContext(ageYears: 12, guardianManaged: true))
        XCTAssertEqual(coordinator.directory?.profiles.count, 1)
        authorization.succeed = true
        await coordinator.createProfile(name: "Junior", age: try TrainingAgeContext(ageYears: 12, guardianManaged: true))
        let junior = try XCTUnwrap(coordinator.visibleWorkspace)
        XCTAssertNotEqual(adult.scope.profileID, junior.scope.profileID)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
        adult.training.persist(record)
        try adult.profile.saveMeasurements(LocalBodyMeasurements(heightCM: 170, weightKG: 70))
        XCTAssertTrue(junior.training.history.isEmpty)
        XCTAssertNil(junior.profile.profile?.bodyMeasurements)
        XCTAssertFalse(junior.training.rewards.allowsTimePressureRewards)
        XCTAssertFalse(AccountPolicy.allowsHealth(profile: junior.profile.profile))
        XCTAssertEqual(try HistoryStore(url: adult.scope.file("history.json")).load(), [record])
        let reloaded = try AccountProfileDirectory(accountID: adult.scope.accountID, root: root)
        XCTAssertEqual(reloaded.selectedID, junior.scope.profileID)
        await coordinator.choose(adult.scope.profileID)
        let resumed = try XCTUnwrap(coordinator.visibleWorkspace)
        resumed.training.beginAuthorizedSession(); resumed.training.pause()
        let workoutID = resumed.training.session.id
        await coordinator.choose(junior.scope.profileID)
        XCTAssertEqual(coordinator.visibleWorkspace?.scope, adult.scope)
        XCTAssertEqual(coordinator.visibleWorkspace?.training.session.id, workoutID)
        await account.signOut(); coordinator.accountChanged()
        XCTAssertNil(coordinator.visibleWorkspace)
        XCTAssertEqual(coordinator.workspace?.training.session.id, workoutID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: adult.scope.file("pending-phone-workout.json").path))
        await coordinator.archivePausedWorkout()
        XCTAssertNil(coordinator.workspace)
        let pending = try JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: adult.scope.file("pending-phone-workout.json")))
        XCTAssertEqual(pending.record.id, workoutID)
        XCTAssertEqual(pending.accountID, adult.scope.accountID)
        XCTAssertEqual(try HistoryStore(url: adult.scope.file("history.json")).load(), [record])
    }

    func testLateRestoreCannotReplaceNewPendingIdentityFlow() async throws {
        let wire = AccountTestTransport(); wire.holdFirst = true
        let vault = MemoryAccountCredentials(); try vault.save(fixtureCredential())
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        let restore = Task { await account.restore() }
        while wire.held == nil { await Task.yield() }
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        wire.replies = [Data(#"{"flowToken":"new-flow","expiresAt":"2030-01-01T00:00:00Z","accepted":true}"#.utf8)]
        await account.startEmail(email: "owner@example.test", purpose: .enroll)
        XCTAssertEqual(account.state, .pendingMFA)
        wire.failure = URLError(.notConnectedToInternet)
        wire.held?.resume(); wire.held = nil
        await restore.value
        XCTAssertEqual(account.state, .pendingMFA)
        XCTAssertNil(account.accountID)
    }

    private func fixtureCredential() throws -> StoredAccountCredential {
        let account = UUID()
        return StoredAccountCredential(session: NativeAccountSession(authenticated: true, accountID: account, appAccountToken: account, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: Date().addingTimeInterval(900), refreshExpiresAt: Date().addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation)
    }
}

@MainActor final class AccountTestTransport: AccountTransport {
    var requests: [URLRequest] = []
    var replies: [Data] = []
    var failure: Error?
    var status = 200
    var holdFirst = false
    var held: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if holdFirst { holdFirst = false; await withCheckedContinuation { held = $0 } }
        await Task.yield()
        if let failure { throw failure }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        return (replies.removeFirst(), status)
    }
}
@MainActor final class MemoryAccountCredentials: AccountCredentialStorage {
    var value: StoredAccountCredential?
    func load() throws -> StoredAccountCredential? { value }
    func save(_ value: StoredAccountCredential) throws { self.value = value }
    func clear() throws { value = nil }
}
@MainActor final class AccountTestAuthorization: NativeAccountAuthorization {
    var succeed = false
    var appleNonce: String?
    var registrationUserID: Data?
    func apple(nonce: String) async throws -> AppleIdentityResult {
        guard succeed else { throw AccountFailure.cancelled }
        appleNonce = nonce
        return AppleIdentityResult(identityToken: "actual-native-identity-token", authorizationCode: "actual-native-code")
    }
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential {
        guard succeed else { throw AccountFailure.cancelled }
        registrationUserID = Data(base64URL: options.user.id)
        return RegistrationCredential(id: "aWQ", rawId: "aWQ", response: .init(clientDataJSON: "Y2xpZW50", attestationObject: "YXR0ZXN0"))
    }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential { throw AccountFailure.cancelled }
    func guardian() async throws { if !succeed { throw AccountFailure.cancelled } }
}
