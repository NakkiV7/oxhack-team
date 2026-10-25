import XCTest
@testable import Spottr

@MainActor
final class CoachSettingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_886_400)
    private func credential(expiry: Date) throws -> Data {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try JSONSerialization.data(withJSONObject: ["token": String(repeating: "d", count: 32), "expiresAt": format.string(from: expiry)])
    }

    func testPublicHostIsDefaultAndExplicitCustomChoiceIsPreserved() throws {
        let suite = "CoachSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CoachSettings.address(defaults: defaults), "https://spottr.omarchoudhry.co.uk/demo")
        defaults.set("https://custom.example", forKey: "coach.gatewayURL")
        XCTAssertEqual(CoachSettings.address(defaults: defaults), "https://custom.example")
        CoachSettings.resetAddress(defaults: defaults)
        XCTAssertEqual(CoachSettings.address(defaults: defaults), "https://spottr.omarchoudhry.co.uk/demo")
    }

    func testFreshPrivateInjectionIsSavedOnceWithoutNetworkAccess() throws {
        let injected = try credential(expiry: now.addingTimeInterval(3600))
        var stored: Data?, writes = 0
        for _ in 0..<2 {
            let token = try CoachSettings.demoToken(injected: injected, now: now, read: { stored }, write: { stored = $0; writes += 1 })
            XCTAssertEqual(token, String(repeating: "d", count: 32))
        }
        XCTAssertEqual(stored, injected)
        XCTAssertEqual(writes, 1)
    }

    func testMissingExpiredMalformedAndOverlongInjectionFailClosed() throws {
        let valid = try credential(expiry: now.addingTimeInterval(60))
        for data in [nil, Data("{}".utf8), try credential(expiry: now), try credential(expiry: now.addingTimeInterval(86_401))] {
            var writes = 0
            XCTAssertThrowsError(try CoachSettings.demoToken(injected: data, now: now, read: { nil }, write: { _ in writes += 1 }))
            XCTAssertEqual(writes, 0)
        }
        XCTAssertThrowsError(try CoachSettings.demoToken(injected: valid, now: now, read: { nil }, write: { _ in throw CoachGatewayError.configuration }))
    }

    func testExpiredStoredAccessCanBeRenewedByNewPrivateBuildButNeverReturnedAtDeadline() throws {
        var stored: Data? = try credential(expiry: now)
        let renewed = try credential(expiry: now.addingTimeInterval(120))
        XCTAssertEqual(try CoachSettings.demoToken(injected: renewed, now: now, read: { stored }, write: { stored = $0 }), String(repeating: "d", count: 32))
        XCTAssertEqual(stored, renewed)
        XCTAssertThrowsError(try CoachSettings.demoToken(injected: renewed, now: now.addingTimeInterval(120), read: { stored }, write: { stored = $0 }))
    }

    func testStoredAccessWorksWithoutResourceAndDoesNotGetRewritten() throws {
        let stored = try credential(expiry: now.addingTimeInterval(120))
        XCTAssertEqual(try CoachSettings.demoToken(injected: nil, now: now, read: { stored }, write: { _ in XCTFail("Unexpected rewrite") }), String(repeating: "d", count: 32))
    }

    func testCredentialRejectsWhitespaceShortTokensAndNoncanonicalDates() throws {
        for fields in [
            ["token": String(repeating: "d", count: 32) + "\n", "expiresAt": "2026-10-25T01:00:00.000Z"],
            ["token": "short", "expiresAt": "2026-10-25T01:00:00.000Z"],
            ["token": String(repeating: "d", count: 32), "expiresAt": "2026-10-25T01:00:00Z"]
        ] {
            let data = try JSONSerialization.data(withJSONObject: fields)
            XCTAssertThrowsError(try CoachSettings.demoToken(injected: data, now: now, read: { nil }, write: { _ in XCTFail("Malformed access must not persist") }))
        }
    }
}
