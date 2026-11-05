// Test-only WCSession delivery boundary. No radio, pairing or Apple SDK acceptance.
@_exported import Foundation
public protocol WCSessionDelegate: AnyObject {}
public enum WCSessionActivationState { case notActivated, activated }
public final class WCSessionUserInfoTransfer {
    public let userInfo: [String: Any]
    public init(userInfo: [String: Any]) { self.userInfo = userInfo }
}
public final class WCSession {
    public static let `default` = WCSession()
    public static func isSupported() -> Bool { true }
    public weak var delegate: WCSessionDelegate?
    public var activationState = WCSessionActivationState.activated
    public var isReachable = true
    public var messageReply: (([String: Any]) -> [String: Any])?
    public var receivedApplicationContext: [String: Any] = [:]
    public private(set) var applicationContext: [String: Any] = [:]
    public private(set) var messages: [[String: Any]] = []
    public private(set) var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] = []
    public private(set) var transfers: [WCSessionUserInfoTransfer] = []
    public func transferUserInfo(_ payload: [String: Any]) -> WCSessionUserInfoTransfer {
        let transfer = WCSessionUserInfoTransfer(userInfo: payload)
        outstandingUserInfoTransfers.append(transfer); transfers.append(transfer)
        return transfer
    }
    public func complete(_ transfer: WCSessionUserInfoTransfer) {
        outstandingUserInfoTransfers.removeAll { $0 === transfer }
    }
    public init() {}
    public func activate() {}
    public func updateApplicationContext(_ payload: [String: Any]) throws { applicationContext = payload }
    public func sendMessage(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
        messages.append(payload); replyHandler?(messageReply?(payload) ?? ["received": true])
    }
}
