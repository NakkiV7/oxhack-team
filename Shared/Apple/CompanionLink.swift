import Foundation
import WatchConnectivity

final class CompanionLink: NSObject, WCSessionDelegate {
    var onSnapshot: ((CompanionSnapshot) -> Void)?
    var onCommand: ((CompanionCommand) -> Void)?
    var onTelemetry: ((WatchTelemetry) -> Void)?
    var onReachability: ((Bool) -> Void)?
    var onRequest: (() -> Void)?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        super.init(); session?.delegate = self; session?.activate()
    }
    func publish(_ snapshot: CompanionSnapshot) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let payload: [String: Any] = ["snapshot": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }
    func command(_ command: CompanionCommand, completion: @escaping (Bool) -> Void) {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder().encode(command) else { completion(false); return }
        session.sendMessage(["command": data], replyHandler: { _ in completion(true) }, errorHandler: { _ in completion(false) })
    }
    func telemetry(_ telemetry: WatchTelemetry) {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(telemetry) else { return }
        let payload: [String: Any] = ["telemetry": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }
    func request() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": true], replyHandler: nil, errorHandler: nil)
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
        onReachability?(session.isReachable)
        onRequest?()
    }
    func sessionReachabilityDidChange(_ session: WCSession) { onReachability?(session.isReachable); onRequest?() }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message); replyHandler(["received": true])
    }
    private func receive(_ payload: [String: Any]) {
        if let data = payload["snapshot"] as? Data, let snapshot = try? JSONDecoder().decode(CompanionSnapshot.self, from: data) { onSnapshot?(snapshot) }
        if let data = payload["command"] as? Data, let command = try? JSONDecoder().decode(CompanionCommand.self, from: data) { onCommand?(command) }
        if let data = payload["telemetry"] as? Data, let telemetry = try? JSONDecoder().decode(WatchTelemetry.self, from: data) { onTelemetry?(telemetry) }
        if payload["request"] as? Bool == true { onRequest?() }
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
