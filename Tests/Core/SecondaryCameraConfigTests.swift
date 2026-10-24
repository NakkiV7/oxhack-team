import XCTest
@testable import SpottrCore

final class SecondaryCameraConfigTests: XCTestCase {
    func testPairingRejectsPlaintextCredentialsQueriesPathsAndInvalidPins() {
        let pin = String(repeating: "a", count: 64)
        for url in ["", "camera.local", "http://192.0.2.14:8765", "https://user:fixture@camera.local",
                    "https://camera.local?token=fixture", "https://camera.local#fragment",
                    "https://camera.local/api", "https://camera.local:0", "https://camera.local:65536"] {
            XCTAssertThrowsError(try SecondaryCameraConfig(url: url, certificateSHA256: pin), url)
        }
        for invalid in ["", String(repeating: "x", count: 64), String(repeating: "a", count: 63)] {
            XCTAssertThrowsError(try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: invalid))
        }
    }
    func testExplicitHTTPSPairingNormalizesOnlyThePublicCertificatePin() throws {
        let pin = String(repeating: "AB:", count: 31) + "AB"
        let config = try SecondaryCameraConfig(url: " https://192.0.2.14:8765/ ", certificateSHA256: pin)
        XCTAssertEqual(config.baseURL.absoluteString, "https://192.0.2.14:8765/")
        XCTAssertEqual(config.certificateSHA256, String(repeating: "ab", count: 32))
    }
    func testFrameFreshnessIncludesServerAgeRequestDurationAndCaptureIdentity() throws {
        let metadata = try SecondaryCameraFrameMetadata(frameID: "capture:3", capturedAt: "2026-10-24T18:00:00.000+00:00",
            serverAgeMilliseconds: "100", expectedCaptureID: "capture", receivedAt: Date(timeIntervalSince1970: 1792864800.3),
            requestDuration: 0.2, afterSequence: 2)
        XCTAssertEqual(metadata.sequence, 3)
        XCTAssertEqual(metadata.validFor, 1.7, accuracy: 0.001)
        XCTAssertEqual(metadata.frameID, "capture:3")
    }
    func testFramesRejectOtherCapturesReorderingExpiredTimeAndInvalidAges() {
        let now = Date(timeIntervalSince1970: 1792864800.3)
        let fixtures: [(String, String, String, Double, Int64?)] = [
            ("old:3", "2026-10-24T18:00:00.000+00:00", "0", 0.1, nil),
            ("capture:0", "2026-10-24T18:00:00.000+00:00", "0", 0.1, nil),
            ("capture:2", "2026-10-24T18:00:00.000+00:00", "0", 0.1, 3),
            ("capture:3", "2026-10-24T18:00:00.000+00:00", "1800", 0.3, nil),
            ("capture:3", "2026-10-24T17:59:56.000+00:00", "0", 0.1, nil),
            ("capture:3", "2026-10-24T18:00:05.000+00:00", "0", 0.1, nil),
            ("capture:3", "2026-10-24T18:00:00.000+00:00", "nan", 0.1, nil),
            ("capture:3", "2026-10-24T18:00:00.000+00:00", "-1", 0.1, nil),
        ]
        for (id, timestamp, age, duration, sequence) in fixtures {
            XCTAssertThrowsError(try SecondaryCameraFrameMetadata(frameID: id, capturedAt: timestamp,
                serverAgeMilliseconds: age, expectedCaptureID: "capture", receivedAt: now,
                requestDuration: duration, afterSequence: sequence), "Accepted \(id) / \(age)")
        }
    }
    func testAccessTokenValidationRejectsEmptyOversizedAndHeaderUnsafeValues() {
        XCTAssertNoThrow(try SecondaryCameraConfig.validateAccessToken("private-fixture"))
        for invalid in ["", "contains space", "fixture\r\nHeader: injected", String(repeating: "a", count: 1025)] {
            XCTAssertThrowsError(try SecondaryCameraConfig.validateAccessToken(invalid))
        }
    }

}
