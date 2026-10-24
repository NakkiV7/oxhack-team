import XCTest
@testable import SpottrCore

final class CoachGroundingTests: XCTestCase {
    func testEmptyHistoryIsExplicitAndSkillPointsAreNotFitnessMeasurements() {
        let facts = CoachGrounding.facts(history: [])
        XCTAssertTrue(facts.contains { $0.id == "context" && $0.text.contains("0 saved sessions") })
        XCTAssertTrue(facts.contains { $0.id == "skill-strength" && $0.text.contains("game points") })
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)
        XCTAssertFalse(facts.contains { $0.text.contains("bpm") })
    }
    func testSavedSelectionSurvivesRoundTripAndNeverAddsUnselectedExercise() throws {
        let context = CoachValidationContext(generationID: "g", suppliedFactIDs: ["context"], availableSupport: [])
        let proposal = try CoachContracts.parseProposal(Data(#"{"generationID":"g","items":[{"exerciseID":"squat","sets":2,"target":8,"unit":"reps","restSeconds":60,"factIDs":["context"]},{"exerciseID":"plank","sets":1,"target":15,"unit":"seconds","restSeconds":30,"factIDs":["context"]}],"rationale":{"text":"A short session.","factIDs":["context"]}}"#.utf8), context: context)
        let plan = try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: ["plank"], context: context)
        let restored = try JSONDecoder().decode(CoachSavedPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.items.map(\.exerciseID), ["plank"])
        XCTAssertEqual(restored.items.first?.target, 15)
        XCTAssertThrowsError(try CoachSavedPlan(proposal: proposal, selectedExerciseIDs: [], context: context))
    }
    func testRepeatedSavedSetIsSharedOnlyOnce() throws {
        let original = try LoggedWorkout.make(exerciseID: "squat", count: 12, sets: 1, reason: .voluntary)
        let duplicate = SessionRecord(id: UUID(), date: original.date, sets: [], loggedSets: original.loggedSets)
        let facts = CoachGrounding.facts(history: [original, duplicate])
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)
    }

    func testObservedWatchSummariesDeduplicateReadingsAndKeepGapsExplicit() {
        let id = UUID(), start = Date(timeIntervalSince1970: 1_792_836_000)
        let first = SensorReading(value: 100, date: start)
        let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 2, target: 12,
            activeSeconds: 6, source: .camera, reason: .voluntary, repDurations: [2, 4], restSecondsBefore: 60)
        let telemetry: [WatchTelemetry] = [
            .init(sessionID: id, sentAt: start, heartRate: first, accelerationG: .init(value: 1, date: start), rotationRadiansPerSecond: .init(value: 0.4, date: start)),
            .init(sessionID: id, sentAt: start.addingTimeInterval(1), heartRate: first, accelerationG: nil, rotationRadiansPerSecond: nil),
            .init(sessionID: id, sentAt: start.addingTimeInterval(30), heartRate: .init(value: 140, date: start.addingTimeInterval(30)), accelerationG: .init(value: 3, date: start.addingTimeInterval(30)), rotationRadiansPerSecond: nil),
            .init(sessionID: UUID(), sentAt: start, heartRate: .init(value: 200, date: start), accelerationG: nil, rotationRadiansPerSecond: nil),
            .init(sessionID: id, sentAt: start.addingTimeInterval(300), heartRate: .init(value: 250, date: start.addingTimeInterval(100)), accelerationG: nil, rotationRadiansPerSecond: nil)
        ]
        let facts = CoachGrounding.facts(history: [.init(id: id, date: start, sets: [set], telemetry: telemetry)])
        let heart = facts.first { $0.id == "watch-heartRate-\(id.uuidString)" }?.text ?? ""
        XCTAssertTrue(heart.contains("2 distinct readings"))
        XCTAssertTrue(heart.contains("mean 120.0 bpm"))
        XCTAssertTrue(heart.contains("peak 140.0 bpm"))
        XCTAssertTrue(heart.contains("2 observed segments"))
        XCTAssertTrue(heart.contains(start.ISO8601Format()))
        XCTAssertTrue(heart.contains(start.addingTimeInterval(30).ISO8601Format()))
        XCTAssertTrue(facts.contains { $0.id == "watch-acceleration-\(id.uuidString)" && $0.text.contains("mean 2.0 g") })
        XCTAssertTrue(facts.contains { $0.id == "watch-rotation-\(id.uuidString)" && $0.text.contains("mean 0.4 rad/s") })
        let session = facts.first { $0.id == "session-\(id.uuidString)" }?.text ?? ""
        XCTAssertTrue(session.contains("mean 3.0 seconds across 2 timed reps"))
        XCTAssertTrue(session.contains("60.0 recorded rest seconds"))
        XCTAssertTrue(facts.contains { $0.id == "set-\(set.id.uuidString)" && $0.text.contains("source camera") })
        XCTAssertTrue(facts.contains { $0.id == "context" && $0.text.contains("Raw sensor streams are not shared") })
    }
    func testLegacyHistoryDoesNotInventRepRestOrSensorTiming() {
        let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 12, target: 12,
            activeSeconds: 30, source: .camera, reason: .target)
        let record = SessionRecord(id: UUID(), date: Date(), sets: [set])
        let facts = CoachGrounding.facts(history: [record])
        let session = facts.first { $0.id == "session-\(record.id.uuidString)" }?.text ?? ""
        XCTAssertTrue(session.contains("Rep timing not recorded"))
        XCTAssertTrue(session.contains("Rest timing not recorded"))
        XCTAssertFalse(facts.contains { $0.id.hasPrefix("watch-") })
        XCTAssertFalse(facts.contains { $0.text.contains("bpm") || $0.text.contains("mean rep") })
    }
    func testScopeTotalsIncludeSessionsBeyondRecentDetailsWithoutCountingDuplicateSessions() throws {
        let history = try (0..<12).map { offset in
            try LoggedWorkout.make(exerciseID: "squat", count: 10, sets: 1,
                date: Date(timeIntervalSince1970: 1_792_836_000 + Double(offset * 60)), reason: .voluntary)
        }
        let facts = CoachGrounding.facts(history: history + [history[0]])
        let scope = facts.first { $0.id == "scope-totals" }?.text ?? ""
        XCTAssertTrue(scope.contains("12 sessions"))
        XCTAssertTrue(scope.contains("12 distinct sets"))
        XCTAssertTrue(scope.contains("120 reps"))
        XCTAssertTrue(scope.contains("12 manual"))
        XCTAssertTrue(scope.contains(history[0].date.ISO8601Format()))
        XCTAssertEqual(facts.filter { $0.id.hasPrefix("session-") }.count, 8)
        XCTAssertLessThanOrEqual(facts.count, 128)
    }

    func testYearOfDailySessionsKeepsCompleteTotalsWithinGatewayFactAndBaselineBudgets() throws {
        let history = try (0..<400).map { offset in
            try LoggedWorkout.make(exerciseID: "squat", count: 10, sets: 1,
                date: Date(timeIntervalSince1970: 1_760_000_000 + Double(offset) * 86400), reason: .voluntary)
        }
        let facts = CoachGrounding.facts(history: history)
        let scope = try XCTUnwrap(facts.first { $0.id == "scope-totals" })
        XCTAssertTrue(scope.text.contains("400 sessions"))
        XCTAssertTrue(scope.text.contains("400 distinct sets"))
        XCTAssertTrue(scope.text.contains("4000 reps"))
        XCTAssertTrue(scope.text.contains("400 UTC session days"))
        XCTAssertTrue(facts.allSatisfy { $0.text.count <= 2000 })
        XCTAssertLessThanOrEqual(facts.count, 128)
        for message in [nil, "Help me plan"] as [String?] {
            let baseline = try JSONEncoder().encode(CoachRequest(message: message, facts: facts))
            XCTAssertLessThanOrEqual(baseline.count, 65_536)
        }
    }
    func testScopeWatchReadingsDeduplicateAcrossWorkoutsAndKeepSeparateCoverageSegments() throws {
        let date = Date(timeIntervalSince1970: 1_792_836_000)
        func record(at date: Date, readingDate: Date, value: Double) -> SessionRecord {
            let id = UUID()
            let telemetry = WatchTelemetry(sessionID: id, sentAt: readingDate, heartRate: .init(value: value, date: readingDate), accelerationG: nil, rotationRadiansPerSecond: nil)
            return .init(id: id, date: date, sets: [], telemetry: [telemetry])
        }
        let duplicate = [record(at: date, readingDate: date, value: 100), record(at: date, readingDate: date, value: 100)]
        let scope = try XCTUnwrap(CoachGrounding.facts(history: duplicate).first { $0.id == "scope-heartRate-watch" })
        XCTAssertTrue(scope.text.contains("1 distinct readings"))
        XCTAssertTrue(scope.text.contains("1 observed segments"))
        let later = record(at: date.addingTimeInterval(5), readingDate: date.addingTimeInterval(5), value: 140)
        let separate = try XCTUnwrap(CoachGrounding.facts(history: duplicate + [later]).first { $0.id == "scope-heartRate-watch" })
        XCTAssertTrue(separate.text.contains("2 distinct readings"))
        XCTAssertTrue(separate.text.contains("mean 120.0 bpm"))
        XCTAssertTrue(separate.text.contains("2 observed segments"))
    }

}
