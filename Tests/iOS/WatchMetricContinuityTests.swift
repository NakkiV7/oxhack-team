import XCTest
@testable import Spottr

@MainActor
final class WatchMetricContinuityTests: XCTestCase {
    func testLegacyHeartRateSurvivesPartialPacketsUntilItsOriginalObservationExpires() async throws {
        try await checkContinuity(configured: false)
    }

    func testConfiguredHeartRateSurvivesPartialPacketsUntilItsOriginalObservationExpires() async throws {
        try await checkContinuity(configured: true)
    }

    private func checkContinuity(configured: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TrainingStore(historyURL: folder.appendingPathComponent("history.json"))
        if configured {
            store.startPlan(try CoachSavedPlan.catalogue(exerciseID: "squat", sets: 1, target: 2, restSeconds: 0), availableSupport: [])
        } else { store.start() }
        let sessionID = store.configured?.id ?? store.session.id
        let now = Date()
        func packet(_ offset: Double, heartRate: SensorReading? = nil, motion: SensorReading? = nil,
                    energy: ActiveEnergy? = nil, id: UUID? = nil) -> WatchTelemetry {
            .init(sessionID: id ?? sessionID, sentAt: now.addingTimeInterval(offset), heartRate: heartRate,
                  accelerationG: motion, rotationRadiansPerSecond: nil, activeEnergy: energy)
        }
        await deliver(packet(-1, heartRate: .init(value: 72, date: now.addingTimeInterval(-1))), to: store, count: 1)
        XCTAssertEqual(store.heartRate(at: now), "72 bpm")
        await deliver(packet(-0.5, motion: .init(value: 0.3, date: now.addingTimeInterval(-0.5))), to: store, count: 2)
        XCTAssertEqual(store.heartRate(at: now), "72 bpm", "A motion-only envelope must not clear fresh heart rate")
        await deliver(packet(0, energy: .init(recordingID: UUID(), kilocalories: 5, asOf: now)), to: store, count: 3)
        XCTAssertEqual(store.heartRate(at: now), "72 bpm", "An energy-only envelope must not clear fresh heart rate")
        await deliver(packet(0.01, heartRate: .init(value: 150, date: now.addingTimeInterval(-30))), to: store, count: 4)
        XCTAssertEqual(store.heartRate(at: now), "72 bpm", "A fresh envelope cannot make an old observation replace fresh heart rate")
        store.companion.onTelemetry?(packet(0.02, heartRate: .init(value: 190, date: now), id: UUID()))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual((store.configured?.telemetry ?? store.session.telemetry).count, 4)
        XCTAssertEqual(store.heartRate(at: now), "72 bpm")
        XCTAssertEqual(store.heartRate(at: now.addingTimeInterval(11)), "72 bpm")
        XCTAssertEqual(store.heartRate(at: now.addingTimeInterval(11.001)), "—", "Partial packets must not extend the original 12-second freshness window")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("history.json").path))
    }

    private func deliver(_ packet: WatchTelemetry, to store: TrainingStore, count: Int) async {
        store.companion.onTelemetry?(packet)
        for _ in 0..<100 where (store.configured?.telemetry ?? store.session.telemetry).count < count { await Task.yield() }
        XCTAssertEqual((store.configured?.telemetry ?? store.session.telemetry).count, count)
    }
}
