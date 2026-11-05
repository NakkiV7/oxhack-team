import XCTest
import WatchConnectivity
@testable import Spottr

@MainActor
final class WatchSetupConnectionTests: XCTestCase {
    func testOpeningSetupReadsConnectionWithoutReplacingSharedDelegate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let original = session.delegate
        let setup = WatchSetupStore()
        setup.refresh()
        XCTAssertTrue(session.delegate === original)
        XCTAssertEqual(setup.presentation.milestones.count, 4)
    }
}
