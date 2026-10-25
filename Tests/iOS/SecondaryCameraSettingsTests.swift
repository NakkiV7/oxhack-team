import XCTest
@testable import Spottr

@MainActor
private final class PairingFixtureStore: SecondaryCameraSecretStore {
    var value: Data?
    var rejectWrite = false
    func read() throws -> Data? { value }
    func write(_ data: Data) throws {
        if rejectWrite { throw SecondaryCameraError.configuration }
        value = data
    }
    func remove() throws { value = nil }
}

@MainActor
final class SecondaryCameraSettingsTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)
    func testPairingSavesNormalizedDeviceAndSecretAsOneRecordWithoutOpeningCamera() throws {
        let store = PairingFixtureStore()
        XCTAssertNil(try SecondaryCameraSettings.connection(store: store))
        try SecondaryCameraSettings.save(url: " https://camera.local:8765/ ", certificateSHA256: pin.uppercased(), token: "fixture-private", store: store)
        let connection = try XCTUnwrap(SecondaryCameraSettings.connection(store: store))
        XCTAssertEqual(connection.configuration.baseURL.absoluteString, "https://camera.local:8765/")
        XCTAssertEqual(connection.configuration.certificateSHA256, pin)
        XCTAssertEqual(connection.token, "fixture-private")
        let client = try SecondaryCameraSettings.client(store: store)
        XCTAssertEqual(client.status, .stopped)
    }
    func testInvalidReplacementAndFailedSavePreserveExistingPairing() throws {
        let store = PairingFixtureStore()
        try SecondaryCameraSettings.save(url: "https://camera.local", certificateSHA256: pin, token: "first-private", store: store)
        let original = store.value
        for (url, token) in [("http://camera.local", "valid"), ("https://camera.local", "bad\ntoken")] {
            XCTAssertThrowsError(try SecondaryCameraSettings.save(url: url, certificateSHA256: pin, token: token, store: store))
            XCTAssertEqual(store.value, original)
        }
        store.rejectWrite = true
        XCTAssertThrowsError(try SecondaryCameraSettings.save(url: "https://other.local", certificateSHA256: pin, token: "second-private", store: store))
        XCTAssertEqual(store.value, original)
    }
    func testManualFormLoadsSavedPairingAndReportsInvalidEditsWithoutChangingIt() throws {
        let store = PairingFixtureStore()
        try SecondaryCameraSettings.save(url: "https://camera.local", certificateSHA256: pin, token: "private-fixture", store: store)
        let form = SecondaryCameraPairingForm(store: store)
        XCTAssertEqual(form.url, "https://camera.local")
        XCTAssertEqual(form.certificateSHA256, pin)
        XCTAssertEqual(form.token, "private-fixture")
        form.url = "http://unsafe.local"
        XCTAssertFalse(form.save())
        XCTAssertNotNil(form.errorMessage)
        XCTAssertEqual(try SecondaryCameraSettings.connection(store: store)?.configuration.baseURL.host, "camera.local")
        form.url = "https://replacement.local"
        XCTAssertTrue(form.save())
        XCTAssertNil(form.errorMessage)
        XCTAssertEqual(try SecondaryCameraSettings.connection(store: store)?.configuration.baseURL.host, "replacement.local")
        XCTAssertTrue(form.forget())
        XCTAssertEqual(form.token, "")
        XCTAssertNil(try SecondaryCameraSettings.connection(store: store))
    }
    func testForgetRemovesTheEntirePairingAndCorruptRecordsFailClosed() throws {
        let store = PairingFixtureStore()
        store.value = Data("corrupt-private-value".utf8)
        XCTAssertThrowsError(try SecondaryCameraSettings.connection(store: store)) { error in
            XCTAssertFalse(error.localizedDescription.contains("corrupt-private-value"))
        }
        try SecondaryCameraSettings.forget(store: store)
        XCTAssertNil(try SecondaryCameraSettings.connection(store: store))
        XCTAssertThrowsError(try SecondaryCameraSettings.client(store: store))
    }
}
