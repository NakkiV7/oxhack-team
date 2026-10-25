import AVFoundation
import XCTest
@testable import Spottr

@MainActor
final class PhoneCameraLifecycleTests: XCTestCase {
    func testInactivePhoneCameraCannotResumeDirectlyOrFromMatchingWatch() async throws {
        for fromWatch in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let camera = LifecyclePhoneCamera()
            let store = makeStore(folder: folder, camera: camera)
            defer { store.finish(); try? FileManager.default.removeItem(at: folder) }
            let initial = expectation(description: "Explicit foreground phone capture")
            camera.onStart = { initial.fulfill() }
            store.start(); store.camera()
            await fulfillment(of: [initial], timeout: 2)
            store.pause(); store.setAppActive(false)
            let generation = store.session.generation
            let blocked = expectation(description: "Inactive resume cannot start phone capture")
            blocked.isInverted = true
            camera.onStart = { blocked.fulfill() }
            if fromWatch {
                store.companion.onCommand?(.init(sessionID: store.session.id, generation: generation, action: .resume))
            } else { store.resume() }
            await fulfillment(of: [blocked], timeout: 0.15)
            XCTAssertEqual(store.session.phase, .paused, "Watch and direct Resume must respect phone foreground ownership")
            XCTAssertEqual(store.session.generation, generation)
            XCTAssertEqual(camera.startCount, 1)
            guard store.session.phase == .paused else { continue }
            store.setAppActive(true)
            XCTAssertEqual(store.session.phase, .paused, "Foreground entry alone cannot restart capture")
            XCTAssertEqual(camera.startCount, 1)
            let resumed = expectation(description: "Explicit foreground resume")
            camera.onStart = { resumed.fulfill() }
            store.resume()
            await fulfillment(of: [resumed], timeout: 2)
            XCTAssertEqual(store.session.phase, .active)
            XCTAssertEqual(camera.startCount, 2)
        }
    }

    func testInactiveConfiguredPhoneCameraCannotStartDirectlyOrFromMatchingWatch() async throws {
        for fromWatch in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let camera = LifecyclePhoneCamera()
            let store = makeStore(folder: folder, camera: camera)
            defer { store.finish(); try? FileManager.default.removeItem(at: folder) }
            store.startPlan(try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 2, restSeconds: 30), availableSupport: [])
            XCTAssertTrue(store.selectConfiguredInput(.phoneCamera))
            store.setAppActive(false)
            let run = try XCTUnwrap(store.configured)
            let blocked = expectation(description: "Inactive Start cannot begin a phone-camera set")
            blocked.isInverted = true
            camera.onStart = { blocked.fulfill() }
            if fromWatch {
                store.companion.onCommand?(.init(sessionID: run.id, generation: run.generation, action: .startSet))
            } else { store.beginConfiguredSet() }
            await fulfillment(of: [blocked], timeout: 0.15)
            XCTAssertFalse(store.configured?.hasStarted ?? true, "An inactive phone set must remain ready for an explicit foreground Start")
            XCTAssertEqual(camera.startCount, 0)
            XCTAssertTrue(store.configured?.completed.isEmpty == true)
            guard store.configured?.hasStarted == false else { continue }
            store.setAppActive(true)
            XCTAssertFalse(store.configured?.hasStarted ?? true)
            XCTAssertEqual(camera.startCount, 0)
            let started = expectation(description: "Explicit foreground configured Start")
            camera.onStart = { started.fulfill() }
            store.beginConfiguredSet()
            await fulfillment(of: [started], timeout: 2)
            XCTAssertTrue(store.configured?.hasStarted == true)
            XCTAssertEqual(camera.startCount, 1)
        }
    }

    private func makeStore(folder: URL, camera: LifecyclePhoneCamera) -> TrainingStore {
        let vision = VisionWorker(cameraAvailable: { true }, requestAccess: { $0(true) }, cameraDriver: camera,
            makePoseProcessor: { { _, time in .init(time: time, width: 1, height: 1, points: []) } })
        return TrainingStore(historyURL: folder.appendingPathComponent("history.json"), vision: vision)
    }
}

private final class LifecyclePhoneCamera: VisionCameraDriving {
    let capture = AVCaptureSession()
    private let lock = NSLock()
    private var starts = 0
    private var callback: (() -> Void)?
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var onStart: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); defer { lock.unlock() }; callback = newValue }
    }
    func start(worker: VisionWorker, queue: DispatchQueue, captureID: UUID) throws {
        lock.lock(); starts += 1; let notify = callback; lock.unlock()
        notify?()
    }
    func stop() {}
}
