import SwiftUI

@MainActor
enum CloudInstallation {
    static func id(defaults: UserDefaults = .standard, namespace: String? = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"]) -> UUID {
        let key = "cloud.installationID" + (namespace.map { ".\($0)" } ?? "")
        if let stored = defaults.string(forKey: key), let id = UUID(uuidString: stored) { return id }
        let id = UUID(); defaults.set(id.uuidString, forKey: key); return id
    }
}

@MainActor @Observable
final class CloudSyncModel {
    private(set) var isLoading = false
    private(set) var receipt: WorkoutSyncReceipt?
    private(set) var error: String?
    private var generation = UUID()
    private let configuration: @MainActor () throws -> WorkoutSyncClient

    init(configuration: @escaping @MainActor () throws -> WorkoutSyncClient = {
        guard let url = URL(string: CoachSettings.gatewayURL), !CoachSettings.gatewayURL.isEmpty,
              let token = CoachSettings.token(), !token.isEmpty else { throw WorkoutSyncError.configuration }
        return WorkoutSyncClient(baseURL: url, token: token)
    }) { self.configuration = configuration }

    func sync(record: SessionRecord, installationID: UUID) async {
        receipt = nil; isLoading = false; error = WorkoutSyncError.retired.errorDescription
    }
    func cancel() { generation = UUID(); isLoading = false }
    func invalidate() { cancel(); receipt = nil; error = nil }
}

struct CloudSyncCard: View {
    let record: SessionRecord
    var body: some View {
        Text("Full-workout cloud upload is retired. Your history remains available through protected local export.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
