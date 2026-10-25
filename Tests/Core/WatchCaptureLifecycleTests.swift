import XCTest
@testable import SpottrCore

final class WatchCaptureLifecycleTests: XCTestCase {
    func testOldWorkoutFailureCannotEndNewCapture() {
        var capture = WatchCaptureLifecycle()
        let old = capture.start()
        XCTAssertTrue(capture.beginCollection(for: old))
        capture.end()
        let current = capture.start()
        XCTAssertTrue(capture.beginCollection(for: current))

        if capture.isCurrent(old) { capture.end() }

        XCTAssertTrue(capture.acceptsSamples(for: current))
        XCTAssertFalse(capture.acceptsSamples(for: old))
    }

    func testPausedEndedAndReplacedRunsRejectQueuedHeartAndMotion() throws {
        var capture = WatchCaptureLifecycle()
        let run = capture.start()
        XCTAssertFalse(capture.acceptsSamples(for: run))
        XCTAssertTrue(capture.beginCollection(for: run))
        let stream = try XCTUnwrap(capture.startMotion(for: run))
        XCTAssertTrue(capture.acceptsMotion(for: run, stream: stream))
        capture.pause()
        XCTAssertFalse(capture.acceptsSamples(for: run))
        XCTAssertFalse(capture.acceptsMotion(for: run, stream: stream))
        capture.end()
        XCTAssertFalse(capture.acceptsSamples(for: run))
        XCTAssertFalse(capture.acceptsMotion(for: run, stream: stream))
        _ = capture.start()
        XCTAssertFalse(capture.acceptsSamples(for: run))
    }

    func testLateCollectionOrSaveStatusOnlyBelongsToLatestRun() {
        var capture = WatchCaptureLifecycle()
        let old = capture.start()
        capture.end()
        XCTAssertTrue(capture.isCurrent(old))
        XCTAssertFalse(capture.beginCollection(for: old))
        let current = capture.start()
        XCTAssertFalse(capture.isCurrent(old))
        XCTAssertFalse(capture.beginCollection(for: old))
        XCTAssertTrue(capture.beginCollection(for: current))
        XCTAssertFalse(capture.beginCollection(for: current))
    }

    func testResumeRequiresFreshMotionStreamAndAllowsNewSamples() throws {
        var capture = WatchCaptureLifecycle()
        let run = capture.start()
        XCTAssertTrue(capture.beginCollection(for: run))
        let oldStream = try XCTUnwrap(capture.startMotion(for: run))
        capture.pause()
        capture.resume()
        XCTAssertTrue(capture.acceptsSamples(for: run))
        XCTAssertFalse(capture.acceptsMotion(for: run, stream: oldStream))
        let newStream = try XCTUnwrap(capture.startMotion(for: run))
        XCTAssertNotEqual(oldStream, newStream)
        XCTAssertTrue(capture.acceptsMotion(for: run, stream: newStream))
    }

    func testPermissionCompletionWhilePausedCannotPublishUntilResume() {
        var capture = WatchCaptureLifecycle()
        let run = capture.start()
        capture.pause()
        XCTAssertTrue(capture.beginCollection(for: run))
        XCTAssertTrue(capture.isPaused)
        XCTAssertFalse(capture.acceptsSamples(for: run))
        XCTAssertNil(capture.startMotion(for: run))
        capture.resume()
        XCTAssertTrue(capture.acceptsSamples(for: run))
        XCTAssertNotNil(capture.startMotion(for: run))
    }

    func testHeartSampleQueuedBeforeResumeCannotBecomeFreshAfterResume() {
        var capture = WatchCaptureLifecycle()
        let start = Date(timeIntervalSince1970: 100)
        let run = capture.start(at: start)
        XCTAssertTrue(capture.beginCollection(for: run))
        XCTAssertTrue(capture.acceptsSamples(for: run, measuredAt: start.addingTimeInterval(1)))
        capture.pause()
        capture.resume(at: start.addingTimeInterval(10))
        XCTAssertFalse(capture.acceptsSamples(for: run, measuredAt: start.addingTimeInterval(2)))
        XCTAssertTrue(capture.acceptsSamples(for: run, measuredAt: start.addingTimeInterval(11)))
    }

    func testNewMotionStreamRejectsCachedMeasurementFromBeforeResume() throws {
        var capture = WatchCaptureLifecycle()
        let start = Date(timeIntervalSince1970: 100)
        let run = capture.start(at: start)
        XCTAssertTrue(capture.beginCollection(for: run))
        capture.pause()
        capture.resume(at: start.addingTimeInterval(10))
        let stream = try XCTUnwrap(capture.startMotion(for: run))
        XCTAssertFalse(capture.acceptsMotion(for: run, stream: stream, measuredAt: start.addingTimeInterval(9)))
        XCTAssertTrue(capture.acceptsMotion(for: run, stream: stream, measuredAt: start.addingTimeInterval(11)))
    }
}
