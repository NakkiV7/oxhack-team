import AVFoundation
import XCTest
@testable import Spottr

final class VisionPreviewTests: XCTestCase {
    func testFrontPreviewUsesExistingCaptureWithoutPoseAndKeepsStateSeparate() async throws {
        let camera = PreviewFakeCamera()
        let started = expectation(description: "Front preview started")
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
                                  makePoseProcessor: { XCTFail("Preview must not construct pose detector"); return { _, time in .init(time: time, width: 1, height: 1, points: []) } })
        worker.onState = { _, _ in XCTFail("Front preview must not overwrite Pi form state") }
        let token = UUID()
        worker.onPreviewState = { _, generation in if generation == token { started.fulfill() } }
        worker.frontPreview(token: token)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(worker.capture === camera.capture)
        XCTAssertEqual(camera.startCount, 1)
        worker.stop()
        await camera.drain()
    }

    func testSampleDeliveryPrecedesPoseThrottleAndHasOneInFlightAcrossGenerations() async throws {
        let camera = PreviewFakeCamera()
        let started = expectation(description: "Front preview started")
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera)
        worker.onPreviewState = { _, _ in started.fulfill() }
        worker.frontPreview(token: UUID())
        await fulfillment(of: [started], timeout: 2)
        worker.onPreviewState = nil
        var completions: [() -> Void] = [], delivered: [UUID] = []
        worker.onSample = { _, token, done in delivered.append(token); completions.append(done) }
        let a = try sample(at: 1), b = try sample(at: 1.001)
        camera.emit(a); camera.emit(b)
        await camera.drain()
        XCTAssertEqual(delivered.count, 1)
        let newToken = UUID()
        worker.frontPreview(token: newToken)
        await camera.drain()
        camera.emit(b)
        await camera.drain()
        XCTAssertEqual(delivered.count, 1, "Old in-flight work must not allow an unbounded replacement queue")
        completions[0]()
        await camera.drain()
        camera.emit(b)
        await camera.drain()
        XCTAssertEqual(delivered.count, 2, "A sub-10fps interval still reaches the optional sample sink")
        XCTAssertEqual(delivered.last, newToken)
        completions[0]() // Duplicate old completion cannot release the new in-flight frame.
        await camera.drain()
        camera.emit(try sample(at: 1.002))
        await camera.drain()
        XCTAssertEqual(delivered.count, 2)
        completions[1]()
        worker.stop()
        await camera.drain()
    }

    func testPauseAndStopRejectFramesImmediatelyAndResumeRetainsPreviewMode() async throws {
        let camera = PreviewFakeCamera()
        let started = expectation(description: "Front preview started")
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
                                  makePoseProcessor: { XCTFail("Resume must preserve preview-only mode"); return { _, time in .init(time: time, width: 1, height: 1, points: []) } })
        worker.onPreviewState = { _, _ in started.fulfill() }
        worker.frontPreview(token: UUID())
        await fulfillment(of: [started], timeout: 2)
        worker.onPreviewState = nil
        var delivered: [UUID] = []
        worker.onSample = { _, token, done in delivered.append(token); done() }
        worker.pause()
        camera.emit(try sample(at: 1))
        await camera.drain()
        XCTAssertTrue(delivered.isEmpty)
        let resumed = UUID()
        worker.resume(token: resumed, source: .camera)
        await camera.drain()
        camera.emit(try sample(at: 2))
        await camera.drain()
        XCTAssertEqual(delivered, [resumed])
        worker.stop()
        camera.emit(try sample(at: 3))
        await camera.drain()
        XCTAssertEqual(delivered, [resumed])
        XCTAssertEqual(camera.startCount, 2)
    }

    func testOptionalSampleSinkReceivesFramesThatPoseThrottleSkips() async throws {
        let camera = PreviewFakeCamera()
        let started = expectation(description: "Pose camera started")
        var detections = 0, samples = 0
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
                                  makePoseProcessor: { { _, time in
            detections += 1
            return .init(time: time, width: 1, height: 1, points: [])
        } })
        worker.onState = { _, _ in started.fulfill() }
        worker.camera(token: UUID())
        await fulfillment(of: [started], timeout: 2)
        worker.onState = nil
        worker.onSample = { _, _, done in samples += 1; done() }
        camera.emit(try sample(at: 1))
        await camera.drain()
        await camera.drain() // completion runs on the capture queue, after the first delivery.
        camera.emit(try sample(at: 1.001))
        await camera.drain()
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(detections, 1)
        worker.stop()
        await camera.drain()
    }

    func testPermissionResponseAfterStopCannotStartPreview() async {
        var permission: ((Bool) -> Void)?
        let camera = PreviewFakeCamera()
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { permission = $0 }, cameraDriver: camera)
        let cancelled = expectation(description: "Cancelled permission must not publish or start")
        cancelled.isInverted = true
        worker.onPreviewState = { _, _ in cancelled.fulfill() }
        worker.frontPreview(token: UUID())
        worker.stop()
        permission?(true)
        await fulfillment(of: [cancelled], timeout: 0.3)
        XCTAssertEqual(camera.startCount, 0)
    }

    func testRetainedOldCameraDelegateCannotPublishIntoRestartedPreview() async throws {
        let camera = PreviewFakeCamera()
        let firstStart = expectation(description: "First preview")
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera)
        worker.onPreviewState = { _, _ in firstStart.fulfill() }
        worker.frontPreview(token: UUID())
        await fulfillment(of: [firstStart], timeout: 2)
        worker.onPreviewState = nil
        let oldReceiver = try XCTUnwrap(camera.retainedReceiver)
        worker.stop()
        await camera.drain()
        let current = UUID()
        worker.frontPreview(token: current)
        await camera.drain()
        var delivered: [UUID] = []
        worker.onSample = { _, token, done in delivered.append(token); done() }
        camera.emit(try sample(at: 1), using: oldReceiver)
        await camera.drain()
        XCTAssertTrue(delivered.isEmpty, "A retained old delegate must not relabel its frame with the new workout token")
        await camera.drain()
        camera.emit(try sample(at: 2))
        await camera.drain()
        XCTAssertEqual(delivered, [current])
        worker.stop()
        await camera.drain()
    }

    private func sample(at time: Double) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA, nil, &pixels), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixels)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}

private final class PreviewFakeCamera: VisionCameraDriving {
    let capture = AVCaptureSession()
    var startCount = 0
    var retainedReceiver: ((CMSampleBuffer) -> Void)?
    private var queue: DispatchQueue?
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        retainedReceiver = { [weak worker] sample in worker?.receiveCameraSample(sample, captureID: captureID) }
        self.queue = queue; startCount += 1
    }
    func stop() {}
    func emit(_ sample: CMSampleBuffer, using receiver: ((CMSampleBuffer) -> Void)? = nil) {
        let deliver = receiver ?? retainedReceiver
        queue?.async { deliver?(sample) }
    }
    func drain() async {
        guard let queue else { await Task.yield(); return }
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}
