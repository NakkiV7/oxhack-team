import XCTest
import SwiftUI
import UIKit
@testable import Spottr

@MainActor final class ProgrammeRenderedTests: XCTestCase {
    private var window: UIWindow?
    private var controller: UIViewController?
    private var hidden = false
    private var level = UIWindow.Level.normal
    override func tearDown() {
        window?.rootViewController = controller; window?.isHidden = hidden; window?.windowLevel = level; window?.makeKey()
        window = nil; controller = nil; super.tearDown()
    }
    func testWholeTodayShowsPersistedMovesAndNoDefaultSquatPicker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(profile(age: 30))
        let week = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        let expired = try ProgrammePlanner.makeWeek(profile: XCTUnwrap(workspace.profile.profile), history: [], start: Date().addingTimeInterval(-14 * 86400))
        try workspace.programme.restore(expired, profile: XCTUnwrap(workspace.profile.profile))
        let window = try host(TodayView(store: workspace.training, profileStore: workspace.profile, showSettings: {}))
        try await waitForContent(window, containing: "Your whole workout")
        capture(window, "today-populated")
        let labels = elements(window).compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains("Your whole workout"))
        XCTAssertFalse(labels.contains("Start with Squats"))
        for item in try XCTUnwrap(week.days.first?.plan?.items) {
            XCTAssertTrue(labels.contains { $0.contains(ExerciseCatalog.find(item.exerciseID)!.name) })
        }
        XCTAssertEqual(workspace.programme.current, week)
        XCTAssertEqual(workspace.programme.day()?.id, week.days.first?.id)
        XCTAssertTrue(workspace.training.history.isEmpty)
    }
    func testEmptyFamilyRestAndLargeTextRenderWithoutFormalFamilySets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let window = try host(TodayView(store: workspace.training, profileStore: workspace.profile, showSettings: {}).dynamicTypeSize(.accessibility2))
        try await waitForContent(window, containing: "Prepare your week"); capture(window, "today-empty-large")
        XCTAssertTrue(elements(window).compactMap(\.accessibilityLabel).contains("Prepare your week"))
        try workspace.profile.save(profile(age: 3))
        _ = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        window.rootViewController = UIHostingController(rootView: FamilyMovementView(workspace: workspace, authorization: AuthenticationServicesAccountAuthorization()).dynamicTypeSize(.accessibility2))
        try await waitForContent(window, containing: "Move and play together"); capture(window, "today-family-large")
        XCTAssertTrue(elements(window).compactMap(\.accessibilityLabel).contains("Move and play together"))
        XCTAssertTrue(workspace.programme.current?.days.allSatisfy { $0.plan == nil } == true)
    }
    func testRestDayAndRecordedInsightsUseRealData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let weekday = (Calendar.current.component(.weekday, from: tomorrow) + 5) % 7 + 1
        try workspace.profile.save(LocalProfile(bodyMeasurements: .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.balance], weekdays: [weekday], ageContext: .init(ageYears: 30, guardianManaged: false))))
        _ = try workspace.programme.prepare(profile: XCTUnwrap(workspace.profile.profile), history: [])
        let window = try host(TodayView(store: workspace.training, profileStore: workspace.profile, showSettings: {}))
        try await waitForContent(window, containing: "Time to recover"); capture(window, "today-rest")
        XCTAssertTrue(elements(window).compactMap(\.accessibilityLabel).contains("Time to recover"))
        XCTAssertFalse(elements(window).contains { ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == "today-start-session" })
        let dated = Date().addingTimeInterval(-86400)
        try workspace.programme.recordWeight(kilograms: 73.2, date: dated)
        let set = LoggedSet(id: UUID(), exerciseID: "frontArmRaise", reps: 3, seconds: 0, source: .manual, reason: .voluntary, effort: .easy)
        workspace.training.persist(.init(id: UUID(), date: dated, sets: [], loggedSets: [set]))
        window.rootViewController = UIHostingController(rootView: ScrollView { ProgrammeInsightsSection(store: workspace.training, profile: workspace.profile.profile) })
        try await waitForContent(window, containing: "Your recorded weight"); capture(window, "insights-dated-weight-actual-effort")
        let labels = elements(window).compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains("Your recorded weight"))
        XCTAssertTrue(labels.contains { $0.contains("73.2") })
        XCTAssertTrue(labels.contains { $0.contains("4 · Easy") })
        XCTAssertEqual(workspace.programme.weights.first?.date, dated)
    }
    func testLargeWorkoutRestShowsUnratedAndJuniorReportOmitsHealth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        try workspace.profile.save(profile(age: 12))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "frontArmRaise", sets: 1, target: 3, restSeconds: 60)
        workspace.training.beginAuthorizedPlan(plan, availableSupport: [], trainingContext: workspace.programme.capture(dayID: nil))
        workspace.training.beginConfiguredSet(); workspace.training.setConfiguredReps(2); workspace.training.endSet()
        let window = try host(ConfiguredSessionView(store: workspace.training).dynamicTypeSize(.accessibility2))
        try await waitForContent(window, containing: "How did this set feel?")
        try await scrollToContent(window, label: "Unrated"); capture(window, "workout-rest-large-unrated")
        let unrated = try XCTUnwrap(elements(window).first { $0.accessibilityLabel == "Unrated" && $0.accessibilityTraits.contains(.button) })
        XCTAssertGreaterThan(unrated.accessibilityFrame.width, window.bounds.width / 2, "Accessibility effort controls need room for readable labels")
        window.rootViewController = UIHostingController(rootView: ConfiguredSessionView(store: workspace.training).dynamicTypeSize(.large))
        try await waitForContent(window, containing: "Unrated"); capture(window, "workout-rest-normal-unrated")
        workspace.training.finish()
        let record = try XCTUnwrap(workspace.training.history.first)
        window.rootViewController = UIHostingController(rootView: SessionReportView(record: record, profile: workspace.profile.profile))
        try await waitForContent(window, containing: "Recorded work"); capture(window, "junior-report-local-work")
        let labels = elements(window).compactMap(\.accessibilityLabel)
        XCTAssertFalse(labels.contains { $0.contains("Watch heart rate") || $0.contains("Watch active energy") || $0.contains("HealthKit") })
        XCTAssertFalse(labels.isEmpty)
    }
    func testHealthSummariesRequireCapturedAndCurrentAdultWhileKeepingOrdinaryWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try AccountWorkspace(scope: .init(accountID: UUID(), profileID: UUID(), root: root))
        let adult = try profile(age: 30), junior = try profile(age: 12)
        try workspace.profile.save(adult)
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(60)
        let owner = WorkoutOwner(accountID: workspace.scope.accountID, profileID: workspace.scope.profileID)
        func record(age: TrainingAgeContext?, bpm: Double) -> SessionRecord {
            let id = UUID()
            return .init(id: id, date: date, sets: [], telemetry: [0.0, 5.0, 10.0].map { offset in
                WatchTelemetry(sessionID: id, sentAt: date.addingTimeInterval(offset), heartRate: .init(value: bpm, date: date.addingTimeInterval(offset)), accelerationG: nil, rotationRadiansPerSecond: nil)
            }, loggedSets: [.init(id: UUID(), exerciseID: "frontArmRaise", reps: 3, seconds: 0, source: .manual, reason: .voluntary, effort: .hard)],
                endedAt: date.addingTimeInterval(10), trainingContext: .init(owner: owner, age: age))
        }
        let juniorRecord = record(age: junior.effectiveProgrammePreferences.ageContext, bpm: 180)
        let unknownRecord = record(age: nil, bpm: 210)
        let adultRecord = record(age: adult.effectiveProgrammePreferences.ageContext, bpm: 120)
        [juniorRecord, unknownRecord].forEach { workspace.training.persist($0) }
        let window = try host(ScrollView { TrainingOverviewSection(store: workspace.training, profile: adult) })
        try await waitForContent(window, containing: "Recent session measurements")
        capture(window, "summary-ineligible-health")
        XCTAssertFalse(elements(window).compactMap(\.accessibilityLabel).contains("Time-weighted Watch heart rate"))
        workspace.training.persist(adultRecord)
        window.rootViewController = UIHostingController(rootView: ScrollView { TrainingOverviewSection(store: workspace.training, profile: adult) })
        try await waitForContent(window, containing: "Time-weighted Watch heart rate")
        capture(window, "summary-adult-health")
        XCTAssertEqual(workspace.training.history.count, 3)
        window.rootViewController = UIHostingController(rootView: DayDetail(date: date, records: workspace.training.history, profile: adult, history: workspace.training.history))
        try await waitForContent(window, containing: "Time-weighted HR")
        capture(window, "calendar-captured-adult-health")
        let labels = elements(window).compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains { $0.contains("120") }, labels.joined(separator: "; "))
        XCTAssertFalse(labels.contains { $0.contains("170") }, "Ineligible captured telemetry must not enter the average")
        XCTAssertEqual(TrainingDashboard(history: workspace.training.history).totalSets, 3)
        XCTAssertEqual(TrainingDashboard(history: workspace.training.history).totalReps, 9)
        window.rootViewController = UIHostingController(rootView: DayDetail(date: date, records: workspace.training.history, profile: junior, history: workspace.training.history))
        try await waitForContent(window, containing: "No Watch intervals")
        XCTAssertFalse(elements(window).compactMap(\.accessibilityLabel).contains("Time-weighted HR"))
        XCTAssertEqual(workspace.training.history.flatMap(\.loggedSets).filter { $0.effort == .hard }.count, 3)
    }
    private func profile(age: Int) throws -> LocalProfile {
        try LocalProfile(bodyMeasurements: age >= 18 ? .init(heightCM: 170, weightKG: 70) : nil, onboardingRevision: TrainingSetup.revision,
            programmePreferences: .init(goals: [.balance, .strength], weekdays: Set(1...7), startingPoint: .startingOut,
                ageContext: .init(ageYears: age, guardianManaged: age < 18), comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, .unsure) })))
    }
    private func host<V: View>(_ view: V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        self.window = window; controller = window.rootViewController; hidden = window.isHidden; level = window.windowLevel
        window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible(); return window
    }
    private func elements(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = []; var seen = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return }
            result.append(value)
            (value as? UIView)?.subviews.forEach(visit)
            value.accessibilityElements?.compactMap { $0 as? NSObject }.forEach(visit)
            let count = value.accessibilityElementCount()
            if count > 0 && count < 500 { for index in 0..<count { if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) } } }
        }
        visit(root); return result
    }
    private func scrollToContent(_ window: UIWindow, label: String) async throws {
        for _ in 0..<5 {
            if elements(window).contains(where: { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) && window.bounds.intersects($0.accessibilityFrame) }) { return }
            let scroll = try XCTUnwrap(elements(window).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > $0.bounds.height && $0.bounds.width > 200 })
            let maximum = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: min(maximum, scroll.contentOffset.y + scroll.bounds.height * 0.6)), animated: false)
            try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
        }
        XCTFail("The actual scroll view did not reveal the requested control: " + label)
    }
    private func waitForContent(_ window: UIWindow, containing text: String) async throws {
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if elements(window).compactMap(\.accessibilityLabel).contains(where: { $0.contains(text) }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("PROGRAMME_AX_LABELS", elements(window).compactMap(\.accessibilityLabel))
        XCTFail("Rendered content did not become accessible: " + text)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        print("PROGRAMME_RENDER_READY \(name)")
    }
}
