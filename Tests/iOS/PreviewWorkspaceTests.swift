import XCTest
@testable import Spottr

@MainActor
final class PreviewWorkspaceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_792_900_000)

    func testFreshNormalWorkspaceDoesNotInventProfileHistoryRewardsOrPreview() throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root, now: { self.referenceDate })
        XCTAssertFalse(workspace.isPreview)
        XCTAssertTrue(workspace.store.history.isEmpty)
        XCTAssertNil(workspace.profileStore.profile)
        XCTAssertNil(workspace.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    func testExplicitPreviewSeedsSeparateDataAndDisablingRestoresRealFilesByteForByte() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let realBytes = try snapshots(fixture.folder)
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root, now: { self.referenceDate })
        let realIDs = workspace.store.history.map(\.id)
        try workspace.setPreview(true)
        XCTAssertTrue(workspace.isPreview)
        XCTAssertEqual(Set(workspace.store.history.map(\.id)), Set(DemoPreviewData.sessions(referenceDate: referenceDate).map(\.id)))
        XCTAssertEqual(workspace.profileStore.profile, DemoPreviewData.profile)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        XCTAssertNil(workspace.error)

        try workspace.setPreview(false)
        XCTAssertFalse(workspace.isPreview)
        XCTAssertEqual(workspace.store.history.map(\.id), realIDs)
        XCTAssertEqual(workspace.profileStore.profile?.name, "Real synthetic guest")
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        XCTAssertEqual(fixture.defaults.string(forKey: "unrelated-sentinel"), "preserved")
    }

    func testRepeatedSwitchesAndRelaunchKeepBothStoresWithoutReseedingExistingPreview() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let realBytes = try snapshots(fixture.folder)
        var workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root, now: { self.referenceDate })
        try workspace.setPreview(true)
        let extra = try LoggedWorkout.make(exerciseID: "catCow", count: 2, sets: 1, date: referenceDate)
        workspace.store.persist(extra, completedAt: referenceDate)
        try workspace.profileStore.save(LocalProfile(name: "Edited demo", weeklyTarget: 2, goals: [.balance]))
        let previewBytes = try snapshots(fixture.folder.appendingPathComponent("Preview"))
        try workspace.setPreview(false)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        try workspace.setPreview(true)
        XCTAssertTrue(workspace.store.history.contains(extra))
        XCTAssertEqual(workspace.profileStore.profile?.name, "Edited demo")
        XCTAssertEqual(try snapshots(fixture.folder.appendingPathComponent("Preview")), previewBytes)
        workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root, now: { self.referenceDate.addingTimeInterval(86_400) })
        XCTAssertTrue(workspace.isPreview)
        XCTAssertTrue(workspace.store.history.contains(extra))
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        XCTAssertEqual(try snapshots(fixture.folder.appendingPathComponent("Preview")), previewBytes)
    }

    func testCorruptPreviewFilesAreNeverOverwrittenAndFailedEnableKeepsTheActiveRealStore() throws {
        for filename in ["history.json", "profile.json", "rewards.json"] {
            let fixture = try fixture(seedReal: true)
            defer { fixture.clean() }
            let preview = fixture.folder.appendingPathComponent("Preview")
            try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
            let unreadable = Data("preserve unreadable preview".utf8)
            try unreadable.write(to: preview.appendingPathComponent(filename))
            let realBytes = try snapshots(fixture.folder)
            let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
            let current = ObjectIdentifier(workspace.store)
            XCTAssertThrowsError(try workspace.setPreview(true))
            XCTAssertFalse(workspace.isPreview)
            XCTAssertEqual(ObjectIdentifier(workspace.store), current)
            XCTAssertNotNil(workspace.error)
            XCTAssertEqual(try Data(contentsOf: preview.appendingPathComponent(filename)), unreadable)
            XCTAssertEqual(try snapshots(fixture.folder), realBytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: preview.path), [filename])
            XCTAssertFalse(PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root).isPreview)
        }
    }

    func testSeedWriteFailureDoesNotChangeModeStoreOrRealDataAndCanRetry() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let blocker = fixture.folder.appendingPathComponent("Preview")
        let bytes = Data("file blocks preview directory".utf8)
        try bytes.write(to: blocker)
        let realBytes = try snapshots(fixture.folder)
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        let current = ObjectIdentifier(workspace.store)
        XCTAssertThrowsError(try workspace.setPreview(true))
        XCTAssertFalse(workspace.isPreview)
        XCTAssertEqual(ObjectIdentifier(workspace.store), current)
        XCTAssertEqual(try Data(contentsOf: blocker), bytes)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        try FileManager.default.removeItem(at: blocker)
        try workspace.setPreview(true)
        XCTAssertTrue(workspace.isPreview)
        XCTAssertNil(workspace.error)
    }

    func testCorruptRealHistoryBlocksDisablingWithoutReplacingEitherFile() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        try workspace.setPreview(true)
        let unreadable = Data("preserve unreadable real history".utf8)
        try unreadable.write(to: fixture.folder.appendingPathComponent("history.json"))
        let previewBytes = try snapshots(fixture.folder.appendingPathComponent("Preview"))
        let current = ObjectIdentifier(workspace.store)
        XCTAssertThrowsError(try workspace.setPreview(false))
        XCTAssertTrue(workspace.isPreview)
        XCTAssertEqual(ObjectIdentifier(workspace.store), current)
        XCTAssertNotNil(workspace.error)
        XCTAssertEqual(try Data(contentsOf: fixture.folder.appendingPathComponent("history.json")), unreadable)
        XCTAssertEqual(try snapshots(fixture.folder.appendingPathComponent("Preview")), previewBytes)
    }

    func testPresentedOrUnfinishedWorkoutBlocksSwitchWithoutFinishingOrSavingIt() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        let realBytes = try snapshots(fixture.folder)
        workspace.store.start()
        let id = workspace.store.session.id
        XCTAssertThrowsError(try workspace.setPreview(true))
        XCTAssertEqual(workspace.store.session.phase, .active)
        XCTAssertEqual(workspace.store.session.id, id)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        workspace.store.presented = false
        workspace.store.pause()
        XCTAssertThrowsError(try workspace.setPreview(true))
        XCTAssertEqual(workspace.store.session.phase, .paused)
        XCTAssertFalse(workspace.isPreview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("Preview").path))
    }

    func testSwitchReleasesPreviousTrainingStoreInsteadOfKeepingTwoCompanionOwners() async throws {
        let fixture = try fixture()
        defer { fixture.clean() }
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        weak var previous = workspace.store
        try workspace.setPreview(true)
        for _ in 0..<20 where previous != nil { await Task.yield() }
        XCTAssertNil(previous)
    }

    func testDisablingAfterCorruptPersistedPreviewFallbackStopsRetryingItOnRelaunch() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let realBytes = try snapshots(fixture.folder)
        var workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        try workspace.setPreview(true)
        let previewProfile = fixture.folder.appendingPathComponent("Preview/profile.json")
        let unreadable = Data("preserve corrupt persisted preview".utf8)
        try unreadable.write(to: previewProfile)
        workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        XCTAssertFalse(workspace.isPreview)
        XCTAssertNotNil(workspace.error)
        XCTAssertEqual(workspace.profileStore.profile?.name, "Real synthetic guest")
        try workspace.setPreview(false)
        workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        XCTAssertFalse(workspace.isPreview)
        XCTAssertNil(workspace.error, "Explicitly disabling preview must clear the persisted request to reopen corrupt preview data")
        XCTAssertEqual(try Data(contentsOf: previewProfile), unreadable)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
    }

    func testPreviewSymlinkToRealWorkspaceCannotEnableOrChangeRealData() throws {
        let fixture = try fixture(seedReal: true)
        defer { fixture.clean() }
        let realBytes = try snapshots(fixture.folder)
        let preview = fixture.folder.appendingPathComponent("Preview")
        try FileManager.default.createSymbolicLink(at: preview, withDestinationURL: fixture.folder)
        let workspace = PreviewWorkspace(defaults: fixture.defaults, rootURL: fixture.root)
        let current = ObjectIdentifier(workspace.store)
        XCTAssertThrowsError(try workspace.setPreview(true))
        XCTAssertFalse(workspace.isPreview)
        XCTAssertEqual(ObjectIdentifier(workspace.store), current)
        XCTAssertNotNil(workspace.error)
        XCTAssertEqual(try snapshots(fixture.folder), realBytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: preview.path), fixture.folder.path)
    }

    private func snapshots(_ folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in ["history.json", "profile.json", "rewards.json"] {
            let url = folder.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) { result[file] = try Data(contentsOf: url) }
        }
        return result
    }

    private func fixture(seedReal: Bool = false) throws -> Fixture {
        let name = "PreviewWorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set("preserved", forKey: "unrelated-sentinel")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let folder = namespace.map { root.appendingPathComponent($0.uuidString) } ?? root
        if seedReal {
            try HistoryStore(url: folder.appendingPathComponent("history.json")).save(LoggedWorkout.make(exerciseID: "catCow", count: 1, sets: 1, date: referenceDate))
            try NativeProfileStore(url: folder.appendingPathComponent("profile.json")).save(LocalProfile(name: "Real synthetic guest", weeklyTarget: 2, goals: [.balance]))
            try NativeRewardsStore(url: folder.appendingPathComponent("rewards.json"), createdAt: referenceDate).schedule(startHour: 10, at: referenceDate)
        }
        return Fixture(root: root, folder: folder, defaults: defaults, suiteName: name)
    }

    private struct Fixture {
        let root: URL
        let folder: URL
        let defaults: UserDefaults
        let suiteName: String
        func clean() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
