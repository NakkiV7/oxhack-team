import Foundation

public struct WorkoutSyncReceipt: Decodable, Equatable, Sendable {
    public let workoutID: UUID
    public let replayed: Bool
    public let sha256: String
}

public enum WorkoutSyncError: Error, Equatable, LocalizedError {
    case retired, configuration, rejected(Int), invalidReceipt, noCompletedSets
    public var errorDescription: String? {
        switch self {
        case .retired: return "Full-workout cloud upload is retired. Use protected local export or optional coarse statistics."
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
        throw WorkoutSyncError.retired
    }
}
