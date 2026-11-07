import XCTest
@testable import SpottrCore

final class WatchWorkoutJournalTests: XCTestCase {
    func testUnresolvedMembershipPreservesOnlySamePolicyAuthorityWithoutRenewingItsDeadline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(), age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID()), policy = UUID()
        let grant = WatchAccessGrant(owner: owner, policyID: policy, age: age, verifiedAt: date, membershipDeadline: date.addingTimeInterval(90))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60)
        let resolved = WatchProgrammeTransport(sequence: 1, owner: owner, policyID: policy, age: age, sharing: true, grant: grant, choices: [.init(id: "day", date: date, plan: plan)], support: [], timeZoneID: "UTC")
        for change in ["same", "off", "owner", "policy", "age", "revoked"] {
            let archive = try WatchWorkoutArchive(url: root.appendingPathComponent(change + ".json"))
            try archive.receive(resolved)
            let next = WatchProgrammeTransport(sequence: 2,
                owner: change == "owner" ? .init(accountID: UUID(), profileID: UUID()) : owner,
                policyID: change == "policy" ? UUID() : policy,
                age: change == "age" ? try .init(ageYears: 12, guardianManaged: true) : age,
                sharing: change != "off", grant: nil, membershipResolved: change == "revoked",
                choices: [], support: [], timeZoneID: "UTC")
            try archive.receive(next)
            if change == "same" {
                XCTAssertEqual(archive.transport?.grant, grant)
                XCTAssertEqual(archive.transport?.choices, resolved.choices)
                let reopened = try WatchWorkoutArchive(url: root.appendingPathComponent(change + ".json"))
                XCTAssertEqual(reopened.transport?.grant?.expiresAt, grant.expiresAt)
                XCTAssertThrowsError(try reopened.start(choiceID: "day", at: date.addingTimeInterval(91)))
            } else { XCTAssertNil(archive.transport?.grant); XCTAssertTrue(archive.transport?.choices.isEmpty == true) }
        }
    }

    func testLeaseNeverExceedsGenuineVerificationOrEarlierMembershipAndRejectsClockRollback() throws {
        let verified = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let lifetime = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: verified, membershipDeadline: nil)
        let longSubscription = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: verified, membershipDeadline: verified.addingTimeInterval(90 * 86400))
        let shortSubscription = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: verified, membershipDeadline: verified.addingTimeInterval(86400))
        XCTAssertTrue(lifetime.permitsStart(at: verified))
        XCTAssertFalse(lifetime.permitsStart(at: verified.addingTimeInterval(30 * 86400)))
        XCTAssertFalse(lifetime.permitsStart(at: verified.addingTimeInterval(-1)))
        XCTAssertEqual(longSubscription.expiresAt, lifetime.expiresAt)
        XCTAssertFalse(shortSubscription.permitsStart(at: verified.addingTimeInterval(86400)))
        let cached = try JSONDecoder().decode(WatchAccessGrant.self, from: JSONEncoder().encode(shortSubscription))
        XCTAssertFalse(cached.permitsStart(at: verified.addingTimeInterval(2 * 86400)))
    }
    func testWholeWorkoutKeepsActualManualValuesEffortAndRestAcrossRestartAndExpiry() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: .init(accountID: UUID(), profileID: UUID()), policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: date.addingTimeInterval(20))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 60, availableSupport: [])
        var journal = try WatchWorkoutJournal(grant: grant, plan: plan, support: [], plannedWorkoutID: "today", at: date)
        XCTAssertNil(journal.reps)
        try journal.beginSet(); try journal.setReps(3); journal.advance(seconds: 4)
        try journal.endSet()
        XCTAssertEqual(journal.completed.map(\.reps), [3])
        XCTAssertEqual(journal.completed.first?.quantityOrigin, .selfReport)
        XCTAssertEqual(journal.phase, .rest)
        journal.advance(seconds: 4)
        let copy = try JSONDecoder().decode(WatchWorkoutJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(copy, journal)
        journal = copy; try journal.nextSet(); try journal.beginSet()
        XCTAssertNil(journal.reps)
        journal.advance(seconds: 2); try journal.setReps(2); journal.pause(); journal.advance(seconds: 4)
        XCTAssertEqual(journal.activeSeconds, 2)
        journal.resume(); try journal.endSet(); journal.finish(at: date.addingTimeInterval(40))
        XCTAssertEqual(journal.completed.map(\.reps), [3, 2])
        XCTAssertNil(journal.completed.first?.restSecondsBefore)
        XCTAssertEqual(journal.completed.last?.restSecondsBefore, 4)
        XCTAssertEqual(journal.finishedAt, date.addingTimeInterval(40))
        let finished = journal; journal.finish(at: date.addingTimeInterval(50))
        XCTAssertEqual(journal, finished)
    }
    func testDurableOutboxSurvivesRestartRejectsStaleTransportAndFailsBeforeOverflow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("watch.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 60, availableSupport: [])
        let value = WatchProgrammeTransport(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "old-day", date: date.addingTimeInterval(-86400), plan: plan)], support: [], timeZoneID: "Europe/London")
        let archive = try WatchWorkoutArchive(url: url, capacity: 1)
        try archive.receive(value); try archive.start(choiceID: "old-day", at: date)
        XCTAssertNotNil(archive.active)
        XCTAssertNil(archive.active?.plannedWorkoutID)
        try archive.update { try $0.beginSet(); try $0.setReps(3); $0.advance(seconds: 4) }
        let recordingID = try XCTUnwrap(archive.active?.id)
        XCTAssertTrue(try archive.markRecordingAttempt(id: recordingID))
        let restarted = try WatchWorkoutArchive(url: url, capacity: 1)
        XCTAssertFalse(try restarted.markRecordingAttempt(id: recordingID))
        XCTAssertEqual(restarted.active?.reps, 3)
        XCTAssertEqual(restarted.active?.phase, .paused)
        try restarted.update { try $0.endSet(); $0.finish(at: date.addingTimeInterval(60)) }
        XCTAssertNil(restarted.active)
        XCTAssertEqual(restarted.pendingCount, 1)
        XCTAssertThrowsError(try restarted.start(choiceID: "old-day", at: date))
        let finished = try XCTUnwrap(try restarted.pendingWorkouts().first)
        try restarted.acknowledge(id: finished.id, owner: .init(accountID: UUID(), profileID: UUID()))
        XCTAssertEqual(restarted.pendingCount, 1)
        try restarted.receive(.init(sequence: 2, owner: owner, policyID: grant.policyID, age: age, sharing: false, grant: nil, choices: [], support: [], timeZoneID: "Europe/London"))
        try restarted.receive(value)
        XCTAssertEqual(restarted.transport?.sequence, 2)
        try restarted.acknowledge(id: finished.id, owner: owner)
        XCTAssertTrue(try WatchWorkoutArchive(url: url).pendingWorkouts().isEmpty)
        XCTAssertThrowsError(try restarted.start(choiceID: "old-day", at: date))
    }
    func testSameOwnerRestrictiveCorrectionStopsPrescriptionButPreservesOriginalManualFinish() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let junior = try TrainingAgeContext(ageYears: 12, guardianManaged: true)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: adult, verifiedAt: date, membershipDeadline: nil)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 2, target: 8, restSeconds: 60)
        var journal = try WatchWorkoutJournal(grant: grant, plan: plan, support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(3); journal.advance(seconds: 2)
        journal.applyPolicy(owner: .init(accountID: owner.accountID, profileID: UUID()), age: junior, sharing: false)
        XCTAssertFalse(journal.policyRestricted); XCTAssertTrue(journal.completionAllowsAdult)
        journal.applyPolicy(owner: owner, age: junior, sharing: true)
        XCTAssertTrue(journal.policyRestricted); XCTAssertFalse(journal.completionAllowsAdult)
        XCTAssertEqual(journal.phase, .paused)
        XCTAssertEqual(journal.grant.age, adult)
        try journal.endSet(); XCTAssertThrowsError(try journal.nextSet())
        journal.finish(at: date.addingTimeInterval(5))
        XCTAssertEqual(journal.completed.first?.reps, 3)
        XCTAssertEqual(journal.grant.owner, owner)
    }
    func testRestrictedCompletionPreservesAdultOriginWithoutNewAdultBenchmarkOrHealthEligibility() throws {
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let raw = try LoggedWorkout.make(exerciseID: "squat", count: 8, sets: 1)
        let record = SessionRecord(id: raw.id, date: raw.date, sets: [], loggedSets: raw.loggedSets, trainingContext: .init(owner: owner, age: adult, completionAllowsAdult: false))
        let policy = SkillCurriculum.BenchmarkPolicy(owner: owner, legacyHistory: [], calendar: .current)
        XCTAssertTrue(policy.qualifiedHistory([record]).isEmpty)
        XCTAssertTrue(WorkoutAnalytics.healthRecords(in: [record], currentAge: adult).isEmpty)
        XCTAssertEqual(record.trainingContext?.age, adult)
        XCTAssertEqual(record.reps, 8)
    }
    func testProgrammeGrantUsesCanonicalAccountSetupMembershipAndOriginalVerificationTime() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = WorkoutOwner(accountID: UUID(), profileID: UUID()), policy = UUID()
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let preferences = try ProgrammePreferences(goals: [.strength], weekdays: [1,2,3,4,5,6,7], startingPoint: .startingOut, ageContext: age,
            comfortAnswers: Dictionary(uniqueKeysWithValues: ExerciseFamily.allCases.map { ($0, TrainingSetup.Comfort.unsure) }))
        let profile = try LocalProfile(bodyMeasurements: try .init(heightCM: 170, weightKG: 70), onboardingRevision: TrainingSetup.revision, programmePreferences: preferences)
        let week = try ProgrammePlanner.makeWeek(profile: profile, history: [], start: date)
        let membership = MembershipAccess.resolve([.verified(.init(productID: MembershipPlan.lifetime.productID, kind: .nonConsumable))], now: date)
        func transport(trusted: WorkoutOwner? = owner, verified: Date? = date, selected: LocalProfile? = profile, sharing: Bool = true, at now: Date = date) -> WatchProgrammeTransport {
            .authorized(sequence: 1, owner: owner, policyID: policy, trustedOwner: trusted, verifiedAt: verified, profile: selected, sharing: sharing, membership: membership, programme: week, at: now)
        }
        let first = transport()
        XCTAssertNotNil(first.grant); XCTAssertFalse(first.choices.isEmpty)
        XCTAssertEqual(first.programmeID, week.id); XCTAssertEqual(first.programmeRevision, week.revision)
        XCTAssertEqual(first.choices.map(\.plan), week.days.compactMap(\.plan))
        XCTAssertNil(transport(trusted: nil).grant)
        XCTAssertNil(transport(verified: nil).grant)
        XCTAssertNil(transport(selected: nil).grant)
        XCTAssertNil(transport(sharing: false).grant)
        XCTAssertNil(transport(verified: date.addingTimeInterval(1)).grant)
        XCTAssertNil(transport(at: date.addingTimeInterval(31 * 86400)).grant)
        XCTAssertEqual(transport(at: date.addingTimeInterval(86400)).grant?.expiresAt, first.grant?.expiresAt)
        XCTAssertTrue(transport(sharing: false).choices.isEmpty)
    }
    func testCompletionSurvivesManifestCommitFailureAndCompletedPayloadRemainsImmutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("watch.json")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path); try? FileManager.default.removeItem(at: root) }
        let date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60)
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier))
        try archive.start(choiceID: "today", at: date)
        try archive.update { try $0.beginSet(); try $0.setReps(3); $0.advance(seconds: 2); try $0.endSet() }
        let id = try XCTUnwrap(archive.active?.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        XCTAssertThrowsError(try archive.update { $0.finish(at: date.addingTimeInterval(3)) })
        XCTAssertEqual(archive.active?.completed.first?.reps, 3)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let reopened = try WatchWorkoutArchive(url: url)
        XCTAssertNil(reopened.active)
        XCTAssertEqual(try reopened.pendingWorkouts().first?.id, id)
        XCTAssertEqual(try reopened.pendingWorkouts().first?.completed.first?.reps, 3)
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
        let completedFile = try XCTUnwrap(files.first { (try? JSONDecoder().decode(WatchWorkoutJournal.self, from: Data(contentsOf: $0)))?.id == id })
        let original = try Data(contentsOf: completedFile)
        try reopened.start(choiceID: "today", at: date.addingTimeInterval(5))
        try reopened.update { try $0.beginSet(); $0.advance(seconds: 4) }
        XCTAssertEqual(try Data(contentsOf: completedFile), original)
        try reopened.acknowledge(id: id, owner: .init(accountID: UUID(), profileID: UUID()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedFile.path))
        try reopened.acknowledge(id: id, owner: owner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedFile.path))
    }
    func testSensorPayloadIsSeparateFromCheckpointAndCompletionCarriesWatchAndLocalClockProvenance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("watch.json"), date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil)
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60)
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier, programmeID: "week", programmeRevision: 3))
        try archive.start(choiceID: "today", at: date)
        let id = try XCTUnwrap(archive.active?.id), initial = try Data(contentsOf: url)
        for second in 1...10 {
            let measured = date.addingTimeInterval(Double(second))
            try archive.appendTelemetry(.init(sessionID: id, sentAt: measured, heartRate: .init(value: 80, date: measured), accelerationG: nil, rotationRadiansPerSecond: nil))
        }
        XCTAssertEqual(try Data(contentsOf: url), initial)
        try archive.update { try $0.beginSet(); try $0.setReps(3); $0.advance(seconds: 2); try $0.endSet(); $0.finish(at: date.addingTimeInterval(20), timeZone: TimeZone(identifier: "America/New_York")!) }
        let finished = try XCTUnwrap(archive.pendingWorkouts().first)
        XCTAssertEqual(finished.record.telemetry.count, 10)
        XCTAssertEqual(finished.record.trainingContext?.recordingDevice, .watch)
        XCTAssertEqual(finished.record.trainingContext?.programmeID, "week")
        XCTAssertEqual(finished.record.trainingContext?.programmeRevision, 3)
        XCTAssertEqual(finished.completionTimeZoneID, "America/New_York")
        XCTAssertTrue(finished.record.loggedSets.allSatisfy { $0.source == .manual && $0.quantityOrigin == .selfReport })
    }
    func testCorruptCheckpointFailsClosedAndRejectedExpiredStartCannotReviveAfterClockRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("watch.json"), date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: date.addingTimeInterval(60))
        let plan = try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 60)
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier))
        XCTAssertThrowsError(try archive.start(choiceID: "today", at: date.addingTimeInterval(61)))
        XCTAssertThrowsError(try archive.start(choiceID: "today", at: date))
        let fresh = WatchAccessGrant(owner: owner, policyID: grant.policyID, age: age, verifiedAt: date.addingTimeInterval(61), membershipDeadline: nil)
        try archive.receive(.init(sequence: 2, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: fresh, choices: [.init(id: "today", date: date, plan: plan)], support: [], timeZoneID: TimeZone.current.identifier))
        try archive.start(choiceID: "today", at: date.addingTimeInterval(61))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var active = try XCTUnwrap(object["active"] as? [String: Any]); active["index"] = 999; object["active"] = active
        let corrupt = try JSONSerialization.data(withJSONObject: object); try corrupt.write(to: url)
        XCTAssertThrowsError(try WatchWorkoutArchive(url: url))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
    func testJuniorCannotStartAdultPrescriptionAndRestrictedAdultCompletionCannotCompleteAdultQuest() throws {
        let date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let child = try TrainingAgeContext(ageYears: 10, guardianManaged: true)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: child, verifiedAt: date, membershipDeadline: nil)
        XCTAssertThrowsError(try WatchWorkoutJournal(grant: grant, plan: .catalogue(exerciseID: "squat", sets: 1, target: 6, restSeconds: 30), support: [], plannedWorkoutID: nil, at: date))
        let adult = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        var journal = try WatchWorkoutJournal(grant: .init(owner: owner, policyID: UUID(), age: adult, verifiedAt: date, membershipDeadline: nil), plan: .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 30), support: [], plannedWorkoutID: nil, at: date)
        try journal.beginSet(); try journal.setReps(8); try journal.endSet()
        journal.applyPolicy(owner: owner, age: child, sharing: false)
        journal.finish(at: date.addingTimeInterval(10))
        let quest = Quest(id: "practice", periodID: "day", title: "Practice", detail: "", kind: .practice, exerciseID: "squat", target: 8, requiredDays: 1, startsAt: date.addingTimeInterval(-1), endsAt: date.addingTimeInterval(86400), xp: 10)
        XCTAssertFalse(QuestProgress.evaluate(quest, owner: owner, currentAge: adult, history: [journal.record], checkIns: [], now: date.addingTimeInterval(20), calendar: .current).isComplete)
    }

    func testDamagedSensorAppendDoesNotPreventSavingActualManualWork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("watch.json"), date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 30, guardianManaged: false)
        let grant = WatchAccessGrant(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil)
        let archive = try WatchWorkoutArchive(url: url)
        try archive.receive(.init(sequence: 1, owner: owner, policyID: grant.policyID, age: age, sharing: true, grant: grant, choices: [.init(id: "today", date: date, plan: .catalogue(exerciseID: "squat", sets: 1, target: 8, restSeconds: 30))], support: [], timeZoneID: TimeZone.current.identifier))
        try archive.start(choiceID: "today", at: date)
        let id = try XCTUnwrap(archive.active?.id)
        try archive.appendTelemetry(.init(sessionID: id, sentAt: date, heartRate: .init(value: 80, date: date), accelerationG: nil, rotationRadiansPerSecond: nil))
        let sensor = url.deletingPathExtension().appendingPathExtension("journals").appendingPathComponent(owner.accountID.uuidString).appendingPathComponent(owner.profileID.uuidString).appendingPathComponent(id.uuidString + ".sensors.jsonl")
        var bytes = try Data(contentsOf: sensor)
        bytes.append(try JSONEncoder().encode(WatchTelemetry(sessionID: UUID(), sentAt: date, heartRate: .init(value: 90, date: date), accelerationG: nil, rotationRadiansPerSecond: nil))); bytes.append(10)
        bytes.append(Data("partial append".utf8)); try bytes.write(to: sensor)
        try archive.update { try $0.beginSet(); try $0.setReps(3); try $0.endSet(); $0.finish(at: date.addingTimeInterval(5)) }
        let finished = try XCTUnwrap(archive.pendingWorkouts().first)
        XCTAssertEqual(finished.completed.first?.reps, 3)
        XCTAssertEqual(finished.telemetry.count, 1)
        XCTAssertEqual(finished.omittedSensorSamples, 2)
    }

    func testDecodedJuniorJournalCannotClaimAdultPermissionOrCarryHealth() throws {
        let date = Date(), owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
        let age = try TrainingAgeContext(ageYears: 10, guardianManaged: true)
        let journal = try WatchWorkoutJournal(grant: .init(owner: owner, policyID: UUID(), age: age, verifiedAt: date, membershipDeadline: nil), plan: .catalogue(exerciseID: "frontArmRaise", sets: 1, target: 6, restSeconds: 30), support: [], plannedWorkoutID: nil, at: date)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        object["completionAllowsAdult"] = true
        let decoded = try JSONDecoder().decode(WatchWorkoutJournal.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isValid)
        object["completionAllowsAdult"] = false
        let packet = WatchTelemetry(sessionID: journal.id, sentAt: date, heartRate: .init(value: 80, date: date), accelerationG: nil, rotationRadiansPerSecond: nil)
        object["telemetry"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([packet]))
        XCTAssertFalse(try JSONDecoder().decode(WatchWorkoutJournal.self, from: JSONSerialization.data(withJSONObject: object)).isValid)
    }

}
