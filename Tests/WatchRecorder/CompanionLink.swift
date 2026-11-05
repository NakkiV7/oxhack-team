import Foundation

final class CompanionLink {
    var onSnapshot: ((CompanionSnapshot) -> Void)?
    var onReachability: ((Bool) -> Void)?
    var onTelemetryDeliveryStatus: ((WatchTelemetryDeliveryStatus) -> Void)?
    var telemetryDeliveryStatus = WatchTelemetryDeliveryStatus()
    private(set) var commands: [CompanionCommand] = []
    private(set) var samples: [WatchTelemetry] = []
    private(set) var batches: [[WatchTelemetry]] = []
    private(set) var flushCount = 0
    func telemetryBatch(_ samples: [WatchTelemetry]) { batches.append(samples) }
    func flushTelemetry() { flushCount += 1 }
    func retryTelemetry() {}
    func request() {}
    func command(_ command: CompanionCommand, completion: @escaping (Bool) -> Void) {
        commands.append(command); completion(true)
    }
    func telemetry(_ telemetry: WatchTelemetry) { samples.append(telemetry) }
}
