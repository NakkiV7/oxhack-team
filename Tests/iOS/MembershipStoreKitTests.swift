import XCTest
import StoreKit
import StoreKitTest
@testable import Spottr

@MainActor
final class MembershipStoreKitTests: XCTestCase {
    private let account = UUID()
    func testLocalProductsUseApplesLocalizedPricesAndEligibleFourteenDayTrial() async throws {
        let session = try await localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = MembershipStore()
        store.setAccount(account)
        await store.load()
        let rawProducts = try await Product.products(for: MembershipPlan.allCases.map(\.productID))
        XCTAssertEqual(store.offers.count, 2)
        for offer in store.offers {
            XCTAssertEqual(offer.displayPrice, try XCTUnwrap(rawProducts.first { $0.id == offer.plan.productID }).displayPrice)
        }
        XCTAssertEqual(store.offers.first { $0.plan == .monthly }?.eligibleTrialDays, 14)
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testLocalLifetimePurchaseRestoresOnNewStoreAndRefundRemovesAccess() async throws {
        let session = try await localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = MembershipStore()
        store.setAccount(account)
        await store.load()
        await store.buy(.lifetime)
        XCTAssertTrue(store.hasAccess, store.error ?? store.status)
        XCTAssertTrue(store.access.lifetime)
        let receipt = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == MembershipPlan.lifetime.productID })
        let relaunched = MembershipStore()
        relaunched.setAccount(account)
        await relaunched.refreshEntitlements()
        XCTAssertTrue(relaunched.hasAccess)
        try session.refundTransaction(identifier: receipt.identifier)
        await relaunched.refreshEntitlements()
        XCTAssertFalse(relaunched.hasAccess)
    }

    func testLocalExpiredSubscriptionDoesNotGrantAccessOrStartAnotherTrial() async throws {
        let session = try await localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        _ = try await session.buyProduct(identifier: MembershipPlan.monthly.productID)
        let store = MembershipStore()
        store.setAccount(account)
        await store.load()
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.offers.first { $0.plan == .monthly }?.eligibleTrialDays)
        try session.expireSubscription(productIdentifier: MembershipPlan.monthly.productID)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
    }

    func testLocalUnverifiedPurchaseNeverGrantsAccess() async throws {
        let session = try await localSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = MembershipStore()
        store.setAccount(account)
        await store.load()
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        await store.buy(.lifetime)
        XCTAssertFalse(store.hasAccess)
        XCTAssertNotNil(store.error)
    }

    private enum LocalStoreKitFailure: Error { case notLocal }

    private func localSession() async throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Spottr")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        // Establish local transactions before using Product.purchase: older runtimes
        // silently ignore configuration setters, including setSimulatedError(nil).
        let probe = try await session.buyProduct(identifier: MembershipPlan.lifetime.productID)
        guard probe.environment == .xcode else { throw LocalStoreKitFailure.notLocal }
        session.clearTransactions()
        return session
    }
}
