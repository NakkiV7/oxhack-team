import XCTest
@testable import SpottrCore

@MainActor
final class MembershipJourneyTests: XCTestCase {
    func testStoreOutageDoesNotRemoveVerifiedLifetimeAndNeverShowsInventedPrices() async {
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        client.productError = URLError(.notConnectedToInternet)
        let store = MembershipCoordinator(client: client)
        await store.load()
        XCTAssertTrue(store.hasAccess)
        XCTAssertTrue(store.offers.isEmpty)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
    }

    func testCheckoutCancellationPendingAndUnverifiedPurchaseCannotUnlock() async {
        let forged = MembershipTransaction(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let cases: [(MembershipPurchaseResult, String, Bool)] = [
            (.cancelled, "cancelled", false), (.pending, "pending", false),
            (.completed(.unverified(forged)), "verified", true)
        ]
        for (result, message, expectsError) in cases {
            let client = MembershipTestClient()
            client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "€240.00")]
            client.purchaseResult = result
            let store = MembershipCoordinator(client: client)
            await store.load()
            await store.buy(.lifetime)
            XCTAssertFalse(store.hasAccess)
            XCTAssertEqual(store.error != nil, expectsError)
            XCTAssertTrue((store.error ?? store.status).contains(message))
            XCTAssertTrue(client.finished.isEmpty)
            XCTAssertFalse(store.busy)
        }
    }

    func testVerifiedCheckoutRefreshesAppleEntitlementsAndFinishesOnlyMatchingTransactions() async {
        let lifetime = MembershipTransaction(id: 42, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "€240.00")]
        client.purchaseResult = .completed(.verified(lifetime))
        let store = MembershipCoordinator(client: client)
        await store.load()
        await store.buy(.lifetime)
        XCTAssertFalse(store.hasAccess, "A purchase callback alone must not substitute for Apple's current entitlements.")
        XCTAssertEqual(client.finished, [42])
        client.purchaseEntitlements = [.verified(lifetime)]
        await store.buy(.lifetime)
        XCTAssertTrue(store.hasAccess)
        await store.buy(.lifetime)
        XCTAssertEqual(client.purchases.count, 2, "Lifetime owners must not be charged a second time.")

        let wrongClient = MembershipTestClient()
        wrongClient.availableOffers = client.availableOffers
        wrongClient.purchaseResult = .completed(.verified(.init(id: 44, productID: "other.product", kind: .nonConsumable)))
        let wrongStore = MembershipCoordinator(client: wrongClient)
        await wrongStore.load()
        await wrongStore.buy(.lifetime)
        XCTAssertFalse(wrongStore.hasAccess)
        XCTAssertNotNil(wrongStore.error)
        XCTAssertTrue(wrongClient.finished.isEmpty)
    }

    func testRestoreRefreshesVerifiedOwnershipWithoutCreatingOrExtendingATrial() async {
        var now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(20)
        let monthly = MembershipTransaction(productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: deadline)
        let client = MembershipTestClient()
        client.restoredEntitlements = [.verified(monthly)]
        let store = MembershipCoordinator(client: client, now: { now })
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertEqual(store.access.expiresAt, deadline)
        now = deadline
        XCTAssertFalse(store.hasAccess)
        await store.restore()
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(client.purchases.isEmpty)
        client.restoreError = URLError(.notConnectedToInternet)
        await store.restore()
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
    }

    func testRedemptionCompletionCannotGrantMembershipUntilAppleReportsOwnership() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client)
        await store.completeRedemption(.success(()))
        XCTAssertFalse(store.hasAccess)
        client.entitlements = [.verified(.init(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await store.completeRedemption(.success(()))
        XCTAssertTrue(store.hasAccess)
        await store.completeRedemption(.failure(URLError(.cancelled)))
        XCTAssertTrue(store.hasAccess)
        XCTAssertNotNil(store.error)
    }

    func testTransactionUpdatesRefreshPendingApprovalAndRefundAndFinishVerifiedKnownProducts() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
        let lifetime = MembershipTransaction(id: 55, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.entitlements = [.verified(lifetime)]
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<100 where !store.hasAccess { await Task.yield() }
        XCTAssertTrue(store.hasAccess)
        for _ in 0..<100 where client.finished.isEmpty { await Task.yield() }
        XCTAssertEqual(client.finished, [55])
        client.entitlements = []
        client.continuation.yield(.verified(.init(id: 55, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: .now)))
        for _ in 0..<100 where store.hasAccess { await Task.yield() }
        XCTAssertFalse(store.hasAccess)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
    }

    func testSubscriptionDeadlineRefreshesVisibleMembershipWithoutAPurchaseOrRelaunch() async throws {
        let client = MembershipTestClient()
        let deadline = Date.now.addingTimeInterval(0.05)
        client.entitlements = [.verified(.init(productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: deadline))]
        let store = MembershipCoordinator(client: client)
        await store.refreshEntitlements()
        XCTAssertTrue(store.hasAccess)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(store.status.contains("ended"))
        XCTAssertTrue(client.purchases.isEmpty)
    }

    func testCompletedPurchaseReloadsTrialEligibilityInsteadOfAdvertisingAUsedTrial() async {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .monthly, displayName: "Monthly", displayPrice: "£10.00", eligibleTrialDays: 14)]
        let store = MembershipCoordinator(client: client)
        await store.load()
        XCTAssertEqual(store.offers.first?.eligibleTrialDays, 14)
        client.availableOffers = [.init(plan: .monthly, displayName: "Monthly", displayPrice: "£10.00")]
        let transaction = MembershipTransaction(id: 67, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(200))
        client.purchaseResult = .completed(.verified(transaction))
        client.purchaseEntitlements = [.verified(transaction)]
        await store.buy(.monthly)
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.offers.first?.eligibleTrialDays)
    }

    func testOlderEntitlementRefreshCannotOverwriteANewerRefundResult() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client)
        client.deferNextEntitlementRequest = true
        let older = Task { await store.refreshEntitlements() }
        for _ in 0..<100 where client.deferredEntitlements == nil { await Task.yield() }
        XCTAssertNotNil(client.deferredEntitlements)
        await store.refreshEntitlements()
        client.deferredEntitlements?.resume(returning: [.verified(.init(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))])
        await older.value
        XCTAssertFalse(store.hasAccess)
    }
}

@MainActor
private final class MembershipTestClient: MembershipClient {
    var entitlements: [MembershipVerification] = []
    var availableOffers: [MembershipOffer] = []
    var productError: Error?
    var purchaseResult: MembershipPurchaseResult = .cancelled
    var purchaseError: Error?
    var purchaseEntitlements: [MembershipVerification]?
    var restoredEntitlements: [MembershipVerification]?
    var restoreError: Error?
    var purchases: [MembershipPlan] = []
    var finished: [UInt64] = []
    var deferNextEntitlementRequest = false
    var deferredEntitlements: CheckedContinuation<[MembershipVerification], Never>?
    let stream: AsyncStream<MembershipVerification>
    let continuation: AsyncStream<MembershipVerification>.Continuation

    init() {
        let pair = AsyncStream<MembershipVerification>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func products() async throws -> [MembershipOffer] {
        if let productError { throw productError }
        return availableOffers
    }

    func currentEntitlements() async -> [MembershipVerification] {
        if deferNextEntitlementRequest {
            deferNextEntitlementRequest = false
            return await withCheckedContinuation { deferredEntitlements = $0 }
        }
        return entitlements
    }
    func updates() -> AsyncStream<MembershipVerification> { stream }
    func purchase(_ plan: MembershipPlan) async throws -> MembershipPurchaseResult {
        purchases.append(plan)
        if let purchaseError { throw purchaseError }
        if let purchaseEntitlements { entitlements = purchaseEntitlements }
        return purchaseResult
    }
    func restore() async throws {
        if let restoreError { throw restoreError }
        if let restoredEntitlements { entitlements = restoredEntitlements }
    }
    func finish(transactionID: UInt64) async { finished.append(transactionID) }
}
