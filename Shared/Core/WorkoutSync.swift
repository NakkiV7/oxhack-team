import Foundation

public struct WorkoutSyncReceipt: Decodable, Equatable, Sendable {
    public let workoutID: UUID
    public let replayed: Bool
    public let sha256: String
}

public enum WorkoutSyncError: Error, Equatable, LocalizedError {
    case configuration, rejected(Int), invalidReceipt, noCompletedSets
    public var errorDescription: String? {
        switch self {
        case .noCompletedSets: return "Skipped steps stay in your local history. There are no completed sets to upload."
        case .configuration: return "Set an HTTPS gateway URL and access token in Coach settings. Localhost HTTP is supported for development."
        case .invalidReceipt: return "The gateway didn’t confirm this workout. Retry to check its saved state."
        case .rejected(401): return "Gateway access was refused. Check your access token in Coach settings."
        case .rejected(403): return "This installation isn’t linked to the gateway. Match the installation ID shown below in the server configuration."
        case .rejected(409): return "A different snapshot of this workout is already stored. Your local workout is unchanged."
        case .rejected(503): return "Cloud storage is unavailable or not configured. Your workout is still saved on this iPhone."
        case .rejected(let status): return "Cloud sync couldn’t finish (\(status)). Your local workout is still saved. Try again."
        }
    }
}

public struct WorkoutSyncClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let transport: CoachGatewayClient.Transport
    public init(baseURL: URL, token: String, transport: @escaping CoachGatewayClient.Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL; self.token = token; self.transport = transport
    }

    public func upload(record: SessionRecord, installationID: UUID) async throws -> WorkoutSyncReceipt {
        guard record.skippedSets.isEmpty || record.setCount > 0 else { throw WorkoutSyncError.noCompletedSets }
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.host != nil, (baseURL.scheme == "https" || (local && baseURL.scheme == "http")),
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkoutSyncError.configuration }
        try Task.checkCancellation()
        struct LegacyTelemetry: Encodable {
            let sessionID: UUID
            let sentAt: Date
            let heartRate: SensorReading?
            let accelerationG: SensorReading?
            let rotationRadiansPerSecond: SensorReading?
            init(_ sample: WatchTelemetry) {
                sessionID = sample.sessionID; sentAt = sample.sentAt; heartRate = sample.heartRate
                accelerationG = sample.accelerationG; rotationRadiansPerSecond = sample.rotationRadiansPerSecond
            }
        }
        struct SyncRecord: Encodable {
            let id: UUID
            let date: Date
            let sets: [SetRecord]
            let telemetry: [LegacyTelemetry]
            let loggedSets: [LoggedSet]
        }
        struct Upload: Encodable { let installationID: String; let record: SyncRecord }
        let projected = SyncRecord(id: record.id, date: record.date, sets: record.sets,
                                   telemetry: record.telemetry.filter {
                                       $0.activeEnergy == nil || $0.heartRate != nil || $0.accelerationG != nil || $0.rotationRadiansPerSecond != nil
                                   }.map(LegacyTelemetry.init), loggedSets: record.loggedSets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, output in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var value = output.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/workouts"))
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Upload(installationID: installationID.uuidString.lowercased(), record: projected))
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw WorkoutSyncError.invalidReceipt }
        guard response.statusCode == 200 || response.statusCode == 201 else { throw WorkoutSyncError.rejected(response.statusCode) }
        guard !data.isEmpty, data.count <= 65_536, let receipt = try? JSONDecoder().decode(WorkoutSyncReceipt.self, from: data),
              receipt.workoutID == record.id, receipt.sha256.count == 64,
              receipt.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }), receipt.replayed == (response.statusCode == 200) else { throw WorkoutSyncError.invalidReceipt }
        return receipt
    }
}
