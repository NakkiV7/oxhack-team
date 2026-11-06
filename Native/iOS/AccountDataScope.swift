import Foundation
import CryptoKit
import Observation

struct AccountDataScope: Hashable {
    let accountID: UUID
    let profileID: UUID
    let root: URL
    var folder: URL { root.appendingPathComponent("Accounts").appendingPathComponent(accountID.uuidString).appendingPathComponent("Profiles").appendingPathComponent(profileID.uuidString) }
    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
    func prepare() throws {
        try ProtectedLocalStorage.prepare(folder)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) { try ProtectedLocalStorage.protect(file) }
    }
    func importLegacy(from source: URL, age: TrainingAgeContext) throws {
        guard age.ageYears >= 18 else { throw AccountFailure.checkpointRequired }
        try prepare()
        guard !FileManager.default.fileExists(atPath: file("legacy-import.json").path) else { throw CocoaError(.fileWriteFileExists) }
        let names = ["history.json", "rewards.json", "training-path.json", "watch-inbox.json"]
        let available = names.filter { FileManager.default.fileExists(atPath: source.appendingPathComponent($0).path) }
        guard !available.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        for name in available where FileManager.default.fileExists(atPath: file(name).path) { throw CocoaError(.fileWriteFileExists) }
        var dataByName: [String: Data] = [:]
        for name in available { dataByName[name] = try Data(contentsOf: source.appendingPathComponent(name)) }
        if let data = dataByName["history.json"] { _ = try JSONDecoder().decode([SessionRecord].self, from: data) }
        if let data = dataByName["rewards.json"] { _ = try JSONDecoder().decode(GamificationLedger.self, from: data) }
        if let data = dataByName["training-path.json"] { _ = try JSONDecoder().decode(TrainingPathStore.Saved.self, from: data) }
        let archive = folder.appendingPathComponent("LegacyArchive")
        try ProtectedLocalStorage.prepare(archive)
        for (name, data) in dataByName {
            let copy = archive.appendingPathComponent(name)
            try ProtectedLocalStorage.write(data, to: copy)
            guard try Data(contentsOf: copy) == data else { throw CocoaError(.fileReadCorruptFile) }
        }
        let oldProfile = source.appendingPathComponent("profile.json")
        if FileManager.default.fileExists(atPath: oldProfile.path) { try ProtectedLocalStorage.write(Data(contentsOf: oldProfile), to: archive.appendingPathComponent("profile.json")) }
        for (name, data) in dataByName { try ProtectedLocalStorage.write(data, to: file(name)) }
        let hashes = dataByName.mapValues { Data(SHA256.hash(data: $0)).base64URL }
        try ProtectedLocalStorage.write(JSONEncoder().encode(hashes), to: file("legacy-import.json"))
    }
}

struct TrainingProfileDescriptor: Codable, Identifiable, Equatable {
    let id: UUID
    let age: TrainingAgeContext
    var name: String
}

@MainActor @Observable final class AccountProfileDirectory {
    private(set) var profiles: [TrainingProfileDescriptor] = []
    private(set) var selectedID: UUID?
    let accountID: UUID
    let root: URL
    private let url: URL
    private struct Saved: Codable { let profiles: [TrainingProfileDescriptor]; let selectedID: UUID? }
    init(accountID: UUID, root: URL) throws {
        self.accountID = accountID; self.root = root
        url = root.appendingPathComponent("Accounts").appendingPathComponent(accountID.uuidString).appendingPathComponent("profiles.json")
        try ProtectedLocalStorage.prepare(url.deletingLastPathComponent())
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
        guard Set(saved.profiles.map(\.id)).count == saved.profiles.count,
              saved.selectedID == nil || saved.profiles.contains(where: { $0.id == saved.selectedID }) else { throw AccountFailure.invalidResponse }
        profiles = saved.profiles; selectedID = saved.selectedID
    }
    func add(age: TrainingAgeContext, name: String) throws -> TrainingProfileDescriptor {
        let profile = TrainingProfileDescriptor(id: UUID(), age: age, name: String(name.prefix(40)))
        let scope = scope(profile.id)
        try scope.prepare()
        let preferences = try ProgrammePreferences(goals: [.balance], weekdays: [1, 3, 5], ageContext: age)
        try NativeProfileStore(url: scope.file("profile.json")).save(LocalProfile(name: profile.name, programmePreferences: preferences))
        let candidate = profiles + [profile]
        try save(candidate, selectedID: profile.id)
        return profile
    }
    func select(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw AccountFailure.invalidResponse }
        try save(profiles, selectedID: id)
    }
    func scope(_ id: UUID) -> AccountDataScope { AccountDataScope(accountID: accountID, profileID: id, root: root) }
    private func save(_ profiles: [TrainingProfileDescriptor], selectedID: UUID) throws {
        try ProtectedLocalStorage.write(JSONEncoder().encode(Saved(profiles: profiles, selectedID: selectedID)), to: url)
        self.profiles = profiles; self.selectedID = selectedID
    }
}

@MainActor @Observable final class AccountWorkspace {
    let scope: AccountDataScope
    let profile: NativeProfileStore
    let training: TrainingStore
    let health: HealthDataStore
    let path: TrainingPathStore
    init(scope: AccountDataScope) throws {
        try scope.prepare(); self.scope = scope
        profile = NativeProfileStore(url: scope.file("profile.json"))
        path = TrainingPathStore(url: scope.file("training-path.json"))
        let defaults = UserDefaults(suiteName: "Spottr.Scope.\(scope.accountID.uuidString).\(scope.profileID.uuidString)")!
        let rewards = NativeRewardsStore(url: scope.file("rewards.json"), allowsTimePressureRewards: profile.profile?.programmePreferences?.ageContext?.allowsTimePressureRewards == true)
        training = TrainingStore(historyURL: scope.file("history.json"), rewardsStore: rewards, defaults: defaults, accountScope: scope)
        health = HealthDataStore(client: ScopedHealthReadingClient(profile: profile), defaults: try FileHealthPreferences(url: scope.file("health-preferences.plist")))
    }
    var hasOngoingWorkout: Bool { training.sessionPhase != .idle && training.sessionPhase != .finished }
    func suspend() {
        training.setAccountActive(false)
        do { try training.preservePendingWorkout() } catch { training.error = "The paused workout could not be archived. Keep this app open and retry before switching accounts." }
        health.disconnect()
    }
}

@MainActor final class ScopedHealthReadingClient: HealthReadingClient {
    private let profile: NativeProfileStore
    private lazy var client = AppleHealthReadingClient()
    init(profile: NativeProfileStore) { self.profile = profile }
    var isAvailable: Bool { AccountPolicy.allowsHealth(profile: profile.profile) && client.isAvailable }
    func requestReadAuthorization() async throws {
        guard AccountPolicy.allowsHealth(profile: profile.profile) else { throw AccountFailure.checkpointRequired }
        try await client.requestReadAuthorization()
    }
    func read(asOf: Date, dayStart: Date, dayEnd: Date) async throws -> [HealthObservation] {
        guard AccountPolicy.allowsHealth(profile: profile.profile) else { throw AccountFailure.checkpointRequired }
        return try await client.read(asOf: asOf, dayStart: dayStart, dayEnd: dayEnd)
    }
}

@MainActor final class FileHealthPreferences: HealthPreferenceStorage {
    private enum Value: Codable { case boolean(Bool), number(Double) }
    private var values: [String: Value]
    private let url: URL
    private(set) var writeError: Error?
    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) { values = try PropertyListDecoder().decode([String: Value].self, from: Data(contentsOf: url)); try ProtectedLocalStorage.protect(url) }
        else { values = [:] }
    }
    func bool(forKey key: String) -> Bool { if case .boolean(let value) = values[key] { return value }; return false }
    func double(forKey key: String) -> Double { if case .number(let value) = values[key] { return value }; return 0 }
    func object(forKey key: String) -> Any? {
        switch values[key] { case .boolean(let value): return value; case .number(let value): return value; case nil: return nil }
    }
    func set(_ value: Any?, forKey key: String) {
        var next = values
        if let bool = value as? Bool { next[key] = .boolean(bool) }
        else if let number = value as? Double, number.isFinite { next[key] = .number(number) }
        else { next[key] = nil }
        do { try ProtectedLocalStorage.write(PropertyListEncoder().encode(next), to: url); values = next; writeError = nil }
        catch { writeError = error }
    }
    func removeObject(forKey key: String) { set(nil, forKey: key) }
}

struct PendingPhoneWorkout: Codable {
    let accountID: UUID
    let profileID: UUID
    let record: SessionRecord
    let phase: SessionPhase
    let exerciseID: String
    let actualReps: Int?
    let measuredSeconds: Double?
    let quantityOrigin: LoggedSet.QuantityOrigin?
}

struct AccountLocalExport: Codable {
    let formatVersion: Int
    let accountID: UUID
    let profileID: UUID
    let profile: LocalProfile?
    let history: [SessionRecord]
    let rewards: GamificationLedger?
    let pendingWorkout: PendingPhoneWorkout?
    let unfinishedWorkouts: [PendingPhoneWorkout]
}

enum AccountLocalArchives {
    static func scopes(root: URL) throws -> [AccountDataScope] {
        let accounts = root.appendingPathComponent("Accounts")
        guard FileManager.default.fileExists(atPath: accounts.path) else { return [] }
        var result: [AccountDataScope] = []
        for account in try FileManager.default.contentsOfDirectory(at: accounts, includingPropertiesForKeys: [.isDirectoryKey]) {
            guard let accountID = UUID(uuidString: account.lastPathComponent), try account.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            let profiles = account.appendingPathComponent("Profiles")
            guard FileManager.default.fileExists(atPath: profiles.path) else { continue }
            for profile in try FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: [.isDirectoryKey]) {
                guard let profileID = UUID(uuidString: profile.lastPathComponent), try profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                result.append(AccountDataScope(accountID: accountID, profileID: profileID, root: root))
            }
        }
        return result.sorted { $0.folder.path < $1.folder.path }
    }
}
extension AccountDataScope {
    func exportLocalData() throws -> URL {
        func read<Value: Decodable>(_ type: Value.Type, name: String) throws -> Value? {
            let url = file(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        }
        let export = AccountLocalExport(formatVersion: 2, accountID: accountID, profileID: profileID,
            profile: try read(LocalProfile.self, name: "profile.json"), history: try HistoryStore(url: file("history.json")).load(),
            rewards: try read(GamificationLedger.self, name: "rewards.json"), pendingWorkout: try read(PendingPhoneWorkout.self, name: "pending-phone-workout.json"),
            unfinishedWorkouts: try unfinishedSnapshots().map(\.snapshot))
        let target = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("spottr-local-profile.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try ProtectedLocalStorage.write(encoder.encode(export), to: target)
        return target
    }
}

struct UnfinishedWorkoutSnapshot {
    let url: URL
    let snapshot: PendingPhoneWorkout
}
extension PendingPhoneWorkout {
    static func files(in folder: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]).filter { url in
            let name = url.lastPathComponent
            let isSnapshot = name == "pending-phone-workout.json" ||
                (name.hasPrefix("pending-") && name.hasSuffix(".json") && UUID(uuidString: String(name.dropFirst(8).dropLast(5))) != nil)
            guard isSnapshot else { return false }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
extension AccountDataScope {
    func unfinishedSnapshots() throws -> [UnfinishedWorkoutSnapshot] {
        try PendingPhoneWorkout.files(in: folder).map { url in
            let saved = try JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: url))
            guard saved.accountID == accountID, saved.profileID == profileID else { throw CocoaError(.fileReadCorruptFile) }
            return UnfinishedWorkoutSnapshot(url: url, snapshot: saved)
        }
    }
}
