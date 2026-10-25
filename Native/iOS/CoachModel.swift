import SwiftUI
import Security

@MainActor @Observable
final class CoachModel {
    private(set) var turns: [CoachTurn] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var proposal: WorkoutProposal?
    private(set) var summary: CoachSummary?
    private(set) var approvedPlan: CoachSavedPlan?
    private(set) var proposalContext: CoachValidationContext?
    private var generation = UUID()
    private let configuration: @MainActor () throws -> CoachGatewayClient
    private let planDefaults: UserDefaults
    private var lastMessage = ""
    private var profile: LocalProfile?

    init(configuration: @escaping @MainActor () throws -> CoachGatewayClient = CoachSettings.client, savedPlanData: Data? = CoachSettings.planData(), profile: LocalProfile? = nil, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        planDefaults = defaults
        self.profile = profile
        approvedPlan = savedPlanData.flatMap { try? JSONDecoder().decode(CoachSavedPlan.self, from: $0) }
    }

    func cancel() { generation = UUID(); isLoading = false }

    func invalidateContext() { cancel(); proposal = nil; proposalContext = nil; summary = nil }

    func updateProfile(_ profile: LocalProfile?) {
        let changed = self.profile?.goals != profile?.goals || self.profile?.weeklyTarget != profile?.weeklyTarget
        self.profile = profile
        if changed { invalidateContext() }
    }

    func send(message: String, history: [SessionRecord], support: Set<String>, retry: Bool = false) async {
        let text = retry ? lastMessage : message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty, text.count <= 4000 else { return }
        lastMessage = text
        let conversation = retry && turns.last?.role == .user ? Array(turns.dropLast()) : turns
        let prior = Array(conversation.suffix(20))
        if !retry { turns.append(.init(role: .user, text: text)) }
        let token = begin()
        do {
            let input = CoachRequest(generationID: token.uuidString, message: text, history: prior, facts: CoachGrounding.facts(history: history, profile: profile), availableSupport: support.sorted())
            let answer = try await configuration().chat(input)
            guard generation == token, !Task.isCancelled else { return }
            turns.append(.init(role: .model, text: answer)); isLoading = false
        } catch { finish(error, token: token) }
    }

    func propose(message: String = "", history: [SessionRecord], support: Set<String>) async {
        guard !isLoading, !Task.isCancelled else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 4000 else {
            error = "Keep your workout instructions to 4,000 characters, then tap Propose again."
            return
        }
        proposal = nil; proposalContext = nil
        let token = begin()
        let input = CoachRequest(generationID: token.uuidString, message: text.isEmpty ? nil : text,
                                 history: Array(turns.suffix(20)), facts: CoachGrounding.facts(history: history, profile: profile),
                                 availableSupport: support.sorted())
        do {
            let response = try await configuration().proposal(input)
            guard generation == token, !Task.isCancelled else { return }
            proposal = response; proposalContext = input.context; isLoading = false
        } catch { finish(error, token: token) }
    }

    func summarize(history: [SessionRecord], kind: CoachSummaryKind) async {
        guard !isLoading else { return }
        summary = nil
        let token = begin()
        let input = CoachRequest(generationID: token.uuidString, facts: CoachGrounding.facts(history: history, profile: profile), kind: kind)
        do {
            let response = try await configuration().summary(input, kind: kind)
            guard generation == token, !Task.isCancelled else { return }
            summary = response; isLoading = false
        } catch { finish(error, token: token) }
    }

    func approve(selected: Set<String>, currentSupport: Set<String>) {
        guard let proposal, let proposalContext else { return }
        guard proposalContext.availableSupport == currentSupport else {
            invalidateContext(); error = "Your available support changed. Request a new workout."; return
        }
        do {
            let plan = try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: selected, context: proposalContext)
            let data = try JSONEncoder().encode(plan)
            planDefaults.set(data, forKey: "coach.approvedPlan")
            approvedPlan = plan; self.proposal = nil; error = nil
        } catch { self.error = "Select at least one valid exercise before saving your plan." }
    }

    func removeApprovedPlan() {
        planDefaults.removeObject(forKey: "coach.approvedPlan")
        approvedPlan = nil
    }

    private func begin() -> UUID { generation = UUID(); isLoading = true; error = nil; return generation }
    private func finish(_ failure: Error, token: UUID) {
        guard generation == token else { return }
        isLoading = false
        if failure is CancellationError || (failure as? URLError)?.code == .cancelled { return }
        error = (failure as? LocalizedError)?.errorDescription ?? "The coach couldn’t respond. Check your connection and try again."
    }
}

@MainActor
enum CoachSettings {
    nonisolated static func planData(environment: [String: String] = ProcessInfo.processInfo.environment, defaults: UserDefaults = .standard) -> Data? {
        #if DEBUG
        if let namespace = environment["SPOTTR_DATA_NAMESPACE"], UUID(uuidString: namespace) != nil,
           let fixture = environment["SPOTTR_APPROVED_PLAN_FIXTURE"], let data = fixture.data(using: .utf8),
           (try? JSONDecoder().decode(CoachSavedPlan.self, from: data)) != nil { return data }
        #endif
        return defaults.data(forKey: "coach.approvedPlan")
    }
    static var gatewayURL: String { UserDefaults.standard.string(forKey: "coach.gatewayURL") ?? "" }
    static func client() throws -> CoachGatewayClient {
        guard let url = URL(string: gatewayURL), !gatewayURL.isEmpty, let token = token(), !token.isEmpty else { throw CoachGatewayError.configuration }
        return CoachGatewayClient(baseURL: url, token: token)
    }
    static func save(url: String, token: String) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: address), parsed.scheme == "https" || (parsed.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(parsed.host ?? "")), parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil, !token.isEmpty else { throw CoachGatewayError.configuration }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spottr.coach.gateway", kSecAttrAccount as String: "access-token"]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CoachGatewayError.configuration }
        } else if status != errSecSuccess { throw CoachGatewayError.configuration }
        UserDefaults.standard.set(address, forKey: "coach.gatewayURL")
    }
    static func token() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spottr.coach.gateway", kSecAttrAccount as String: "access-token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
