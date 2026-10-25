import Foundation

final class CompanionLink {
    var onSnapshot: ((CompanionSnapshot) -> Void)?
    var onReachability: ((Bool) -> Void)?
    private(set) var commands: [CompanionCommand] = []
    private(set) var samples: [WatchTelemetry] = []
    func request() {}
    func command(_ command: CompanionCommand, completion: @escaping (Bool) -> Void) {
        commands.append(command); completion(true)
    }
    func telemetry(_ telemetry: WatchTelemetry) { samples.append(telemetry) }
}
