import XCTest
@testable import SpottrCore

final class ConsentedAnalyticsTests: XCTestCase {
    private let owner = WorkoutOwner(accountID: UUID(), profileID: UUID())
    private var adult: TrainingAgeContext { try! .init(ageYears: 30, guardianManaged: false) }
    private let date = Date(timeIntervalSince1970: 1794000000)
    private func record(age: TrainingAgeContext?, owner: WorkoutOwner) -> SessionRecord {
        .init(id: UUID(), date: date, sets: [], loggedSets: [.init(id: UUID(), exerciseID: "squat", reps: 13, seconds: 0, source: .manual, reason: .voluntary)], endedAt: date, trainingContext: .init(owner: owner, age: age))
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
