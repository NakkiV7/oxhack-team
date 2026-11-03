import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class PresageWorkoutPanelTests: XCTestCase {
    func testExampleValuesNeedFiveContinuousSecondsOfVisibleFrontCamera() {
        var gate = CameraExampleGate()
        gate.update(cameraVisible: false, at: 10)
        XCTAssertFalse(gate.ready(at: 100))
        gate.update(cameraVisible: true, at: 100)
        XCTAssertFalse(gate.ready(at: 104.999))
        XCTAssertTrue(gate.ready(at: 105))
        gate.update(cameraVisible: false, at: 106)
        XCTAssertFalse(gate.ready(at: 1000))
        gate.update(cameraVisible: true, at: 1001)
        XCTAssertFalse(gate.ready(at: 1005))
        XCTAssertTrue(gate.ready(at: 1006))
        XCTAssertFalse(gate.ready(at: .nan))
        XCTAssertFalse(gate.ready(at: .infinity))
    }

    func testCompletedCheckDetachesCameraHookWithoutErasingFrozenResults() async throws {
        let driver = PanelPresageDriver(), vision = VisionWorker()
        var now = Date(timeIntervalSince1970: 100)
        var expire: CheckedContinuation<Void, Never>?
        var identity: (UUID, UUID)?
        let controller = PresageCaptureController(now: { now }, waitForDeadline: {
            await withCheckedContinuation { expire = $0 }
        }) { session, measurement in identity = (session, measurement); return driver }
        let model = PresageWorkoutModel(vision: vision, controller: controller)
        model.update(sessionID: UUID(), generation: UUID(), phase: .rest, frontEnabled: true, appActive: true)
        await model.start(allowAutomaticInsights: true, stationary: true)
        while expire == nil { await Task.yield() }
        now = Date(timeIntervalSince1970: 131)
        let ids = try XCTUnwrap(identity)
        driver.onUpdate?(.init(samples: [.init(sessionID: ids.0, measurementID: ids.1, metric: .pulse,
            value: 72, date: now, confidence: 90, stable: true)], validationOK: true))
        expire?.resume()
        for _ in 0..<200 where controller.state != .completed || vision.onSample != nil { await Task.yield() }
        XCTAssertEqual(controller.state, .completed)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(vision.onSample)
        XCTAssertEqual(controller.vitals?.pulse(at: try XCTUnwrap(controller.completedAt))?.value, 72)
        await model.stop()
        XCTAssertNil(controller.vitals)
    }

    func testNoAutostartAndConsentPrecedesDriverConstruction() async {
        let driver = PanelPresageDriver()
        var constructions = 0
        let controller = PresageCaptureController { _, _ in constructions += 1; return driver }
        let vision = VisionWorker()
        let model = PresageWorkoutModel(vision: vision, controller: controller)
        model.update(sessionID: UUID(), generation: UUID(), phase: .rest, frontEnabled: true, appActive: true)
        XCTAssertEqual(constructions, 0)
        XCTAssertNil(vision.onSample)
        await model.start(allowAutomaticInsights: false, stationary: true)
        XCTAssertEqual(constructions, 0)
        XCTAssertEqual(controller.state, .disclosureRequired)
        await model.start(allowAutomaticInsights: true, stationary: false)
        XCTAssertEqual(constructions, 0)
        await model.start(allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(driver.starts, 1)
        await model.stop()
    }

    func testOnlyCurrentFrontSamplesAreForwardedAndEverySampleIsReleased() async throws {
        let driver = PanelPresageDriver(), vision = VisionWorker()
        let controller = PresageCaptureController { _, _ in driver }
        let model = PresageWorkoutModel(vision: vision, controller: controller)
        let session = UUID(), generation = UUID()
        model.update(sessionID: session, generation: generation, phase: .rest, frontEnabled: true, appActive: true)
        await model.start(allowAutomaticInsights: true, stationary: true)
        let hook = try XCTUnwrap(vision.onSample)
        let sample = try sampleBuffer()
        let accepted = expectation(description: "Current sample released")
        hook(sample, generation) { accepted.fulfill() }
        await fulfillment(of: [accepted], timeout: 1)
        XCTAssertEqual(driver.submits, 1)
        let rejected = expectation(description: "Old generation released")
        hook(sample, UUID()) { rejected.fulfill() }
        await fulfillment(of: [rejected], timeout: 1)
        XCTAssertEqual(driver.submits, 1)
        await model.stop()
        XCTAssertNil(vision.onSample)
        let stopped = expectation(description: "Retained old hook releases without forwarding")
        hook(sample, generation) { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(driver.submits, 1)
    }

    func testSessionGenerationPhaseForegroundAndFrontAvailabilityChangesStopMeasurement() async {
        for change in 0..<7 {
            let driver = PanelPresageDriver(), vision = VisionWorker()
            let controller = PresageCaptureController { _, _ in driver }
            let model = PresageWorkoutModel(vision: vision, controller: controller)
            let session = UUID(), generation = UUID()
            model.update(sessionID: session, generation: generation, phase: .rest, frontEnabled: true, appActive: true)
            await model.start(allowAutomaticInsights: true, stationary: true)
            model.update(sessionID: change == 0 ? UUID() : session, generation: change == 1 ? UUID() : generation,
                         phase: change == 2 ? .paused : (change == 3 ? .active : (change == 6 ? .finished : .rest)),
                         frontEnabled: change != 4, appActive: change != 5)
            XCTAssertNil(vision.onSample)
            await model.stop()
            XCTAssertGreaterThanOrEqual(driver.stops, 1)
            XCTAssertFalse(model.isRunning)
        }
    }

    func testActiveWorkoutCannotMeasureAndRestRequiresAnExplicitStart() async {
        let driver = PanelPresageDriver(), vision = VisionWorker()
        var constructions = 0
        let controller = PresageCaptureController { _, _ in constructions += 1; return driver }
        let model = PresageWorkoutModel(vision: vision, controller: controller)
        let session = UUID(), generation = UUID()
        model.update(sessionID: session, generation: generation, phase: .active, frontEnabled: true, appActive: true)
        await model.start(allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(constructions, 0, "Presage must not start while exercising")
        XCTAssertEqual(driver.starts, 0)
        XCTAssertNil(vision.onSample)
        model.update(sessionID: session, generation: generation, phase: .rest, frontEnabled: true, appActive: true)
        XCTAssertEqual(driver.starts, 0, "Enabling the rest camera alone must not start the SDK")
        await model.start(allowAutomaticInsights: true, stationary: true)
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(driver.starts, 1)
        XCTAssertNotNil(vision.onSample)
        await model.stop()
    }

    private func sampleBuffer() throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pixel), kCVReturnSuccess)
        let image = try XCTUnwrap(pixel)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}

@MainActor private final class PanelPresageDriver: PresageDriving {
    var onUpdate: ((PresageUpdate) -> Void)?
    var starts = 0, stops = 0, submits = 0
    func start() async throws { starts += 1 }
    func stop() async { stops += 1 }
    func submit(_ sample: CMSampleBuffer) -> Bool { submits += 1; return true }
}
