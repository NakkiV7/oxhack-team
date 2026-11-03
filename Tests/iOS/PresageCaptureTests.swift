import CoreMedia
import XCTest
@testable import Spottr

@MainActor
final class PresageCaptureTests: XCTestCase {
    func testDeadlineFreezesQualifiedResultWhileSerializedStopSettlesAndManualStopClearsIt() async throws {
        let driver = FakePresageDriver()
        driver.suspendStop = true
        var now = Date(timeIntervalSince1970: 100)
        var expire: CheckedContinuation<Void, Never>?
        var identity: (UUID, UUID)?
        let controller = PresageCaptureController(now: { now }, waitForDeadline: {
            await withCheckedContinuation { expire = $0 }
        }) { session, measurement in
            identity = (session, measurement)
            return driver
        }
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        while expire == nil { await Task.yield() }
        now = Date(timeIntervalSince1970: 131)
        let ids = try XCTUnwrap(identity)
        driver.onUpdate?(.init(samples: [
            .init(sessionID: ids.0, measurementID: ids.1, metric: .pulse, value: 72, date: now, confidence: 95, stable: true),
            .init(sessionID: ids.0, measurementID: ids.1, metric: .breathing, value: 14, date: now, confidence: 95, stable: true)
        ], validationOK: true))
        now = Date(timeIntervalSince1970: 132)
        expire?.resume()
        while controller.state != .completed || driver.stopContinuation == nil { await Task.yield() }
        let completedAt = try XCTUnwrap(controller.completedAt)
        XCTAssertEqual(completedAt, now)
        XCTAssertEqual(controller.vitals?.pulse(at: completedAt)?.value, 72)
        XCTAssertEqual(controller.vitals?.breathing(at: completedAt)?.value, 14)
        now = Date(timeIntervalSince1970: 1000)
        driver.onUpdate?(.init(samples: [], validationOK: false, failed: true))
        XCTAssertEqual(controller.state, .completed)
        XCTAssertEqual(controller.vitals?.pulse(at: completedAt)?.value, 72)
        XCTAssertNil(controller.vitals?.pulse(at: now))
        let stopping = Task { await controller.stop() }
        while controller.state != .idle { await Task.yield() }
        XCTAssertNil(controller.completedAt)
        XCTAssertNil(controller.vitals)
        driver.stopContinuation?.resume()
        await stopping.value
        XCTAssertEqual(driver.stopCount, 1)
    }

    func testConsentAndStationaryCheckPrecedeAnySDKConstructionOrStart() async {
        var constructions = 0
        let controller = PresageCaptureController { _, _ in
            constructions += 1
            return FakePresageDriver()
        }
        await controller.start(sessionID: UUID(), allowAutomaticInsights: false, stationary: true)
        XCTAssertEqual(constructions, 0)
        XCTAssertEqual(controller.state, .disclosureRequired)
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: false)
        XCTAssertEqual(constructions, 0)
        XCTAssertEqual(controller.state, .stationaryRequired)
    }

    func testStopDropsLateStartAndCallbacksFromCancelledMeasurement() async {
        let first = FakePresageDriver(), second = FakePresageDriver()
        first.suspendStart = true
        var count = 0
        let controller = PresageCaptureController { _, _ in
            count += 1
            return count == 1 ? first : second
        }
        let session = UUID()
        let pending = Task { await controller.start(sessionID: session, allowAutomaticInsights: true, stationary: true) }
        while first.startContinuation == nil { await Task.yield() }
        let stopping = Task { await controller.stop() }
        while controller.state != .idle { await Task.yield() }
        let restarting = Task { await controller.start(sessionID: session, allowAutomaticInsights: true, stationary: true) }
        await Task.yield()
        XCTAssertEqual(count, 1, "A process-global SDK must finish old startup/teardown before its replacement")
        first.startContinuation?.resume()
        await pending.value
        await stopping.value
        await restarting.value
        let replacement = controller.measurementID
        first.onUpdate?(.init(samples: [], validationOK: false))
        XCTAssertEqual(controller.state, .measuring)
        XCTAssertEqual(controller.measurementID, replacement)
        XCTAssertGreaterThanOrEqual(first.stopCount, 1)
        await controller.stop()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.vitals)
    }

    func testDeadlineCompletesAPendingStartWithoutRetryOrLatePublishing() async {
        let driver = FakePresageDriver()
        driver.suspendStart = true
        var expire: CheckedContinuation<Void, Never>?
        let controller = PresageCaptureController(waitForDeadline: {
            await withCheckedContinuation { expire = $0 }
        }) { _, _ in driver }
        let pending = Task { await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true) }
        while driver.startContinuation == nil || expire == nil { await Task.yield() }
        expire?.resume()
        while controller.state != .completed { await Task.yield() }
        XCTAssertNotNil(controller.vitals)
        XCTAssertNotNil(controller.completedAt)
        XCTAssertNil(controller.vitals?.pulse(at: controller.completedAt!))
        driver.startContinuation?.resume()
        await pending.value
        XCTAssertEqual(controller.state, .completed)
        XCTAssertEqual(driver.stopCount, 1)
    }

    func testOnlyCurrentQualifiedMetricsAreProjectedAndFailureIsSanitized() async {
        let driver = FakePresageDriver()
        var now = Date(timeIntervalSince1970: 100)
        var ids: (UUID, UUID)?
        let controller = PresageCaptureController(now: { now }) { session, measurement in
            ids = (session, measurement)
            return driver
        }
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        now = now.addingTimeInterval(31)
        let identity = try! XCTUnwrap(ids)
        driver.onUpdate?(.init(samples: [.init(sessionID: identity.0, measurementID: identity.1,
            metric: .breathing, value: 14, date: now, confidence: 90, stable: true)], validationOK: true))
        XCTAssertEqual(controller.vitals?.breathing(at: now)?.value, 14)
        await controller.stop()
        driver.onUpdate?(.init(samples: [], validationOK: true))
        XCTAssertNil(controller.vitals)
        driver.failure = NSError(domain: "secret provider text", code: 123)
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertNil(controller.vitals)
        XCTAssertNil(controller.completedAt)
        XCTAssertEqual(controller.guidance, "The camera check couldn’t start.")
    }

    func testMappedGuidanceSurvivesFailureAndClearsForStopAndNewStart() async {
        let driver = FakePresageDriver()
        let controller = PresageCaptureController { _, _ in driver }
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        driver.onUpdate?(.init(samples: [], validationOK: false, failed: true,
            guidance: "Keep your face fully in the camera frame."))
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(controller.guidance, "Keep your face fully in the camera frame.")
        XCTAssertNil(controller.completedAt)
        await controller.stop()
        XCTAssertNil(controller.guidance)
        driver.failure = PresageFailure(guidance: "The camera service could not be reached.")
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(controller.guidance, "The camera service could not be reached.")
        driver.failure = nil
        await controller.start(sessionID: UUID(), allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(controller.state, .measuring)
        XCTAssertNil(controller.guidance)
        XCTAssertNil(controller.completedAt)
        await controller.stop()
    }
}

@MainActor
private final class FakePresageDriver: PresageDriving {
    var onUpdate: ((PresageUpdate) -> Void)?
    var suspendStart = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopCount = 0
    var suspendStop = false
    var stopContinuation: CheckedContinuation<Void, Never>?
    var failure: Error?
    func start() async throws {
        if suspendStart { await withCheckedContinuation { startContinuation = $0 } }
        if let failure { throw failure }
    }
    func stop() async {
        stopCount += 1
        if suspendStop { await withCheckedContinuation { stopContinuation = $0 } }
    }
    func submit(_ sample: CMSampleBuffer) -> Bool { true }
}
