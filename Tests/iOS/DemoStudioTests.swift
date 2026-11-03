import XCTest
import AVFoundation
@testable import Spottr

final class DemoStudioTests: XCTestCase {
    func testBothPitchExamplesAreBundledPlayableMovies() async throws {
        for name in ["squat_side", "pushup_side"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "mp4"))
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            XCTAssertTrue(playable)
            XCTAssertGreaterThan(duration, 1)
            XCTAssertLessThan(duration, 120)
        }
    }
}
