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
        guard !isLoading else { return }
        generation = UUID(); let current = generation
        isLoading = true; error = nil; receipt = nil
        do {
            let result = try await configuration().upload(record: record, installationID: installationID)
            guard generation == current, !Task.isCancelled else { return }
            receipt = result; isLoading = false
        } catch {
            guard generation == current else { return }
            isLoading = false
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Cloud sync couldn’t finish. Your local workout is still saved. Try again."
        }
    }
    func cancel() { generation = UUID(); isLoading = false }
    func invalidate() { cancel(); receipt = nil; error = nil }
}

struct CloudSyncCard: View {
    let record: SessionRecord
    @State private var model = CloudSyncModel()
    @State private var installationID = CloudInstallation.id()
    @State private var task: Task<Void, Never>?
    @State private var settingsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Cloud backup", systemImage: "externaldrive.badge.icloud").font(.headline)
            Text("Save a copy of this workout to your configured Tiger database. This includes recorded sets, timestamps and any Watch heart-rate and motion readings. Your local workout stays on this iPhone.")
                .font(.caption).foregroundStyle(.secondary)
            if let receipt = model.receipt {
                Label(receipt.replayed ? "Already saved · cloud copy confirmed" : "Cloud copy confirmed", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                Text("Workout \(receipt.workoutID.uuidString.prefix(8)) · receipt \(receipt.sha256.prefix(12))").font(.caption2).monospaced().foregroundStyle(.secondary)
            }
            if model.isLoading {
                HStack {
                    ProgressView(); Text("Saving cloud copy…").font(.caption); Spacer()
                    Button("Cancel") { task?.cancel(); model.cancel() }.font(.caption.weight(.semibold))
                }
            } else {
                Button(model.receipt == nil ? "Sync this workout" : "Check saved copy") {
                    task = Task { await model.sync(record: record, installationID: installationID) }
                }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("sync-workout")
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            DisclosureGroup("Cloud connection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use the same gateway connection as Coach. On your server, set SPOTTR_INSTALLATION_ID to this iPhone’s ID before syncing.").font(.caption).foregroundStyle(.secondary)
                    Text(installationID.uuidString.lowercased()).font(.caption2).monospaced().textSelection(.enabled)
                    Button("Copy installation ID") { UIPasteboard.general.string = installationID.uuidString.lowercased() }.font(.caption.weight(.semibold))
                    Button("Connection settings") { settingsPresented = true }.font(.caption.weight(.semibold))
                }.padding(.top, 8)
            }.font(.caption.weight(.medium))
            Text("Uploads happen only when you tap. Repeating an unchanged upload confirms the same snapshot. Cancelling may leave a completed server copy; sync again to confirm.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .sheet(isPresented: $settingsPresented) { CoachSettingsView() }
            .onChange(of: record) { _, _ in task?.cancel(); model.invalidate() }
            .onDisappear { task?.cancel(); model.cancel() }
    }
}
