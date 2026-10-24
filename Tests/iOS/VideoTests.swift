import XCTest
@testable import Spottr

final class VideoTests: XCTestCase {
    func testVideoPauseAndResumeContinueFromNextFrame() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "blank", withExtension: "mp4"))
        let worker = VisionWorker()
        let first = expectation(description: "First frame")
        let resumed = expectation(description: "Next frame after resume")
        let firstToken = UUID(), secondToken = UUID()
        worker.onFrame = { frame, _, token in
            worker.pause()
            if token == firstToken {
                XCTAssertEqual(frame.time, 0)
                first.fulfill()
            } else {
                XCTAssertEqual(frame.time, 0.1, accuracy: 0.001)
                XCTAssertEqual(token, secondToken)
                resumed.fulfill()
            }
        }
        worker.video(url: url, token: firstToken)
        await fulfillment(of: [first], timeout: 5)
        worker.resume(token: secondToken, source: .video)
        await fulfillment(of: [resumed], timeout: 5)
        worker.stop()
    }
}
