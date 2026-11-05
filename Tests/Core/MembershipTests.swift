import XCTest
@testable import SpottrCore

final class MembershipTests: XCTestCase {
    func testMissingOrUnverifiedTransactionsNeverGrantMembership() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(MembershipAccess.resolve([], now: now).hasAccess)
        let forged = MembershipTransaction(productID: "com.omarchoudhry.spottr.lifetime", kind: .nonConsumable)
        XCTAssertFalse(MembershipAccess.resolve([.unverified(forged)], now: now).hasAccess)
    }

    func testVerifiedLifetimeGrantsAccessWithoutAnExpiry() {
        let transaction = MembershipTransaction(productID: "com.omarchoudhry.spottr.lifetime", kind: .nonConsumable)
        XCTAssertTrue(MembershipAccess.resolve([.verified(transaction)], now: Date(timeIntervalSince1970: 1_000)).hasAccess)
    }

    func testAccessUsesVerifiedProductTypeAndCurrentSubscriptionDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        let cases: [(MembershipTransaction, Bool)] = [
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable, expirationDate: now.addingTimeInterval(1)), true),
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable, expirationDate: now), false),
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable), false),
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable, expirationDate: now.addingTimeInterval(-1), gracePeriodExpirationDate: now.addingTimeInterval(2)), true),
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable, expirationDate: now.addingTimeInterval(-1), gracePeriodExpirationDate: now), false),
            (.init(productID: "com.omarchoudhry.spottr.lifetime", kind: .nonConsumable, revocationDate: now), false),
            (.init(productID: "com.omarchoudhry.spottr.monthly", kind: .autoRenewable, expirationDate: now.addingTimeInterval(20), isUpgraded: true), false),
            (.init(productID: "com.omarchoudhry.spottr.lifetime", kind: .autoRenewable, expirationDate: now.addingTimeInterval(20)), false),
            (.init(productID: "other.lifetime", kind: .nonConsumable), false)
        ]
        for (transaction, expected) in cases {
            XCTAssertEqual(MembershipAccess.resolve([.verified(transaction)], now: now).hasAccess, expected, transaction.productID)
        }
    }

    func testLifetimePreventsDuplicatePurchasesAndRetainsMonthlyCancellationReminder() {
        let now = Date(timeIntervalSince1970: 1_000)
        let monthly = MembershipTransaction(productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: now.addingTimeInterval(20))
        let lifetime = MembershipTransaction(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let subscription = MembershipAccess.resolve([.verified(monthly)], now: now)
        XCTAssertFalse(subscription.mayPurchase(.monthly))
        XCTAssertTrue(subscription.mayPurchase(.lifetime))
        XCTAssertEqual(subscription.expiresAt, now.addingTimeInterval(20))
        let overlap = MembershipAccess.resolve([.verified(monthly), .verified(lifetime)], now: now)
        XCTAssertTrue(overlap.lifetime)
        XCTAssertTrue(overlap.hasOverlappingSubscription)
        XCTAssertFalse(overlap.mayPurchase(.monthly))
        XCTAssertFalse(overlap.mayPurchase(.lifetime))
    }
}
