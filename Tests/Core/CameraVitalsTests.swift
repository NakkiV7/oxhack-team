import Foundation
import Testing
@testable import SpottrCore

private let cameraNow = Date(timeIntervalSince1970: 100)
private func cameraSample(_ run: CameraVitalsRun, metric: CameraVitalMetric = .pulse,
                          value: Double = 72, date: Date = cameraNow,
                          confidence: Double = 90, stable: Bool = true) -> CameraVitalSample {
    .init(sessionID: run.sessionID, measurementID: run.measurementID, metric: metric,
          value: value, date: date, confidence: confidence, stable: stable)
}

@Test func cameraVitalsRequiresObservedWarmupAndQualityInsteadOfElapsedDisplayTime() {
    var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-30))
    run.ingest([cameraSample(run, date: cameraNow.addingTimeInterval(-20))],
               validationOK: true, stationary: true, now: cameraNow)
    #expect(run.pulse(at: cameraNow) == nil)
    run.ingest([cameraSample(run), cameraSample(run, metric: .breathing, value: 14)],
               validationOK: true, stationary: true, now: cameraNow)
    #expect(run.pulse(at: cameraNow)?.value == 72)
    #expect(run.breathing(at: cameraNow)?.value == 14)
    #expect(run.pulse(at: cameraNow.addingTimeInterval(6)) == nil)
}

@Test func cameraVitalsRejectsWrongRunFutureUnstableInvalidAndOutOfModelRange() {
    let start = cameraNow.addingTimeInterval(-40)
    for sample in [
        CameraVitalSample(sessionID: UUID(), measurementID: UUID(), metric: .pulse, value: 72,
                          date: cameraNow, confidence: 90, stable: true)
    ] {
        var run = CameraVitalsRun(sessionID: UUID(), startedAt: start)
        run.ingest([sample], validationOK: true, stationary: true, now: cameraNow)
        #expect(run.pulse(at: cameraNow) == nil)
    }
    for (value, confidence, stable, offset) in [(Double.nan, 90.0, true, 0.0),
        (111, 90, true, 0), (39, 90, true, 0), (72, .infinity, true, 0),
        (72, 101, true, 0), (72, 39, true, 0), (72, 90, false, 0), (72, 90, true, 3)] {
        var run = CameraVitalsRun(sessionID: UUID(), startedAt: start)
        run.ingest([cameraSample(run, value: value, date: cameraNow.addingTimeInterval(offset),
                                 confidence: confidence, stable: stable)],
                   validationOK: true, stationary: true, now: cameraNow)
        #expect(run.pulse(at: cameraNow) == nil)
    }
    var breathing = CameraVitalsRun(sessionID: UUID(), startedAt: start)
    breathing.ingest([cameraSample(breathing, metric: .breathing, value: 41)],
                      validationOK: true, stationary: true, now: cameraNow)
    #expect(breathing.breathing(at: cameraNow) == nil)
}

@Test func cameraVitalsGapsDoNotBecomeZeroOrRegressAndInvalidContextClearsEstimates() {
    var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-40))
    run.ingest([cameraSample(run)], validationOK: true, stationary: true, now: cameraNow)
    run.ingest([], validationOK: true, stationary: true, now: cameraNow)
    run.ingest([cameraSample(run, value: 65, date: cameraNow.addingTimeInterval(-1))],
               validationOK: true, stationary: true, now: cameraNow)
    #expect(run.pulse(at: cameraNow)?.value == 72)
    run.ingest([], validationOK: false, stationary: true, now: cameraNow)
    #expect(run.pulse(at: cameraNow) == nil)
    run.ingest([cameraSample(run)], validationOK: true, stationary: false, now: cameraNow)
    #expect(run.pulse(at: cameraNow) == nil)
    run.stop()
    run.ingest([cameraSample(run)], validationOK: true, stationary: true, now: cameraNow)
    #expect(run.pulse(at: cameraNow) == nil)
}

@Test func freshWatchHeartRateWinsWithoutReplacingCameraBreathingOrMixingSessions() {
    let session = UUID()
    var run = CameraVitalsRun(sessionID: session, startedAt: cameraNow.addingTimeInterval(-40))
    run.ingest([cameraSample(run), cameraSample(run, metric: .breathing, value: 14)],
               validationOK: true, stationary: true, now: cameraNow)
    func watch(_ id: UUID = session, age: Double = 0) -> WatchTelemetry {
        .init(sessionID: id, sentAt: cameraNow, heartRate: .init(value: 120, date: cameraNow.addingTimeInterval(-age)),
              accelerationG: nil, rotationRadiansPerSecond: nil)
    }
    let preferred = VitalsDisplay(sessionID: session, watch: watch(), camera: run, now: cameraNow)
    #expect(preferred.heartRate?.value == 120)
    #expect(preferred.heartRate?.source == .watch)
    #expect(preferred.breathingRate?.value == 14)
    #expect(VitalsDisplay(sessionID: session, watch: watch(age: 13), camera: run, now: cameraNow).heartRate?.source == .presage)
    #expect(VitalsDisplay(sessionID: session, watch: watch(UUID()), camera: run, now: cameraNow).heartRate?.value == 72)
    #expect(VitalsDisplay(sessionID: UUID(), watch: watch(), camera: run, now: cameraNow).heartRate == nil)
}
