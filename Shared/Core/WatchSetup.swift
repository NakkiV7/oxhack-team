import Foundation

public enum WatchModelPreference: String, CaseIterable, Codable, Sendable {
    case se, series6OrLater, ultra, notSure, noWatch

    public var title: String {
        switch self {
        case .se: return "Apple Watch SE"
        case .series6OrLater: return "Series 6 or later"
        case .ultra: return "Apple Watch Ultra"
        case .notSure: return "Not sure"
        case .noWatch: return "No Watch"
        }
    }

    public var sensorExplanation: String {
        switch self {
        case .se:
            return "SE doesn’t measure blood oxygen. Existing Health readings from another device can still appear with their source and date."
        case .series6OrLater, .ultra:
            return "Available readings depend on your model, region and Health settings. Existing Health readings keep their source and date."
        case .notSure:
            return "That’s OK. Spottr uses the readings your Watch actually provides. Existing Health readings stay separate."
        case .noWatch:
            return "Train and save workouts on your iPhone. You can connect a Watch later."
        }
    }
}

public struct WatchSetupConfirmation: Equatable, Sendable {
    public let checkedAt: Date
    public let pendingSamples: Int
    public let droppedSamples: Int
    public let queueMessage: String?
    public let motionAvailable: Bool?

    public init(checkedAt: Date, pendingSamples: Int, droppedSamples: Int, queueMessage: String?, motionAvailable: Bool? = nil) {
        self.checkedAt = checkedAt; self.pendingSamples = pendingSamples
        self.droppedSamples = droppedSamples; self.queueMessage = queueMessage; self.motionAvailable = motionAvailable
    }

    public func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince(checkedAt)
        return age.isFinite && (0...15).contains(age)
    }
}

public struct WatchSetupObservation: Equatable, Sendable {
    public let supported: Bool
    public let activated: Bool
    public let paired: Bool
    public let installed: Bool
    public let reachable: Bool
    public let confirmation: WatchSetupConfirmation?
    public let lastDataReceivedAt: Date?

    public init(supported: Bool = false, activated: Bool = false, paired: Bool = false,
                installed: Bool = false, reachable: Bool = false,
                confirmation: WatchSetupConfirmation? = nil, lastDataReceivedAt: Date? = nil) {
        self.supported = supported; self.activated = activated; self.paired = paired
        self.installed = installed; self.reachable = reachable; self.confirmation = confirmation
        self.lastDataReceivedAt = lastDataReceivedAt
    }
}

public struct WatchSetupMilestone: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let isComplete: Bool
}

public struct WatchSetupPresentation: Sendable {
    public let summary: String
    public let milestones: [WatchSetupMilestone]
    public let queueText: String?
    public let lastCheckedAt: Date?
    public let lastDataReceivedAt: Date?
    public let needsInstallation: Bool
    public let motionText: String

    public init(observation: WatchSetupObservation, at date: Date) {
        let paired = observation.supported && observation.activated && observation.paired
        let installed = paired && observation.installed
        let reachable = installed && observation.reachable
        let confirmed = reachable && observation.confirmation?.isFresh(at: date) == true
        needsInstallation = !installed
        if confirmed, let available = observation.confirmation?.motionAvailable {
            motionText = available ? "Motion is available on your Watch" : "Motion is unavailable on this Watch"
        } else { motionText = "Motion availability has not been confirmed" }
        lastCheckedAt = observation.confirmation?.checkedAt
        lastDataReceivedAt = observation.lastDataReceivedAt
        milestones = [
            .init(id: "paired", title: "Watch paired", detail: paired ? "Reported by your iPhone" : "Pair your Watch in Apple’s Watch app", isComplete: paired),
            .init(id: "installed", title: "Spottr installed", detail: installed ? "Installed on your paired Watch" : "Install the companion on your Watch", isComplete: installed),
            .init(id: "reachable", title: "Live connection", detail: reachable ? "Your Watch is reachable now" : "Open Spottr on both devices nearby", isComplete: reachable),
            .init(id: "confirmed", title: "Companion checked", detail: confirmed ? "Spottr replied from your Watch" : "Check that the companion responds", isComplete: confirmed)
        ]
        if !observation.supported { summary = "Watch connection is unavailable on this device" }
        else if !observation.activated { summary = "Getting connection status" }
        else if !paired { summary = "Pair a Watch to get started" }
        else if !installed { summary = "Install Spottr on your Watch" }
        else if !reachable { summary = "Open Spottr on your Watch to connect" }
        else { summary = confirmed ? "Your Watch companion responded" : "Your Watch is reachable. Check the companion." }
        guard confirmed, let confirmation = observation.confirmation else { queueText = nil; return }
        if let message = confirmation.queueMessage { queueText = message }
        else if confirmation.droppedSamples > 0 {
            queueText = "\(confirmation.pendingSamples) waiting. \(confirmation.droppedSamples) removed at the Watch queue limit."
        } else {
            queueText = confirmation.pendingSamples > 0
                ? "\(confirmation.pendingSamples) Watch samples waiting for iPhone"
                : "No queued Watch samples at last check"
        }
    }
}

public struct WatchSetupProbe: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let sentAt: Date

    public init(sentAt: Date = Date()) { version = 1; id = UUID(); self.sentAt = sentAt }
}

public struct WatchSetupReply: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let pendingSamples: Int
    public let droppedSamples: Int
    public let queueMessage: String?
    public let motionAvailable: Bool?

    public init(requestID: UUID, pendingSamples: Int, droppedSamples: Int, queueMessage: String?, motionAvailable: Bool? = nil) {
        version = 1; self.requestID = requestID; self.pendingSamples = pendingSamples
        self.droppedSamples = droppedSamples; self.queueMessage = queueMessage; self.motionAvailable = motionAvailable
    }

    public func confirmation(for probe: WatchSetupProbe, receivedAt date: Date) -> WatchSetupConfirmation? {
        let elapsed = date.timeIntervalSince(probe.sentAt)
        guard version == 1, probe.version == 1, requestID == probe.id,
              elapsed.isFinite, (0...15).contains(elapsed),
              (0...7200).contains(pendingSamples), droppedSamples >= 0,
              (queueMessage?.count ?? 0) <= 512 else { return nil }
        return .init(checkedAt: date, pendingSamples: pendingSamples,
                     droppedSamples: droppedSamples, queueMessage: queueMessage, motionAvailable: motionAvailable)
    }
}
