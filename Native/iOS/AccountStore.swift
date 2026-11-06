import Foundation
import Observation
import CryptoKit

@MainActor @Observable final class NativeAccountStore {
    enum State: Equatable { case signedOut, pendingMFA, trustedOnline, trustedOffline, credentialsUnknown, revoked, error }
    enum Step: Equatable { case identity, emailCode, passkey, recoveryBackup, authenticatorSetup, secondFactor, complete }
    private(set) var state: State = .signedOut
    private(set) var step: Step = .identity
    private(set) var checkpoint: TrainingAgeContext?
    private(set) var accountID: UUID?
    private(set) var appAccountToken: UUID?
    private(set) var message: String?
    private(set) var authenticatorSecret: String?
    private(set) var authenticatorURI: String?
    private(set) var backupCodes: [String] = []
    private(set) var busy = false
    private var flowToken: String?
    private var flowExpiry: Date?
    private var purpose: IdentityPurpose = .enroll
    private var credential: StoredAccountCredential?
    private var refreshTask: Task<Void, Never>?
    private var epoch = UUID()
    var authenticationGeneration: UUID { epoch }
    private let client: AccountClient
    private let credentials: any AccountCredentialStorage
    let authorization: any NativeAccountAuthorization
    init(client: AccountClient, credentials: any AccountCredentialStorage, authorization: any NativeAccountAuthorization) {
        self.client = client; self.credentials = credentials; self.authorization = authorization
    }
    convenience init() { self.init(client: AccountClient(), credentials: SecureAccountCredentials(), authorization: AuthenticationServicesAccountAuthorization()) }
    var lastTrustedVerification: Date? { trusted ? credential?.lastTrustedVerification : nil }
    var trusted: Bool { accountID != nil && (state == .trustedOnline || state == .trustedOffline) }
    func setCheckpoint(ageYears: Int, role: AccountPolicy.Role) throws { checkpoint = try AccountPolicy.checkpoint(ageYears: ageYears, role: role) }
    func consumeInitialProfileCheckpoint() { checkpoint = nil }
    func startEmail(email: String, purpose: IdentityPurpose) async {
        await operation {
            if purpose == .enroll, self.checkpoint == nil { throw AccountFailure.checkpointRequired }
            let reply: IdentityStart = try await self.client.post("/identity/email/start", body: EmailStart(email: email, purpose: purpose), credential: purpose == .link ? try self.requireCredential() : nil)
            guard reply.accepted == true else { throw AccountFailure.invalidResponse }
            self.purpose = purpose; self.beginFlow(reply.flowToken, expires: reply.expiresAt); self.step = .emailCode
        }
    }
    func verifyEmail(code: String) async {
        await operation {
            let reply: FlowReply = try await self.client.post("/identity/email/verify", body: EmailVerify(flowToken: try self.requireFlow(), code: code))
            guard reply.verified == true else { throw AccountFailure.invalidResponse }
            self.flowToken = reply.flowToken; self.step = self.purpose == .recover ? .recoveryBackup : .passkey
            if self.purpose == .link { try await self.completeLink() }
        }
    }
    func startApple(purpose: IdentityPurpose) async {
        await operation {
            if purpose == .enroll, self.checkpoint == nil { throw AccountFailure.checkpointRequired }
            let reply: IdentityStart = try await self.client.post("/identity/apple/start", body: AppleStart(purpose: purpose), credential: purpose == .link ? try self.requireCredential() : nil)
            guard let nonce = reply.nonce else { throw AccountFailure.invalidResponse }
            self.purpose = purpose; self.beginFlow(reply.flowToken, expires: reply.expiresAt)
            let apple = try await self.authorization.apple(nonce: nonce)
            let verified: FlowReply = try await self.client.post("/identity/apple/verify", body: AppleVerify(flowToken: try self.requireFlow(), identityToken: apple.identityToken, authorizationCode: apple.authorizationCode))
            guard verified.verified == true else { throw AccountFailure.invalidResponse }
            self.flowToken = verified.flowToken; self.step = purpose == .recover ? .recoveryBackup : .passkey
            if purpose == .link { try await self.completeLink() }
        }
    }
    func enrollPasskey(recoveryBackup: String? = nil) async {
        await operation {
            let reply: RegistrationOptionsReply
            if self.purpose == .recover {
                guard let recoveryBackup, !recoveryBackup.isEmpty else { throw AccountFailure.reauthenticate }
                reply = try await self.client.post("/recovery/options", body: RecoveryOptionsRequest(flowToken: try self.requireFlow(), backupCode: recoveryBackup))
            } else { reply = try await self.client.post("/passkey/enroll/options", body: FlowRequest(flowToken: try self.requireFlow())) }
            self.flowToken = reply.flowToken
            let registration = try await self.authorization.register(options: reply.options)
            let seed: EnrollmentSecret = try await self.client.post("/passkey/enroll/verify", body: RegistrationVerify(flowToken: try self.requireFlow(), credential: registration))
            self.flowToken = seed.flowToken; self.authenticatorSecret = seed.secret; self.authenticatorURI = seed.uri; self.step = .authenticatorSetup
        }
    }
    func login() async {
        await operation {
            let reply: LoginOptionsReply = try await self.client.post("/passkey/login/options", body: EmptyRequest())
            self.beginFlow(reply.flowToken, expires: reply.expiresAt)
            let assertion = try await self.authorization.authenticate(options: reply.options)
            let verified: FlowReply = try await self.client.post("/passkey/login/verify", body: AssertionVerify(flowToken: try self.requireFlow(), credential: assertion))
            guard verified.needsSecondFactor == true else { throw AccountFailure.invalidResponse }
            self.flowToken = verified.flowToken; self.step = .secondFactor
        }
    }
    func complete(code: String, useBackup: Bool = false) async {
        await operation {
            let key = P256.Signing.PrivateKey()
            let reply: NativeAccountSession
            if self.step == .authenticatorSetup {
                guard !useBackup else { throw AccountFailure.invalidResponse }
                reply = try await self.client.post("/enroll/complete", body: EnrollmentComplete(flowToken: try self.requireFlow(), code: code, deviceKey: NativeDeviceProof.publicKey(key)))
            } else {
                guard self.step == .secondFactor else { throw AccountFailure.reauthenticate }
                reply = try await self.client.post("/mfa/complete", body: MFAComplete(flowToken: try self.requireFlow(), code: useBackup ? nil : code, backupCode: useBackup ? code : nil, deviceKey: NativeDeviceProof.publicKey(key)))
            }
            try reply.validate()
            self.backupCodes = reply.backupCodes ?? []
            var persisted = reply; persisted.backupCodes = nil
            let stored = StoredAccountCredential(session: persisted, privateKey: key.rawRepresentation, lastTrustedVerification: Date())
            try self.credentials.save(stored)
            self.epoch = UUID(); self.credential = stored; self.trust(stored, online: true); self.clearFlow(); self.step = .complete
        }
    }
    func restore() async {
        guard !busy else { return }
        let capturedEpoch = epoch
        do {
            guard let stored = try credentials.load(), !stored.locallySignedOut else { return }
            try stored.session.validate(); credential = stored
            guard stored.session.refreshExpiresAt > Date() else { state = .credentialsUnknown; return }
            if stored.refreshRequestID != nil || stored.session.accessExpiresAt <= Date() { await refresh(); return }
            let reply: CurrentSessionReply = try await client.post("/session/current", body: EmptyRequest(), credential: stored)
            guard epoch == capturedEpoch else { return }
            guard reply.authenticated, reply.accountID == stored.session.accountID, reply.appAccountToken == reply.accountID, reply.deviceID == stored.session.deviceID else { throw AccountFailure.invalidResponse }
            var verified = stored; verified.lastTrustedVerification = Date()
            try credentials.save(verified); credential = verified
            trust(verified, online: true)
        } catch { if epoch == capturedEpoch { handle(error, restoring: true) } }
    }
    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let capturedEpoch = epoch
        let task = Task { @MainActor in
            do {
                var stored = try self.requireCredential(allowExpiredAccess: true)
                if let started = stored.refreshStartedAt, Date().timeIntervalSince(started) >= 55 { throw AccountFailure.reauthenticate }
                if stored.refreshRequestID == nil { stored.refreshRequestID = UUID(); stored.refreshStartedAt = Date(); try self.credentials.save(stored); self.credential = stored }
                let reply: NativeAccountSession = try await self.client.post("/session/refresh", body: RefreshRequest(requestID: stored.refreshRequestID!), credential: stored, refresh: true)
                guard self.epoch == capturedEpoch else { return }
                try reply.validate()
                guard reply.accountID == stored.session.accountID, reply.deviceID == stored.session.deviceID else { throw AccountFailure.invalidResponse }
                stored.session = reply; stored.refreshRequestID = nil; stored.refreshStartedAt = nil; stored.lastTrustedVerification = Date()
                try self.credentials.save(stored); self.credential = stored; self.trust(stored, online: true)
            } catch { if self.epoch == capturedEpoch { self.handle(error, restoring: true) } }
        }
        refreshTask = task; await task.value; refreshTask = nil
    }
    func signOut() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        epoch = UUID()
        do {
            if let stored = credential {
                var signedOut = stored; signedOut.locallySignedOut = true
                try credentials.save(signedOut)
                credential = signedOut
                accountID = nil; appAccountToken = nil; state = .signedOut; backupCodes = []; clearFlow()
                do {
                    let reply: SignedOutReply = try await client.post("/session/sign-out", body: EmptyRequest(), credential: stored)
                    guard reply.signedOut else { throw AccountFailure.invalidResponse }
                    try credentials.clear(); credential = nil
                } catch { message = "Signed out on this phone. Remote sign-out could not be confirmed. Your local records are preserved." }
            } else { state = .signedOut; accountID = nil; appAccountToken = nil; clearFlow() }
        } catch { handle(error) }
    }
    func deleteAccount() async {
        await operation {
            let reply: DeletedReply = try await self.client.post("/account/delete", body: DeleteRequest(), credential: try self.requireCredential())
            guard reply.deleted, reply.phoneHistoryUnchanged else { throw AccountFailure.invalidResponse }
            self.epoch = UUID(); try self.credentials.clear(); self.credential = nil; self.accountID = nil; self.appAccountToken = nil; self.state = .revoked; self.backupCodes = []; self.clearFlow()
        }
    }
    func revoke(deviceID: UUID) async {
        await operation {
            let stored = try self.requireCredential()
            let reply: SignedOutReply = try await self.client.post("/session/revoke", body: RevocationRequest(deviceID: deviceID), credential: stored)
            guard reply.signedOut else { throw AccountFailure.invalidResponse }
            if deviceID == stored.session.deviceID { self.epoch = UUID(); try self.credentials.clear(); self.credential = nil; self.accountID = nil; self.appAccountToken = nil; self.state = .revoked }
        }
    }
    func dismissBackupCodes() { backupCodes = [] }
    func cancelSetup() { guard !busy else { return }; clearFlow(); step = .identity; state = credential != nil && accountID != nil ? .trustedOffline : .signedOut }
    private func completeLink() async throws {
        let reply: LinkedReply = try await client.post("/identity/link/complete", body: FlowRequest(flowToken: try requireFlow()), credential: try requireCredential())
        guard reply.linked else { throw AccountFailure.invalidResponse }; clearFlow(); step = .complete; state = .trustedOnline
    }
    private func operation(_ action: () async throws -> Void) async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do { try await action() } catch { handle(error) }
    }
    private func beginFlow(_ token: String, expires: Date) { epoch = UUID(); flowToken = token; flowExpiry = expires; state = .pendingMFA }
    private func requireFlow() throws -> String { guard let flowToken, let flowExpiry, flowExpiry > Date() else { throw AccountFailure.reauthenticate }; return flowToken }
    private func requireCredential(allowExpiredAccess: Bool = false) throws -> StoredAccountCredential {
        guard let credential, !credential.locallySignedOut, credential.session.refreshExpiresAt > Date(), allowExpiredAccess || credential.session.accessExpiresAt > Date() else { throw AccountFailure.reauthenticate }
        return credential
    }
    private func clearFlow() { flowToken = nil; flowExpiry = nil; authenticatorSecret = nil; authenticatorURI = nil }
    private func trust(_ stored: StoredAccountCredential, online: Bool) { accountID = stored.session.accountID; appAccountToken = stored.session.appAccountToken; state = online ? .trustedOnline : .trustedOffline; message = nil }
    private func invalidateWatchVerification() {
        guard var stored = credential else { return }
        stored.lastTrustedVerification = nil
        credential = stored
        do { try credentials.save(stored) }
        catch { message = "Secure account storage could not be updated. Reconnect and verify this account before using Watch workouts." }
    }
    private func handle(_ error: Error, restoring: Bool = false) {
        message = (error as? AccountFailure)?.errorDescription ?? "The request could not be completed. Your saved data is unchanged. Retry when connected."
        if case AccountFailure.service(401, _) = error { invalidateWatchVerification(); state = .credentialsUnknown; accountID = nil; appAccountToken = nil; return }
        if case AccountFailure.reauthenticate = error, restoring { invalidateWatchVerification(); state = .credentialsUnknown; accountID = nil; appAccountToken = nil; return }
        if restoring, let credential, !credential.locallySignedOut, credential.session.refreshExpiresAt > Date(), error is URLError { trust(credential, online: false); return }
        if restoring, case AccountFailure.service(503, _) = error, let credential { trust(credential, online: false); return }
        if state != .pendingMFA && !trusted { state = .error }
    }
}

@MainActor extension NativeAccountStore: ProgrammeCloudClient {
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply {
        let captured = epoch
        let reply: ProgrammeWriteReply = try await client.post("/plans/write", body: request, credential: requireCredential())
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply {
        let captured = epoch
        let reply: ProgrammeReadReply = try await client.post("/plans/read", body: request, credential: requireCredential())
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply {
        let captured = epoch
        let reply: ProgrammeWithdrawReply = try await client.post("/plans/withdraw", body: request, credential: requireCredential())
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
}
