import Foundation
import Observation
import CryptoKit
import AuthenticationServices

@MainActor @Observable final class NativeAccountStore {
    enum State: Equatable { case signedOut, pendingMFA, trustedOnline, trustedOffline, credentialsUnknown, revoked, error }
    enum Step: Equatable { case identity, emailCode, passkey, recoveryBackup, authenticatorSetup, secondFactor, complete, restart }
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
    private(set) var setupExpiresAt: Date?
    private struct OutstandingRegistration {
        let token: String
        let expiry: Date
        let purpose: IdentityPurpose
        let options: PasskeyCreationOptions
    }
    private var outstandingRegistration: OutstandingRegistration?
    private enum SetupFailure: Error { case expired, restart, completionUnconfirmed }
    private let now: @MainActor () -> Date
    private var purpose: IdentityPurpose = .enroll
    private var credential: StoredAccountCredential?
    private var refreshTask: Task<Void, Never>?
    private var epoch = UUID()
    var authenticationGeneration: UUID { epoch }
    private let client: AccountClient
    private let credentials: any AccountCredentialStorage
    let authorization: any NativeAccountAuthorization
    init(client: AccountClient, credentials: any AccountCredentialStorage, authorization: any NativeAccountAuthorization, now: @escaping @MainActor () -> Date = { .now }) {
        self.client = client; self.credentials = credentials; self.authorization = authorization; self.now = now
    }
    convenience init() { self.init(client: AccountClient(), credentials: SecureAccountCredentials(), authorization: AuthenticationServicesAccountAuthorization()) }
    var lastTrustedVerification: Date? { trusted ? credential?.lastTrustedVerification : nil }
    var trusted: Bool { accountID != nil && (state == .trustedOnline || state == .trustedOffline) }
    func setCheckpoint(ageYears: Int, role: AccountPolicy.Role) throws { checkpoint = try AccountPolicy.checkpoint(ageYears: ageYears, role: role) }
    func consumeInitialProfileCheckpoint() { checkpoint = nil }
    func startEmail(email: String, purpose: IdentityPurpose) async {
        await operation {
            if purpose == .enroll, self.checkpoint == nil { throw AccountFailure.checkpointRequired }
            let reply: IdentityStart
            if purpose == .link { reply = try await self.signedPost("/identity/email/start", body: EmailStart(email: email, purpose: purpose)) }
            else { reply = try await self.client.post("/identity/email/start", body: EmailStart(email: email, purpose: purpose)) }
            guard reply.accepted == true else { throw AccountFailure.invalidResponse }
            self.purpose = purpose; self.beginFlow(reply.flowToken, expires: reply.expiresAt); self.step = .emailCode
        }
    }
    func verifyEmail(code: String) async {
        await operation {
            let reply: FlowReply = try await self.client.post("/identity/email/verify", body: EmailVerify(flowToken: try self.requireFlow(), code: code))
            _ = try self.requireFlow()
            guard reply.verified == true else { throw AccountFailure.invalidResponse }
            self.flowToken = reply.flowToken; self.step = self.purpose == .recover ? .recoveryBackup : .passkey
            if self.purpose == .link { try await self.completeLink() }
        }
    }
    func startApple(purpose: IdentityPurpose) async {
        await operation {
            if purpose == .enroll, self.checkpoint == nil { throw AccountFailure.checkpointRequired }
            let reply: IdentityStart
            if purpose == .link { reply = try await self.signedPost("/identity/apple/start", body: AppleStart(purpose: purpose)) }
            else { reply = try await self.client.post("/identity/apple/start", body: AppleStart(purpose: purpose)) }
            guard let nonce = reply.nonce else { throw AccountFailure.invalidResponse }
            self.purpose = purpose; self.beginFlow(reply.flowToken, expires: reply.expiresAt)
            let apple = try await self.authorization.apple(nonce: nonce)
            let verified: FlowReply = try await self.client.post("/identity/apple/verify", body: AppleVerify(flowToken: try self.requireFlow(), identityToken: apple.identityToken, authorizationCode: apple.authorizationCode))
            _ = try self.requireFlow()
            guard verified.verified == true else { throw AccountFailure.invalidResponse }
            self.flowToken = verified.flowToken; self.step = purpose == .recover ? .recoveryBackup : .passkey
            if purpose == .link { try await self.completeLink() }
        }
    }
    func enrollPasskey(recoveryBackup: String? = nil) async {
        guard step == .passkey || step == .recoveryBackup else { return }
        await operation {
            let token = try self.requireFlow()
            let options: PasskeyCreationOptions
            if let pending = self.outstandingRegistration, pending.token == token,
               pending.expiry == self.setupExpiresAt, pending.purpose == self.purpose {
                options = pending.options
            } else {
                let recoveryProof: String?
                if self.purpose == .recover {
                    guard let recoveryBackup, !recoveryBackup.isEmpty else { throw AccountFailure.reauthenticate }
                    recoveryProof = recoveryBackup
                } else { recoveryProof = nil }
                let reply: RegistrationOptionsReply
                do {
                    if let recoveryProof {
                        reply = try await self.client.post("/recovery/options", body: RecoveryOptionsRequest(flowToken: token, backupCode: recoveryProof))
                    } else { reply = try await self.client.post("/passkey/enroll/options", body: FlowRequest(flowToken: token)) }
                } catch {
                    if case AccountFailure.service(let status, _) = error, (400..<500).contains(status) { throw error }
                    throw SetupFailure.restart
                }
                _ = try self.requireFlow()
                guard let expiry = self.setupExpiresAt else { throw SetupFailure.expired }
                self.flowToken = reply.flowToken
                self.outstandingRegistration = OutstandingRegistration(token: reply.flowToken, expiry: expiry, purpose: self.purpose, options: reply.options)
                options = reply.options
            }
            let registration: RegistrationCredential
            do { registration = try await self.authorization.register(options: options) }
            catch {
                if case AccountFailure.cancelled = error { throw error }
                if (error as? ASAuthorizationError)?.code == .canceled { throw AccountFailure.cancelled }
                throw SetupFailure.restart
            }
            let registrationToken = try self.requireFlow()
            self.outstandingRegistration = nil
            let seed: EnrollmentSecret
            do { seed = try await self.client.post("/passkey/enroll/verify", body: RegistrationVerify(flowToken: registrationToken, credential: registration)) }
            catch { throw SetupFailure.restart }
            _ = try self.requireFlow()
            self.flowToken = seed.flowToken; self.authenticatorSecret = seed.secret; self.authenticatorURI = seed.uri; self.step = .authenticatorSetup
        }
    }
    func login() async {
        await operation {
            let reply: LoginOptionsReply = try await self.client.post("/passkey/login/options", body: EmptyRequest())
            self.beginFlow(reply.flowToken, expires: reply.expiresAt)
            let assertion = try await self.authorization.authenticate(options: reply.options)
            let verified: FlowReply = try await self.client.post("/passkey/login/verify", body: AssertionVerify(flowToken: try self.requireFlow(), credential: assertion))
            _ = try self.requireFlow()
            guard verified.needsSecondFactor == true else { throw AccountFailure.invalidResponse }
            self.flowToken = verified.flowToken; self.step = .secondFactor
        }
    }
    func complete(code: String, useBackup: Bool = false) async {
        guard step == .authenticatorSetup || step == .secondFactor else { return }
        await operation {
            let key = P256.Signing.PrivateKey()
            let reply: NativeAccountSession
            if self.step == .authenticatorSetup {
                guard !useBackup else { throw AccountFailure.invalidResponse }
                let token = try self.requireFlow()
                do {
                    let enrolled: NativeAccountSession = try await self.client.post("/enroll/complete", body: EnrollmentComplete(flowToken: token, code: code, deviceKey: NativeDeviceProof.publicKey(key)))
                    try enrolled.validate(); reply = enrolled
                } catch {
                    if case AccountFailure.service(let status, _) = error, status < 500 { throw error }
                    throw SetupFailure.completionUnconfirmed
                }
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
        var capturedCredential: StoredAccountCredential?
        do {
            guard let stored = try credentials.load(), !stored.locallySignedOut else { return }
            if stored.requiresReauthentication == true || (credential?.requiresReauthentication == true && credential?.session.deviceID == stored.session.deviceID) {
                if stored.requiresReauthentication == true { credential = stored }
                accountID = nil; appAccountToken = nil; state = .credentialsUnknown; return
            }
            try stored.session.validate(); credential = stored; capturedCredential = stored
            guard (try? P256.Signing.PrivateKey(rawRepresentation: stored.privateKey)) != nil else { throw AccountFailure.reauthenticate }
            guard stored.session.refreshExpiresAt > Date() else { state = .credentialsUnknown; return }
            let needsRefresh = stored.refreshRequestID != nil || stored.session.accessExpiresAt <= Date()
            if needsRefresh, let started = stored.refreshStartedAt, Date().timeIntervalSince(started) >= 55 { await refresh(); return }
            trust(stored, online: false)
            if needsRefresh { await refresh(); return }
            let reply: CurrentSessionReply = try await client.post("/session/current", body: EmptyRequest(), credential: stored)
            guard epoch == capturedEpoch, credential == stored else { return }
            guard reply.authenticated, reply.accountID == stored.session.accountID, reply.appAccountToken == reply.accountID, reply.deviceID == stored.session.deviceID else { throw AccountFailure.invalidResponse }
            var verified = stored; verified.lastTrustedVerification = Date()
            try credentials.save(verified); credential = verified
            trust(verified, online: true)
        } catch {
            if epoch == capturedEpoch, capturedCredential == nil || credential == capturedCredential { handle(error, restoring: true) }
        }
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
            let reply: DeletedReply = try await self.signedPost("/account/delete", body: DeleteRequest())
            guard reply.deleted, reply.phoneHistoryUnchanged else { throw AccountFailure.invalidResponse }
            self.epoch = UUID(); try self.credentials.clear(); self.credential = nil; self.accountID = nil; self.appAccountToken = nil; self.state = .revoked; self.backupCodes = []; self.clearFlow()
        }
    }
    func revoke(deviceID: UUID) async {
        await operation {
            let stored = try await self.credentialForSignedAction()
            let reply: SignedOutReply = try await self.signedPost("/session/revoke", body: RevocationRequest(deviceID: deviceID))
            guard reply.signedOut else { throw AccountFailure.invalidResponse }
            if deviceID == stored.session.deviceID { self.epoch = UUID(); try self.credentials.clear(); self.credential = nil; self.accountID = nil; self.appAccountToken = nil; self.state = .revoked }
        }
    }
    func dismissBackupCodes() { backupCodes = [] }
    func cancelSetup() {
        guard !busy else { return }
        clearFlow(); step = .identity; message = nil
        if let credential, !credential.locallySignedOut, credential.requiresReauthentication != true,
           credential.session.refreshExpiresAt > Date() { trust(credential, online: false) }
        else { accountID = nil; appAccountToken = nil; state = credential?.requiresReauthentication == true ? .credentialsUnknown : .signedOut }
    }
    private func completeLink() async throws {
        let reply: LinkedReply = try await signedPost("/identity/link/complete", body: FlowRequest(flowToken: try requireFlow()))
        guard reply.linked else { throw AccountFailure.invalidResponse }
        let stored = try requireCredential(allowExpiredAccess: true)
        clearFlow(); step = .complete; trust(stored, online: true)
    }
    private func operation(_ action: () async throws -> Void) async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do { try await action() } catch { handle(error) }
    }
    private func beginFlow(_ token: String, expires: Date) {
        clearFlow()
        epoch = UUID(); flowToken = token; setupExpiresAt = expires
        accountID = nil; appAccountToken = nil; state = .pendingMFA
    }
    var setupTimeRemaining: TimeInterval? { setupExpiresAt.map { max(0, $0.timeIntervalSince(now())) } }
    func checkSetupExpiry() {
        guard let setupExpiresAt, setupExpiresAt <= now() else { return }
        restartSetup("Setup expired. Start again to verify your identity. Your saved data and existing credentials are unchanged.")
    }
    private func restartSetup(_ reason: String) {
        clearFlow(); step = .restart; message = reason
    }
    private func requireFlow() throws -> String {
        guard let flowToken, let setupExpiresAt else { throw AccountFailure.reauthenticate }
        guard setupExpiresAt > now() else { throw SetupFailure.expired }
        return flowToken
    }
    private func requireCredential(allowExpiredAccess: Bool = false) throws -> StoredAccountCredential {
        guard let credential, !credential.locallySignedOut, credential.requiresReauthentication != true, credential.session.refreshExpiresAt > Date(), allowExpiredAccess || credential.session.accessExpiresAt > Date() else { throw AccountFailure.reauthenticate }
        return credential
    }
    private func credentialForSignedAction() async throws -> StoredAccountCredential {
        let captured = epoch
        let prior = try requireCredential(allowExpiredAccess: true)
        if prior.refreshRequestID != nil || prior.session.accessExpiresAt <= Date() { await refresh() }
        guard epoch == captured, credential?.session.accountID == prior.session.accountID,
              credential?.session.deviceID == prior.session.deviceID else { throw AccountFailure.reauthenticate }
        return try requireCredential()
    }
    private func signedPost<Body: Encodable, Reply: Decodable>(_ path: String, body: Body) async throws -> Reply {
        let captured = epoch
        let stored = try await credentialForSignedAction()
        do { return try await client.post(path, body: body, credential: stored) }
        catch {
            if epoch == captured, case AccountFailure.service(401, _) = error { handle(error, restoring: true) }
            throw error
        }
    }
    private func clearFlow() { flowToken = nil; setupExpiresAt = nil; outstandingRegistration = nil; authenticatorSecret = nil; authenticatorURI = nil }
    private func trust(_ stored: StoredAccountCredential, online: Bool) { accountID = stored.session.accountID; appAccountToken = stored.session.appAccountToken; state = online ? .trustedOnline : .trustedOffline; message = nil }
    private func requireRetainedAccountAuthentication() {
        epoch = UUID(); accountID = nil; appAccountToken = nil; state = .credentialsUnknown
        backupCodes = []; clearFlow(); step = .identity
        guard var stored = credential else { return }
        stored.lastTrustedVerification = nil; stored.requiresReauthentication = true
        credential = stored
        do { try credentials.save(stored) }
        catch {
            do { try credentials.clear(); credential = nil }
            catch { message = "This device session could not be removed from secure storage. Reconnect and verify this account before continuing." }
        }
    }
    private func handle(_ error: Error, restoring: Bool = false) {
        if !restoring, case SetupFailure.completionUnconfirmed = error {
            restartSetup("Setup may have finished, but this phone could not confirm it. Sign in with your passkey and Authenticator, or Start again. Your saved local data is unchanged.")
            return
        }
        if !restoring, let setupExpiresAt, setupExpiresAt <= now() { checkSetupExpiry(); return }
        if !restoring, case SetupFailure.expired = error { checkSetupExpiry(); return }
        if !restoring, case SetupFailure.restart = error {
            restartSetup("This setup could not be confirmed. Start again to verify your identity. Your saved data and existing credentials are unchanged.")
            return
        }
        if !restoring, step == .restart, flowToken == nil { return }
        message = (error as? AccountFailure)?.errorDescription ?? "The request could not be completed. Your saved data is unchanged. Retry when connected."
        if case AccountFailure.service(401, _) = error, restoring { requireRetainedAccountAuthentication(); return }
        if case AccountFailure.reauthenticate = error, restoring { requireRetainedAccountAuthentication(); return }
        if restoring, let credential, !credential.locallySignedOut, credential.requiresReauthentication != true, credential.session.refreshExpiresAt > Date(), error is URLError { trust(credential, online: false); return }
        if restoring, case AccountFailure.service(503, _) = error, let credential, credential.requiresReauthentication != true { trust(credential, online: false); return }
        if state != .pendingMFA && !trusted { state = .error }
    }
}

@MainActor extension NativeAccountStore: ProgrammeCloudClient {
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply {
        let captured = epoch
        let reply: ProgrammeWriteReply = try await signedPost("/plans/write", body: request)
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply {
        let captured = epoch
        let reply: ProgrammeReadReply = try await signedPost("/plans/read", body: request)
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply {
        let captured = epoch
        let reply: ProgrammeWithdrawReply = try await signedPost("/plans/withdraw", body: request)
        guard epoch == captured, trusted else { throw AccountFailure.reauthenticate }
        return reply
    }
}
