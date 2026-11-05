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
    func purchase(_ plan: MembershipPlan) async throws -> MembershipPurchaseResult
    func restore() async throws
    func finish(transactionID: UInt64) async
}

@MainActor @Observable
public final class MembershipCoordinator {
    public private(set) var offers: [MembershipOffer] = []
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var status = "Checking App Store availability…"
    private var entitlements: [MembershipVerification] = []
    private let client: any MembershipClient
    private let now: @MainActor () -> Date
    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?
    @ObservationIgnored private var expirationRefresh: Task<Void, Never>?
    @ObservationIgnored private var entitlementRefreshID = UUID()

    public init(client: any MembershipClient, now: @escaping @MainActor () -> Date = { .now }) {
        self.client = client
        self.now = now
        let stream = client.updates()
        transactionUpdates = Task { [weak self] in
            for await result in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(result)
            }
        }
    }

    deinit { transactionUpdates?.cancel(); expirationRefresh?.cancel() }

    public var access: MembershipAccess { .resolve(entitlements, now: now()) }
    public var hasAccess: Bool { access.hasAccess }

    public func load() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        await refreshEntitlements()
        await refreshOffers()
    }

    private func refreshOffers() async {
        do {
            offers = try await client.products()
            status = offers.isEmpty ? "App Store plans are unavailable right now." : "Prices and eligible trials are supplied by the App Store."
        } catch {
            offers = []
            self.error = "App Store plans could not be loaded. Check your connection and try again."
            status = "App Store plans are unavailable right now."
        }
    }

    public func buy(_ plan: MembershipPlan) async {
        guard !busy, offers.contains(where: { $0.plan == plan }), access.mayPurchase(plan) else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch try await client.purchase(plan) {
            case .cancelled: status = "Purchase cancelled. Access has not changed."
            case .pending: status = "Purchase is pending approval. Access has not changed."
            case .completed(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == plan.productID, transaction.kind == plan.kind else {
                    error = "The App Store purchase couldn’t be verified. Access has not changed."
                    return
                }
                await refreshEntitlements()
                await client.finish(transactionID: transaction.id)
                await refreshOffers()
                status = hasAccess ? "Membership is active." : "Purchase verified. No active membership was found."
            }
        } catch {
            self.error = "The App Store purchase could not be completed. Try again."
        }
    }

    public func restore() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await client.restore()
            await refreshEntitlements()
            await refreshOffers()
            status = hasAccess ? "Membership is active." : "No active membership was found to restore."
        } catch {
            self.error = "Purchases could not be restored. Check your connection and try again."
        }
    }

    public func completeRedemption(_ result: Result<Void, Error>) async {
        await refreshEntitlements()
        await refreshOffers()
        error = nil
        switch result {
        case .success:
            status = hasAccess ? "Membership is active." : "Apple has not reported an active membership after code redemption."
        case .failure:
            error = "Code redemption was not completed. Try again with the App Store."
        }
    }

    public func refreshEntitlements() async {
        let refreshID = UUID()
        entitlementRefreshID = refreshID
        let current = await client.currentEntitlements()
        guard entitlementRefreshID == refreshID else { return }
        entitlements = current
        expirationRefresh?.cancel()
        guard let deadline = access.expiresAt else { return }
        let delay = max(0, deadline.timeIntervalSince(now()))
        expirationRefresh = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            await self?.refreshEntitlements()
            guard let self else { return }
            self.status = self.hasAccess ? "Membership is active." : "Membership ended. Your history, export and manual tracking remain available."
        }
    }

    private func receive(_ result: MembershipVerification) async {
        guard case .verified(let transaction) = result,
              let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }),
              plan.kind == transaction.kind else { return }
        await refreshEntitlements()
        await client.finish(transactionID: transaction.id)
        await refreshOffers()
        status = hasAccess ? "Membership is active." : "No active membership. Your history, export and manual tracking remain available."
    }
}
