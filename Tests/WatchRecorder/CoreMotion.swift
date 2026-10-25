// Test-only device-motion boundary; callbacks can be delivered after stop.
@_exported import Foundation

public struct CMAcceleration {
    public let x: Double, y: Double, z: Double
    public init(x: Double = 0.1, y: Double = 0.2, z: Double = 0.3) { self.x = x; self.y = y; self.z = z }
}
public struct CMRotationRate {
    public let x: Double, y: Double, z: Double
    public init(x: Double = 0.1, y: Double = 0.2, z: Double = 0.3) { self.x = x; self.y = y; self.z = z }
}
public final class CMDeviceMotion {
    public let userAcceleration: CMAcceleration
    public let rotationRate: CMRotationRate
    public let timestamp: TimeInterval
    public init(acceleration: CMAcceleration = CMAcceleration(), rotation: CMRotationRate = CMRotationRate(),
                timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.userAcceleration = acceleration; self.rotationRate = rotation; self.timestamp = timestamp
    }
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
    public func deliverQueuedSample(_ sample: CMDeviceMotion = CMDeviceMotion()) { callback?(sample, nil) }
}
