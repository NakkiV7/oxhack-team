import XCTest
@testable import SpottrCore

private let testAccount = UUID()

@MainActor
final class MembershipJourneyTests: XCTestCase {
    func testMonthlyMembershipSurvivesPendingAndCancelledLifetimeAttempts() async {
        for (result, text) in [(MembershipPurchaseResult.pending, "pending approval"), (.cancelled, "cancelled")] {
            let client = MembershipTestClient()
            client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
            client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
            client.purchaseResult = result
            let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
            store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
            XCTAssertTrue(store.status.contains(text)); XCTAssertTrue(store.operationMessage?.contains(text) == true)
            await store.load()
            XCTAssertTrue(store.operationMessage?.contains(text) == true, "A catalogue refresh must not hide the purchase outcome")
            XCTAssertTrue(store.hasAccess)
            XCTAssertFalse(store.access.lifetime); XCTAssertTrue(store.access.mayPurchase(.lifetime))
            XCTAssertTrue(client.finished.isEmpty)
            store.setAccount(UUID()); XCTAssertNil(store.operationMessage)
        }
    }
    func testNewUpgradeClearsPreviousOutcomeAndLateResultCannotCrossAccounts() async {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
        XCTAssertTrue(store.operationMessage?.contains("cancelled") == true)
        client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<100 where client.purchaseContinuation == nil { await Task.yield() }
        XCTAssertNotNil(client.purchaseContinuation); XCTAssertNil(store.operationMessage)
        store.setAccount(UUID())
        client.purchaseContinuation?.resume(returning: .pending); await buying.value
        XCTAssertNil(store.operationMessage); XCTAssertFalse(store.hasAccess)
    }
    func testUnrelatedUpdatesPreservePendingAndCancelledLifetimeOutcomes() async throws {
        for (result, text) in [(MembershipPurchaseResult.pending, "pending approval"), (.cancelled, "cancelled")] {
            let client = MembershipTestClient()
            client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
            let monthly = MembershipTransaction(id: 801, appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600))
            client.entitlements = [.verified(monthly)]; client.purchaseResult = result
            let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
            store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
            let unrelated = [monthly,
                MembershipTransaction(id: 802, appAccountToken: UUID(), productID: MembershipPlan.lifetime.productID, kind: .nonConsumable),
                MembershipTransaction(id: 803, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: .now)]
            for transaction in unrelated {
                let requests = client.productRequests
                client.continuation.yield(.verified(transaction))
                for _ in 0..<200 where client.productRequests == requests || !client.finished.contains(transaction.id) { await Task.yield() }
                try await Task.sleep(for: .milliseconds(1))
                XCTAssertGreaterThan(client.productRequests, requests); XCTAssertTrue(client.finished.contains(transaction.id))
                XCTAssertTrue(store.operationMessage?.contains(text) == true, "Unrelated updates cannot replace this lifetime outcome")
                XCTAssertTrue(store.hasAccess); XCTAssertFalse(store.access.lifetime)
            }
        }
    }
    func testVerifiedCurrentAccountLifetimeUpdateResolvesPendingOutcome() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        let monthly = MembershipTransaction(id: 811, appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600))
        client.entitlements = [.verified(monthly)]; client.purchaseResult = .pending
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
        XCTAssertTrue(store.operationMessage?.contains("pending approval") == true)
        let lifetime = MembershipTransaction(id: 812, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.entitlements.append(.verified(lifetime)); let requests = client.productRequests
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.productRequests == requests || !client.finished.contains(lifetime.id) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(1))
        XCTAssertTrue(store.access.lifetime); XCTAssertEqual(store.operationMessage, "Membership is active.")
    }
    func testDelayedLifetimeResolutionCannotReplaceNewerUserOutcome() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        let monthly = MembershipTransaction(id: 821, appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600))
        client.entitlements = [.verified(monthly)]; client.purchaseResult = .pending
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
        let lifetime = MembershipTransaction(id: 822, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.deferNextEntitlementRequest = true
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.deferredEntitlements == nil { await Task.yield() }
        let held = try XCTUnwrap(client.deferredEntitlements)
        client.purchaseResult = .cancelled; await store.buy(.lifetime)
        XCTAssertTrue(store.operationMessage?.contains("cancelled") == true)
        client.entitlements.append(.verified(lifetime)); let requests = client.productRequests
        held.resume(returning: client.entitlements); client.deferredEntitlements = nil
        for _ in 0..<200 where client.productRequests == requests || !client.finished.contains(lifetime.id) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(1))
        XCTAssertTrue(store.access.lifetime)
        XCTAssertTrue(store.operationMessage?.contains("cancelled") == true, "An older stream refresh cannot replace a newer user result")
    }
    func testVerifiedPendingPlanEndsApprovalWhileCurrentEntitlementsCatchUp() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        client.purchaseResult = .pending
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
        let lifetime = MembershipTransaction(id: 831, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let requests = client.productRequests; client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.productRequests == requests || !client.finished.contains(lifetime.id) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(1))
        XCTAssertTrue(store.operationMessage?.contains("Purchase verified") == true)
        XCTAssertFalse(store.access.lifetime, "The operation result must not grant access without current verified entitlements")
    }
    func testLifetimeResolutionBeforePendingReplyDoesNotRestorePendingNotice() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<200 where client.purchaseContinuation == nil { await Task.yield() }
        let held = try XCTUnwrap(client.purchaseContinuation)
        let lifetime = MembershipTransaction(id: 841, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.entitlements.append(.verified(lifetime)); let requests = client.productRequests
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.productRequests == requests || !client.finished.contains(lifetime.id) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(1))
        XCTAssertTrue(store.access.lifetime)
        held.resume(returning: .pending); await buying.value
        XCTAssertEqual(store.operationMessage, "Membership is active.")
    }
    func testHeldLifetimeRefreshResolvesPendingRecordedAfterRefreshStarted() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        let monthly = MembershipTransaction(id: 851, appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600))
        client.entitlements = [.verified(monthly)]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<200 where client.purchaseContinuation == nil { await Task.yield() }
        let purchase = try XCTUnwrap(client.purchaseContinuation)
        let lifetime = MembershipTransaction(id: 852, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.deferNextEntitlementRequest = true; client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.deferredEntitlements == nil { await Task.yield() }
        let refresh = try XCTUnwrap(client.deferredEntitlements)
        purchase.resume(returning: .pending); await buying.value
        XCTAssertTrue(store.operationMessage?.contains("pending approval") == true)
        XCTAssertFalse(store.access.lifetime, "A held entitlement response cannot grant access")
        client.entitlements.append(.verified(lifetime)); refresh.resume(returning: client.entitlements); client.deferredEntitlements = nil
        for _ in 0..<200 where !client.finished.contains(lifetime.id) || store.operationMessage != "Membership is active." { await Task.yield() }
        XCTAssertTrue(client.finished.contains(lifetime.id)); XCTAssertTrue(store.access.lifetime)
        XCTAssertEqual(store.operationMessage, "Membership is active.")
    }
    func testVerifiedLifetimeBeforePendingReplyPreservesVerifiedResultWhileEntitlementsLag() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<200 where client.purchaseContinuation == nil { await Task.yield() }
        let purchase = try XCTUnwrap(client.purchaseContinuation)
        let lifetime = MembershipTransaction(id: 861, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where !client.finished.contains(lifetime.id) || store.status != "Membership is active." { await Task.yield() }
        XCTAssertTrue(client.finished.contains(lifetime.id)); XCTAssertFalse(store.access.lifetime)
        purchase.resume(returning: .pending); await buying.value
        XCTAssertTrue(store.operationMessage?.contains("Purchase verified") == true)
        XCTAssertTrue(store.hasAccess); XCTAssertFalse(store.access.lifetime)
    }
    func testCancelledPurchaseKeepsItsOutcomeWhenHeldMatchingRefreshResumes() async throws {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<200 where client.purchaseContinuation == nil { await Task.yield() }
        let purchase = try XCTUnwrap(client.purchaseContinuation)
        let lifetime = MembershipTransaction(id: 871, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.deferNextEntitlementRequest = true; client.continuation.yield(.verified(lifetime))
        for _ in 0..<200 where client.deferredEntitlements == nil { await Task.yield() }
        let refresh = try XCTUnwrap(client.deferredEntitlements)
        purchase.resume(returning: .cancelled); await buying.value
        client.entitlements.append(.verified(lifetime)); refresh.resume(returning: client.entitlements); client.deferredEntitlements = nil
        for _ in 0..<200 where !client.finished.contains(lifetime.id) || !store.access.lifetime { await Task.yield() }
        XCTAssertTrue(client.finished.contains(lifetime.id)); XCTAssertTrue(store.access.lifetime)
        XCTAssertTrue(store.operationMessage?.contains("cancelled") == true)
    }
    func testCurrentVerifiedPendingPlanResolvesOnReloadWithoutStreamReplay() async {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(3600)))]
        client.purchaseResult = .pending
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount); await store.load(); await store.buy(.lifetime)
        client.entitlements.append(.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)))
        await store.load()
        XCTAssertTrue(store.access.lifetime); XCTAssertEqual(store.operationMessage, "Membership is active.")
    }
    func testExplicitRestoreRecoversAttributedPurchaseIntoNewAccountAndRevalidates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = UUID(), b = UUID(), client = MembershipTestClient()
        let now = Date()
        func receipt(expiry: Date = now.addingTimeInterval(3600), revoked: Date? = nil) -> MembershipVerification {
            .verified(.init(id: 45, originalID: 44, appAccountToken: a, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: expiry, revocationDate: revoked))
        }
        client.entitlements = [receipt()]
        let store = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        store.setAccount(b); await store.load()
        XCTAssertFalse(store.hasAccess, "No automatic grant of another account's attributed purchase")
        await store.restore(); XCTAssertTrue(store.hasAccess)
        let reopened = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        reopened.setAccount(b); await reopened.load(); XCTAssertTrue(reopened.hasAccess)
        XCTAssertEqual(client.restoreCount, 1)
        for value in [receipt(expiry: now.addingTimeInterval(-1)), receipt(revoked: now), .unverified(.init(id: 45, originalID: 44, appAccountToken: a, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: now.addingTimeInterval(3600)))] {
            client.entitlements = [value]; await reopened.refreshEntitlements(); XCTAssertFalse(reopened.hasAccess)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Accounts/\(a.uuidString)").path), "Restoring creates no old account data or authentication")
    }

    func testCatalogueFailureStaysSeparateFromVerifiedAccessAndRestoreErrors() async {
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        client.productError = URLError(.notConnectedToInternet)
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.load()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNotNil(store.catalogueError)
        XCTAssertNil(store.accessError)
        client.restoreError = URLError(.cannotConnectToHost)
        await store.restore()
        XCTAssertNotNil(store.accessError, "Purchase, claim and restore errors must remain visible")
    }

    func testExplicitLegacyRestoreSurvivesSameAccountReauthentication() async {
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        store.setAccount(nil)
        XCTAssertFalse(store.hasAccess)
        store.setAccount(testAccount)
        XCTAssertFalse(store.hasAccess, "Saved ownership alone cannot grant access.")
        await store.load()
        XCTAssertTrue(store.hasAccess, "The same account revalidates its explicit claim without another Restore.")
    }

    func testProtectedClaimSurvivesCoordinatorRecreationButNotAnotherAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        store.setAccount(testAccount)
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertEqual(client.restoreCount, 1)
        let file = root.appendingPathComponent("Accounts/\(testAccount.uuidString)/membership-claims.json")
        XCTAssertTrue(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        XCTAssertTrue(try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let relaunched = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        relaunched.setAccount(testAccount)
        XCTAssertFalse(relaunched.hasAccess)
        await relaunched.load()
        XCTAssertTrue(relaunched.hasAccess)
        XCTAssertEqual(client.restoreCount, 1, "Revalidation must not require another Apple sync.")
        relaunched.setAccount(UUID())
        await relaunched.load()
        XCTAssertFalse(relaunched.hasAccess)
        await relaunched.restore()
        XCTAssertTrue(relaunched.hasAccess, "Another account must explicitly restore its own claim.")
        relaunched.setAccount(nil)
        await relaunched.restore()
        XCTAssertFalse(relaunched.hasAccess)
    }

    func testRenewalUsesOriginalIdentityButClaimsNeverReplaceCurrentVerifiedEntitlements() async {
        let now = Date.now
        let client = MembershipTestClient(), claims = MembershipTestClaims()
        func transaction(id: UInt64 = 10, originalID: UInt64 = 9, token: UUID? = nil,
                         productID: String = MembershipPlan.monthly.productID, kind: MembershipProductKind = .autoRenewable,
                         expires: Date? = now.addingTimeInterval(300), revoked: Date? = nil, upgraded: Bool = false) -> MembershipTransaction {
            .init(id: id, originalID: originalID, appAccountToken: token, productID: productID, kind: kind,
                  expirationDate: expires, revocationDate: revoked, isUpgraded: upgraded)
        }
        client.entitlements = [.verified(transaction())]
        let store = MembershipCoordinator(client: client, claims: claims)
        store.setAccount(testAccount)
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        let relaunched = MembershipCoordinator(client: client, claims: claims)
        relaunched.setAccount(testAccount)
        client.entitlements = [.verified(transaction(id: 11))]
        await relaunched.load()
        XCTAssertTrue(relaunched.hasAccess, "Verified renewals retain original-transaction ownership.")
        let rejected: [[MembershipVerification]] = [[], [.unverified(transaction())],
            [.verified(transaction(revoked: now))], [.verified(transaction(expires: now.addingTimeInterval(-1)))],
            [.verified(transaction(upgraded: true))], [.verified(transaction(originalID: 99))],
            [.verified(transaction(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))],
            [.verified(transaction(kind: .nonConsumable))]]
        for current in rejected {
            client.entitlements = current
            await relaunched.refreshEntitlements()
            XCTAssertFalse(relaunched.hasAccess)
        }
    }

    func testRestoreDoesNotPersistUnverifiedRevokedExpiredOrWrongProductReceipts() async throws {
        let client = MembershipTestClient(), claims = MembershipTestClaims()
        let store = MembershipCoordinator(client: client, claims: claims)
        store.setAccount(testAccount)
        client.entitlements = [
            .unverified(.init(id: 1, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)),
            .verified(.init(id: 2, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: .now)),
            .verified(.init(id: 3, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .distantPast)),
            .verified(.init(id: 5, productID: MembershipPlan.lifetime.productID, kind: .autoRenewable)),
            .verified(.init(id: 6, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, isUpgraded: true))]
        await store.restore()
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(try claims.load(accountID: testAccount).isEmpty)
    }

    func testLateRestoreAndLoadCannotAssignClaimsAfterAccountChanges() async throws {
        let client = MembershipTestClient(), claims = MembershipTestClaims()
        let store = MembershipCoordinator(client: client, claims: claims)
        let other = UUID()
        store.setAccount(testAccount)
        client.deferRestore = true
        let restoring = Task { await store.restore() }
        for _ in 0..<100 where client.restoreContinuation == nil { await Task.yield() }
        XCTAssertNotNil(client.restoreContinuation)
        store.setAccount(other)
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        client.restoreContinuation?.resume()
        await restoring.value
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(try claims.load(accountID: testAccount).isEmpty)
        XCTAssertTrue(try claims.load(accountID: other).isEmpty)
        client.deferRestore = false
        store.setAccount(testAccount)
        await store.restore()
        client.deferNextEntitlementRequest = true
        let loading = Task { await store.load() }
        for _ in 0..<100 where client.deferredEntitlements == nil { await Task.yield() }
        XCTAssertNotNil(client.deferredEntitlements)
        store.setAccount(nil)
        store.setAccount(testAccount)
        client.deferredEntitlements?.resume(returning: client.entitlements)
        await loading.value
        XCTAssertFalse(store.hasAccess, "Even an A→signed-out→A transition invalidates the old callback.")
        await store.load()
        XCTAssertTrue(store.hasAccess)
    }

    func testClaimPersistenceFailureIsVisibleAndRetryDoesNotGrantFromMemory() async {
        let client = MembershipTestClient(), claims = MembershipTestClaims()
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: claims)
        store.setAccount(testAccount)
        claims.writeError = CocoaError(.fileWriteNoPermission)
        await store.restore()
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(store.error?.contains("saved") == true)
        XCTAssertFalse(store.busy)
        claims.writeError = nil
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.error)
        claims.readError = CocoaError(.fileReadCorruptFile)
        await store.load()
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(store.error?.contains("Restore") == true)
        claims.readError = nil
        await store.load()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.error)
    }

    func testBlockedProtectedDirectoryReportsFailedSaveAndRecoversOnExplicitRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("existing file must not be replaced".utf8)
        try original.write(to: root)
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        store.setAccount(testAccount)
        await store.restore()
        XCTAssertFalse(store.hasAccess)
        XCTAssertTrue(store.error?.contains("saved") == true)
        XCTAssertEqual(try Data(contentsOf: root), original)
        try FileManager.default.removeItem(at: root)
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.error)
    }

    func testMissingCorruptAndWrongAccountFilesFailClosedAndExplicitRestoreRepairsClaim() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        store.setAccount(testAccount)
        await store.load()
        XCTAssertFalse(store.hasAccess)
        XCTAssertNil(store.error)
        let file = root.appendingPathComponent("Accounts/\(testAccount.uuidString)/membership-claims.json")
        let corrupt = Data("broken claim metadata".utf8)
        try ProtectedLocalStorage.write(corrupt, to: file)
        await store.load()
        XCTAssertFalse(store.hasAccess)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try Data(contentsOf: file), corrupt, "Automatic load must not erase damaged metadata.")
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.error)
        let other = UUID(), copied = root.appendingPathComponent("Accounts/\(other.uuidString)/membership-claims.json")
        try ProtectedLocalStorage.write(Data(contentsOf: file), to: copied)
        store.setAccount(other)
        await store.load()
        XCTAssertFalse(store.hasAccess, "An account directory cannot adopt another account's saved envelope.")
        XCTAssertNotNil(store.error)
    }

    func testSignedOutCannotUseUnattributedAppleEntitlements() async {
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        await store.load()
        XCTAssertFalse(store.hasAccess)
    }

    func testAccountSwitchRejectsLatePurchaseAndRequiresExplicitLegacyRestore() async {
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£200")]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.load()
        client.deferPurchase = true
        let buying = Task { await store.buy(.lifetime) }
        for _ in 0..<100 where client.purchaseContinuation == nil { await Task.yield() }
        XCTAssertEqual(client.purchaseTokens, [testAccount])
        store.setAccount(UUID())
        XCTAssertTrue(store.busy, "A pending Apple checkout still owns the operation until it returns.")
        let old = MembershipTransaction(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.entitlements = [.verified(old)]
        client.purchaseContinuation?.resume(returning: .completed(.verified(old)))
        await buying.value
        XCTAssertFalse(store.busy)
        XCTAssertFalse(store.hasAccess)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
        let legacy = MembershipVerification.verified(.init(id: 97, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))
        client.entitlements = [legacy]
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
        await store.restore()
        XCTAssertTrue(store.hasAccess)
        store.setAccount(UUID())
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
        store.setAccount(nil)
        await store.restore()
        XCTAssertFalse(store.hasAccess)
        let count = client.purchases.count
        await store.buy(.lifetime)
        XCTAssertEqual(client.purchases.count, count)
    }

    func testVerifiedExpiredRevokedAndGraceStatesRemainDistinct() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        let now = Date.now
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: now.addingTimeInterval(-10), gracePeriodExpirationDate: now.addingTimeInterval(30)))]
        await store.refreshEntitlements()
        XCTAssertEqual(store.condition, .gracePeriod)
        XCTAssertTrue(store.hasAccess)
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: now.addingTimeInterval(-10)))]
        await store.refreshEntitlements()
        XCTAssertEqual(store.condition, .expired)
        XCTAssertFalse(store.hasAccess)
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: now))]
        await store.refreshEntitlements()
        XCTAssertEqual(store.condition, .revoked)
        XCTAssertFalse(store.hasAccess)
        client.entitlements = [.unverified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: now))]
        await store.refreshEntitlements()
        XCTAssertEqual(store.condition, .none)
    }

    func testStoreOutageDoesNotRemoveVerifiedLifetimeAndNeverShowsInventedPrices() async {
        let client = MembershipTestClient()
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        client.productError = URLError(.notConnectedToInternet)
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.load()
        XCTAssertTrue(store.hasAccess)
        XCTAssertTrue(store.offers.isEmpty)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.busy)
    }

    func testCheckoutCancellationPendingAndUnverifiedPurchaseCannotUnlock() async {
        let forged = MembershipTransaction(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let cases: [(MembershipPurchaseResult, String, Bool)] = [
            (.cancelled, "cancelled", false), (.pending, "pending", false),
            (.completed(.unverified(forged)), "verified", true)
        ]
        for (result, message, expectsError) in cases {
            let client = MembershipTestClient()
            client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "€240.00")]
            client.purchaseResult = result
            let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
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
        let lifetime = MembershipTransaction(id: 42, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        let client = MembershipTestClient()
        client.availableOffers = [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "€240.00")]
        client.purchaseResult = .completed(.verified(lifetime))
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
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
        wrongClient.purchaseResult = .completed(.verified(.init(id: 44, appAccountToken: testAccount, productID: "other.product", kind: .nonConsumable)))
        let wrongStore = MembershipCoordinator(client: wrongClient, claims: MembershipTestClaims())
        wrongStore.setAccount(testAccount)
        await wrongStore.load()
        await wrongStore.buy(.lifetime)
        XCTAssertFalse(wrongStore.hasAccess)
        XCTAssertNotNil(wrongStore.error)
        XCTAssertTrue(wrongClient.finished.isEmpty)
    }

    func testRestoreRefreshesVerifiedOwnershipWithoutCreatingOrExtendingATrial() async {
        var now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(20)
        let monthly = MembershipTransaction(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: deadline)
        let client = MembershipTestClient()
        client.restoredEntitlements = [.verified(monthly)]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims(), now: { now })
        store.setAccount(testAccount)
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
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.completeRedemption(.success(()))
        XCTAssertFalse(store.hasAccess)
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))]
        await store.completeRedemption(.success(()))
        XCTAssertTrue(store.hasAccess)
        await store.completeRedemption(.failure(URLError(.cancelled)))
        XCTAssertTrue(store.hasAccess)
        XCTAssertNotNil(store.error)
    }

    func testTransactionUpdatesRefreshPendingApprovalAndRefundAndFinishVerifiedKnownProducts() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
        let lifetime = MembershipTransaction(id: 55, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable)
        client.entitlements = [.verified(lifetime)]
        client.continuation.yield(.verified(lifetime))
        for _ in 0..<100 where !store.hasAccess { await Task.yield() }
        XCTAssertTrue(store.hasAccess)
        for _ in 0..<100 where client.finished.isEmpty { await Task.yield() }
        XCTAssertEqual(client.finished, [55])
        client.entitlements = []
        client.continuation.yield(.verified(.init(id: 55, appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable, revocationDate: .now)))
        for _ in 0..<100 where store.hasAccess { await Task.yield() }
        XCTAssertFalse(store.hasAccess)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasAccess)
    }

    func testSubscriptionDeadlineRefreshesVisibleMembershipWithoutAPurchaseOrRelaunch() async throws {
        let client = MembershipTestClient()
        let deadline = Date.now.addingTimeInterval(0.05)
        client.entitlements = [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: deadline))]
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
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
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        await store.load()
        XCTAssertEqual(store.offers.first?.eligibleTrialDays, 14)
        client.availableOffers = [.init(plan: .monthly, displayName: "Monthly", displayPrice: "£10.00")]
        let transaction = MembershipTransaction(id: 67, appAccountToken: testAccount, productID: MembershipPlan.monthly.productID, kind: .autoRenewable, expirationDate: .now.addingTimeInterval(200))
        client.purchaseResult = .completed(.verified(transaction))
        client.purchaseEntitlements = [.verified(transaction)]
        await store.buy(.monthly)
        XCTAssertTrue(store.hasAccess)
        XCTAssertNil(store.offers.first?.eligibleTrialDays)
    }

    func testOlderEntitlementRefreshCannotOverwriteANewerRefundResult() async {
        let client = MembershipTestClient()
        let store = MembershipCoordinator(client: client, claims: MembershipTestClaims())
        store.setAccount(testAccount)
        client.deferNextEntitlementRequest = true
        let older = Task { await store.refreshEntitlements() }
        for _ in 0..<100 where client.deferredEntitlements == nil { await Task.yield() }
        XCTAssertNotNil(client.deferredEntitlements)
        await store.refreshEntitlements()
        client.deferredEntitlements?.resume(returning: [.verified(.init(appAccountToken: testAccount, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))])
        await older.value
        XCTAssertFalse(store.hasAccess)
    }
}

@MainActor
private final class MembershipTestClient: MembershipClient {
    var entitlements: [MembershipVerification] = []
    var availableOffers: [MembershipOffer] = []
    var productError: Error?
    var productRequests = 0
    var purchaseResult: MembershipPurchaseResult = .cancelled
    var purchaseError: Error?
    var purchaseEntitlements: [MembershipVerification]?
    var restoredEntitlements: [MembershipVerification]?
    var restoreError: Error?
    var restoreCount = 0
    var deferRestore = false
    var restoreContinuation: CheckedContinuation<Void, Never>?
    var purchases: [MembershipPlan] = []
    var purchaseTokens: [UUID] = []
    var deferPurchase = false
    var purchaseContinuation: CheckedContinuation<MembershipPurchaseResult, Never>?
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
        productRequests += 1
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
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult {
        purchases.append(plan)
        purchaseTokens.append(appAccountToken)
        if deferPurchase { return await withCheckedContinuation { purchaseContinuation = $0 } }
        if let purchaseError { throw purchaseError }
        if let purchaseEntitlements { entitlements = purchaseEntitlements }
        return purchaseResult
    }
    func restore() async throws {
        restoreCount += 1
        if deferRestore { await withCheckedContinuation { restoreContinuation = $0 } }
        if let restoreError { throw restoreError }
        if let restoredEntitlements { entitlements = restoredEntitlements }
    }
    func finish(transactionID: UInt64) async { finished.append(transactionID) }
}

@MainActor
private final class MembershipTestClaims: MembershipClaimStore {
    private var saved: [UUID: Set<MembershipClaim>] = [:]
    var readError: Error?
    var writeError: Error?
    func load(accountID: UUID) throws -> Set<MembershipClaim> {
        if let readError { throw readError }
        return saved[accountID] ?? []
    }
    func save(_ claims: Set<MembershipClaim>, accountID: UUID) throws {
        if let writeError { throw writeError }
        saved[accountID] = claims
    }
}
