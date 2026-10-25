import XCTest
@testable import Spottr

final class PoseDetectorTests: XCTestCase {
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
