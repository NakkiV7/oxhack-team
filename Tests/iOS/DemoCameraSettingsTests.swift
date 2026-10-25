import XCTest
@testable import Spottr

@MainActor
final class DemoCameraSettingsTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)
    private func pairing(url: String = "https://preview-camera.local:8765", pin: String? = nil,
                         token: String = "synthetic-preview-token") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["url": url, "certificateSHA256": pin ?? self.pin, "token": token])
    }

    func testExplicitPreviewPairingUsesValidatedMemoryDataWithoutAccessingKeychain() throws {
        let store = DemoPairingStore()
        store.forbidAccess = true
        let data = try pairing(url: " https://preview-camera.local:8765/ ", pin: pin.uppercased())
        let connection = try XCTUnwrap(SecondaryCameraSettings.connection(store: store, previewData: data))
        XCTAssertEqual(connection.configuration.baseURL.absoluteString, "https://preview-camera.local:8765/")
        XCTAssertEqual(connection.configuration.certificateSHA256, pin)
        XCTAssertEqual(connection.token, "synthetic-preview-token")
        let client = try SecondaryCameraSettings.client(store: store, previewData: data)
        XCTAssertEqual(client.status, .stopped, "Reading preview pairing must not start capture")
        XCTAssertEqual(store.accesses, 0)
    }

    func testMalformedPreviewDataFailsClosedWithoutFallingBackToSavedPairing() throws {
        let store = DemoPairingStore()
        store.value = try pairing(url: "https://normal-camera.local", token: "synthetic-normal-token")
        store.forbidAccess = true
        let invalid = [Data(), Data("not-json".utf8),
                       try pairing(url: "http://preview-camera.local"),
                       try pairing(pin: "invalid"), try pairing(token: ""), try pairing(token: "bad\ntoken")]
        for data in invalid {
            XCTAssertThrowsError(try SecondaryCameraSettings.connection(store: store, previewData: data))
            XCTAssertThrowsError(try SecondaryCameraSettings.client(store: store, previewData: data))
        }
        XCTAssertEqual(store.accesses, 0)
    }

    func testNilPreviewDataPreservesNormalSecretStoreBehaviorAndMissingPairing() throws {
        let store = DemoPairingStore()
        let original = try pairing(url: "https://normal-camera.local", token: "synthetic-normal-token")
        store.value = original
        let connection = try XCTUnwrap(SecondaryCameraSettings.connection(store: store, previewData: nil))
        XCTAssertEqual(connection.configuration.baseURL.host, "normal-camera.local")
        XCTAssertEqual(connection.token, "synthetic-normal-token")
        XCTAssertEqual(try SecondaryCameraSettings.client(store: store, previewData: nil).status, .stopped)
        XCTAssertEqual(store.value, original)
        XCTAssertEqual(store.reads, 2)
        XCTAssertEqual(store.writes, 0)
        store.value = nil
        XCTAssertNil(try SecondaryCameraSettings.connection(store: store, previewData: nil))
        XCTAssertThrowsError(try SecondaryCameraSettings.client(store: store, previewData: nil))
    }
}

@MainActor
private final class DemoPairingStore: SecondaryCameraSecretStore {
    var value: Data?
    var forbidAccess = false
    var accesses = 0, reads = 0, writes = 0
    private func access() throws {
        accesses += 1
        if forbidAccess { XCTFail("Explicit preview pairing must not access Keychain"); throw SecondaryCameraError.configuration }
    }
    func read() throws -> Data? { try access(); reads += 1; return value }
    func write(_ data: Data) throws { try access(); writes += 1; value = data }
    func remove() throws { try access(); value = nil }
}
