import XCTest
import SwiftUI
import UIKit
import Vision
@testable import Spottr

@MainActor final class CoachPolishRenderedTests: XCTestCase {
    private var window: UIWindow?
    private var original: UIViewController?
    private var hidden = false
    private var level = UIWindow.Level.normal
    private var roots: [URL] = []
    override func tearDown() {
        window?.rootViewController = original; window?.windowLevel = level; window?.isHidden = hidden; window?.makeKey()
        roots.forEach { try? FileManager.default.removeItem(at: $0) }; roots = []
        window = nil; original = nil; super.tearDown()
    }
    private func workspace(age: Int = 30) throws -> AccountWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); roots.append(root)
        let scope = AccountDataScope(accountID: UUID(), profileID: UUID(), root: root)
        let profile = try LocalProfile(name: "Alex", bodyMeasurements: age >= 18 ? .init(heightCM: 170, weightKG: 70) : nil,
            onboardingRevision: TrainingSetup.revision, programmePreferences: .init(goals: [.strength, .balance], weekdays: Set(1...7), availableSupport: Set(PathSurvey.equipmentChoices), startingPoint: .startingOut,
                ageContext: .init(ageYears: age, guardianManaged: age < 18), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) })))
        try NativeProfileStore(url: scope.file("profile.json")).save(profile)
        let w = try AccountWorkspace(scope: scope)
        try w.programme.prepare(profile: profile, history: [])
        return w
    }
    func testCoachNormalShowsActualPlanAndAllActions() async throws { try await coach(age: 30, size: .large) }
    func testCoachLargeShowsActualPlanAndAllActions() async throws { try await coach(age: 30, size: .accessibility2) }
    func testCoachJuniorShowsSafePlanAndAllActions() async throws { try await coach(age: 12, size: .large) }
    private func coach(age: Int, size: DynamicTypeSize) async throws {
        let w = try workspace(age: age)
        let window = try await host(OfflineCoachView(store: w.training, profileStore: w.profile).dynamicTypeSize(size), workspace: w)
        let text = try await inspect(window, name: "coach-\(age)-\(size)")
        for title in ["Make it easier", "Shorten this workout", "Swap a movement", "Move training day", "Take a recovery day", "Review progress"] {
            XCTAssertTrue(text.contains { $0.contains(title) }, title)
        }
        XCTAssertTrue(w.training.history.isEmpty)
    }
    func testTrainerLargeHasVisibleStopAndMuteControls() async throws {
        let w = try workspace()
        let view = VoiceCoachSettingsView(previews: try XCTUnwrap(w.training.voicePreviews), repVoice: w.training.repVoice).dynamicTypeSize(.accessibility2)
        let window = try await host(view, workspace: w)
        let text = try await inspect(window, name: "trainer-large")
        for title in ["Stop preview", "Preview selections", "Maya", "Leo", "Goggins", "Local voice"] { XCTAssertTrue(text.contains { $0.contains(title) }, title) }
    }
    func testTodayPartialProgressKeepsActualCountsWithNaturalCopy() async throws {
        let w = try workspace(), day = try XCTUnwrap(w.programme.day())
        let repFirst = try CoachSavedPlan(items: day.plan!.items.sorted { $0.unit == .reps && $1.unit != .reps }, availableSupport: Set(PathSurvey.equipmentChoices), createdAt: day.date, rationale: "Rep-first partial-work fixture")
        w.training.beginAuthorizedPlan(repFirst, availableSupport: Set(PathSurvey.equipmentChoices), plannedWorkoutID: day.id)
        w.training.beginConfiguredSet(); w.training.setConfiguredReps(3); w.training.endSet(); w.training.finish()
        let window = try await host(TodayView(store: w.training, profileStore: w.profile, showSettings: {}), workspace: w)
        let text = try await inspect(window, name: "today-partial")
        XCTAssertTrue(text.contains { $0.contains("3 actual reps") })
        assertNaturalCopy(text)
    }
    func testSkillsLargeAndRewardControlsUseNaturalCopy() async throws {
        let w = try workspace()
        let window = try await host(PathSkillsView(store: w.training, profile: w.profile.profile).dynamicTypeSize(.accessibility2), workspace: w)
        let text = try await inspect(window, name: "skills-large")
        XCTAssertTrue(text.contains { $0.contains("Jump to current") })
        assertNaturalCopy(text)
    }
    func testJuniorReportKeepsUnratedWorkAndNoHealth() async throws {
        let w = try workspace(age: 12)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 3, restSeconds: 60)
        w.training.beginAuthorizedPlan(plan, availableSupport: [], trainingContext: w.programme.capture(dayID: nil))
        w.training.beginConfiguredSet(); w.training.setConfiguredReps(2); w.training.endSet(); w.training.finish()
        let record = try XCTUnwrap(w.training.history.first)
        let window = try await host(SessionReportView(record: record, profile: w.profile.profile), workspace: w)
        let text = try await inspect(window, name: "report-junior")
        XCTAssertTrue(text.contains { $0.contains("Unrated") })
        XCTAssertFalse(text.contains { $0.contains("Watch heart rate") })
        assertNaturalCopy(text)
    }
    func testRestLargeKeepsRealReasonAndUnratedControls() async throws {
        let w = try workspace(age: 12)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 3, restSeconds: 60)
        w.training.beginAuthorizedPlan(plan, availableSupport: [])
        w.training.beginConfiguredSet(); w.training.setConfiguredReps(2); w.training.endSet()
        let window = try await host(ConfiguredSessionView(store: w.training).dynamicTypeSize(.accessibility2), workspace: w)
        let text = try await inspect(window, name: "rest-large")
        XCTAssertTrue(text.contains { $0.contains("Unrated") })
        assertNaturalCopy(text)
    }
    func testFamilyLargeHasWrappingHeadingAndAgeAppropriateProgress() async throws {
        let w = try workspace(age: 4)
        let window = try await host(FamilyMovementView(workspace: w, authorization: AuthenticationServicesAccountAuthorization()).dynamicTypeSize(.accessibility2), workspace: w)
        let text = try await inspect(window, name: "family-large")
        XCTAssertTrue(text.contains { $0.contains("Family movement") })
        XCTAssertFalse(text.contains { $0.contains("bonus window") })
        assertNaturalCopy(text)
    }
    func testSavedProgrammeUsesDeliberateShareAndPasteReviewFlow() async throws {
        let w = try workspace()
        let sync = ProgrammeSyncStore(programme: w.programme, profile: w.profile, client: PolishCloudClient(), isCurrent: { true }, hasOngoingWorkout: { false })
        try sync.consent()
        let window = try await host(NavigationStack { ProgrammeSyncView(sync: sync) }, workspace: w)
        let text = try await inspect(window, name: "saved-programme")
        XCTAssertTrue(text.contains { $0.contains("Share programme code") })
        XCTAssertTrue(text.contains { $0.contains("Enter a saved programme code") })
        XCTAssertFalse(text.contains { $0.contains(sync.profileSlot.uuidString.lowercased()) })
        XCTAssertFalse(text.contains { $0.contains("Plan sync enabled") || $0.contains("upload its configuration") })
        assertNaturalCopy(text)
    }
    func testGogginsSettingsExplainRecordedStyleAndFormCoverage() async throws {
        let w = try workspace()
        try w.training.remoteVoice?.configureSelection(.david, tone: .direct)
        let window = try await host(VoiceCoachSettingsView(previews: try XCTUnwrap(w.training.voicePreviews)), workspace: w)
        let text = try await inspect(window, name: "goggins-coverage")
        XCTAssertTrue(text.contains { $0.contains("Recorded style") })
        XCTAssertFalse(text.contains { $0.contains("Style changes encouragement") })
        XCTAssertTrue(text.contains { $0.contains("Form and stop instructions appear on screen") })
    }
    func testDayReportsKeepDistinctActualSessionCards() async throws {
        let w = try workspace()
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(60)
        let records: [SessionRecord] = (0..<3).map { index in
            .init(id: UUID(), date: date.addingTimeInterval(Double(index * 20)), sets: [], loggedSets: [.init(id: UUID(), exerciseID: "frontArmRaise", reps: index + 1, seconds: 0, source: .manual, reason: .voluntary)])
        }
        let window = try await host(NavigationStack { ScrollView { DayDetail(date: date, records: records, profile: w.profile.profile, history: records) } }, workspace: w)
        let text = try await inspect(window, name: "distinct-session-cards")
        let visible = try renderedText(window)
        for record in records { XCTAssertTrue(visible.contains(record.date.formatted(.dateTime.hour().minute().second())), visible) }
        XCTAssertTrue(visible.contains("1 set and 1 recorded rep"), visible)
        assertNaturalCopy(text)
    }
    func testVideoReviewCardNeverCountsAsCameraOrManualPractice() async throws {
        let w = try workspace(), date = Date()
        let record = SessionRecord(id: UUID(), date: date, sets: [], loggedSets: [.init(id: UUID(), exerciseID: "frontArmRaise", reps: 7, seconds: 0, source: .video, reason: .voluntary)])
        let window = try await host(NavigationStack { ScrollView { DayDetail(date: date, records: [record], profile: w.profile.profile, history: [record]) } }, workspace: w)
        _ = try await inspect(window, name: "video-review-card")
        let visible = try renderedText(window)
        XCTAssertTrue(visible.contains("Video review"), visible)
        XCTAssertTrue(visible.contains("7 reviewed reps"), visible)
        XCTAssertFalse(visible.contains("Manual") || visible.contains("Camera"), visible)
        XCTAssertEqual(TrainingDashboard(history: [record]).totalReps, 0)
    }
    func testWatchSharingCopyKeepsOffSeparateFromModelChoice() async throws {
        let w = try workspace()
        let window = try await host(NavigationStack { WatchSetupView().environment(\.watchSharing, w.watchSharing) }, workspace: w)
        let text = try await inspect(window, name: "watch-sharing")
        XCTAssertFalse(text.contains { $0.contains("model choice is kept separately") })
        XCTAssertFalse(w.watchSharing.enabled)
    }
    func testOnlyMembershipOfferIsSelectedAndCatalogueFailureDoesNotHideAccess() async throws {
        let w = try workspace(), client = PolishMembershipClient()
        let membership = MembershipStore(root: roots.last!, client: client)
        membership.setAccount(w.scope.accountID)
        await membership.load()
        let window = try await host(NavigationStack { MembershipView(store: membership) }, workspace: w)
        let text = try await inspect(window, name: "membership-only-offer")
        XCTAssertFalse(text.contains { $0.contains("Prices and eligible trials are supplied") })
        XCTAssertTrue(elements(window).contains { $0.accessibilityTraits.contains(.selected) && ($0.accessibilityLabel?.contains("Lifetime") == true) })
    }
    func testLoadedOffersKeepPendingAndCancelledPurchaseOutcomesVisible() async throws {
        let w = try workspace(), client = PolishMembershipClient()
        let store = MembershipStore(root: roots.last!, client: client); store.setAccount(w.scope.accountID)
        let window = try await host(NavigationStack { MembershipView(store: store) }, workspace: w)
        XCTAssertFalse(store.offers.isEmpty)
        client.purchaseResult = .pending; await store.buy(.lifetime)
        XCTAssertNil(store.accessError); XCTAssertFalse(store.hasAccess)
        var text = try await inspect(window, name: "membership-pending")
        XCTAssertTrue(text.contains { $0.contains("Purchase is pending approval. Access has not changed.") })
        client.purchaseResult = .cancelled; await store.buy(.lifetime)
        text = try await inspect(window, name: "membership-cancelled")
        XCTAssertTrue(text.contains { $0.contains("Purchase cancelled. Access has not changed.") })
    }
    func testLoadedOffersKeepNoAccessRestoreOutcomeVisible() async throws {
        let w = try workspace(), store = MembershipStore(root: roots.last!, client: PolishMembershipClient())
        store.setAccount(w.scope.accountID)
        let window = try await host(NavigationStack { MembershipView(store: store) }, workspace: w)
        await store.restore()
        XCTAssertFalse(store.offers.isEmpty); XCTAssertFalse(store.hasAccess); XCTAssertNil(store.accessError)
        let text = try await inspect(window, name: "membership-restore-outcome")
        XCTAssertTrue(text.contains { $0.contains("No active membership for this account. Sign in and restore a previous Apple purchase.") })
    }
    func testLoadedOffersKeepRedemptionFollowUpVisible() async throws {
        let w = try workspace(), store = MembershipStore(root: roots.last!, client: PolishMembershipClient())
        store.setAccount(w.scope.accountID)
        let window = try await host(NavigationStack { MembershipView(store: store) }, workspace: w)
        await store.completeRedemption(.success(()))
        XCTAssertFalse(store.offers.isEmpty); XCTAssertFalse(store.hasAccess); XCTAssertNil(store.accessError)
        let text = try await inspect(window, name: "membership-redemption-outcome")
        XCTAssertTrue(text.contains { $0.contains("If Apple completed your redemption, use Restore purchases to verify it for this account.") })
    }
    private func host<V: View>(_ content: V, workspace: AccountWorkspace) async throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; original = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        window.rootViewController = UIHostingController(rootView: content.id(ObjectIdentifier(workspace)))
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
        return window
    }
    private func inspect(_ window: UIWindow, name: String) async throws -> Set<String> {
        var all = Set<String>()
        for index in 0..<14 {
            window.layoutIfNeeded()
            all.formUnion(elements(window).compactMap(\.accessibilityLabel))
            if index == 0 || index == 2 || index == 5 { capture(window, "\(name)-\(index)") }
            guard let scroll = elements(window).compactMap({ $0 as? UIScrollView }).first(where: { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 }) else { break }
            let maximum = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let next = min(maximum, scroll.contentOffset.y + scroll.bounds.height * 0.65)
            if next <= scroll.contentOffset.y { capture(window, "\(name)-bottom"); break }
            scroll.setContentOffset(.init(x: 0, y: next), animated: false)
            try await Task.sleep(for: .milliseconds(150))
        }
        return all
    }
    private func assertNaturalCopy(_ text: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        let prohibited = text.filter { $0.contains(" · ") || $0.contains("Optional:") || $0.contains("Effort:") || $0.contains("Next bonus window:") || $0.contains("count; rest") }
        XCTAssertTrue(prohibited.isEmpty, prohibited.sorted().joined(separator: " | "), file: file, line: line)
    }
    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return }
            result.append(value); (value as? UIView)?.subviews.forEach(visit)
            value.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = value.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    // A plain ScrollView hosting DayDetail does not export its SwiftUI children to this
    // in-process AX walker. Verify the actual rendered screen, not an empty text set.
    private func renderedText(_ window: UIWindow) throws -> String {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private struct PolishCloudClient: ProgrammeCloudClient {
    func writePlan(_ request: ProgrammeWriteRequest) async throws -> ProgrammeWriteReply { throw URLError(.notConnectedToInternet) }
    func readPlan(_ request: ProgrammeReadRequest) async throws -> ProgrammeReadReply { throw URLError(.notConnectedToInternet) }
    func withdrawPlan(_ request: ProgrammeWithdrawRequest) async throws -> ProgrammeWithdrawReply { throw URLError(.notConnectedToInternet) }
}

@MainActor private final class PolishMembershipClient: MembershipClient {
    var purchaseResult: MembershipPurchaseResult = .cancelled
    func products() async throws -> [MembershipOffer] { [.init(plan: .lifetime, displayName: "Lifetime", displayPrice: "£87.99", eligibleTrialDays: nil)] }
    func currentEntitlements() async -> [MembershipVerification] { [] }
    func updates() -> AsyncStream<MembershipVerification> { AsyncStream { $0.finish() } }
    func purchase(_ plan: MembershipPlan, appAccountToken: UUID) async throws -> MembershipPurchaseResult { purchaseResult }
    func restore() async throws {}
    func finish(transactionID: UInt64) async {}
}
