import Foundation
import Observation

public struct MembershipOffer: Equatable, Sendable, Identifiable {
    public let plan: MembershipPlan
    public let displayName: String
    public let displayPrice: String
    public let eligibleTrialDays: Int?
    public var id: MembershipPlan { plan }

    public init(plan: MembershipPlan, displayName: String, displayPrice: String, eligibleTrialDays: Int? = nil) {
        self.plan = plan
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.eligibleTrialDays = eligibleTrialDays
    }
}

public enum MembershipPurchaseResult: Sendable {
    case completed(MembershipVerification)
    case pending
    case cancelled
}

@MainActor
public protocol MembershipClient: AnyObject {
    func products() async throws -> [MembershipOffer]
    func currentEntitlements() async -> [MembershipVerification]
    func updates() -> AsyncStream<MembershipVerification>
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult
    func restore() async throws
    func finish(transactionID: UInt64) async
}

@MainActor @Observable
public final class MembershipCoordinator {
    public private(set) var offers: [MembershipOffer] = []
    public private(set) var busy = false
    public var error: String? { accessError ?? catalogueError }
    public var accessError: String? { claimError ?? operationError }
    public private(set) var catalogueError: String?
    private enum OperationFeedback {
        case accessSnapshot(String, Bool)
        case outcome(String)
    }
    private var operationFeedback: OperationFeedback?
    public var operationMessage: String? {
        switch operationFeedback {
        case .accessSnapshot(let message, _)?: return message
        case .outcome(let message)?: return message
        case nil: return nil
        }
    }
    private struct PendingPurchase: Equatable {
        let id = UUID()
        let accountID: UUID
        let plan: MembershipPlan
    }
    private var pendingPurchase: PendingPurchase?
    private var operationError: String?
    private var claimError: String?
    public private(set) var status = "Checking App Store availability…"
    public private(set) var accountID: UUID?
    public private(set) var entitlementsResolved = false
    @ObservationIgnored private var currentRefresh: Task<Void, Never>?
    @ObservationIgnored private var currentRefreshID = UUID()
    private var entitlements: [MembershipVerification] = []
    private var restoredClaims: Set<MembershipClaim> = []
    private var accountGeneration = UUID()
    private let client: any MembershipClient
    private let claims: any MembershipClaimStore
    private let now: @MainActor () -> Date
    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?
    @ObservationIgnored private var expirationRefresh: Task<Void, Never>?
    @ObservationIgnored private var entitlementRefreshID = UUID()

    public init(client: any MembershipClient, claims: any MembershipClaimStore, now: @escaping @MainActor () -> Date = { .now }) {
        self.client = client; self.claims = claims; self.now = now
        let stream = client.updates()
        transactionUpdates = Task { [weak self] in
            for await result in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(result)
            }
        }
    }
    deinit { transactionUpdates?.cancel(); expirationRefresh?.cancel(); currentRefresh?.cancel() }

    public func setAccount(_ accountID: UUID?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID; accountGeneration = UUID(); entitlementRefreshID = UUID()
        entitlements = []; restoredClaims = []; operationError = nil; claimError = nil; operationFeedback = nil; pendingPurchase = nil
        entitlementsResolved = false; currentRefresh?.cancel(); currentRefresh = nil; currentRefreshID = UUID()
        expirationRefresh?.cancel()
        status = accountID == nil ? "Sign in to use membership. Restore purchases remains available." : "Checking your Apple membership…"
    }
    private var ownedTransactions: [MembershipTransaction] {
        guard let accountID else { return [] }
        return entitlements.compactMap { result in
            guard case .verified(let transaction) = result,
                  let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }), plan.kind == transaction.kind,
                  transaction.appAccountToken == accountID || MembershipClaim(transaction: transaction).map(restoredClaims.contains) == true else { return nil }
            return transaction
        }
    }
    public var access: MembershipAccess { .resolve(ownedTransactions.map(MembershipVerification.verified), now: now()) }
    public enum Condition: Equatable { case signedOut, none, active, gracePeriod, expired, revoked }
    public var condition: Condition {
        guard accountID != nil else { return .signedOut }
        if access.lifetime { return .active }
        if hasAccess {
            return ownedTransactions.contains { transaction in
                transaction.revocationDate == nil && !transaction.isUpgraded &&
                (transaction.expirationDate ?? .distantFuture) <= now() && (transaction.gracePeriodExpirationDate ?? .distantPast) > now()
            } ? .gracePeriod : .active
        }
        if ownedTransactions.contains(where: { $0.revocationDate != nil }) { return .revoked }
        if ownedTransactions.contains(where: { ($0.expirationDate ?? .distantFuture) <= now() }) { return .expired }
        return .none
    }
    public var hasAccess: Bool { access.hasAccess }

    public func load() async {
        guard !busy else { return }
        let generation = accountGeneration
        busy = true; operationError = nil
        defer { busy = false }
        await refreshEntitlements()
        guard generation == accountGeneration else { return }
        await refreshOffers()
    }
    private func refreshOffers() async {
        let generation = accountGeneration
        do {
            let loaded = try await client.products()
            guard generation == accountGeneration else { return }
            offers = loaded; catalogueError = nil
            status = offers.isEmpty ? "App Store plans are unavailable right now." : "Prices and eligible trials are supplied by the App Store."
        } catch {
            guard generation == accountGeneration else { return }
            offers = []; self.catalogueError = "App Store plans could not be loaded. Check your connection and try again."
            status = "App Store plans are unavailable right now."
        }
    }
    public func buy(_ plan: MembershipPlan) async {
        guard let accountID, !busy, offers.contains(where: { $0.plan == plan }), access.mayPurchase(plan) else { return }
        let generation = accountGeneration, purchase = PendingPurchase(accountID: accountID, plan: plan)
        busy = true; operationError = nil; operationFeedback = nil; pendingPurchase = purchase
        defer { busy = false }
        do {
            let result = try await client.purchase(plan, appAccountToken: accountID)
            guard generation == accountGeneration else { return }
            switch result {
            case .cancelled:
                if pendingPurchase == purchase { pendingPurchase = nil }
                status = "Purchase cancelled. Access has not changed."; operationFeedback = .outcome(status)
            case .pending:
                guard pendingPurchase == purchase else { return }
                let planActive = access.activePlans.contains(plan)
                if planActive { pendingPurchase = nil; status = "Membership is active." }
                else { status = "Purchase is pending approval. Access has not changed." }
                operationFeedback = planActive ? .accessSnapshot(status, true) : .outcome(status)
            case .completed(let result):
                if pendingPurchase == purchase { pendingPurchase = nil }
                guard case .verified(let transaction) = result,
                      transaction.productID == plan.productID, transaction.kind == plan.kind,
                      transaction.appAccountToken == accountID else {
                    operationError = "The App Store purchase couldn’t be verified for this account. Access has not changed."
                    return
                }
                await refreshEntitlements()
                await client.finish(transactionID: transaction.id)
                guard generation == accountGeneration else { return }
                await refreshOffers()
                guard generation == accountGeneration else { return }
                let active = hasAccess
                status = active ? "Membership is active." : "Purchase verified. No active membership was found."
                operationFeedback = .accessSnapshot(status, active)
            }
        } catch {
            guard generation == accountGeneration else { return }
            if pendingPurchase == purchase { pendingPurchase = nil }
            self.operationError = "The App Store purchase could not be completed. Try again."
        }
    }
    public func restore() async {
        guard !busy else { return }
        let generation = accountGeneration, restoringAccount = accountID
        busy = true; operationError = nil; operationFeedback = nil; pendingPurchase = nil
        defer { busy = false }
        do {
            try await client.restore()
            guard generation == accountGeneration else { return }
            await refreshEntitlements()
            guard generation == accountGeneration else { return }
            if let restoringAccount {
                let verifiedClaims = Set(entitlements.compactMap { result -> MembershipClaim? in
                    guard case .verified(let transaction) = result,
                          MembershipAccess.resolve([result], now: now()).hasAccess else { return nil }
                    return MembershipClaim(transaction: transaction)
                })
                if !verifiedClaims.isEmpty {
                    do {
                        // No await between this captured-owner check and the atomic protected write.
                        guard generation == accountGeneration, accountID == restoringAccount else { return }
                        try claims.save(restoredClaims.union(verifiedClaims), accountID: restoringAccount)
                    } catch {
                        claimError = "Your restored membership claim could not be saved on this device. Try Restore purchases again."
                        return
                    }
                    await refreshEntitlements()
                }
            }
            guard generation == accountGeneration else { return }
            await refreshOffers()
            guard generation == accountGeneration else { return }
            let active = hasAccess
            status = active ? "Membership is active." : "No active membership for this account. Sign in and restore a previous Apple purchase."
            operationFeedback = .accessSnapshot(status, active)
        } catch {
            guard generation == accountGeneration else { return }
            self.operationError = "Purchases could not be restored. Check your connection and try again."
        }
    }
    public func completeRedemption(_ result: Result<Void, Error>) async {
        operationFeedback = nil; pendingPurchase = nil
        let generation = accountGeneration
        await refreshEntitlements()
        guard generation == accountGeneration else { return }
        await refreshOffers()
        guard generation == accountGeneration else { return }
        operationError = nil
        switch result {
        case .success:
            let active = hasAccess
            status = active ? "Membership is active." : "If Apple completed your redemption, use Restore purchases to verify it for this account."
            operationFeedback = .accessSnapshot(status, active)
        case .failure: operationError = "Code redemption was not completed. Try again with the App Store."
        }
    }
    public func refreshCurrentEntitlements() async {
        if let currentRefresh { await currentRefresh.value; return }
        let id = UUID(), generation = accountGeneration
        currentRefreshID = id
        let task = Task { [weak self] in
            guard let self, self.accountGeneration == generation else { return }
            await self.refreshEntitlements()
        }
        currentRefresh = task
        await task.value
        if currentRefreshID == id { currentRefresh = nil }
    }
    public func refreshEntitlements() async {
        let refreshID = UUID(), generation = accountGeneration, pending = pendingPurchase
        entitlementRefreshID = refreshID
        let current = await client.currentEntitlements()
        guard generation == accountGeneration, entitlementRefreshID == refreshID else { return }
        entitlements = current; entitlementsResolved = true
        restoredClaims = []
        claimError = nil
        if let accountID {
            do { restoredClaims = try claims.load(accountID: accountID) }
            catch { claimError = "Your saved membership claim could not be read. Try again or use Restore purchases." }
        }
        let currentAccess = access
        if case .accessSnapshot(_, let previouslyActive)? = operationFeedback, previouslyActive != currentAccess.hasAccess {
            operationFeedback = nil
            status = currentAccess.hasAccess ? "Membership is active." : "No active membership. Your history, export and help remain available."
        }
        if let pending, pendingPurchase == pending, pending.accountID == accountID,
           currentAccess.activePlans.contains(pending.plan) {
            pendingPurchase = nil; operationFeedback = .accessSnapshot("Membership is active.", true)
        }
        expirationRefresh?.cancel()
        guard let deadline = currentAccess.expiresAt else { return }
        expirationRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(self?.now() ?? .now)))) }
            catch { return }
            guard let self, generation == self.accountGeneration else { return }
            await self.refreshEntitlements()
            guard generation == self.accountGeneration else { return }
            self.status = self.hasAccess ? "Membership is active." : "Membership ended. Your history, export and help remain available."
        }
    }
    private func receive(_ result: MembershipVerification) async {
        guard case .verified(let transaction) = result,
              let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }),
              plan.kind == transaction.kind else { return }
        let generation = accountGeneration, pending = pendingPurchase
        await refreshEntitlements()
        await client.finish(transactionID: transaction.id)
        guard generation == accountGeneration else { return }
        await refreshOffers()
        guard generation == accountGeneration else { return }
        status = hasAccess ? "Membership is active." : "No active membership. Your history, export and help remain available."
        guard let pending, pendingPurchase == pending,
              pending.accountID == accountID, transaction.appAccountToken == pending.accountID,
              pending.plan == plan, MembershipAccess.resolve([result], now: now()).activePlans.contains(plan) else { return }
        pendingPurchase = nil
        operationFeedback = access.activePlans.contains(plan) ? .accessSnapshot("Membership is active.", true) : .outcome("Purchase verified. Use Restore purchases to confirm current access.")
    }
}
