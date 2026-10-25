import XCTest
@testable import Spottr

final class VisionLifecycleTests: XCTestCase {
    func testStopCancelsPendingCameraPermission() async {
        var permissionReply: ((Bool) -> Void)?
        let worker = VisionWorker(cameraAvailable: { true }, requestAccess: { permissionReply = $0 })
        let lateState = expectation(description: "Stopped request must not open camera or publish state")
        lateState.isInverted = true
        worker.onState = { _, _ in lateState.fulfill() }
        worker.camera(token: UUID())
        worker.stop()
        permissionReply?(true)
        await fulfillment(of: [lateState], timeout: 0.3)
        XCTAssertFalse(worker.capture.isRunning)
    }
}
