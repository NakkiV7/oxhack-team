// Test-only WCSession delivery boundary. No radio, pairing or Apple SDK acceptance.
@_exported import Foundation
public protocol WCSessionDelegate: AnyObject {}
public enum WCSessionActivationState { case notActivated, activated }
public final class WCSession {
    public static let `default` = WCSession()
    public static func isSupported() -> Bool { true }
    public weak var delegate: WCSessionDelegate?
    public var activationState = WCSessionActivationState.activated
    public var isReachable = true
    public var receivedApplicationContext: [String: Any] = [:]
    public private(set) var applicationContext: [String: Any] = [:]
    public private(set) var messages: [[String: Any]] = []
    public init() {}
    public func activate() {}
    public func updateApplicationContext(_ payload: [String: Any]) throws { applicationContext = payload }
    public func sendMessage(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
        messages.append(payload); replyHandler?(["received": true])
    }
}
