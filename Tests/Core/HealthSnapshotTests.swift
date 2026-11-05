import XCTest
@testable import SpottrCore

final class HealthSnapshotTests: XCTestCase {
    func testHistoricalPhysiologyAndTodaysActivityStayInSeparateDatedContexts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let resting = try XCTUnwrap(HealthObservation(metric: .restingHeartRate, value: 61, date: yesterday, source: "My Watch"))
        let steps = try XCTUnwrap(HealthObservation(metric: .steps, value: 1200, date: now, source: "Apple Health — iPhone, Watch"))
        let snapshot = HealthSnapshot(observations: [resting, steps], asOf: now, calendar: calendar)
        XCTAssertEqual(snapshot.latestObservations.map(\.metric), [.restingHeartRate])
        XCTAssertEqual(snapshot.latestObservations.first?.date, yesterday)
        XCTAssertEqual(snapshot.dailyObservations.map(\.metric), [.steps])
        XCTAssertEqual(snapshot.dailyObservations.first?.value, 1200)
        XCTAssertEqual(snapshot.dailyObservations.first?.unit, "steps")
        XCTAssertEqual(snapshot.dayStart, calendar.startOfDay(for: now))
        XCTAssertEqual(snapshot.dayEnd.timeIntervalSince(snapshot.dayStart), 86_400)
    }

    func testInvalidValuesFutureDatesAndPriorDayTotalsNeverBecomeCurrentHealthFacts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(HealthObservation(metric: .restingHeartRate, value: .nan, date: now, source: "Watch"))
        XCTAssertNil(HealthObservation(metric: .steps, value: -1, date: now, source: "Watch"))
        XCTAssertNil(HealthObservation(metric: .restingHeartRate, value: 0, date: now, source: "Watch"))
        XCTAssertNil(HealthObservation(metric: .oxygenSaturation, value: 101, date: now, source: "Watch"))
        XCTAssertNil(HealthObservation(metric: .vo2Max, value: 40, date: now, source: "  "))
        let oldSteps = try XCTUnwrap(HealthObservation(metric: .steps, value: 500, date: now.addingTimeInterval(-86_400), source: "Watch"))
        let future = try XCTUnwrap(HealthObservation(metric: .restingHeartRate, value: 80, date: now.addingTimeInterval(1), source: "Watch"))
        let earlier = try XCTUnwrap(HealthObservation(metric: .restingHeartRate, value: 64, date: now.addingTimeInterval(-100), source: "Watch"))
        let latest = try XCTUnwrap(HealthObservation(metric: .restingHeartRate, value: 62, date: now.addingTimeInterval(-10), source: "Watch"))
        let zeroDistance = try XCTUnwrap(HealthObservation(metric: .walkingRunningDistance, value: 0, date: now, source: "Health"))
        let snapshot = HealthSnapshot(observations: [oldSteps, future, earlier, latest, zeroDistance], asOf: now)
        XCTAssertEqual(snapshot.latestObservations, [latest])
        XCTAssertEqual(snapshot.dailyObservations, [zeroDistance])
    }

    func testDailyBoundsFollowLocalCalendarAcrossDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-29T12:00:00Z"))
        let snapshot = HealthSnapshot(observations: [], asOf: date, calendar: calendar)
        XCTAssertEqual(snapshot.dayEnd.timeIntervalSince(snapshot.dayStart), 23 * 3_600)
        XCTAssertTrue(snapshot.observations.isEmpty)
    }

    func testWatchSetupDoesNotClaimPairingInstallationOrReachabilityBeforeActivation() {
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: false, activated: false, paired: false, installed: false, reachable: false), .unsupported)
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: true, activated: false, paired: false, installed: false, reachable: false), .notReady)
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: true, activated: true, paired: false, installed: false, reachable: false), .notPaired)
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: true, activated: true, paired: true, installed: false, reachable: false), .notInstalled)
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: true, activated: true, paired: true, installed: true, reachable: false), .installedOffline)
        XCTAssertEqual(WatchSetupStatus.evaluate(supported: true, activated: true, paired: true, installed: true, reachable: true), .reachable)
    }
}
