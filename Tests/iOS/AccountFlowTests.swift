import XCTest
import CryptoKit
import AuthenticationServices
@testable import Spottr

@MainActor final class AccountFlowTests: XCTestCase {
    func testDelayedCurrentSuccessPreservesPendingRefreshReservation() async throws {
        try await delayedCurrentCannotReplaceRefresh(pending: true, status: 200)
    }
    func testDelayedCurrentFailurePreservesPendingRefreshReservation() async throws {
        try await delayedCurrentCannotReplaceRefresh(pending: true, status: 401)
    }
    func testDelayedCurrentSuccessPreservesCompletedRotation() async throws {
        try await delayedCurrentCannotReplaceRefresh(pending: false, status: 200)
    }
    func testDelayedCurrentFailureCannotRevokeCompletedRotation() async throws {
        try await delayedCurrentCannotReplaceRefresh(pending: false, status: 401)
    }
    private func delayedCurrentCannotReplaceRefresh(pending: Bool, status: Int) async throws {
        var original = try fixtureCredential(); original.lastTrustedVerification = Date().addingTimeInterval(-3600)
        let prior = original.session
        let successor = NativeAccountSession(authenticated: true, accountID: prior.accountID, appAccountToken: prior.appAccountToken, deviceID: prior.deviceID,
            accessToken: "rotated-access", refreshToken: "rotated-refresh", accessExpiresAt: Date().addingTimeInterval(900), refreshExpiresAt: prior.refreshExpiresAt)
        let vault = MemoryAccountCredentials(); try vault.save(original)
        let wire = RestoreRotationTransport(successor: successor, holdRefresh: pending)
        defer { wire.cancelHeldResponses() }
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        let restoring = Task { await account.restore() }
        let currentDeadline = Date().addingTimeInterval(5)
        while wire.current == nil && Date() < currentDeadline { try await Task.sleep(for: .milliseconds(1)) }
        let current = try XCTUnwrap(wire.current)
        XCTAssertEqual(account.state, .trustedOffline); XCTAssertEqual(account.lastTrustedVerification, original.lastTrustedVerification)
        let refreshing = Task { await account.refresh() }
        if pending {
            let refreshDeadline = Date().addingTimeInterval(5)
            while wire.refresh == nil && Date() < refreshDeadline { try await Task.sleep(for: .milliseconds(1)) }
            let reserved = try XCTUnwrap(vault.load()), requestID = try XCTUnwrap(reserved.refreshRequestID)
            XCTAssertNotNil(wire.refresh)
            current.resume(returning: (try AccountJSON.encoder().encode(prior), status)); wire.current = nil
            await restoring.value
            XCTAssertEqual(try vault.load()?.refreshRequestID, requestID, "A delayed current-session result must preserve the durable retry identity")
            XCTAssertEqual(try vault.load()?.refreshStartedAt, reserved.refreshStartedAt)
            XCTAssertEqual(try vault.load()?.lastTrustedVerification, reserved.lastTrustedVerification)
            XCTAssertNotEqual(try vault.load()?.requiresReauthentication, true, "A stale failure cannot retire the in-flight successor")
            wire.refresh?.resume(returning: (try AccountJSON.encoder().encode(successor), 200)); wire.refresh = nil
            await refreshing.value
        } else {
            await refreshing.value
            let verified = try vault.load()?.lastTrustedVerification
            current.resume(returning: (try AccountJSON.encoder().encode(prior), status)); wire.current = nil
            await restoring.value
            XCTAssertEqual(try vault.load()?.lastTrustedVerification, verified, "Stale success or failure must not alter successor freshness")
        }
        XCTAssertEqual(try vault.load()?.session.accessToken, successor.accessToken)
        XCTAssertEqual(try vault.load()?.session.refreshToken, successor.refreshToken)
        XCTAssertNil(try vault.load()?.refreshRequestID); XCTAssertNotEqual(try vault.load()?.requiresReauthentication, true)
        XCTAssertTrue(account.trusted)
        await account.revoke(deviceID: UUID())
        XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/session/refresh") == true }.count, 1)
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer " + successor.accessToken, "The next signed action must use the durably rotated credential without MFA")
        XCTAssertTrue(account.trusted)
    }
    func testRetainedTrustedAccountOpensWorkspaceWhileActualVerificationIsHeld() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var stored = try fixtureCredential()
        let cachedVerification = Date().addingTimeInterval(-3600); stored.lastTrustedVerification = cachedVerification
        let directory = try AccountProfileDirectory(accountID: stored.session.accountID, root: root)
        let person = try directory.add(age: .init(ageYears: 30, guardianManaged: false), name: "Retained profile")
        let vault = MemoryAccountCredentials(); try vault.save(stored)
        let wire = AccountTestTransport(); wire.holdFirst = true
        wire.replies = [Data(#"{"challenge":"challenge","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8), try AccountJSON.encoder().encode(stored.session)]
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        let start = ProcessInfo.processInfo.systemUptime
        let restore = Task { await account.restore() }
        while wire.held == nil { await Task.yield() }
        coordinator.accountChanged()
        print("TASK10_RESTORE_HELD_CACHED_STATE_\(account.state)_WORKSPACE_\(coordinator.visibleWorkspace != nil)_ELAPSED_\(ProcessInfo.processInfo.systemUptime - start)")
        XCTAssertEqual(account.state, .trustedOffline)
        XCTAssertEqual(coordinator.visibleWorkspace?.scope.profileID, person.id)
        XCTAssertEqual(account.lastTrustedVerification, cachedVerification, "Cached restoration must not mint Watch freshness")
        wire.held?.resume(); wire.held = nil
        await restore.value
        coordinator.accountChanged()
        XCTAssertEqual(account.state, .trustedOnline)
        XCTAssertGreaterThan(try XCTUnwrap(account.lastTrustedVerification), cachedVerification)
        coordinator.visibleWorkspace?.suspend()
    }
    func testKnown401CannotRestoreCachedTrustAfterReopenOffline() async throws {
        let vault = MemoryAccountCredentials(); try vault.save(fixtureCredential())
        let wire = AccountTestTransport(); wire.failure = AccountFailure.service(401, "Revoked")
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore(); XCTAssertFalse(account.trusted)
        wire.failure = URLError(.notConnectedToInternet)
        let reopened = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await reopened.restore()
        XCTAssertFalse(reopened.trusted, "Known revoked credentials cannot become trusted again merely by going offline")
    }
    func testWrongPartialEmailCodeDoesNotInvalidateRetainedDeviceSessionOrVerification() async throws {
        var stored = try fixtureCredential(); stored.lastTrustedVerification = Date().addingTimeInterval(-3600)
        let vault = MemoryAccountCredentials(); try vault.save(stored)
        let wire = AccountTestTransport(); wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        wire.failure = nil
        wire.replies = [Data(#"{"challenge":"challenge","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8), Data(#"{"flowToken":"partial-link","expiresAt":"2030-01-01T00:00:00Z","accepted":true}"#.utf8)]
        await account.startEmail(email: "owner@example.test", purpose: .link)
        wire.status = 401; wire.replies = [Data(#"{"error":"verification_failed"}"#.utf8)]
        await account.verifyEmail(code: "000000")
        XCTAssertEqual(try vault.load()?.lastTrustedVerification, stored.lastTrustedVerification, "A wrong partial-flow code is not a device-session revocation")
        wire.status = 200; wire.failure = URLError(.notConnectedToInternet)
        let reopened = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await reopened.restore(); XCTAssertTrue(reopened.trusted)
    }
    func testCancelledNewIdentityFlowReturnsToRetainedAccountWithoutMintingFreshness() async throws {
        var stored = try fixtureCredential(); stored.lastTrustedVerification = Date().addingTimeInterval(-3600)
        let vault = MemoryAccountCredentials(); try vault.save(stored)
        let wire = AccountTestTransport(); wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        wire.failure = nil; wire.replies = [Data(#"{"flowToken":"partial-enroll","expiresAt":"2030-01-01T00:00:00Z","accepted":true}"#.utf8)]
        await account.startEmail(email: "owner@example.test", purpose: .enroll)
        XCTAssertEqual(account.state, .pendingMFA); XCTAssertNil(account.accountID)
        account.cancelSetup()
        XCTAssertTrue(account.trusted); XCTAssertEqual(account.accountID, stored.session.accountID)
        XCTAssertEqual(account.lastTrustedVerification, stored.lastTrustedVerification)
    }
    func testSafeExpiredAccessShowsCachedAccountDuringRefreshButExpiredAmbiguityDoesNot() async throws {
        let original = try fixtureCredential(), prior = original.session
        let expired = NativeAccountSession(authenticated: true, accountID: prior.accountID, appAccountToken: prior.accountID, deviceID: prior.deviceID, accessToken: "expired", refreshToken: prior.refreshToken, accessExpiresAt: Date().addingTimeInterval(-60), refreshExpiresAt: prior.refreshExpiresAt)
        let vault = MemoryAccountCredentials(); try vault.save(.init(session: expired, privateKey: original.privateKey))
        let wire = AccountTestTransport(); wire.holdFirst = true; wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        let restore = Task { await account.restore() }
        while wire.held == nil { await Task.yield() }
        XCTAssertEqual(account.state, .trustedOffline)
        XCTAssertNil(account.lastTrustedVerification)
        wire.held?.resume(); wire.held = nil; await restore.value
        var ambiguous = try XCTUnwrap(vault.load()); ambiguous.refreshStartedAt = Date().addingTimeInterval(-70)
        try vault.save(ambiguous)
        let previousRequests = wire.requests.count
        let reopened = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await reopened.restore()
        XCTAssertFalse(reopened.trusted); XCTAssertEqual(wire.requests.count, previousRequests)
    }
    func testCorruptRetainedSigningKeyNeverRestoresOfflineTrust() async throws {
        let stored = try fixtureCredential(), vault = MemoryAccountCredentials()
        try vault.save(.init(session: stored.session, privateKey: Data([1, 2, 3])))
        let wire = AccountTestTransport(); wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        XCTAssertFalse(account.trusted)
    }
    func testKnownInvalidCredentialIsClearedIfPersistingItsDenialFails() async throws {
        let vault = RevocationSaveFailureVault(value: try fixtureCredential())
        let wire = AccountTestTransport(); wire.failure = AccountFailure.service(401, "Revoked")
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        XCTAssertFalse(account.trusted)
        XCTAssertNil(vault.value, "Only the known-invalid credential should be cleared when its denial cannot be saved")
        wire.failure = URLError(.notConnectedToInternet)
        let reopened = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await reopened.restore(); XCTAssertFalse(reopened.trusted)
    }
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

    func testOnlyGenuineOnlineAccountVerificationDurablyRenewsWatchFreshness() async throws {
        let vault = MemoryAccountCredentials(), wire = AccountTestTransport()
        let original = try fixtureCredential()
        try vault.save(original)
        wire.failure = URLError(.notConnectedToInternet)
        func makeStore() -> NativeAccountStore { NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization()) }
        let offline = makeStore(); await offline.restore()
        XCTAssertTrue(offline.trusted); XCTAssertNil(offline.lastTrustedVerification)
        wire.failure = nil
        let before = Date()
        wire.replies = [Data("{\"challenge\":\"challenge\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}".utf8), try AccountJSON.encoder().encode(original.session)]
        await offline.refresh()
        let verified = try XCTUnwrap(offline.lastTrustedVerification)
        XCTAssertGreaterThanOrEqual(verified, before)
        XCTAssertEqual(try vault.load()?.lastTrustedVerification, verified)
        wire.failure = URLError(.notConnectedToInternet)
        let reopened = makeStore(); await reopened.restore(); await reopened.restore()
        XCTAssertEqual(reopened.lastTrustedVerification, verified)
        XCTAssertEqual(try vault.load()?.lastTrustedVerification, verified)
        let legacy = try AccountJSON.decoder().decode(StoredAccountCredential.self, from: AccountJSON.encoder().encode(original))
        XCTAssertNil(legacy.lastTrustedVerification)
    }

    func testKnownInvalidSessionCannotResurrectWatchVerificationOnLaterOfflineRestore() async throws {
        let vault = MemoryAccountCredentials(), wire = AccountTestTransport()
        var original = try fixtureCredential(); original.lastTrustedVerification = Date()
        try vault.save(original)
        wire.failure = AccountFailure.service(401, "Session invalid")
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await store.restore()
        XCTAssertNil(store.lastTrustedVerification)
        wire.failure = URLError(.notConnectedToInternet)
        let reopened = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await reopened.restore()
        XCTAssertNil(reopened.lastTrustedVerification)
        XCTAssertNil(try vault.load()?.lastTrustedVerification)
    }

    func testWatchReconnectVerifiesOnlineOnceWithoutReplacingWorkspaceOrMintingCachedFreshness() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = AccountTestTransport(), vault = MemoryAccountCredentials(), stored = try fixtureCredential()
        try vault.save(stored); wire.failure = URLError(.notConnectedToInternet)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await account.restore()
        let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
        coordinator.accountChanged()
        await coordinator.createProfile(name: "Watch reconnect", age: try TrainingAgeContext(ageYears: 30, guardianManaged: false))
        let workspace = try XCTUnwrap(coordinator.visibleWorkspace)
        try workspace.watchSharing.setEnabled(true)
        let before = wire.requests.count
        wire.failure = nil; wire.replies = [Data("{\"challenge\":\"challenge\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}".utf8), try AccountJSON.encoder().encode(stored.session)]
        workspace.training.companion.onRequest?(); workspace.training.companion.onRequest?(); workspace.training.companion.onRequest?()
        for _ in 0..<30 { try await Task.sleep(for: .milliseconds(20)); if account.lastTrustedVerification != nil { break } }
        XCTAssertEqual(wire.requests.count, before + 2)
        let verified = try XCTUnwrap(account.lastTrustedVerification)
        XCTAssertEqual(try vault.load()?.lastTrustedVerification, verified)
        coordinator.accountChanged()
        XCTAssertTrue(coordinator.visibleWorkspace === workspace)
        wire.failure = URLError(.notConnectedToInternet)
        workspace.training.companion.onRequest?()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(wire.requests.count, before + 2)
        XCTAssertEqual(account.lastTrustedVerification, verified)
        try workspace.watchSharing.setEnabled(false)
        workspace.training.companion.onRequest?()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(wire.requests.count, before + 2)
    }

    func testContinuouslyOpenAccountRefreshesBeforeSignedDeviceAction() async throws {
        let wire = AccountTestTransport(), vault = MemoryAccountCredentials()
        let original = try fixtureCredential(), session = original.session
        let expiring = NativeAccountSession(authenticated: true, accountID: session.accountID, appAccountToken: session.appAccountToken, deviceID: session.deviceID, accessToken: "expiring", refreshToken: session.refreshToken, accessExpiresAt: Date().addingTimeInterval(0.2), refreshExpiresAt: session.refreshExpiresAt)
        try vault.save(.init(session: expiring, privateKey: original.privateKey))
        wire.failure = URLError(.notConnectedToInternet)
        let store = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: AccountTestAuthorization())
        await store.restore(); XCTAssertTrue(store.trusted)
        try await Task.sleep(for: .milliseconds(250))
        wire.failure = nil
        let challenge = Data("{\"challenge\":\"challenge\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}".utf8)
        wire.replies = [challenge, try AccountJSON.encoder().encode(session), challenge, Data("{\"signedOut\":true}".utf8)]
        await store.revoke(deviceID: UUID())
        XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/session/refresh") == true }.count, 1)
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer " + session.accessToken)
        XCTAssertNil(try vault.load()?.refreshRequestID)
        XCTAssertTrue(store.trusted)
    }

    private func fixtureCredential() throws -> StoredAccountCredential {
        let account = UUID()
        return StoredAccountCredential(session: NativeAccountSession(authenticated: true, accountID: account, appAccountToken: account, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: Date().addingTimeInterval(900), refreshExpiresAt: Date().addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation)
    }
}

@MainActor private final class RestoreRotationTransport: AccountTransport {
    let successor: NativeAccountSession
    let holdRefresh: Bool
    var requests: [URLRequest] = []
    var current: CheckedContinuation<(Data, Int), Error>?
    var refresh: CheckedContinuation<(Data, Int), Error>?
    init(successor: NativeAccountSession, holdRefresh: Bool) { self.successor = successor; self.holdRefresh = holdRefresh }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.lastPathComponent {
        case "challenge": return (Data(#"{"challenge":"challenge","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8), 200)
        case "current": return try await withCheckedThrowingContinuation { current = $0 }
        case "refresh":
            if holdRefresh { return try await withCheckedThrowingContinuation { refresh = $0 } }
            return (try AccountJSON.encoder().encode(successor), 200)
        case "revoke": return (Data(#"{"signedOut":true}"#.utf8), 200)
        default: throw URLError(.badServerResponse)
        }
    }
    func cancelHeldResponses() {
        current?.resume(throwing: CancellationError()); current = nil
        refresh?.resume(throwing: CancellationError()); refresh = nil
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

@MainActor private final class RevocationSaveFailureVault: AccountCredentialStorage {
    var value: StoredAccountCredential?
    init(value: StoredAccountCredential) { self.value = value }
    func load() throws -> StoredAccountCredential? { value }
    func save(_ value: StoredAccountCredential) throws { throw AccountFailure.keychain(-50) }
    func clear() throws { value = nil }
}

@MainActor final class AccountRetryTests: XCTestCase {
    func testCancelledEnrollmentReusesOutstandingChallenge() async throws {
        try await cancelledRegistration(purpose: .enroll)
    }
    func testCancelledRecoveryReusesIdentityAndBackupProof() async throws {
        try await cancelledRegistration(purpose: .recover)
    }
    private func cancelledRegistration(purpose: IdentityPurpose) async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization(), vault = MemoryAccountCredentials()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: auth)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: purpose); await account.verifyEmail(code: "123456")
        auth.cancelNextRegistration = true
        await account.enrollPasskey(recoveryBackup: purpose == .recover ? "unused-backup" : nil)
        XCTAssertFalse(account.trusted); XCTAssertNil(try vault.load())
        await account.enrollPasskey(recoveryBackup: purpose == .recover ? "" : nil)
        XCTAssertEqual(account.step, .authenticatorSetup)
        XCTAssertEqual(wire.optionsRequests, 1, "A cancelled system sheet must reuse the still-valid challenge")
        await account.complete(code: "654321")
        XCTAssertTrue(account.trusted); XCTAssertEqual(account.backupCodes, ["new-backup"])
        XCTAssertEqual(wire.rejectedTransitions, 0)
    }
    func testNewFlowCannotReuseCancelledChallenge() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        auth.cancelNextRegistration = true; await account.enrollPasskey()
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        XCTAssertEqual(account.step, .authenticatorSetup); XCTAssertEqual(wire.optionsRequests, 2)
        XCTAssertEqual(auth.challenges, ["Y2hhbGxlbmdlLTE", "Y2hhbGxlbmdlLTI"])
        XCTAssertEqual(wire.rejectedTransitions, 0)
    }
    func testAmbiguousVerificationCannotReplayAdvancedRegistration() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        wire.loseVerificationReply = true
        await account.enrollPasskey()
        XCTAssertTrue(account.message?.contains("Start again") == true)
        let requests = wire.requests.count
        await account.enrollPasskey()
        XCTAssertEqual(wire.requests.count, requests, "An uncertain advanced stage must require a fresh flow")
        XCTAssertNil(account.authenticatorSecret); XCTAssertFalse(account.trusted)
        account.cancelSetup()
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        await account.enrollPasskey()
        XCTAssertEqual(account.step, .authenticatorSetup); XCTAssertEqual(wire.rejectedTransitions, 0)
    }
    func testLostFinalCompletionOffersOrdinarySignInWithoutReplayingCommittedFlow() async throws {
        let wire = StagedAccountTransport(), vault = MemoryAccountCredentials(), auth = RetryAccountAuthorization()
        let retained = retryCredential(); try vault.save(retained)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: auth)
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        wire.loseCompletionReply = true
        await account.complete(code: "654321")
        XCTAssertEqual(wire.stage, .complete, "The server consumed the one-time completion before the response was lost")
        XCTAssertTrue(account.message?.contains("passkey and Authenticator") == true)
        XCTAssertNil(account.authenticatorSecret); XCTAssertFalse(account.trusted)
        let requests = wire.requests.count
        await account.complete(code: "654321")
        XCTAssertEqual(wire.requests.count, requests, "A committed flow cannot be replayed")
        XCTAssertEqual(try vault.load(), retained)
        account.cancelSetup(); await account.login()
        XCTAssertEqual(account.step, .secondFactor, "Ordinary passkey plus existing Authenticator sign-in remains reachable")
    }
    func testActualPlatformCancellationRetainsTheOutstandingChallenge() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        auth.registrationError = ASAuthorizationError(.canceled)
        await account.enrollPasskey(); auth.registrationError = nil
        await account.enrollPasskey()
        XCTAssertEqual(account.step, .authenticatorSetup); XCTAssertEqual(wire.optionsRequests, 1)
    }
    func testCancelledOrdinarySignInAfterRestartShowsItsOwnFeedback() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth)
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        wire.loseVerificationReply = true; await account.enrollPasskey()
        auth.cancelAuthentication = true; await account.login()
        XCTAssertTrue(account.message?.contains("cancelled") == true, "A new ordinary sign-in must replace earlier restart feedback")
        XCTAssertFalse(account.trusted)
    }
    func testExpiredCancelledChallengeIsNeverPresentedOrRequestedAgain() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization()
        var now = Date.now
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: MemoryAccountCredentials(), authorization: auth, now: { now })
        try account.setCheckpoint(ageYears: 30, role: .adultSelf)
        await account.startEmail(email: "owner@example.test", purpose: .enroll); await account.verifyEmail(code: "123456")
        auth.cancelNextRegistration = true; await account.enrollPasskey()
        let requests = wire.requests.count
        now = now.addingTimeInterval(301); await account.enrollPasskey()
        XCTAssertEqual(wire.requests.count, requests); XCTAssertEqual(auth.challenges.count, 1)
        XCTAssertEqual(account.step, .restart); XCTAssertNil(account.setupExpiresAt)
        XCTAssertTrue(account.message?.contains("expired") == true)
    }
    func testUnusableEnrollmentOptionsRequireFreshIdentity() async throws {
        try await unusableOptionsRequireRestart(purpose: .enroll)
    }
    func testUnusableRecoveryOptionsRequireFreshIdentity() async throws {
        try await unusableOptionsRequireRestart(purpose: .recover)
    }
    private func unusableOptionsRequireRestart(purpose: IdentityPurpose) async throws {
        for failure in StagedAccountTransport.OptionsFailure.allCases {
            let wire = StagedAccountTransport(), vault = MemoryAccountCredentials()
            let retained = retryCredential(); try vault.save(retained)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let saved = root.appendingPathComponent("saved-record.txt"), bytes = Data("retained local records".utf8)
            try bytes.write(to: saved)
            let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: RetryAccountAuthorization())
            let coordinator = AccountWorkspaceCoordinator(account: account, root: root)
            try account.setCheckpoint(ageYears: 30, role: .adultSelf)
            await account.startEmail(email: "owner@example.test", purpose: purpose); await account.verifyEmail(code: "123456")
            wire.optionsFailure = failure
            await account.enrollPasskey(recoveryBackup: purpose == .recover ? "unused-backup" : nil)
            XCTAssertEqual(wire.stage, .registration)
            XCTAssertEqual(account.step, .restart, "Unknown options commitment requires restart: \(failure)")
            XCTAssertTrue(account.message?.contains("Start again") == true)
            let requests = wire.requests.count
            await account.enrollPasskey(recoveryBackup: purpose == .recover ? "unused-backup" : nil)
            XCTAssertEqual(wire.requests.count, requests, "An advanced one-time options request must not be replayed")
            XCTAssertEqual(wire.optionsRequests, 1); XCTAssertNil(account.authenticatorSecret)
            XCTAssertEqual(try vault.load(), retained); XCTAssertEqual(try Data(contentsOf: saved), bytes)
            XCTAssertNil(coordinator.visibleWorkspace)
        }
    }
    func testExplicitRecoveryOptionsDenialAllowsCorrectedBackupProof() async throws {
        let wire = StagedAccountTransport(), vault = MemoryAccountCredentials()
        let retained = retryCredential(); try vault.save(retained)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: RetryAccountAuthorization())
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "")
        XCTAssertEqual(account.step, .recoveryBackup); XCTAssertEqual(wire.optionsRequests, 0)
        await account.enrollPasskey(recoveryBackup: "wrong-backup")
        XCTAssertEqual(account.step, .recoveryBackup); XCTAssertEqual(wire.stage, .identity)
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        XCTAssertEqual(account.step, .authenticatorSetup); XCTAssertEqual(wire.optionsRequests, 2)
        XCTAssertEqual(try vault.load(), retained)
    }
    func testIncorrectEnrollmentTOTPRemainsRetryableWithoutReplacingCredentials() async throws {
        let wire = StagedAccountTransport(), vault = MemoryAccountCredentials()
        let retained = retryCredential(); try vault.save(retained)
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: RetryAccountAuthorization())
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        await account.complete(code: "000000")
        XCTAssertEqual(account.step, .authenticatorSetup); XCTAssertEqual(wire.stage, .enrollment)
        XCTAssertNotNil(account.authenticatorSecret); XCTAssertEqual(try vault.load(), retained)
        await account.complete(code: "654321")
        XCTAssertTrue(account.trusted); XCTAssertEqual(wire.stage, .complete)
    }
    func testExpiredSetupClearsSecretAndPreservesRetainedCredential() async throws {
        let wire = StagedAccountTransport(), auth = RetryAccountAuthorization(), vault = MemoryAccountCredentials()
        let retained = retryCredential(); try vault.save(retained)
        var now = Date.now
        let account = NativeAccountStore(client: AccountClient(transport: wire), credentials: vault, authorization: auth, now: { now })
        wire.expiry = now.addingTimeInterval(300)
        await account.startEmail(email: "owner@example.test", purpose: .recover); await account.verifyEmail(code: "123456")
        await account.enrollPasskey(recoveryBackup: "unused-backup")
        XCTAssertNotNil(account.authenticatorSecret)
        now = now.addingTimeInterval(301)
        await account.complete(code: "654321")
        XCTAssertNil(account.authenticatorSecret); XCTAssertNil(account.authenticatorURI)
        XCTAssertTrue(account.message?.contains("expired") == true)
        XCTAssertEqual(try vault.load(), retained); XCTAssertNil(wire.completedBody)
        account.cancelSetup(); XCTAssertEqual(account.step, .identity)
    }
}

@MainActor final class StagedAccountTransport: AccountTransport {
    enum Stage { case email, identity, registration, enrollment, secondFactor, complete }
    enum OptionsFailure: CaseIterable { case malformedSuccess, invalidTransportResponse, serverFailure }
    var optionsFailure: OptionsFailure?
    var stage = Stage.email
    var expiry = Date.now.addingTimeInterval(300)
    var requests: [URLRequest] = []
    var optionsRequests = 0
    var rejectedTransitions = 0
    var loseVerificationReply = false
    var loseCompletionReply = false
    var completedBody: [String: String]?
    private var flow = 0
    private var token = ""
    private var purpose = "enroll"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let body = (try JSONSerialization.jsonObject(with: request.httpBody ?? Data("{}".utf8))) as? [String: Any] ?? [:]
        let path = request.url?.path.replacingOccurrences(of: "/api/native/v1", with: "") ?? ""
        if path == "/identity/email/start" {
            flow += 1; stage = .email; token = "email-\(flow)"; purpose = body["purpose"] as? String ?? "enroll"
            return try reply(["flowToken": token, "expiresAt": expiryString, "accepted": true])
        }
        if path == "/passkey/login/options" {
            flow += 1; token = "login-\(flow)"; stage = .identity
            return try reply(["flowToken": token, "expiresAt": expiryString, "options": ["challenge": "YWJj", "rpId": "spottr.omarchoudhry.co.uk", "userVerification": "required"]])
        }
        guard body["flowToken"] as? String == token, expiry > .now else { return reject() }
        switch path {
        case "/identity/email/verify":
            guard stage == .email else { return reject() }; stage = .identity; token = "identity-\(flow)"
            return try reply(["flowToken": token, "verified": true])
        case "/passkey/login/verify":
            guard stage == .identity else { return reject() }; stage = .secondFactor
            return try reply(["flowToken": token, "needsSecondFactor": true])
        case "/passkey/enroll/options", "/recovery/options":
            optionsRequests += 1
            guard stage == .identity, purpose != "recover" || body["backupCode"] as? String == "unused-backup" else { return reject() }
            stage = .registration; token = "registration-\(flow)"
            if let failure = optionsFailure {
                optionsFailure = nil
                switch failure {
                case .malformedSuccess: return (Data("{truncated".utf8), 200)
                case .invalidTransportResponse: throw AccountFailure.invalidResponse
                case .serverFailure: return (Data(#"{"error":"proxy_unavailable"}"#.utf8), 502)
                }
            }
            return try reply(["flowToken": token, "options": ["challenge": Data("challenge-\(flow)".utf8).base64URL, "rp": ["id": "spottr.omarchoudhry.co.uk", "name": "Spottr"], "user": ["id": "dXNlci1oYW5kbGU", "name": "Account", "displayName": "Account"], "authenticatorSelection": ["userVerification": "required", "residentKey": "required"]]])
        case "/passkey/enroll/verify":
            guard stage == .registration else { return reject() }; stage = .enrollment; token = "enrollment-\(flow)"
            if loseVerificationReply { loseVerificationReply = false; throw URLError(.networkConnectionLost) }
            return try reply(["flowToken": token, "secret": "TEMPORARYSETUPKEY", "uri": "otpauth://totp/Spottr?secret=TEMPORARYSETUPKEY"])
        case "/enroll/complete":
            guard stage == .enrollment, body["code"] as? String == "654321", body["backupCode"] == nil else { return reject() }
            completedBody = body.compactMapValues { $0 as? String }; stage = .complete
            if loseCompletionReply { loseCompletionReply = false; throw URLError(.networkConnectionLost) }
            var session = retryCredential().session; session.backupCodes = ["new-backup"]
            return (try AccountJSON.encoder().encode(session), 200)
        default: return reject()
        }
    }
    private var expiryString: String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: expiry)
    }
    private func reply(_ object: [String: Any]) throws -> (Data, Int) { (try JSONSerialization.data(withJSONObject: object), 200) }
    private func reject() -> (Data, Int) { rejectedTransitions += 1; return (Data(#"{"error":"invalid_stage"}"#.utf8), 401) }
}
@MainActor final class RetryAccountAuthorization: NativeAccountAuthorization {
    var cancelNextRegistration = false
    var registrationError: Error?
    var cancelAuthentication = false
    var guardianAllowed = true
    var challenges: [String] = []
    func register(options: PasskeyCreationOptions) async throws -> RegistrationCredential {
        challenges.append(options.challenge)
        if let registrationError { throw registrationError }
        if cancelNextRegistration { cancelNextRegistration = false; throw AccountFailure.cancelled }
        return RegistrationCredential(id: "aWQ", rawId: "aWQ", response: .init(clientDataJSON: "Y2xpZW50", attestationObject: "YXR0ZXN0"))
    }
    func authenticate(options: PasskeyRequestOptions) async throws -> AssertionCredential {
        if cancelAuthentication { throw AccountFailure.cancelled }
        return AssertionCredential(id: "aWQ", rawId: "aWQ", response: .init(clientDataJSON: "Y2xpZW50", authenticatorData: "YXV0aA", signature: "c2ln", userHandle: "dXNlcg"))
    }
    func apple(nonce: String) async throws -> AppleIdentityResult { throw AccountFailure.cancelled }
    func guardian() async throws { if !guardianAllowed { throw AccountFailure.cancelled } }
}
@MainActor func retryCredential() -> StoredAccountCredential {
    let id = UUID()
    return .init(session: .init(authenticated: true, accountID: id, appAccountToken: id, deviceID: UUID(), accessToken: "access", refreshToken: "refresh", accessExpiresAt: .now.addingTimeInterval(900), refreshExpiresAt: .now.addingTimeInterval(86400)), privateKey: P256.Signing.PrivateKey().rawRepresentation)
}
