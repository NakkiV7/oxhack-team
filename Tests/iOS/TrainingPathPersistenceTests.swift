import XCTest
@testable import Spottr

@MainActor
final class TrainingPathPersistenceTests: XCTestCase {
    func testEditingSurveyDoesNotReplaceAnUnreadPathUntilExplicitAcceptance() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("path.json")
        let original = Data("unread original history".utf8)
        try original.write(to: url)
        let store = TrainingPathStore(url: url)
        let survey = PathSurvey(goal: .squat, abilityKey: "new")
        store.saveSurvey(survey)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(store.loadError)
        XCTAssertNil(store.survey)
        try store.accept(TrainingPathRules.fallback(survey: survey), survey: survey)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(TrainingPathStore(url: url).active?.path.goal, .squat)
    }

    func testReloadReflectsAPathChangedByAnotherScreen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("path.json")
        let writer = TrainingPathStore(url: url)
        let reader = TrainingPathStore(url: url)
        let survey = PathSurvey(goal: .pushup, abilityKey: "first")
        try writer.accept(TrainingPathRules.fallback(survey: survey), survey: survey)
        reader.reload()
        XCTAssertEqual(reader.active, writer.active)
    }

    func testFailedPathReplacementKeepsTheLastSavedVersionAndSurvey() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("path.json")
        let store = TrainingPathStore(url: url)
        let first = PathSurvey(goal: .squat, abilityKey: "new")
        let saved = try store.accept(TrainingPathRules.fallback(survey: first), survey: first)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let replacement = PathSurvey(goal: .pushup, abilityKey: "first")
        XCTAssertThrowsError(try store.accept(TrainingPathRules.fallback(survey: replacement), survey: replacement))
        XCTAssertEqual(store.active?.id, saved.id)
        XCTAssertEqual(store.history.versions.count, 1)
        XCTAssertEqual(store.survey, first)
        XCTAssertNotNil(store.loadError)
    }

    func testFailedSurveyAutosaveKeepsSavedAnswersAndShowsAnError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("path.json")
        let store = TrainingPathStore(url: url)
        let first = PathSurvey(goal: .squat, abilityKey: "new")
        store.saveSurvey(first)
        XCTAssertEqual(TrainingPathStore(url: url).survey, first)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        store.saveSurvey(PathSurvey(goal: .pushup))
        XCTAssertEqual(store.survey, first)
        XCTAssertNotNil(store.loadError)
    }
}
