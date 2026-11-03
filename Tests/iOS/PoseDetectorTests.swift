import XCTest
@testable import Spottr

final class PoseDetectorTests: XCTestCase {
    #if !SPOTTR_EXPERIMENTAL_PRESAGE
    func testFullPoseModelUsedByThePushupPrototypeIsBundledForOfflineTracking() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "pose_landmarker_full", withExtension: "task"))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 9_000_000)
    }
    #endif

    func testBundledMediaPipeFindsHumanAndRejectsBlankImage() throws {
        let detector = try PoseDetector()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pose", withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let result = try detector.detect(image, at: 0)
        XCTAssertEqual(result.points.count, 33)
        XCTAssertGreaterThan(result.points.filter { $0.confidence > 0.6 }.count, 10)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 640))
        }
        XCTAssertTrue(try detector.detect(blank, at: 1).points.isEmpty)
    }
}

@MainActor
final class TrackingContinuityFlowTests: XCTestCase {
    func testSquatKeepsItsObservedBodySideWhenJointsBrieflyDisappear() async throws {
        for oppositeSideVisible in [false, true] {
            let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in })
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
            let store = TrainingStore(historyURL: url, vision: vision)
            store.selectedExercise = .squat; store.start(); store.hasInput = true
            defer { store.cancelCoaching(); vision.stop() }
            for (time, angle) in [(0.0, 170.0), (0.2, 170), (0.6, 90), (0.8, 90)] {
                try await deliver(pose(time, angle, sides: [1]), to: store)
            }
            try await deliver(pose(1.0, 90, sides: oppositeSideVisible ? [0] : []), to: store)
            try await deliver(pose(1.2, 90, sides: []), to: store)
            try await deliver(pose(1.4, 90, sides: [0, 1]), to: store)
            try await deliver(pose(1.8, 170, sides: [0, 1]), to: store)
            try await deliver(pose(2.0, 170, sides: [0, 1]), to: store)
            XCTAssertEqual(store.session.counter.reps, 1, "A short joint dropout must not switch legs and discard observed squat depth")
        }
    }

    func testInvisibleSquatBottomCannotCreateACountedRep() async throws {
        let vision = VisionWorker(cameraAvailable: { false }, requestAccess: { _ in })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let store = TrainingStore(historyURL: url, vision: vision)
        store.selectedExercise = .squat; store.start(); store.hasInput = true
        defer { store.cancelCoaching(); vision.stop() }
        for (time, angle, visible) in [(0.0, 170.0, true), (0.2, 170, true), (0.6, 90, false),
                                       (0.8, 90, false), (1.2, 170, true), (1.4, 170, true)] {
            try await deliver(pose(time, angle, sides: visible ? [1] : []), to: store)
        }
        XCTAssertEqual(store.session.counter.reps, 0)
    }

    private func deliver(_ frame: PoseFrame, to store: TrainingStore) async throws {
        store.vision.onFrame?(frame, UIImage(), store.session.generation)
        for _ in 0..<100 {
            if store.frame?.time == frame.time { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The current-generation camera frame was not delivered")
    }

    private func pose(_ time: Double, _ angle: Double, sides: Set<Int>) -> PoseFrame {
        var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
        for side in sides {
            let x = 0.4 + Double(side) * 0.1
            points[23 + side] = .init(x: x, y: 0.25, confidence: 1)
            points[25 + side] = .init(x: x, y: 0.5, confidence: 1)
            points[27 + side] = .init(x: x + sin(angle * .pi / 180) * 0.25,
                                    y: 0.5 - cos(angle * .pi / 180) * 0.25, confidence: 1)
        }
        return .init(time: time, width: 640, height: 640, points: points)
    }
}
