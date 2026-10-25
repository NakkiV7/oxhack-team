import XCTest
@testable import Spottr

@MainActor
final class DemonstrationVideoTests: XCTestCase {
    func testLocalLessonCopiesOriginalBytesAndPersistsWithoutChangingTheFilmingChecklist() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let library = DemonstrationVideoLibrary(directory: folder)

        try await library.importMovie(from: source, exerciseID: "squat")

        let saved = try XCTUnwrap(library.url(for: "squat"))
        XCTAssertNotEqual(saved, source)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: source))
        XCTAssertFalse(library.recordedIDs.contains("squat"))
        try library.markRecorded("squat", recorded: true)
        let reopened = DemonstrationVideoLibrary(directory: folder)
        XCTAssertEqual(reopened.url(for: "squat"), saved)
        XCTAssertTrue(reopened.recordedIDs.contains("squat"))
        try reopened.removeMovie(for: "squat")
        XCTAssertNil(reopened.url(for: "squat"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(reopened.recordedIDs.contains("squat"))
    }

    func testLessonImportRejectsUnknownExercisesRemoteURLsAndOversizedFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = DemonstrationVideoLibrary(directory: folder.appendingPathComponent("lessons"))
        let oversized = folder.appendingPathComponent("large.mov")
        _ = FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let file = try FileHandle(forWritingTo: oversized)
        try file.truncate(atOffset: UInt64(DemonstrationVideoLibrary.maximumFileBytes + 1))
        try file.close()
        for (url, exerciseID) in [(oversized, "unknown"), (URL(string: "https://example.invalid/lesson.mov")!, "squat"), (oversized, "squat")] {
            do { try await library.importMovie(from: url, exerciseID: exerciseID); XCTFail("Invalid import accepted") }
            catch {}
        }
        XCTAssertNil(library.url(for: "squat"))
        XCTAssertTrue(library.recordedIDs.isEmpty)
    }

    func testUnreadableIndexBlocksChangesAndPreservesRecoverableRecordings() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let original = DemonstrationVideoLibrary(directory: folder)
        try await original.importMovie(from: source, exerciseID: "squat")
        let saved = try XCTUnwrap(original.url(for: "squat"))
        let savedBytes = try Data(contentsOf: saved)
        let index = folder.appendingPathComponent("index.json")
        let damagedIndex = Data("unreadable index".utf8)
        try damagedIndex.write(to: index)
        let library = DemonstrationVideoLibrary(directory: folder)
        let filesBefore = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))

        XCTAssertNotNil(library.loadError)
        XCTAssertThrowsError(try library.markRecorded("squat", recorded: true))
        XCTAssertThrowsError(try library.removeMovie(for: "squat"))
        do {
            try await library.importMovie(from: source, exerciseID: "pushup")
            XCTFail("An unreadable index must block video imports")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: index), damagedIndex)
        XCTAssertEqual(try Data(contentsOf: saved), savedBytes)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), filesBefore)
        XCTAssertFalse(library.isImporting)
    }

    func testFailedRemovalKeepsTheExistingPlayableCopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let library = DemonstrationVideoLibrary(directory: folder)
        try await library.importMovie(from: source, exerciseID: "squat")
        let saved = try XCTUnwrap(library.url(for: "squat"))
        let index = folder.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)

        XCTAssertThrowsError(try library.removeMovie(for: "squat"))

        XCTAssertEqual(library.url(for: "squat"), saved)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: source))
    }

    func testInvalidIndexedPathsCannotDeleteTheIndexOrOutsideFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = folder.appendingPathComponent("outside.mp4")
        let sourceBytes = Data("recoverable source".utf8)
        try sourceBytes.write(to: outside)
        let lessons = folder.appendingPathComponent("lessons")
        try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: false)
        let index = lessons.appendingPathComponent("index.json")
        for filename in ["index.json", "../outside.mp4"] {
            let damagedIndex = try JSONSerialization.data(withJSONObject: [
                "recordedIDs": ["squat"],
                "movies": ["squat": ["exerciseID": "squat", "filename": filename,
                                      "byteCount": 18, "duration": 1, "importedAt": 0]]
            ])
            try damagedIndex.write(to: index)
            let library = DemonstrationVideoLibrary(directory: lessons)

            XCTAssertNotNil(library.loadError)
            XCTAssertNil(library.url(for: "squat"))
            XCTAssertThrowsError(try library.removeMovie(for: "squat"))
            XCTAssertThrowsError(try library.markRecorded("squat", recorded: false))
            XCTAssertEqual(try Data(contentsOf: index), damagedIndex)
            XCTAssertEqual(try Data(contentsOf: outside), sourceBytes)
        }
    }

    func testLessonImportFeedbackConfirmsCommitAndRejectsReplacementWithoutLosingTheExistingClip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let library = DemonstrationVideoLibrary(directory: folder.appendingPathComponent("lessons"))
        let feedback = LessonImportFeedback()
        await feedback.add(source, exerciseID: "squat", library: library)
        let saved = try XCTUnwrap(library.url(for: "squat"))
        XCTAssertNotNil(feedback.message)
        XCTAssertNil(feedback.error)
        let original = try Data(contentsOf: saved)
        let invalid = folder.appendingPathComponent("invalid.mp4")
        try Data("not a playable video".utf8).write(to: invalid)

        await feedback.add(invalid, exerciseID: "squat", library: library)

        XCTAssertNil(feedback.message)
        XCTAssertNotNil(feedback.error)
        XCTAssertEqual(library.url(for: "squat"), saved)
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertEqual(library.importedCount, 1)
        XCTAssertFalse(library.isImporting)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("lessons").path)
        XCTAssertEqual(files.count, 2)
    }

    func testLessonPickerCancellationIsQuietButAnActualPickerFailureHasFeedback() {
        let feedback = LessonImportFeedback()
        feedback.selectionFailed(CocoaError(.fileReadNoPermission))
        XCTAssertNotNil(feedback.error)
        XCTAssertNil(feedback.message)
        feedback.selectionFailed(CocoaError(.userCancelled))
        XCTAssertNil(feedback.error)
        XCTAssertNil(feedback.message)
    }

}
