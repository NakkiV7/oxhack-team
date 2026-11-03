import ImageIO
import UIKit
import Vision
import XCTest
@testable import Spottr

#if SPOTTR_EXPERIMENTAL_PRESAGE
import SmartSpectra
final class PresagePoseCompatibilityTests: XCTestCase {
    @MainActor func testPresageHRVMappingRetainsValuesUnitsIdentityAndEpochTimeWithoutStartingSDK() {
        let session = UUID(), measurement = UUID()
        var hrv = Hrv()
        hrv.rmssd = 34; hrv.sdnn = 42; hrv.meanNn = 800; hrv.baevsky = 65
        hrv.timestamp = 1_001_000_000; hrv.confidence = 88; hrv.stable = true
        var metrics = Metrics(); metrics.cardio.hrv = [hrv]
        let values = SmartSpectraDriver.samples(from: metrics, sessionID: session, measurementID: measurement)
        XCTAssertEqual(values.count, 4)
        for (metric, value) in [(CameraVitalMetric.hrvRMSSD, 34.0), (.hrvSDNN, 42), (.meanNN, 800), (.stressIndex, 65)] {
            let sample = values.first { $0.metric == metric }
            XCTAssertEqual(sample?.value, value)
            XCTAssertEqual(sample?.date, Date(timeIntervalSince1970: 1001))
            XCTAssertEqual(sample?.sessionID, session); XCTAssertEqual(sample?.measurementID, measurement)
            XCTAssertEqual(sample?.confidence, 88); XCTAssertEqual(sample?.stable, true)
        }
        XCTAssertEqual(SmartSpectraDriver.failureGuidance(code: 4), "Presage credits are exhausted. Add credits before trying again.")
        XCTAssertFalse(SmartSpectraDriver.failureGuidance(code: 999).isEmpty)
    }

    func testQuarterTurnCoordinatesReturnToOriginalSideCameraImage() {
        for (turns, x, y) in [(0, 0.25, 0.4), (1, 0.4, 0.75), (2, 0.75, 0.6), (3, 0.6, 0.25)] {
            let frame = AppleVisionPoseAdapter.frame(observations: [[.leftShoulder: .init(x: 0.25, y: 0.6, confidence: 0.9)]],
                time: 3, size: CGSize(width: 640, height: 360), quarterTurns: turns)
            XCTAssertEqual(frame.width, 640)
            XCTAssertEqual(frame.height, 360)
            XCTAssertEqual(frame.points[11].x, x, accuracy: 0.000001)
            XCTAssertEqual(frame.points[11].y, y, accuracy: 0.000001)
            XCTAssertEqual(frame.points[11].confidence, 0.9)
        }
    }

    func testHorizontalPoseFallbackStaysOnTheAcquiredOrientationAndCanReacquire() throws {
        var calls: [CGImagePropertyOrientation] = []
        var preferredLost = false
        let joints: [VNHumanBodyPoseObservation.JointName: PosePoint] = [
            .leftShoulder: .init(x: 0.2, y: 0.8, confidence: 0.95),
            .leftElbow: .init(x: 0.3, y: 0.6, confidence: 0.95),
            .leftWrist: .init(x: 0.4, y: 0.4, confidence: 0.95),
            .leftHip: .init(x: 0.6, y: 0.5, confidence: 0.95)]
        let detector = try PoseDetector(observe: { _, orientation in
            calls.append(orientation)
            return (preferredLost ? orientation == .up : orientation == .right) ? [joints] : []
        })
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).image { _ in }
        XCTAssertEqual(try detector.detect(image, at: 0).points.count, 33)
        XCTAssertEqual(calls, [.up, .right])
        calls = []
        _ = try detector.detect(image, at: 1)
        XCTAssertEqual(calls, [.right], "A good orientation should not cost three inferences each frame")
        calls = []; preferredLost = true
        XCTAssertEqual(try detector.detect(image, at: 2).points.count, 33)
        XCTAssertEqual(calls, [.right, .up])
    }

    func testMultiplePeopleCannotBeRescuedByTryingAnotherOrientation() throws {
        var calls = 0
        let detector = try PoseDetector(observe: { _, _ in
            calls += 1
            return [[.leftHip: .init(x: 0.2, y: 0.3, confidence: 1)], [.leftHip: .init(x: 0.7, y: 0.5, confidence: 1)]]
        })
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        XCTAssertTrue(try detector.detect(image, at: 0).points.isEmpty)
        XCTAssertEqual(calls, 1)
    }

    func testVisionJointsPreserveSideIdentityConfidenceDimensionsAndImageCoordinates() {
        let frame = AppleVisionPoseAdapter.frame(observations: [[
            .leftShoulder: .init(x: 0.2, y: 0.8, confidence: 0.9),
            .rightWrist: .init(x: 0.7, y: 0.6, confidence: 0.75),
            .leftHip: .init(x: 0.25, y: 0.5, confidence: 0.8),
            .rightAnkle: .init(x: 0.8, y: 0.1, confidence: 0.7)
        ]], time: 17, size: CGSize(width: 640, height: 360))
        XCTAssertEqual(frame.time, 17)
        XCTAssertEqual(frame.width, 640)
        XCTAssertEqual(frame.height, 360)
        XCTAssertEqual(frame.points.count, 33)
        XCTAssertEqual(frame.points[11].x, 0.2)
        XCTAssertEqual(frame.points[11].y, 0.2, accuracy: 0.000001)
        XCTAssertEqual(frame.points[11].confidence, 0.9)
        XCTAssertEqual(frame.points[16].y, 0.4, accuracy: 0.000001)
        XCTAssertEqual(frame.points[23].x, 0.25)
        XCTAssertEqual(frame.points[28].y, 0.9, accuracy: 0.000001)
        XCTAssertEqual(frame.points[12].confidence, 0, "Missing joints cannot invent the other side")
        XCTAssertEqual(frame.points[31].confidence, 0, "Vision does not provide MediaPipe foot-index landmarks")
    }

    func testNoPersonOrMultiplePeopleCannotProduceWorkoutObservations() {
        let person: [VNHumanBodyPoseObservation.JointName: PosePoint] = [.leftHip: .init(x: 0.2, y: 0.3, confidence: 1)]
        for observations in [[], [person, person]] {
            XCTAssertTrue(AppleVisionPoseAdapter.frame(observations: observations, time: 0, size: CGSize(width: 360, height: 640)).points.isEmpty)
        }
    }

    func testUIImageOrientationIsConvertedByMeaningRatherThanIncompatibleRawValues() {
        let cases: [(UIImage.Orientation, CGImagePropertyOrientation)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right),
            (.upMirrored, .upMirrored), (.downMirrored, .downMirrored),
            (.leftMirrored, .leftMirrored), (.rightMirrored, .rightMirrored)
        ]
        for (image, vision) in cases { XCTAssertEqual(AppleVisionPoseAdapter.orientation(for: image), vision) }
    }
}
#endif
