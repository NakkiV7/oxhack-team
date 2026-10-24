// Test-only device-motion boundary; callbacks can be delivered after stop.
@_exported import Foundation

public struct CMAcceleration { public let x = 0.1, y = 0.2, z = 0.3 }
public struct CMRotationRate { public let x = 0.1, y = 0.2, z = 0.3 }
public final class CMDeviceMotion {
    public let userAcceleration = CMAcceleration()
    public let rotationRate = CMRotationRate()
    public let timestamp = ProcessInfo.processInfo.systemUptime
    public init() {}
}
public final class CMMotionManager {
    public static var created: [CMMotionManager] = []
    public let isDeviceMotionAvailable = true
    public var deviceMotionUpdateInterval: TimeInterval = 0
    public private(set) var isDeviceMotionActive = false
    private var callback: ((CMDeviceMotion?, Error?) -> Void)?
    public init() { Self.created.append(self) }
    public func startDeviceMotionUpdates(to queue: OperationQueue,
                                        withHandler handler: @escaping (CMDeviceMotion?, Error?) -> Void) {
        callback = handler; isDeviceMotionActive = true
    }
    public func stopDeviceMotionUpdates() { isDeviceMotionActive = false }
    public func deliverQueuedSample() { callback?(CMDeviceMotion(), nil) }
}
