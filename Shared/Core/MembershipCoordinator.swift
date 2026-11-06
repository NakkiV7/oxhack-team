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
    public private(set) var error: String?
    public private(set) var status = "Checking App Store availability…"
    public private(set) var accountID: UUID?
    private var entitlements: [MembershipVerification] = []
    private var restoredLegacyIDs: Set<UInt64> = []
    private var accountGeneration = UUID()
    private let client: any MembershipClient
    private let now: @MainActor () -> Date
    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?
    @ObservationIgnored private var expirationRefresh: Task<Void, Never>?
    @ObservationIgnored private var entitlementRefreshID = UUID()

    public init(client: any MembershipClient, now: @escaping @MainActor () -> Date = { .now }) {
        self.client = client; self.now = now
        let stream = client.updates()
        transactionUpdates = Task { [weak self] in
            for await result in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(result)
            }
        }
    }
    deinit { transactionUpdates?.cancel(); expirationRefresh?.cancel() }

    public func setAccount(_ accountID: UUID?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID; accountGeneration = UUID(); entitlementRefreshID = UUID()
        entitlements = []; restoredLegacyIDs = []; error = nil
        expirationRefresh?.cancel()
        status = accountID == nil ? "Sign in to use membership. Restore purchases remains available." : "Checking your Apple membership…"
    }
    private var ownedTransactions: [MembershipTransaction] {
        guard let accountID else { return [] }
        return entitlements.compactMap { result in
            guard case .verified(let transaction) = result,
                  let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }), plan.kind == transaction.kind,
                  transaction.appAccountToken == accountID || (transaction.appAccountToken == nil && restoredLegacyIDs.contains(transaction.id)) else { return nil }
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
        busy = true; error = nil
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
            offers = loaded
            status = offers.isEmpty ? "App Store plans are unavailable right now." : "Prices and eligible trials are supplied by the App Store."
        } catch {
            guard generation == accountGeneration else { return }
            offers = []; self.error = "App Store plans could not be loaded. Check your connection and try again."
            status = "App Store plans are unavailable right now."
        }
    }
    public func buy(_ plan: MembershipPlan) async {
        guard let accountID, !busy, offers.contains(where: { $0.plan == plan }), access.mayPurchase(plan) else { return }
        let generation = accountGeneration
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await client.purchase(plan, appAccountToken: accountID)
            guard generation == accountGeneration else { return }
            switch result {
            case .cancelled: status = "Purchase cancelled. Access has not changed."
            case .pending: status = "Purchase is pending approval. Access has not changed."
            case .completed(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == plan.productID, transaction.kind == plan.kind,
                      transaction.appAccountToken == accountID else {
                    error = "The App Store purchase couldn’t be verified for this account. Access has not changed."
                    return
                }
                await refreshEntitlements()
                await client.finish(transactionID: transaction.id)
                guard generation == accountGeneration else { return }
                await refreshOffers()
                guard generation == accountGeneration else { return }
                status = hasAccess ? "Membership is active." : "Purchase verified. No active membership was found."
            }
        } catch {
            guard generation == accountGeneration else { return }
            self.error = "The App Store purchase could not be completed. Try again."
        }
    }
    public func restore() async {
        guard !busy else { return }
        let generation = accountGeneration
        busy = true; error = nil
        defer { busy = false }
        do {
            try await client.restore()
            guard generation == accountGeneration else { return }
            await refreshEntitlements()
            guard generation == accountGeneration else { return }
            if accountID != nil {
                restoredLegacyIDs = Set(entitlements.compactMap { result in
                    guard case .verified(let transaction) = result, transaction.appAccountToken == nil else { return nil }
                    return transaction.id
                })
                await refreshEntitlements()
            }
            guard generation == accountGeneration else { return }
            await refreshOffers()
            guard generation == accountGeneration else { return }
            status = hasAccess ? "Membership is active." : "No active membership for this account. Sign in and restore a previous Apple purchase."
        } catch {
            guard generation == accountGeneration else { return }
            self.error = "Purchases could not be restored. Check your connection and try again."
        }
    }
    public func completeRedemption(_ result: Result<Void, Error>) async {
        let generation = accountGeneration
        await refreshEntitlements()
        guard generation == accountGeneration else { return }
        await refreshOffers()
        guard generation == accountGeneration else { return }
        error = nil
        switch result {
        case .success: status = hasAccess ? "Membership is active." : "If Apple completed your redemption, use Restore purchases to verify it for this account."
        case .failure: error = "Code redemption was not completed. Try again with the App Store."
        }
    }
    public func refreshEntitlements() async {
        let refreshID = UUID(), generation = accountGeneration
        entitlementRefreshID = refreshID
        let current = await client.currentEntitlements()
        guard generation == accountGeneration, entitlementRefreshID == refreshID else { return }
        entitlements = current
        expirationRefresh?.cancel()
        guard let deadline = access.expiresAt else { return }
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
        let generation = accountGeneration
        await refreshEntitlements()
        await client.finish(transactionID: transaction.id)
        guard generation == accountGeneration else { return }
        await refreshOffers()
        guard generation == accountGeneration else { return }
        status = hasAccess ? "Membership is active." : "No active membership. Your history, export and help remain available."
    }
}
