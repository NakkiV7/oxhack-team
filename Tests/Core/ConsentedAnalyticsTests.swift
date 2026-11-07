import XCTest
@testable import SpottrCore

final class ConsentedAnalyticsTests: XCTestCase {
    private let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
    private var adult: TrainingAgeContext { try! .init(ageYears: 30, guardianManaged: false) }
    private let date = Date(timeIntervalSince1970: 1794000000)
    private func record(age: TrainingAgeContext?, owner: WorkoutOwner, endedAt: Date? = nil) -> SessionRecord {
        .init(id: UUID(), date: endedAt ?? date, sets: [], loggedSets: [.init(id: UUID(), exerciseID: "squat", reps: 13, seconds: 0, source: .manual, reason: .voluntary)], endedAt: endedAt ?? date, trainingContext: .init(owner: owner, age: age))
    }
    func testLateSundayImportPreservesMondayCumulativeCountsAndReplayProtection() throws {
        let monday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-02T10:00:00Z"))
        let sunday = monday.addingTimeInterval(-12 * 3600)
        var ledger = AnalyticsLedger(owner: owner, age: adult)
        ledger.consent(.workout, enabled: true); ledger.consent(.usage, enabled: true)
        let capture = ledger.capture(.workout)
        let firstMonday = record(age: adult, owner: owner, endedAt: monday)
        ledger.record(firstMonday, captured: capture, currentAge: adult, at: monday)
        ledger.feature("today", captured: ledger.capture(.usage), currentAge: adult, at: monday)
        ledger.record(record(age: adult, owner: owner, endedAt: sunday), captured: capture, currentAge: adult, at: monday.addingTimeInterval(3600))
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .workout }?.counts["sessions"], 1, "Late previous-week work must not retire current-week totals")
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .usage }?.counts["today"], 1)
        let secondMonday = record(age: adult, owner: owner, endedAt: monday.addingTimeInterval(2 * 3600))
        ledger.record(secondMonday, captured: capture, currentAge: adult, at: monday.addingTimeInterval(2 * 3600))
        ledger.feature("today", captured: ledger.capture(.usage), currentAge: adult, at: monday.addingTimeInterval(2 * 3600))
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .workout }?.counts["sessions"], 2)
        let beforeReplay = ledger.snapshots
        ledger.record(firstMonday, captured: capture, currentAge: adult, at: monday.addingTimeInterval(3 * 3600))
        XCTAssertEqual(ledger.snapshots, beforeReplay, "The original Monday identity must remain deduplicated after a late Sunday import")
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-10-26" && $0.kind == .workout }?.counts["sessions"], 1)
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .workout }?.counts["sessions"], 2, "Replaying the first Monday workout must be ignored")
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .workout }?.counts["reps"], 20)
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .usage }?.counts["today"], 2)
        ledger.feature("coach", captured: ledger.capture(.usage), currentAge: adult, at: monday.addingTimeInterval(7 * 86400))
        XCTAssertFalse(ledger.snapshots.contains { $0.week == "2026-10-26" }, "Feature events also retire weeks relative to their current receipt time")
        XCTAssertEqual(ledger.snapshots.first { $0.week == "2026-11-02" && $0.kind == .workout }?.counts["sessions"], 2)
    }
    func testIndependentAdultOnlyConsentsAndCoarseProjection() throws {
        var ledger = AnalyticsLedger(owner: owner, age: adult)
        XCTAssertNil(ledger.capture(.workout)); XCTAssertNil(ledger.capture(.usage))
        ledger.consent(.workout, enabled: true)
        XCTAssertNil(ledger.capture(.usage)); XCTAssertNotNil(ledger.capture(.workout))
        ledger.record(record(age: adult, owner: owner), captured: ledger.capture(.workout), currentAge: adult, at: date)
        let value = try XCTUnwrap(ledger.snapshots.first)
        XCTAssertEqual(value.counts["sessions"], 1); XCTAssertEqual(value.counts["reps"], 10)
        let wire = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        for forbidden in [owner.accountID.uuidString, owner.profileID.uuidString, "age", "heartRate", "date", "exerciseID"] { XCTAssertFalse(wire.contains(forbidden)) }
    }
    func testWithdrawalReconsentOfflineWatchUnknownAndForeignRecordsFailClosed() throws {
        var ledger = AnalyticsLedger(owner: owner, age: adult)
        ledger.consent(.workout, enabled: true); let old = ledger.capture(.workout)
        ledger.record(record(age: adult, owner: owner), captured: old, currentAge: adult, at: date)
        XCTAssertEqual(ledger.snapshots.count, 1)
        ledger.consent(.workout, enabled: false); XCTAssertTrue(ledger.snapshots.isEmpty)
        ledger.consent(.workout, enabled: true)
        ledger.record(record(age: adult, owner: owner), captured: old, currentAge: adult, at: date)
        ledger.record(record(age: nil, owner: owner), captured: ledger.capture(.workout), currentAge: adult, at: date)
        ledger.record(record(age: adult, owner: .init(accountID: UUID(), profileID: UUID())), captured: ledger.capture(.workout), currentAge: adult, at: date)
        ledger.record(record(age: adult, owner: owner), captured: ledger.capture(.workout), currentAge: nil, at: date)
        XCTAssertTrue(ledger.snapshots.isEmpty)
        for age in [nil, try TrainingAgeContext(ageYears: 12, guardianManaged: true)] {
            var excluded = AnalyticsLedger(owner: owner, age: age)
            excluded.consent(.usage, enabled: true); excluded.consent(.workout, enabled: true)
            XCTAssertNil(excluded.capture(.usage)); XCTAssertNil(excluded.capture(.workout))
        }
    }
    func testCompletionReplayBoundsAndUsageWithdrawalAreIndependent() throws {
        var ledger = AnalyticsLedger(owner: owner, age: adult)
        ledger.consent(.usage, enabled: true); ledger.consent(.workout, enabled: true)
        let record = record(age: adult, owner: owner)
        for _ in 0..<100 { ledger.record(record, captured: ledger.capture(.workout), currentAge: adult, at: date) }
        XCTAssertEqual(ledger.snapshots.first?.counts["sessions"], 1)
        for _ in 0..<2500 { ledger.feature("today", captured: ledger.capture(.usage), currentAge: adult, at: date) }
        XCTAssertEqual(ledger.snapshots.first(where: {$0.kind == .usage})?.counts["today"], 2000)
        ledger.consent(.usage, enabled: false)
        XCTAssertEqual(ledger.snapshots.count, 1); XCTAssertNotNil(ledger.capture(.workout))
    }
}
