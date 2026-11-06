import Foundation
import StoreKit

typealias MembershipStore = MembershipCoordinator

extension MembershipCoordinator {
    convenience init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("Spottr"), client: (any MembershipClient)? = nil) {
        self.init(client: client ?? AppleMembershipClient(), claims: ProtectedMembershipClaimStore(root: root))
    }
}

@MainActor
final class AppleMembershipClient: MembershipClient {
    private var cachedProducts: [Product] = []
    private var pendingFinishes: [UInt64: StoreKit.Transaction] = [:]

    func products() async throws -> [MembershipOffer] {
        cachedProducts = try await Product.products(for: MembershipPlan.allCases.map(\.productID))
            .filter { product in
                guard let plan = MembershipPlan.allCases.first(where: { $0.productID == product.id }),
                      Self.kind(product.type) == plan.kind else { return false }
                guard plan == .monthly else { return true }
                return product.subscription?.subscriptionPeriod.unit == .month && product.subscription?.subscriptionPeriod.value == 1
            }
        var offers: [MembershipOffer] = []
        for plan in MembershipPlan.allCases {
            guard let product = cachedProducts.first(where: { $0.id == plan.productID }) else { continue }
            let trialDays = await eligibleTrialDays(product)
            offers.append(.init(plan: plan, displayName: product.displayName,
                                displayPrice: product.displayPrice, eligibleTrialDays: trialDays))
        }
        return offers
    }

    func currentEntitlements() async -> [MembershipVerification] {
        var entitlements: [MembershipVerification] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                entitlements.append(Self.map(result))
                continue
            }
            guard MembershipPlan.allCases.contains(where: { $0.productID == transaction.productID }) else { continue }
            let graceDeadline = await graceDeadline(transaction)
            entitlements.append(.verified(Self.snapshot(transaction, graceDeadline: graceDeadline)))
        }
        for plan in MembershipPlan.allCases {
            let alreadyRead = entitlements.contains { result in
                if case .verified(let transaction) = result { return transaction.productID == plan.productID }
                return false
            }
            guard !alreadyRead, let result = await StoreKit.Transaction.latest(for: plan.productID) else { continue }
            if case .verified(let transaction) = result {
                entitlements.append(.verified(Self.snapshot(transaction, graceDeadline: await graceDeadline(transaction))))
            } else { entitlements.append(Self.map(result)) }
        }
        return entitlements
    }

    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult {
        guard AppStore.canMakePayments, let product = cachedProducts.first(where: { $0.id == plan.productID }) else {
            throw MembershipStoreError.purchaseUnavailable
        }
        do {
            switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
            case .success(let result):
                remember(result)
                return .completed(Self.map(result))
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: throw MembershipStoreError.purchaseUnavailable
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func finish(transactionID: UInt64) async {
        guard let transaction = pendingFinishes.removeValue(forKey: transactionID) else { return }
        await transaction.finish()
    }

    func updates() -> AsyncStream<MembershipVerification> {
        AsyncStream { continuation in
            let listener = Task { [weak self] in
                for await result in StoreKit.Transaction.unfinished {
                    guard !Task.isCancelled else { return }
                    self?.remember(result)
                    continuation.yield(Self.map(result))
                }
                for await result in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { return }
                    self?.remember(result)
                    continuation.yield(Self.map(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in listener.cancel() }
        }
    }

    private func remember(_ result: VerificationResult<StoreKit.Transaction>) {
        guard case .verified(let transaction) = result,
              let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }),
              plan.kind == Self.kind(transaction.productType) else { return }
        pendingFinishes[transaction.id] = transaction
    }

    private func eligibleTrialDays(_ product: Product) async -> Int? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer else { return nil }
        switch offer.period.unit {
        case .day: return offer.period.value * offer.periodCount
        case .week: return 7 * offer.period.value * offer.periodCount
        default: return nil
        }
    }

    private func graceDeadline(_ transaction: StoreKit.Transaction) async -> Date? {
        guard transaction.productID == MembershipPlan.monthly.productID,
              let expiration = transaction.expirationDate, expiration <= .now,
              let group = transaction.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return nil }
        return statuses.compactMap { status -> Date? in
            guard status.state == .inGracePeriod,
                  case .verified(let current) = status.transaction, current.id == transaction.id,
                  case .verified(let renewal) = status.renewalInfo,
                  renewal.currentProductID == transaction.productID,
                  renewal.originalTransactionID == transaction.originalID else { return nil }
            return renewal.gracePeriodExpirationDate
        }.max()
    }

    private static func map(_ result: VerificationResult<StoreKit.Transaction>) -> MembershipVerification {
        switch result {
        case .verified(let transaction): return .verified(snapshot(transaction))
        case .unverified(let transaction, _): return .unverified(snapshot(transaction))
        }
    }

    private static func snapshot(_ transaction: StoreKit.Transaction, graceDeadline: Date? = nil) -> MembershipTransaction {
        .init(id: transaction.id, originalID: transaction.originalID, appAccountToken: transaction.appAccountToken, productID: transaction.productID, kind: kind(transaction.productType),
              expirationDate: transaction.expirationDate, gracePeriodExpirationDate: graceDeadline,
              revocationDate: transaction.revocationDate, isUpgraded: transaction.isUpgraded)
    }

    private static func kind(_ type: Product.ProductType) -> MembershipProductKind {
        switch type {
        case .autoRenewable: .autoRenewable
        case .nonConsumable: .nonConsumable
        default: .unsupported
        }
    }
}

private enum MembershipStoreError: Error { case purchaseUnavailable }
