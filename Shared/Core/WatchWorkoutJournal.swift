import Foundation

public struct WatchAccessGrant: Codable, Equatable, Sendable {
    public let owner: WorkoutOwner
    public let policyID: UUID
    public let age: TrainingAgeContext?
    public let verifiedAt: Date
    public let expiresAt: Date
    public init(owner: WorkoutOwner, policyID: UUID, age: TrainingAgeContext?, verifiedAt: Date, membershipDeadline: Date?) {
        self.owner = owner; self.policyID = policyID; self.age = age; self.verifiedAt = verifiedAt
        expiresAt = min(membershipDeadline ?? .distantFuture, verifiedAt.addingTimeInterval(30 * 86400))
    }
    public func permitsStart(at date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && verifiedAt <= date && date < expiresAt && expiresAt <= verifiedAt.addingTimeInterval(30 * 86400)
    }
}

public struct WatchWorkoutJournal: Codable, Equatable, Sendable, Identifiable {
    public enum Failure: Error { case unavailable, invalidAction, capacity }
    public let id: UUID
    public let grant: WatchAccessGrant
    public let plan: CoachSavedPlan
    public let startedAt: Date
    public let timeZoneID: String
    public let plannedWorkoutID: String?
    public let programmeID: String?
    public let programmeRevision: Int?
    public private(set) var completionTimeZoneID: String?
    public fileprivate(set) var omittedSensorSamples = 0
    public private(set) var finishedAt: Date?
    public private(set) var completed: [LoggedSet] = []
    public fileprivate(set) var telemetry: [WatchTelemetry] = []
    public private(set) var phase: SessionPhase = .active
    public private(set) var index = 0
    public private(set) var reps: Int?
    public private(set) var activeSeconds = 0.0
    public private(set) var restSeconds = 0.0
    public private(set) var hasStarted = false
    public private(set) var completionAllowsAdult: Bool
    public private(set) var policyRestricted = false
    public init(grant: WatchAccessGrant, plan: CoachSavedPlan, support: Set<String>, plannedWorkoutID: String?, at date: Date, timeZone: TimeZone = .current, programmeID: String? = nil, programmeRevision: Int? = nil) throws {
        self.programmeID = programmeID; self.programmeRevision = programmeRevision
        guard grant.permitsStart(at: date), let age = grant.age, age.ageYears >= 5,
              (try? ConfigurableSession(plan: plan, availableSupport: support)) != nil,
              plan.items.allSatisfy({ item in
                  Self.permitsExercise(item.exerciseID, age: age, support: support) && (age.ageYears >= 18 || (item.sets <= (age.ageYears < 13 ? 1 : 2) && item.target <= (item.unit == .reps ? (age.ageYears < 13 ? 6 : 10) : (age.ageYears < 13 ? 10 : 20))))
              }) else { throw Failure.unavailable }
        id = UUID(); self.grant = grant; self.plan = plan; self.plannedWorkoutID = plannedWorkoutID
        startedAt = date; timeZoneID = timeZone.identifier; completionAllowsAdult = grant.age?.allowsTimePressureRewards == true
    }
    private static func permitsExercise(_ id: String, age: TrainingAgeContext, support: Set<String>) -> Bool {
        guard let entry = ExerciseCatalog.find(id),
              let preferences = try? ProgrammePreferences(goals: [.balance], weekdays: [1], availableSupport: support, ageContext: age) else { return false }
        return preferences.canUse(entry)
    }
    public mutating func applyPolicy(owner: WorkoutOwner, age: TrainingAgeContext?, sharing: Bool) {
        guard owner == grant.owner, finishedAt == nil else { return }
        if age != grant.age || !sharing { policyRestricted = true; pause() }
        if age?.allowsTimePressureRewards != true { completionAllowsAdult = false; telemetry = [] }
    }
    public mutating func appendTelemetry(_ packet: WatchTelemetry) throws {
        guard !policyRestricted, grant.age?.allowsHealthIntegration == true, finishedAt == nil else { return }
        telemetry = try WatchTelemetryImporter.merge([packet], into: record, through: packet.sentAt, allowsOpenSession: true).telemetry
    }
    /// Validate decoded checkpoints before exposing index-based controls or accepting an import.
    public var isValid: Bool {
        let support = Set(PathSurvey.equipmentChoices)
        guard (try? ConfigurableSession(plan: plan, availableSupport: support)) != nil,
              items.indices.contains(index), grant.permitsStart(at: startedAt),
              plan.items.allSatisfy({ item in grant.age.map { Self.permitsExercise(item.exerciseID, age: $0, support: support) } == true }),
              grant.age.map({ $0.ageYears >= 5 }) == true,
              TimeZone(identifier: timeZoneID) != nil,
              completionTimeZoneID.map({ TimeZone(identifier: $0) != nil }) ?? true,
              activeSeconds.isFinite, activeSeconds >= 0, restSeconds.isFinite, restSeconds >= 0,
              reps.map({ (1...200).contains($0) }) ?? true,
              omittedSensorSamples >= 0, completed.count <= items.count,
              Set(completed.map(\.id)).count == completed.count,
              telemetry.count <= 7200,
              !completionAllowsAdult || grant.age?.allowsTimePressureRewards == true,
              completionAllowsAdult || telemetry.isEmpty,
              (finishedAt == nil ? phase != .finished : phase == .finished),
              finishedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= startedAt }) ?? true else { return false }
        return completed.enumerated().allSatisfy { offset, set in
            let item = items[offset]
            guard set.exerciseID == item.exerciseID, set.source == .manual,
                  set.activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { return false }
            return item.unit == .reps
                ? (1...200).contains(set.reps) && set.seconds == 0 && set.quantityOrigin == .selfReport
                : set.reps == 0 && set.seconds.isFinite && set.seconds >= 1 && set.quantityOrigin == .activeTimer
        }
    }
    public var record: SessionRecord {
        .init(id: id, date: startedAt, sets: [], telemetry: telemetry, loggedSets: completed, endedAt: finishedAt,
              plannedWorkoutID: plannedWorkoutID, trainingContext: .init(owner: grant.owner, age: grant.age, programmeID: programmeID, programmeRevision: programmeRevision, completionAllowsAdult: completionAllowsAdult, recordingDevice: .watch, omittedWatchSensorSamples: omittedSensorSamples))
    }
    public var items: [CoachSavedPlan.Item] { plan.items.flatMap { item in Array(repeating: item, count: item.sets) } }
    public var current: CoachSavedPlan.Item { items[index] }
    public var setNumber: Int { index - items.prefix(index).filter { $0.exerciseID != current.exerciseID }.count + 1 }
    public var canEndSet: Bool { hasStarted && [.active, .paused].contains(phase) && (current.unit == .reps ? (reps ?? 0) > 0 : activeSeconds >= 1) }
    public var restReady: Bool { phase == .rest && restSeconds >= Double(current.restSeconds) }
    public mutating func beginSet() throws {
        guard phase == .active, !hasStarted, !policyRestricted else { throw Failure.invalidAction }
        hasStarted = true
    }
    public mutating func setReps(_ value: Int?) throws {
        guard [.active, .paused].contains(phase), current.unit == .reps,
              value == nil || (0...200).contains(value!) else { throw Failure.invalidAction }
        reps = value == 0 ? nil : value
    }
    public mutating func advance(seconds: Double) {
        guard seconds.isFinite, (0...21600).contains(seconds) else { return }
        if phase == .active && hasStarted { activeSeconds += seconds }
        if phase == .rest { restSeconds += seconds }
    }
    public mutating func pause() { if phase == .active && hasStarted { phase = .paused } }
    public mutating func resume() { if phase == .paused && !policyRestricted { phase = .active } }
    public mutating func endSet() throws {
        guard canEndSet else { throw Failure.invalidAction }
        completed.append(.init(id: UUID(), exerciseID: current.exerciseID, reps: current.unit == .reps ? (reps ?? 0) : 0,
            seconds: current.unit == .seconds ? activeSeconds : 0, source: .manual, reason: .voluntary,
            number: setNumber, target: current.target, activeSeconds: activeSeconds,
            quantityOrigin: current.unit == .seconds ? .activeTimer : .selfReport))
        phase = .rest; restSeconds = 0
    }
    public mutating func effort(_ value: SetEffort?) throws {
        guard phase == .rest, !completed.isEmpty else { throw Failure.invalidAction }
        completed[completed.count - 1].effort = value
    }
    public mutating func nextSet() throws {
        guard phase == .rest, index + 1 < items.count, !policyRestricted else { throw Failure.invalidAction }
        index += 1; hasStarted = false; reps = nil; activeSeconds = 0; restSeconds = 0; phase = .active
    }
    public mutating func finish(at date: Date, timeZone: TimeZone = .current) {
        guard finishedAt == nil, date >= startedAt, date.timeIntervalSince1970.isFinite else { return }
        finishedAt = date; completionTimeZoneID = timeZone.identifier; phase = .finished
    }
}

public struct WatchProgrammeTransport: Codable, Equatable, Sendable {
    public struct Choice: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let date: Date
        public let plan: CoachSavedPlan
        public init(id: String, date: Date, plan: CoachSavedPlan) { self.id = id; self.date = date; self.plan = plan }
    }
    public let sequence: UInt64
    public let owner: WorkoutOwner
    public let policyID: UUID
    public let age: TrainingAgeContext?
    public let sharing: Bool
    public let grant: WatchAccessGrant?
    public let choices: [Choice]
    public let support: Set<String>
    public let timeZoneID: String
    public let programmeID: String?
    public let programmeRevision: Int?
    public init(sequence: UInt64, owner: WorkoutOwner, policyID: UUID, age: TrainingAgeContext?, sharing: Bool, grant: WatchAccessGrant?, choices: [Choice], support: Set<String>, timeZoneID: String, programmeID: String? = nil, programmeRevision: Int? = nil) {
        self.programmeID = programmeID; self.programmeRevision = programmeRevision
        self.sequence = sequence; self.owner = owner; self.policyID = policyID; self.age = age; self.sharing = sharing
        self.grant = grant; self.choices = choices; self.support = support; self.timeZoneID = timeZoneID
    }
}

public final class WatchWorkoutArchive {
    private struct Reference: Codable { let id: UUID; let owner: WorkoutOwner }
    private struct Contents: Codable {
        var transport: WatchProgrammeTransport?
        var active: WatchWorkoutJournal?
        var pending: [Reference] = []
        var attemptedRecordings: [UUID] = []
        var sensorDrops = 0
        var latestStartCheck: Date?
    }
    private var contents: Contents
    private let url: URL
    private let capacity: Int
    private var sensorCount = 0
    public var transport: WatchProgrammeTransport? { contents.transport }
    public var active: WatchWorkoutJournal? { contents.active }
    public var pendingCount: Int { contents.pending.count }
    public func pendingWorkouts(owner: WorkoutOwner? = nil) throws -> [WatchWorkoutJournal] {
        try contents.pending.filter { owner == nil || $0.owner == owner }.map(loadCompleted)
    }
    public init(url: URL, capacity: Int = 100) throws {
        self.url = url; self.capacity = max(1, min(100, capacity))
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count <= 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            contents = try JSONDecoder().decode(Contents.self, from: data)
            guard contents.active?.isValid ?? true, contents.pending.count <= 100, Set(contents.pending.map(\.id)).count == contents.pending.count else { throw CocoaError(.fileReadCorruptFile) }
            try recoverCompleted()
            if contents.active?.phase == .active && contents.active?.hasStarted == true {
                var next = contents; next.active?.pause(); try persist(next)
            }
            if let active { sensorCount = try readSensors(active).samples.count }
        } else { contents = Contents() }
    }
    private func file(_ reference: Reference, sensors: Bool = false) -> URL {
        url.deletingPathExtension().appendingPathExtension("journals").appendingPathComponent(reference.owner.accountID.uuidString)
            .appendingPathComponent(reference.owner.profileID.uuidString).appendingPathComponent(reference.id.uuidString + (sensors ? ".sensors.jsonl" : ".json"))
    }
    private func reference(_ journal: WatchWorkoutJournal) -> Reference { .init(id: journal.id, owner: journal.grant.owner) }
    private func loadCompleted(_ reference: Reference) throws -> WatchWorkoutJournal {
        let data = try Data(contentsOf: file(reference))
        guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let journal = try JSONDecoder().decode(WatchWorkoutJournal.self, from: data)
        guard journal.isValid, journal.id == reference.id, journal.grant.owner == reference.owner, journal.finishedAt != nil else { throw CocoaError(.fileReadCorruptFile) }
        return journal
    }
    private func recoverCompleted() throws {
        guard let active, FileManager.default.fileExists(atPath: file(reference(active)).path) else { return }
        let finished = try loadCompleted(reference(active))
        guard finished.grant == active.grant, finished.startedAt == active.startedAt else { throw CocoaError(.fileReadCorruptFile) }
        var next = contents
        if !next.pending.contains(where: { $0.id == finished.id }) { next.pending.append(reference(finished)) }
        next.active = nil; next.sensorDrops = 0
        try persist(next); sensorCount = 0
    }
    public func receive(_ transport: WatchProgrammeTransport) throws {
        guard transport.sequence > (contents.transport?.sequence ?? 0) else { return }
        guard transport.choices.count <= 31,
              transport.grant == nil || (transport.grant?.owner == transport.owner && transport.grant?.policyID == transport.policyID && transport.grant?.age == transport.age) else { throw WatchWorkoutJournal.Failure.unavailable }
        var next = contents; next.transport = transport
        next.active?.applyPolicy(owner: transport.owner, age: transport.age, sharing: transport.sharing)
        try persist(next)
    }
    public func start(choiceID: String, at date: Date, calendar: Calendar = .current) throws {
        try recoverCompleted()
        guard contents.active == nil, contents.pending.count < capacity else { throw WatchWorkoutJournal.Failure.capacity }
        guard date.timeIntervalSince1970.isFinite, date >= (contents.latestStartCheck ?? .distantPast) else { throw WatchWorkoutJournal.Failure.unavailable }
        var checked = contents; checked.latestStartCheck = date; try persist(checked)
        guard let transport, transport.sharing, let grant = transport.grant,
              let choice = transport.choices.first(where: { $0.id == choiceID }) else { throw WatchWorkoutJournal.Failure.unavailable }
        var local = calendar; local.timeZone = TimeZone(identifier: transport.timeZoneID) ?? calendar.timeZone
        let scheduled = local.isDate(choice.date, inSameDayAs: date) ? choice.id : nil
        var next = contents
        let journal = try WatchWorkoutJournal(grant: grant, plan: choice.plan, support: transport.support, plannedWorkoutID: scheduled, at: date, timeZone: calendar.timeZone, programmeID: transport.programmeID, programmeRevision: transport.programmeRevision)
        try ProtectedLocalStorage.prepare(file(reference(journal)).deletingLastPathComponent())
        next.active = journal; next.sensorDrops = 0
        try persist(next); sensorCount = 0
    }
    public func update(_ change: (inout WatchWorkoutJournal) throws -> Void) throws {
        try recoverCompleted()
        guard var journal = contents.active else { throw WatchWorkoutJournal.Failure.invalidAction }
        try change(&journal)
        var next = contents
        if journal.finishedAt != nil {
            if journal.completionAllowsAdult {
                let sensorValues = try readSensors(journal)
                let samples = sensorValues.samples
                journal.omittedSensorSamples = sensorValues.omitted
                var record = journal.record
                for offset in stride(from: 0, to: samples.count, by: 60) {
                    do { record = try WatchTelemetryImporter.merge(Array(samples[offset..<min(offset + 60, samples.count)]), into: record, through: journal.finishedAt!) }
                    catch WatchTelemetryImportError.empty { continue }
                }
                journal.telemetry = record.telemetry
            }
            let destination = file(reference(journal))
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            try ProtectedLocalStorage.write(JSONEncoder().encode(journal), to: destination)
            next.pending.append(reference(journal)); next.active = nil; next.sensorDrops = 0
        } else { next.active = journal }
        try persist(next)
    }
    private func readSensors(_ journal: WatchWorkoutJournal) throws -> (samples: [WatchTelemetry], omitted: Int) {
        let source = file(reference(journal), sensors: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return ([], contents.sensorDrops) }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let lines = try Data(contentsOf: source).split(separator: 10)
        var samples: [WatchTelemetry] = [], bytes = 0
        for line in lines {
            guard samples.count < 7200, bytes + line.count + 1 <= 4 * 1024 * 1024,
                  let packet = try? JSONDecoder().decode(WatchTelemetry.self, from: Data(line)),
                  let normalized = try? WatchTelemetryImporter.merge([packet], into: journal.record,
                      through: journal.finishedAt ?? packet.sentAt, allowsOpenSession: journal.finishedAt == nil),
                  let sample = normalized.telemetry.last else { continue }
            samples.append(sample); bytes += line.count + 1
        }
        return (samples, contents.sensorDrops + lines.count - samples.count)
    }
    public func appendTelemetry(_ packet: WatchTelemetry) throws {
        guard let journal = active, !journal.policyRestricted, journal.grant.age?.allowsHealthIntegration == true else { return }
        guard sensorCount < 7200 else {
            var next = contents; next.sensorDrops += 1; try persist(next); throw WatchWorkoutJournal.Failure.capacity
        }
        guard let sample = try WatchTelemetryImporter.merge([packet], into: journal.record, through: packet.sentAt, allowsOpenSession: true).telemetry.last else { return }
        let destination = file(reference(journal), sensors: true)
        if !FileManager.default.fileExists(atPath: destination.path) { try ProtectedLocalStorage.write(Data(), to: destination) }
        let handle = try FileHandle(forUpdating: destination)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        var data = try JSONEncoder().encode(sample); data.append(10)
        guard length + UInt64(data.count) + 1 <= 4 * 1024 * 1024 else {
            var next = contents; next.sensorDrops += 1; try persist(next); throw WatchWorkoutJournal.Failure.capacity
        }
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            let last = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if last != Data([10]) { try handle.write(contentsOf: Data([10])) }
        }
        try handle.write(contentsOf: data); try handle.synchronize(); sensorCount += 1
    }
    public func markRecordingAttempt(id: UUID) throws -> Bool {
        guard !contents.attemptedRecordings.contains(id) else { return false }
        var next = contents; next.attemptedRecordings.append(id)
        next.attemptedRecordings = Array(next.attemptedRecordings.suffix(4096))
        try persist(next); return true
    }
    public func acknowledge(id: UUID, owner: WorkoutOwner) throws {
        guard let saved = contents.pending.first(where: { $0.id == id && $0.owner == owner }) else { return }
        var next = contents; next.pending.removeAll { $0.id == id && $0.owner == owner }
        try persist(next)
        try FileManager.default.removeItem(at: file(saved))
        if FileManager.default.fileExists(atPath: file(saved, sensors: true).path) { try FileManager.default.removeItem(at: file(saved, sensors: true)) }
    }
    private func persist(_ value: Contents) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1024 * 1024 else { throw WatchWorkoutJournal.Failure.capacity }
        try ProtectedLocalStorage.write(data, to: url); contents = value
    }
}

extension WatchProgrammeTransport {
    public static func authorized(sequence: UInt64, owner: WorkoutOwner, policyID: UUID, trustedOwner: WorkoutOwner?, verifiedAt: Date?, profile: LocalProfile?, sharing: Bool, membership: MembershipAccess, programme: TrainingProgramme?, at date: Date) -> WatchProgrammeTransport {
        let age = profile?.programmePreferences?.ageContext
        let support = profile?.effectiveProgrammePreferences.availableSupport ?? []
        let candidate = verifiedAt.map { WatchAccessGrant(owner: owner, policyID: policyID, age: age, verifiedAt: $0, membershipDeadline: membership.lifetime ? nil : membership.expiresAt) }
        let eligible = sharing && trustedOwner == owner && membership.hasAccess && AccountPolicy.setupComplete(profile: profile) && candidate?.permitsStart(at: date) == true
        let choices: [Choice] = eligible ? (programme?.days.compactMap { day in
            guard let plan = day.plan,
                  WorkoutAccessPolicy.decide(trustedOwner: trustedOwner, activeOwner: nil, profile: profile, membership: membership.hasAccess, plan: plan, origin: .watch) == .start else { return nil }
            return Choice(id: day.id, date: day.date, plan: plan)
        } ?? []) : []
        return .init(sequence: sequence, owner: owner, policyID: policyID, age: age, sharing: sharing,
                     grant: eligible && !choices.isEmpty ? candidate : nil, choices: choices, support: support,
                     timeZoneID: programme?.timeZoneID ?? TimeZone.current.identifier, programmeID: programme?.id, programmeRevision: programme?.revision)
    }
}

public struct WatchScopedSnapshot: Codable, Sendable {
    public let snapshot: CompanionSnapshot
    public let owner: WorkoutOwner
    public let policyID: UUID
    public let allowsHealth: Bool
    public init(snapshot: CompanionSnapshot, owner: WorkoutOwner, policyID: UUID, allowsHealth: Bool) {
        self.snapshot = snapshot; self.owner = owner; self.policyID = policyID; self.allowsHealth = allowsHealth
    }
}
public struct WatchWorkoutAcknowledgement: Codable, Sendable {
    public let id: UUID
    public let owner: WorkoutOwner
    public init(id: UUID, owner: WorkoutOwner) { self.id = id; self.owner = owner }
}
