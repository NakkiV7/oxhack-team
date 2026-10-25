import SwiftUI
import Security

@MainActor @Observable
final class CoachModel {
    private(set) var turns: [CoachTurn] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var proposal: WorkoutProposal?
    private(set) var summary: CoachSummary?
    private(set) var weekProposal: CoachWeekProposal?
    private(set) var approvedWeek: CoachSavedWeek?
    private var weekRequest: CoachWeekRequest?
    private var weekContext: CoachValidationContext?
    private enum RequestKind {
        case chat(String), workout(String), week(String, CoachWeekRequest), summary(CoachSummaryKind)
    }
    private var lastRequest: RequestKind?
    var retryTitle: String {
        switch lastRequest {
        case .chat: return "Retry last message"
        case .workout: return "Retry workout proposal"
        case .week: return "Retry week proposal"
        case .summary: return "Retry summary"
        case nil: return "Try again"
        }
    }
    var canRetry: Bool { lastRequest != nil && !isLoading }
    var loadingText: String {
        switch lastRequest {
        case .week: return "Planning your week…"
        case .workout: return "Preparing your workout…"
        case .summary: return "Preparing your summary…"
        default: return "Waiting for your coach…"
        }
    }
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
        approvedWeek = defaults.data(forKey: "coach.approvedWeek").flatMap { try? CoachSavedWeek.decode($0) }
        approvedPlan = savedPlanData.flatMap { try? JSONDecoder().decode(CoachSavedPlan.self, from: $0) }
    }

    func cancel() { generation = UUID(); isLoading = false }

    func invalidateContext() { cancel(); proposal = nil; proposalContext = nil; summary = nil; weekProposal = nil; weekContext = nil; weekRequest = nil; lastRequest = nil }

    func updateProfile(_ profile: LocalProfile?) {
        let changed = self.profile?.goals != profile?.goals || self.profile?.weeklyTarget != profile?.weeklyTarget
        self.profile = profile
        if changed { invalidateContext() }
    }

    func send(message: String, history: [SessionRecord], support: Set<String>, retry: Bool = false) async {
        let text = retry ? lastMessage : message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty, text.count <= 4000 else { return }
        lastMessage = text; lastRequest = .chat(text)
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
        proposal = nil; proposalContext = nil; weekProposal = nil; weekContext = nil; weekRequest = nil
        lastRequest = .workout(text)
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
        lastRequest = .summary(kind)
        let token = begin()
        let input = CoachRequest(generationID: token.uuidString, facts: CoachGrounding.facts(history: history, profile: profile), kind: kind)
        do {
            let response = try await configuration().summary(input, kind: kind)
            guard generation == token, !Task.isCancelled else { return }
            summary = response; isLoading = false
        } catch { finish(error, token: token) }
    }

    func proposeWeek(message: String = "", week: CoachWeekRequest, history: [SessionRecord], support: Set<String>) async {
        guard !isLoading, !Task.isCancelled else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 4000 else { error = "Keep your planning instructions to 4,000 characters or fewer."; return }
        proposal = nil; proposalContext = nil; weekProposal = nil; weekContext = nil; weekRequest = nil
        lastRequest = .week(text, week)
        let token = begin()
        let input = CoachRequest(generationID: token.uuidString, message: text.isEmpty ? nil : text,
                                 history: Array(turns.suffix(20)), facts: CoachGrounding.facts(history: history, profile: profile),
                                 availableSupport: support.sorted(), week: week)
        do {
            let response = try await configuration().weekProposal(input, guidance: CoachGuidanceRegistry.bundled())
            guard generation == token, !Task.isCancelled else { return }
            weekProposal = response; weekContext = input.context; weekRequest = week; isLoading = false
        } catch { finish(error, token: token) }
    }

    func approveWeek(selectedDates: Set<String>, movedDates: [String: String], currentSupport: Set<String>) {
        guard let weekProposal, let weekRequest, let weekContext else { return }
        guard weekContext.availableSupport == currentSupport else {
            invalidateContext(); error = "Your available support changed. Request a new week."; return
        }
        do {
            let week = try CoachSavedWeek(proposal: weekProposal, selectedDates: selectedDates, movedDates: movedDates,
                                          context: weekContext, request: weekRequest, guidance: CoachGuidanceRegistry.bundled())
            planDefaults.set(try JSONEncoder().encode(week), forKey: "coach.approvedWeek")
            approvedWeek = week; self.weekProposal = nil; self.weekRequest = nil; self.weekContext = nil; error = nil
        } catch { self.error = "Select at least one workout day. Keep each selected workout on a different available date." }
    }

    func removeApprovedWeek() {
        planDefaults.removeObject(forKey: "coach.approvedWeek"); approvedWeek = nil
    }

    func retry(history: [SessionRecord], support: Set<String>) async {
        guard let lastRequest, !isLoading else { return }
        switch lastRequest {
        case .chat: await send(message: "", history: history, support: support, retry: true)
        case .workout(let message): await propose(message: message, history: history, support: support)
        case .week(let message, let week): await proposeWeek(message: message, week: week, history: history, support: support)
        case .summary(let kind): await summarize(history: history, kind: kind)
        }
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
    static let demoGatewayURL = "https://spottr.omarchoudhry.co.uk/demo"
    static var gatewayURL: String { address() }
    static var isCustomConnection: Bool { UserDefaults.standard.string(forKey: "coach.gatewayURL") != nil }
    static func address(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "coach.gatewayURL") ?? demoGatewayURL
    }
    static func resetAddress(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "coach.gatewayURL")
    }
    private enum ConnectionError: LocalizedError {
        case unavailable, expired, storage
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Demo access is not included in this build. Update Spottr or add a custom connection in Coach settings."
            case .expired: return "Demo access has expired. Install an updated demo build or add a custom connection in Coach settings."
            case .storage: return "Coach access could not be saved securely. Unlock this iPhone and try again in Coach settings."
            }
        }
    }
    private struct DemoAccess: Decodable {
        let token: String
        let expiresAt: String
    }
    static func demoToken(injected: Data?, now: Date, read: () -> Data?, write: (Data) throws -> Void) throws -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func valid(_ data: Data?) -> DemoAccess? {
            guard let data, data.count <= 1024, let access = try? JSONDecoder().decode(DemoAccess.self, from: data),
                  (32...256).contains(access.token.utf8.count),
                  access.token.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) == nil,
                  let expiry = format.date(from: access.expiresAt), format.string(from: expiry) == access.expiresAt,
                  expiry > now, expiry.timeIntervalSince(now) <= 86_400 else { return nil }
            return access
        }
        let stored = read()
        if let access = valid(injected), let injected {
            if stored != injected { try write(injected) }
            return access.token
        }
        if let access = valid(stored) { return access.token }
        if let data = injected ?? stored, let access = try? JSONDecoder().decode(DemoAccess.self, from: data),
           let expiry = format.date(from: access.expiresAt), expiry <= now { throw ConnectionError.expired }
        throw ConnectionError.unavailable
    }
    private static func includedToken() throws -> String {
        let injected = Bundle.main.url(forResource: "SpottrDemoAccess", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        return try demoToken(injected: injected, now: Date(), read: { keychainData(account: "demo-access-v1") },
                             write: { try saveKeychain($0, account: "demo-access-v1") })
    }
    static var connectionStatus: String {
        if isCustomConnection { return token() == nil ? "Custom connection needs an access token." : "Custom connection saved. Network not checked." }
        do {
            _ = try includedToken()
            return "Included demo access is ready. Network not checked. Requests are sent only when you ask the coach or enable remote voice."
        } catch { return error.localizedDescription }
    }
    static func client() throws -> CoachGatewayClient {
        let access: String
        if isCustomConnection {
            guard let saved = token(), !saved.isEmpty else { throw CoachGatewayError.configuration }
            access = saved
        } else { access = try includedToken() }
        guard let url = URL(string: gatewayURL), !gatewayURL.isEmpty else { throw CoachGatewayError.configuration }
        return CoachGatewayClient(baseURL: url, token: access)
    }
    static func save(url: String, token: String) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: address), parsed.scheme == "https" || (parsed.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(parsed.host ?? "")), parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil, !token.isEmpty else { throw CoachGatewayError.configuration }
        try saveKeychain(Data(token.utf8), account: "access-token")
        UserDefaults.standard.set(address, forKey: "coach.gatewayURL")
    }
    static func reset() throws {
        for account in ["access-token", "demo-access-v1"] {
            let status = SecItemDelete(keychainQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ConnectionError.storage }
        }
        resetAddress()
    }
    private static func keychainQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.spottr.coach.gateway", kSecAttrAccount as String: account]
    }
    private static func saveKeychain(_ data: Data, account: String) throws {
        let query = keychainQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw ConnectionError.storage }
        } else if status != errSecSuccess { throw ConnectionError.storage }
    }
    static func token() -> String? {
        if !isCustomConnection { return try? includedToken() }
        return keychainData(account: "access-token").flatMap { String(data: $0, encoding: .utf8) }
    }
    private static func keychainData(account: String) -> Data? {
        let query = keychainQuery(account: account).merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
