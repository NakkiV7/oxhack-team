import Foundation

public struct CoachFact: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public struct CoachTurn: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, model }
    public var id: String { "\(role.rawValue):\(text)" }
    public let role: Role
    public let text: String
    public init(role: Role, text: String) { self.role = role; self.text = text }
}

public struct CoachRequest: Encodable, Sendable {
    public let generationID: String
    public let message: String?
    public let history: [CoachTurn]
    public let facts: [CoachFact]
    public let availableSupport: [String]
    public let kind: String?
    public let week: CoachWeekRequest?
    public init(generationID: String = UUID().uuidString, message: String? = nil, history: [CoachTurn] = [], facts: [CoachFact], availableSupport: [String] = [], kind: CoachSummaryKind? = nil, week: CoachWeekRequest? = nil) {
        self.generationID = generationID; self.message = message; self.history = history
        self.facts = facts; self.availableSupport = availableSupport; self.kind = kind?.rawValue; self.week = week
    }
    public var context: CoachValidationContext {
        .init(generationID: generationID, suppliedFactIDs: Set(facts.map(\.id)), availableSupport: Set(availableSupport))
    }
}

public enum CoachGatewayError: Error, Equatable, LocalizedError {
    case configuration, rejected(Int), invalidResponse, requestTooLarge
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Add your gateway URL and access token in Coach settings. Use HTTPS, or localhost for development."
        case .rejected(let code): return code == 401 ? "Gateway access was refused. Check your access token." : "The coach couldn’t respond (\(code)). Try again."
        case .invalidResponse: return "The coach returned an invalid response. Try again."
        case .requestTooLarge: return "This request is too large to send. Shorten your message or choose fewer saved sessions, then try again."
        }
    }
}

public struct CoachGatewayClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let baseURL: URL
    private let token: String
    private let transport: Transport
    public init(baseURL: URL, token: String, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL; self.token = token; self.transport = transport
    }
    public func chat(_ input: CoachRequest) async throws -> String {
        let data = try await send(input, path: "chat")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              Set(object.keys) == ["generationID", "text"], let text = object["text"],
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000 else { throw CoachGatewayError.invalidResponse }
        guard object["generationID"] == input.generationID else { throw CoachContractError.staleGeneration }
        return text
    }
    public func summary(_ input: CoachRequest, kind: CoachSummaryKind) async throws -> CoachSummary {
        try CoachContracts.parseSummary(await send(input, path: "summary"), context: input.context, kind: kind)
    }
    public func proposal(_ input: CoachRequest) async throws -> WorkoutProposal {
        try CoachContracts.parseProposal(await send(input, path: "proposal"), context: input.context)
    }
    public func weekProposal(_ input: CoachRequest, guidance: CoachGuidanceRegistry) async throws -> CoachWeekProposal {
        guard let week = input.week else { throw CoachContractError.invalidProposal }
        try week.validate()
        return try CoachWeekContracts.parse(await send(input, path: "week-proposal"), request: week, context: input.context, guidance: guidance)
    }
    private func send(_ input: CoachRequest, path: String) async throws -> Data {
        try await post(try boundedBody(input), path: path)
    }
    /// POSTs an already-bounded JSON body to `v1/<path>` with the same transport, URL and response checks as every route.
    func post(_ body: Data, path: String) async throws -> Data {
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard (baseURL.scheme == "https" || (local && baseURL.scheme == "http")), baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoachGatewayError.configuration }
        try Task.checkCancellation()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/\(path)"))
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CoachGatewayError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw CoachGatewayError.rejected(http.statusCode) }
        guard !data.isEmpty, data.count <= 65_536 else { throw CoachGatewayError.invalidResponse }
        return data
    }
    private func boundedBody(_ input: CoachRequest) throws -> Data {
        for removed in 0...input.history.count {
            let candidate = CoachRequest(generationID: input.generationID, message: input.message,
                history: Array(input.history.dropFirst(removed)), facts: input.facts,
                availableSupport: input.availableSupport, kind: input.kind.flatMap(CoachSummaryKind.init(rawValue:)), week: input.week)
            let data = try JSONEncoder().encode(candidate)
            if data.count <= 65_536 { return data }
        }
        throw CoachGatewayError.requestTooLarge
    }

}
