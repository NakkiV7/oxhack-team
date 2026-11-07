import Foundation
import Observation

@MainActor final class CoarseAnalyticsTransport: NSObject, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    func send(_ request: URLRequest) async throws -> Int {
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1024, let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return response.statusCode
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable final class ConsentedAnalyticsStore {
    typealias Sender = @MainActor (URLRequest) async throws -> Int
    private struct Saved: Codable {
        var ledger: AnalyticsLedger
        var pending: [CoarseAnalyticsSnapshot]
        var retryAt: Date
        var attempts: Int
    }
    private struct TransmissionBudget: Codable {
        var regular = 0
        var final = 0
        var nextAttempt = Date.distantPast
    }
    private struct InstallationWeek: Codable {
        var tag: UUID
        var sequence: Int
        var budgets: [String: TransmissionBudget]? = nil
    }
    private static var withdrawn: [String: Set<AnalyticsKind>] = [:]
    private(set) var ledger: AnalyticsLedger
    private(set) var message: String?
    private(set) var pending: [CoarseAnalyticsSnapshot] = []
    let scope: AccountDataScope
    let profile: NativeProfileStore
    var onConsentChange: (() -> Void)?
    private let send: Sender
    private var active = true
    private var readable = true
    private var retryAt = Date.distantPast
    private var attempts = 0
    private var inFlight: Task<Int, Error>?
    private var inFlightKind: AnalyticsKind?
    private var url: URL { scope.file("analytics-consent.json") }
    private var installationURL: URL { scope.root.appendingPathComponent("analytics-installation.json") }
    private var available: Bool { active && readable && profile.permitsPolicyCallbacks && profile.profile?.programmePreferences?.ageContext == ledger.age }
    init(scope: AccountDataScope, profile: NativeProfileStore, send: Sender? = nil) {
        self.scope = scope; self.profile = profile
        let transport = CoarseAnalyticsTransport()
        self.send = send ?? { try await transport.send($0) }
        let owner = WorkoutOwner(accountID: scope.accountID, profileID: scope.profileID)
        ledger = .init(owner: owner, age: profile.profile?.programmePreferences?.ageContext)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 65536 else { throw AccountFailure.invalidResponse }
                let saved = try JSONDecoder().decode(Saved.self, from: data)
                guard saved.ledger.owner == owner else { throw AccountFailure.invalidResponse }
                if saved.ledger.age == ledger.age {
                    ledger = saved.ledger; pending = Array(saved.pending.prefix(4)); retryAt = saved.retryAt; attempts = saved.attempts
                } else {
                    Self.withdrawn[scope.folder.path] = Set(AnalyticsKind.allCases)
                    try persist()
                    Self.withdrawn[scope.folder.path] = nil
                }
            } catch { readable = false; message = "Statistics are off because their saved settings could not be read." }
        }
        for kind in Self.withdrawn[scope.folder.path] ?? [] { ledger.consent(kind, enabled: false); pending.removeAll { $0.kind == kind } }
    }
    func setConsent(_ kind: AnalyticsKind, enabled: Bool) throws {
        guard available else { throw AccountFailure.reauthenticate }
        if !enabled {
            ledger.consent(kind, enabled: false); pending.removeAll { $0.kind == kind }
            Self.withdrawn[scope.folder.path, default: []].insert(kind)
            if inFlightKind == kind { inFlight?.cancel() }
            onConsentChange?()
            do { try persist(); Self.withdrawn[scope.folder.path]?.remove(kind); message = nil }
            catch { message = "Statistics are off now. Saving this choice will retry when this profile is open."; throw error }
        } else {
            guard Self.withdrawn[scope.folder.path]?.contains(kind) != true else { throw AccountFailure.invalidResponse }
            var next = ledger; next.consent(kind, enabled: true)
            try persist(ledger: next); ledger = next; message = nil; onConsentChange?()
        }
    }
    func record(_ record: SessionRecord, captured: AnalyticsCapture?, at date: Date = Date()) {
        guard available else { return }
        let before = ledger.snapshots
        ledger.record(record, captured: captured, currentAge: profile.profile?.programmePreferences?.ageContext, at: date)
        enqueueChanges(from: before, at: date)
    }
    func feature(_ name: String, at date: Date = Date()) {
        guard available else { return }
        let before = ledger.snapshots
        ledger.feature(name, captured: ledger.capture(.usage), currentAge: profile.profile?.programmePreferences?.ageContext, at: date)
        enqueueChanges(from: before, at: date)
    }
    func setActive(_ value: Bool) { active = value; if !value { inFlight?.cancel() } }
    private func enqueueChanges(from previous: [CoarseAnalyticsSnapshot], at date: Date) {
        do {
            let weeks = [AnalyticsLedger.week(date), AnalyticsLedger.week(date.addingTimeInterval(-7 * 86400))]
            pending.removeAll { !weeks.contains($0.week) }
            for var value in ledger.snapshots where weeks.contains(value.week) && !previous.contains(value) {
                var installed: [String: InstallationWeek] = [:]
                if FileManager.default.fileExists(atPath: installationURL.path) {
                    installed = try JSONDecoder().decode([String: InstallationWeek].self, from: Data(contentsOf: installationURL))
                }
                installed = installed.filter { weeks.contains($0.key) }
                var state = installed[value.week] ?? .init(tag: UUID(), sequence: 0)
                guard state.sequence < 1000000 else { throw AccountFailure.invalidResponse }
                state.sequence += 1; installed[value.week] = state
                try ProtectedLocalStorage.write(JSONEncoder().encode(installed), to: installationURL)
                value.tag = state.tag; value.sequence = state.sequence
                pending.removeAll { $0.kind == value.kind && $0.week == value.week }
                pending.append(value)
            }
            try persist()
        } catch {
            pending = []; message = "Statistics could not be queued. Your training is saved as usual."
        }
    }
    func flush(at date: Date = Date()) async {
        guard available, inFlight == nil, retryAt <= date else { return }
        if !(Self.withdrawn[scope.folder.path] ?? []).isEmpty {
            do { try persist(); Self.withdrawn[scope.folder.path] = nil; message = nil } catch { return }
        }
        let weeks = [AnalyticsLedger.week(date), AnalyticsLedger.week(date.addingTimeInterval(-7 * 86400))]
        pending.removeAll { !weeks.contains($0.week) }
        guard let value = pending.first, let capture = ledger.capture(value.kind) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            guard data.count <= 4096 else { throw AccountFailure.invalidResponse }
            guard try reserveTransmission(value, at: date) else { return }
            var request = URLRequest(url: URL(string: AccountClient.origin + "/api/analytics/v1/weekly")!)
            request.httpMethod = "POST"; request.httpBody = data; request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let task = Task { try await send(request) }; inFlight = task; inFlightKind = value.kind
            defer { inFlight = nil; inFlightKind = nil }
            let status = try await task.value
            guard available, ledger.capture(value.kind) == capture else { return }
            if status == 202 || status == 400 || status == 413 {
                pending.removeAll { $0 == value }; attempts = 0; retryAt = date.addingTimeInterval(12 * 3600)
            } else { backoff(at: date) }
            try persist()
        } catch {
            guard available, ledger.capture(value.kind) == capture else { return }
            backoff(at: date); try? persist()
        }
    }
    private func reserveTransmission(_ snapshot: CoarseAnalyticsSnapshot, at date: Date) throws -> Bool {
        let data = try Data(contentsOf: installationURL)
        guard data.count <= 4096 else { throw AccountFailure.invalidResponse }
        var installed = try JSONDecoder().decode([String: InstallationWeek].self, from: data)
        guard var state = installed[snapshot.week], state.tag == snapshot.tag else { throw AccountFailure.invalidResponse }
        var budget = state.budgets?[snapshot.kind.rawValue] ?? TransmissionBudget()
        guard budget.nextAttempt <= date else { return false }
        if snapshot.week == AnalyticsLedger.week(date) {
            guard budget.regular < 14 else { return false }
            budget.regular += 1
        } else {
            guard snapshot.week == AnalyticsLedger.week(date.addingTimeInterval(-7 * 86400)), budget.final < 2 else { return false }
            budget.final += 1
        }
        budget.nextAttempt = date.addingTimeInterval(12 * 3600)
        var budgets = state.budgets ?? [:]; budgets[snapshot.kind.rawValue] = budget; state.budgets = budgets
        installed[snapshot.week] = state
        try ProtectedLocalStorage.write(JSONEncoder().encode(installed), to: installationURL)
        return true
    }
    private func backoff(at date: Date) {
        attempts += 1; retryAt = date.addingTimeInterval(min(86400, 60 * pow(2, Double(min(attempts, 10)))))
        if attempts >= 8 { pending = []; attempts = 0 }
    }
    private func persist(ledger candidate: AnalyticsLedger? = nil) throws {
        let data = try JSONEncoder().encode(Saved(ledger: candidate ?? ledger, pending: pending, retryAt: retryAt, attempts: attempts))
        guard data.count <= 65536 else { throw AccountFailure.invalidResponse }
        try ProtectedLocalStorage.write(data, to: url)
    }
}
