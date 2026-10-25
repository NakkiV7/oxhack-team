import XCTest
@testable import Spottr

@MainActor
final class ProfileDataControlsTests: XCTestCase {
    func testFailedPendingProfileSavePreventsLeavingUntilTheSameDraftCanBeRetried() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try blockedProfileStore(in: folder)
        let original = try XCTUnwrap(store.profile)
        let persistence = ProfileDraftPersistence(store: store)
        persistence.edit(name: "Updated guest", weeklyTarget: 5, goals: [.mobility])

        XCTAssertTrue(persistence.blocksDismissal)
        XCTAssertFalse(persistence.prepareToLeave())
        XCTAssertNotNil(persistence.validationError)
        XCTAssertTrue(persistence.blocksDismissal)
        XCTAssertEqual(store.profile, original)
        XCTAssertEqual(NativeProfileStore(url: folder.appendingPathComponent("backup/profile.json")).profile, original)

        try restoreProfileFolder(in: folder)
        XCTAssertTrue(persistence.prepareToLeave())
        XCTAssertFalse(persistence.blocksDismissal)
        XCTAssertNil(persistence.validationError)
        let expected = try LocalProfile(name: "Updated guest", weeklyTarget: 5, goals: [.mobility], baselineAbility: .somePractice)
        XCTAssertEqual(store.profile, expected)
        XCTAssertEqual(NativeProfileStore(url: folder.appendingPathComponent("profile/profile.json")).profile, expected)
    }

    func testEarlierAutosaveFailureStillPreventsLeavingAndCanRetryWithoutAnotherEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try blockedProfileStore(in: folder)
        let persistence = ProfileDraftPersistence(store: store)
        persistence.edit(name: "Retry guest", weeklyTarget: 4, goals: [.balance])
        for _ in 0..<100 where persistence.validationError == nil {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertNotNil(persistence.validationError)
        XCTAssertTrue(persistence.blocksDismissal)
        XCTAssertFalse(persistence.prepareToLeave())
        try restoreProfileFolder(in: folder)
        XCTAssertTrue(persistence.prepareToLeave())
        XCTAssertEqual(store.profile?.name, "Retry guest")
        XCTAssertEqual(store.profile?.baselineAbility, .somePractice)
        XCTAssertFalse(persistence.blocksDismissal)
    }

    func testInvalidGoalsAllowLeavingWithTheLastSavedProfileAndCorruptProfilesRequireExplicitSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = NativeProfileStore(url: url)
        let original = try LocalProfile(name: "Saved guest", baselineAbility: .regularPractice)
        try store.save(original)
        let persistence = ProfileDraftPersistence(store: store)
        persistence.edit(name: "Unsaved guest", weeklyTarget: 4, goals: [])
        XCTAssertNotNil(persistence.validationError)
        XCTAssertFalse(persistence.blocksDismissal)
        XCTAssertTrue(persistence.prepareToLeave())
        XCTAssertEqual(NativeProfileStore(url: url).profile, original)

        let unreadable = Data("preserve unreadable profile".utf8)
        try unreadable.write(to: url)
        let corrupt = NativeProfileStore(url: url)
        let recovery = ProfileDraftPersistence(store: corrupt)
        recovery.edit(name: "Replacement guest", weeklyTarget: 2, goals: [.strength])
        XCTAssertTrue(recovery.prepareToLeave())
        XCTAssertEqual(try Data(contentsOf: url), unreadable)
        XCTAssertNotNil(corrupt.loadError)
        XCTAssertTrue(recovery.save(name: "Replacement guest", weeklyTarget: 2, goals: [.strength]))
        XCTAssertNil(corrupt.loadError)
        XCTAssertEqual(NativeProfileStore(url: url).profile?.name, "Replacement guest")
    }

    private func blockedProfileStore(in folder: URL) throws -> NativeProfileStore {
        let directory = folder.appendingPathComponent("profile")
        let store = NativeProfileStore(url: directory.appendingPathComponent("profile.json"))
        try store.save(LocalProfile(name: "Saved guest", baselineAbility: .somePractice))
        try FileManager.default.moveItem(at: directory, to: folder.appendingPathComponent("backup"))
        try Data("file blocks profile directory".utf8).write(to: directory)
        return store
    }

    private func restoreProfileFolder(in folder: URL) throws {
        let directory = folder.appendingPathComponent("profile")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("backup"), to: directory)
    }

    func testExportAndResetUseSavedHistoryAndResetRejectsUnfinishedWorkouts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url)
        let record = try LoggedWorkout.make(exerciseID: "wallPushup", count: 4, sets: 1)
        store.persist(record)
        let original = try Data(contentsOf: url)
        let export = try store.exportHistory()
        defer { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: export)), [record])
        let externalCopy = folder.appendingPathComponent("saved-copy.json")
        try FileManager.default.copyItem(at: export, to: externalCopy)
        let otherStore = TrainingStore(historyURL: folder.appendingPathComponent("other-profile/history.json"))
        otherStore.persist(record)
        let otherExport = try otherStore.exportHistory()
        defer { try? FileManager.default.removeItem(at: otherExport.deletingLastPathComponent()) }
        store.start()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        store.pause()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        store.endSet()
        XCTAssertThrowsError(try store.clearHistory())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(store.history, [record])
        store.finish()
        try store.clearHistory()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(try HistoryStore(url: url).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: externalCopy)), [record])
        XCTAssertEqual(try JSONDecoder().decode([SessionRecord].self, from: Data(contentsOf: otherExport)), [record])
        try store.clearHistory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalCopy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherExport.path))
    }
}
