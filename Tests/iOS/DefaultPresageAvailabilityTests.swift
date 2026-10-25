import Foundation
import MachO
import XCTest
@testable import Spottr

@MainActor
final class DefaultPresageAvailabilityTests: XCTestCase {
    #if !SPOTTR_EXPERIMENTAL_PRESAGE
    func testDefaultAppDoesNotContainOrLoadSmartSpectra() {
        let frameworks = Bundle.main.privateFrameworksURL
        if let framework = frameworks?.appendingPathComponent("SmartSpectra.framework") {
            XCTAssertFalse(FileManager.default.fileExists(atPath: framework.path))
        }
        let images = (0..<_dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }
        XCTAssertFalse(images.contains { $0.contains("/SmartSpectra.framework/") })
        XCTAssertNil(NSClassFromString("PresagePreprocessing"))
        XCTAssertNil(NSClassFromString("PresageCameraInfo"))
    }

    func testDefaultDriverRejectsBeforeSDKConstructionWithClearBuildReason() {
        XCTAssertThrowsError(try SmartSpectraDriver(apiKey: "", sessionID: UUID(), measurementID: UUID())) { error in
            XCTAssertEqual(error.localizedDescription, "Presage is not included in this build.")
        }
    }
    #endif
}
