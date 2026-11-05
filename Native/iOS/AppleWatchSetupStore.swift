import Foundation
import WatchConnectivity

extension WatchSetupStore {
    convenience init() {
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        let defaults = namespace.flatMap { UserDefaults(suiteName: "Spottr.Watch.\($0.uuidString)") } ?? .standard
        self.init(defaults: defaults, observe: {
            guard WCSession.isSupported() else { return .init() }
            let session = WCSession.default
            let link = session.delegate as? CompanionLink
            return .init(supported: true, activated: session.activationState == .activated,
                         paired: session.isPaired, installed: session.isWatchAppInstalled, reachable: session.isReachable,
                         confirmation: link?.setupConfirmation, lastDataReceivedAt: link?.lastDataReceivedAt)
        }, request: {
            guard WCSession.isSupported() else { return }
            (WCSession.default.delegate as? CompanionLink)?.requestSetupStatus()
        })
    }
}
