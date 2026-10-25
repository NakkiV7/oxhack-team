import ImageIO
import UIKit
import Vision
import XCTest
@testable import Spottr

#if SPOTTR_EXPERIMENTAL_PRESAGE
final class PresagePoseCompatibilityTests: XCTestCase {
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
