import Foundation

public enum QuestKind: String, Codable, Sendable { case practice, camera, recovery, reflection, familyActivity }
public struct Quest: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let periodID: String
    public let title: String
    public let detail: String
    public let kind: QuestKind
    public let exerciseID: String?
    public let target: Int
    public let requiredDays: Int
    public let startsAt: Date
    public let endsAt: Date
    public let xp: Int
}
public enum QuestCalendar {
    public struct Slot: Codable, Sendable { public let slot: Int; public let options: [String] }
    public struct Year: Codable, Sendable { public let version: Int; public let daily: [Slot]; public let weekly: [Slot] }
    public static func bundled() throws -> Year {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "quest-calendar", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Year.self, from: Data(contentsOf: url))
    }
    public static func dailySlot(at date: Date, calendar: Calendar) -> Int {
        guard date.timeIntervalSince1970.isFinite else { return 0 }
        var leap = Calendar(identifier: .gregorian); leap.timeZone = calendar.timeZone
        let parts = leap.dateComponents([.month, .day], from: date)
        guard let reference = leap.date(from: DateComponents(year: 2000, month: parts.month, day: parts.day)) else { return 0 }
        return leap.ordinality(of: .day, in: .year, for: reference) ?? 0
    }
    public static func choices(year: Year, profile: LocalProfile, programme: TrainingProgramme?, history: [SessionRecord], at date: Date, calendar: Calendar, weekly: Bool = false) -> [Quest] {
        guard date.timeIntervalSince1970.isFinite, let age = profile.programmePreferences?.ageContext,
              year.version == 1, year.daily.count == 366, year.weekly.count == 53 else { return [] }
        var iso = Calendar(identifier: .iso8601); iso.timeZone = calendar.timeZone
        guard let interval = weekly ? iso.dateInterval(of: .weekOfYear, for: date) : calendar.dateInterval(of: .day, for: date) else { return [] }
        let slot = weekly ? iso.component(.weekOfYear, from: date) : dailySlot(at: date, calendar: calendar)
        let slots = weekly ? year.weekly : year.daily
        guard let template = slots.first(where: { $0.slot == slot }), template.options.count == (weekly ? 2 : 3) else { return [] }
        let period = weekly ? "week:\(iso.component(.yearForWeekOfYear, from: date)):\(slot)" : "day:\(calendar.component(.year, from: date)):\(slot)"
        let days = programme?.days.filter { weekly ? interval.contains($0.date) : calendar.isDate($0.date, inSameDayAs: date) } ?? []
        let curriculum = SkillCurriculum.evaluate(profile: profile, history: history, calendar: calendar)
        let established = Set(curriculum.nodes.filter { $0.state == .earned || $0.state == .placed }.map(\.id))
        let items = days.filter { $0.kind == .workout }.flatMap { $0.plan?.items ?? [] }.filter {
            guard let entry = ExerciseCatalog.find($0.exerciseID) else { return false }
            let ownLevel = ExerciseCatalog.all.filter { $0.family == entry.family && established.contains($0.id) }.map(\.level).max() ?? 1
            let ability = max(ownLevel, profile.effectiveProgrammePreferences.startingPoint?.suggestedLevel ?? 1)
            return profile.effectiveProgrammePreferences.canUse(entry) && (age.ageYears < 18 || entry.level <= ability)
        }
        let item = items.isEmpty ? nil : items[(slot - 1) % items.count]
        let practiceDays = min(2, max(1, days.filter { day in day.kind == .workout && day.plan?.items.contains { $0.exerciseID == item?.exerciseID } == true }.count))
        return template.options.enumerated().map { index, key in
            let kind: QuestKind
            if age.ageYears < 5 { kind = index == 0 ? .familyActivity : index == 1 ? .reflection : .recovery }
            else if item != nil && index == 0 { kind = .practice }
            else if item != nil && key == "camera" && ExerciseCatalog.find(item!.exerciseID)?.tracking != nil { kind = .camera }
            else { kind = index == 1 ? .reflection : .recovery }
            let exercise = kind == .practice || kind == .camera ? item : nil
            let entry = exercise.flatMap { ExerciseCatalog.find($0.exerciseID) }
            let target = exercise.map { min($0.target, age.ageYears < 13 ? ($0.unit == .reps ? 6 : 10) : age.ageYears < 18 ? ($0.unit == .reps ? 10 : 20) : $0.target) } ?? 0
            let requiredDays = weekly ? (exercise == nil ? 2 : practiceDays) : 1
            let title: String
            switch kind {
            case .practice: title = ["A little practice", "Move with control", "Find your balance", "Your own rhythm", "Comfortable movement", "Steady progress"][(slot - 1) % 6]
            case .camera: title = "See your movement"
            case .recovery: title = "Make room for rest"
            case .reflection: title = "Listen to your body"
            case .familyActivity: title = "Move and play together"
            }
            let detail: String
            if let entry { detail = "Record one comfortable set of \(target) \(entry.unit == .reps ? "reps" : "seconds") of \(entry.name)\(weekly ? " on \(requiredDays) planned days" : "").\(kind == .camera ? " Camera observations required." : " Manual or camera practice counts.") Stop for discomfort." }
            else {
                let action = kind == .familyActivity ? "After some guardian-led play, check in together." : kind == .reflection ? "Check in after noticing how you feel and choosing a comfortable next step." : "Check in after taking time to recover. No workout needed."
                detail = action + (weekly ? " Check in on two different days this week." : "")
            }
            return Quest(id: "\(period):\(index):\(key)", periodID: period, title: title, detail: detail, kind: kind, exerciseID: exercise?.exerciseID, target: target, requiredDays: requiredDays, startsAt: interval.start, endsAt: interval.end, xp: weekly ? 30 : 10)
        }
    }
}
public struct QuestCheckIn: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let owner: WorkoutOwner
    public let age: TrainingAgeContext
    public let date: Date
    public let kind: QuestKind
    public init(id: UUID = UUID(), owner: WorkoutOwner, age: TrainingAgeContext, date: Date, kind: QuestKind) {
        self.id = id; self.owner = owner; self.age = age; self.date = date; self.kind = kind
    }
}
public struct QuestEvidence: Equatable, Sendable {
    public let sessionIDs: Set<UUID>
    public let checkInIDs: Set<UUID>
    public let completedDays: Int
    public let isComplete: Bool
}
public enum QuestProgress {
    public static func evaluate(_ quest: Quest, owner: WorkoutOwner, currentAge: TrainingAgeContext?, history: [SessionRecord], checkIns: [QuestCheckIn], now: Date, calendar: Calendar) -> QuestEvidence {
        let empty = QuestEvidence(sessionIDs: [], checkInIDs: [], completedDays: 0, isComplete: false)
        guard let currentAge, now.timeIntervalSince1970.isFinite, quest.requiredDays > 0 else { return empty }
        var sessions = Set<UUID>(), checks = Set<UUID>(), days = Set<Date>(), seenSets = Set<UUID>()
        if let exerciseID = quest.exerciseID, let entry = ExerciseCatalog.find(exerciseID), currentAge.ageYears >= 5 {
            for record in history.sorted(by: { $0.date < $1.date }) where !sessions.contains(record.id) {
                guard record.trainingContext?.owner == owner, record.trainingContext?.age == currentAge,
                      record.date >= quest.startsAt, record.date < quest.endsAt, record.date <= now else { continue }
                let logs = record.loggedSets + record.sets.map { LoggedSet(id: $0.id, exerciseID: $0.exercise.rawValue, reps: $0.reps, seconds: 0, source: $0.source, reason: $0.reason, quantityOrigin: $0.source == .camera ? .cameraObserved : .selfReport) }
                let eligible = logs.filter { set in
                    guard seenSets.insert(set.id).inserted, set.exerciseID == exerciseID, set.source != .video,
                          set.reason != .discomfort, quest.kind != .camera || (set.source == .camera && set.quantityOrigin == .cameraObserved) else { return false }
                    return entry.unit == .reps ? set.reps >= quest.target && set.seconds == 0 : set.seconds.isFinite && set.seconds >= Double(quest.target) && set.reps == 0
                }
                if !eligible.isEmpty { sessions.insert(record.id); days.insert(calendar.startOfDay(for: record.date)) }
            }
        } else {
            for check in checkIns where check.owner == owner && check.age == currentAge && check.kind == quest.kind && check.date >= quest.startsAt && check.date < quest.endsAt && check.date <= now {
                checks.insert(check.id); days.insert(calendar.startOfDay(for: check.date))
            }
        }
        return .init(sessionIDs: sessions, checkInIDs: checks, completedDays: days.count, isComplete: days.count >= quest.requiredDays)
    }
}
public struct QuestClaim: Codable, Equatable, Identifiable, Sendable {
    public var id: String { quest.periodID }
    public let quest: Quest
    public let sessionIDs: Set<UUID>
    public let checkInIDs: Set<UUID>
    public let claimedAt: Date
    public let age: TrainingAgeContext
    public let timeZoneID: String
}
public struct QuestArchive: Codable, Equatable, Sendable {
    public let owner: WorkoutOwner
    public private(set) var checkIns: [QuestCheckIn] = []
    public private(set) var claims: [QuestClaim] = []
    public private(set) var retiredPeriods: Set<String> = []
    public var totalXP: Int { claims.reduce(0) { $0 + $1.quest.xp } }
    public init(owner: WorkoutOwner) { self.owner = owner }
    public mutating func checkIn(kind: QuestKind, age: TrainingAgeContext, at date: Date, calendar: Calendar) {
        guard date.timeIntervalSince1970.isFinite, [.recovery, .reflection, .familyActivity].contains(kind),
              kind != .familyActivity || age.ageYears < 5,
              !checkIns.contains(where: { $0.age == age && $0.kind == kind && calendar.isDate($0.date, inSameDayAs: date) }) else { return }
        checkIns.append(.init(owner: owner, age: age, date: date, kind: kind))
    }
    @discardableResult public mutating func claim(_ quest: Quest, currentAge: TrainingAgeContext?, history: [SessionRecord], now: Date, calendar: Calendar) -> Bool {
        guard now >= quest.startsAt, now < quest.endsAt, !retiredPeriods.contains(quest.periodID), !claims.contains(where: { $0.id == quest.periodID }) else { return false }
        let evidence = QuestProgress.evaluate(quest, owner: owner, currentAge: currentAge, history: history, checkIns: checkIns, now: now, calendar: calendar)
        guard evidence.isComplete, let currentAge else { return false }
        claims.append(.init(quest: quest, sessionIDs: evidence.sessionIDs, checkInIDs: evidence.checkInIDs, claimedAt: now, age: currentAge, timeZoneID: calendar.timeZone.identifier))
        return true
    }
    public mutating func reconcile(currentAge: TrainingAgeContext?, history: [SessionRecord], now: Date, calendar: Calendar) {
        let removed = claims.filter { claim in
            var originalCalendar = Calendar(identifier: .gregorian)
            originalCalendar.timeZone = TimeZone(identifier: claim.timeZoneID) ?? calendar.timeZone
            return !QuestProgress.evaluate(claim.quest, owner: owner, currentAge: claim.age,
                history: history.filter { claim.sessionIDs.contains($0.id) }, checkIns: checkIns.filter { claim.checkInIDs.contains($0.id) },
                now: now, calendar: originalCalendar).isComplete
        }
        retiredPeriods.formUnion(removed.map(\.id))
        claims.removeAll { retiredPeriods.contains($0.id) }
    }
    public mutating func removeCheckIn(id: UUID) { checkIns.removeAll { $0.id == id } }
}
public struct XPReminder: Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let startsAt: Date
    public let isBefore: Bool
}
public enum XPReminderSchedule {
    public static func make(ledger: GamificationLedger, owner: WorkoutOwner, age: TrainingAgeContext?, consent: Bool, authorized: Bool, now: Date, calendar: Calendar, unrelatedPendingCount: Int = 0) -> [XPReminder] {
        guard age?.allowsTimePressureRewards == true, consent, authorized, now.timeIntervalSince1970.isFinite else { return [] }
        let capacity = min(28, max(0, 63 - max(0, unrelatedPendingCount)))
        var reminders: [XPReminder] = []
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let interval = ledger.window(at: day)?.interval(on: day, calendar: calendar) else { continue }
            for before in [true, false] {
                let fire = before ? interval.start.addingTimeInterval(-3600) : interval.start
                guard fire > now else { continue }
                reminders.append(.init(id: prefix(owner: owner) + "\(Int(interval.start.timeIntervalSince1970))" + (before ? ".before" : ".start"), date: fire, startsAt: interval.start, isBefore: before))
            }
        }
        return Array(reminders.sorted { $0.date < $1.date }.prefix(capacity))
    }
    public static func prefix(owner: WorkoutOwner) -> String { "spottr.xp.\(owner.accountID).\(owner.profileID)." }
}
