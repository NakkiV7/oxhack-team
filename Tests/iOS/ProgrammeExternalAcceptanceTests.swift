import XCTest
import SwiftUI
import UIKit
@testable import Spottr

@MainActor final class ProgrammeExternalAcceptanceTests: XCTestCase {
    private var originalWindow: UIWindow?
    private var originalController: UIViewController?
    private var originalHidden = false
    private var originalLevel = UIWindow.Level.normal
    override func tearDown() {
        originalWindow?.rootViewController = originalController; originalWindow?.windowLevel = originalLevel
        originalWindow?.isHidden = originalHidden; originalWindow?.makeKey()
        originalWindow = nil; originalController = nil; super.tearDown()
    }
    func testExternalWholeWorkoutCameraManualEffortAndFinished() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let workspace = try AccountWorkspace(scope: scope)
        try workspace.profile.save(LocalProfile(name: "Alex", bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.strength], weekdays: Set(1...7), startingPoint: .startingOut,
                ageContext: .init(ageYears: 30, guardianManaged: false), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))))
        let week = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        let today = try XCTUnwrap(workspace.programme.day())
        XCTAssertEqual(today.plan?.items.first?.unit, .reps)
        let client = ProgrammeRenderedMembershipClient(accountID: scope.accountID)
        let membership = MembershipCoordinator(client: client, claims: ProtectedMembershipClaimStore(root: root))
        membership.setAccount(scope.accountID); await membership.refreshEntitlements()
        let generation = UUID()
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
            owner: { .init(accountID: scope.accountID, profileID: scope.profileID) }, generation: { generation })
        workspace.launch = launch; workspace.training.launchCoordinator = launch
        let window = try host(SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: workspace.health).id(ObjectIdentifier(workspace)))
        try await Task.sleep(for: .milliseconds(700)); capture(window, "whole-today-before-start")
        print("PROGRAMME_OS_REDUCE_MOTION \(UIAccessibility.isReduceMotionEnabled)")
        try await wait { workspace.training.configured != nil }
        XCTAssertEqual(workspace.training.configured?.steps.count, today.plan?.items.reduce(0) { $0 + $1.sets })
        XCTAssertEqual(workspace.training.configured?.plannedWorkoutID, today.id)
        XCTAssertEqual(workspace.training.configured?.trainingContext?.programmeRevision, week.revision)
        XCTAssertFalse(workspace.training.configured?.hasStarted == true)
        XCTAssertNil(workspace.training.configured?.actualReps)
        try await Task.sleep(for: .milliseconds(600)); capture(window, "whole-workout-ready")
        try await wait { workspace.training.configuredInput == .phoneCamera && workspace.training.configured?.hasStarted == true }
        XCTAssertEqual(workspace.training.configured?.actualReps, 0)
        try await Task.sleep(for: .seconds(1)); capture(window, "camera-active-zero-actual")
        try await wait { workspace.training.configuredInput == .manual && workspace.training.configured?.actualReps == 3 }
        capture(window, "manual-active-three-actual")
        try await wait { workspace.training.configured?.phase == .rest }
        XCTAssertEqual(workspace.training.configured?.completed.first?.reps, 3)
        XCTAssertNil(workspace.training.configured?.completed.first?.effort)
        capture(window, "automatic-rest-unrated")
        try await wait { workspace.training.configured?.completed.first?.effort == .hard }
        capture(window, "rest-effort-eight")
        try await wait(seconds: 120) { workspace.training.configured?.index == 1 && workspace.training.configured?.phase == .active }
        XCTAssertFalse(workspace.training.configured?.hasStarted == true)
        XCTAssertNil(workspace.training.configured?.actualReps)
        capture(window, "rest-ended-next-ready")
        try await wait { workspace.training.configured?.phase == .finished }
        XCTAssertEqual(workspace.training.history.count, 1)
        XCTAssertEqual(workspace.training.history.first?.plannedWorkoutID, today.id)
        XCTAssertEqual(workspace.training.history.first?.trainingContext?.owner, .init(accountID: scope.accountID, profileID: scope.profileID))
        XCTAssertEqual(workspace.training.history.first?.loggedSets.first?.effort, .hard)
        XCTAssertEqual(workspace.training.history.first?.loggedSets.first?.source, .manual)
        XCTAssertEqual(workspace.training.history.first?.loggedSets.first?.quantityOrigin, .selfReport)
        XCTAssertEqual(workspace.training.history.first?.reps, 3)
        let actual = ProgrammeInsights.progress(week: week, history: workspace.training.history).first { $0.id == today.id }
        XCTAssertEqual(actual?.recordedSets, 1); XCTAssertEqual(actual?.recordedReps, 3); XCTAssertEqual(actual?.completed, false)
        capture(window, "whole-workout-finished-actual")
        try await wait { !workspace.training.presented }
        capture(window, "today-after-real-save")
        try await Task.sleep(for: .seconds(8))
    }
    private func host<V: View>(_ view: V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        originalWindow = window; originalController = window.rootViewController; originalHidden = window.isHidden; originalLevel = window.windowLevel
        window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible(); return window
    }
    private func wait(seconds: Int = 120, until predicate: () -> Bool) async throws {
        for _ in 0..<(seconds * 5) { if predicate() { return }; try await Task.sleep(for: .milliseconds(200)) }
        XCTFail("Actual public control did not reach the expected state"); throw CocoaError(.userCancelled)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        print("PROGRAMME_RENDER_READY \(name)")
    }
}

@MainActor private final class ProgrammeRenderedMembershipClient: MembershipClient {
    let accountID: UUID
    init(accountID: UUID) { self.accountID = accountID }
    func products() async throws -> [MembershipOffer] { [] }
    func currentEntitlements() async -> [MembershipVerification] { [.verified(.init(appAccountToken: accountID, productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}
