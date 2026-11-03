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

@Test func restVitalsExamplesRequireExplicitPreviewAndAnUnavailableMeasurement() {
    let session = UUID()
    for preview in [false, true] {
        for unavailable in [false, true] {
            let display = DisplayRestVitals(sessionID: session, watch: nil, camera: nil, now: cameraNow,
                                           previewEnabled: preview, measurementUnavailable: unavailable)
            if preview && unavailable {
                #expect(display.heartRate?.value == 72)
                #expect(display.breathingRate?.value == 14)
                #expect(display.heartRate?.source == .demonstration)
                #expect(display.breathingRate?.source == .demonstration)
            } else {
                #expect(display.heartRate == nil)
                #expect(display.breathingRate == nil)
            }
        }
    }
}

@Test func restVitalsLiveWatchAndQualifiedPresageTakePriorityOverEveryExample() {
    let session = UUID()
    var run = CameraVitalsRun(sessionID: session, startedAt: cameraNow.addingTimeInterval(-40))
    run.ingest([cameraSample(run, value: 76), cameraSample(run, metric: .breathing, value: 17)],
               validationOK: true, stationary: true, now: cameraNow)
    let watch = WatchTelemetry(sessionID: session, sentAt: cameraNow, heartRate: .init(value: 115, date: cameraNow),
                               accelerationG: nil, rotationRadiansPerSecond: nil)
    for preview in [false, true] {
        let display = DisplayRestVitals(sessionID: session, watch: watch, camera: run, now: cameraNow,
                                       previewEnabled: preview, measurementUnavailable: true)
        #expect(display.heartRate?.value == 115)
        #expect(display.heartRate?.source == .watch)
        #expect(display.breathingRate?.value == 17)
        #expect(display.breathingRate?.source == .presage)
    }
    let cameraOnly = DisplayRestVitals(sessionID: session, watch: nil, camera: run, now: cameraNow,
                                      previewEnabled: true, measurementUnavailable: true)
    #expect(cameraOnly.heartRate?.value == 76)
    #expect(cameraOnly.heartRate?.source == .presage)
}

@Test func restVitalsFillOnlyTheMissingMetricAndNeverRelabelStaleOrForeignReadings() {
    let session = UUID()
    var run = CameraVitalsRun(sessionID: session, startedAt: cameraNow.addingTimeInterval(-40))
    run.ingest([cameraSample(run, value: 78)], validationOK: true, stationary: true, now: cameraNow)
    let stale = WatchTelemetry(sessionID: session, sentAt: cameraNow, heartRate: .init(value: 160, date: cameraNow.addingTimeInterval(-13)),
                              accelerationG: nil, rotationRadiansPerSecond: nil)
    let partial = DisplayRestVitals(sessionID: session, watch: stale, camera: run, now: cameraNow,
                                   previewEnabled: true, measurementUnavailable: true)
    #expect(partial.heartRate?.value == 78)
    #expect(partial.heartRate?.source == .presage)
    #expect(partial.breathingRate?.value == 14)
    #expect(partial.breathingRate?.source == .demonstration)
    let expired = DisplayRestVitals(sessionID: session, watch: stale, camera: run, now: cameraNow.addingTimeInterval(6),
                                   previewEnabled: true, measurementUnavailable: true)
    #expect(expired.heartRate?.value == 72)
    #expect(expired.heartRate?.source == .demonstration)
    let foreign = DisplayRestVitals(sessionID: UUID(), watch: stale, camera: run, now: cameraNow,
                                   previewEnabled: true, measurementUnavailable: true)
    #expect(foreign.heartRate?.source == .demonstration)
    #expect(foreign.breathingRate?.source == .demonstration)
    #expect(run.pulse(at: cameraNow)?.value == 78)
    #expect(VitalsDisplay(sessionID: session, watch: nil, camera: nil, now: cameraNow).heartRate == nil)
}

@Test func restVitalsNeverCreateExamplesAtAnInvalidDisplayTime() {
    let display = DisplayRestVitals(sessionID: UUID(), watch: nil, camera: nil,
                                   now: Date(timeIntervalSince1970: .nan), previewEnabled: true, measurementUnavailable: true)
    #expect(display.heartRate == nil)
    #expect(display.breathingRate == nil)
}

private let cameraHRVMetrics: [CameraVitalMetric] = [.hrvRMSSD, .hrvSDNN, .meanNN, .stressIndex]

@Test func cameraHRVRequiresSixtyObservedSecondsAndAQualifiedCurrentPulse() {
    for metric in cameraHRVMetrics {
        for elapsed in [59.0, 60.0] {
            var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-elapsed))
            run.ingest([cameraSample(run, metric: metric, value: 42, confidence: 50), cameraSample(run)],
                       validationOK: true, stationary: true, now: cameraNow)
            #expect(run.reading(metric, at: cameraNow)?.value == (elapsed == 60 ? 42 : nil))
            #expect(run.pulse(at: cameraNow)?.value == 72)
        }
    }
}

@Test func cameraHRVRejectsBadQualityValuesAgeAndMeasurementIdentity() {
    for metric in cameraHRVMetrics {
        for (value, confidence, stable, offset) in [
            (-0.1, 90.0, true, 0.0), (Double.nan, 90, true, 0), (Double.infinity, 90, true, 0),
            (42, 49.9, true, 0), (42, 100.1, true, 0), (42, Double.nan, true, 0),
            (42, 90, false, 0), (42, 90, true, -6), (42, 90, true, 3)
        ] {
            var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-90))
            run.ingest([cameraSample(run), cameraSample(run, metric: metric, value: value,
                date: cameraNow.addingTimeInterval(offset), confidence: confidence, stable: stable)],
                       validationOK: true, stationary: true, now: cameraNow)
            #expect(run.reading(metric, at: cameraNow) == nil)
        }
        for wrongSession in [false, true] {
            var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-90))
            let foreign = CameraVitalSample(sessionID: wrongSession ? UUID() : run.sessionID,
                measurementID: wrongSession ? run.measurementID : UUID(), metric: metric,
                value: 42, date: cameraNow, confidence: 90, stable: true)
            run.ingest([cameraSample(run), foreign], validationOK: true, stationary: true, now: cameraNow)
            #expect(run.reading(metric, at: cameraNow) == nil)
        }
    }
}

@Test func cameraHRVDisappearsWithoutQualifiedPulseAndAfterInvalidContextOrStop() {
    for metric in cameraHRVMetrics {
        for pulse in [Double?.none, 39, 111] {
            var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-90))
            var samples = [cameraSample(run, metric: metric, value: 42)]
            if let pulse { samples.append(cameraSample(run, value: pulse)) }
            run.ingest(samples, validationOK: true, stationary: true, now: cameraNow)
            #expect(run.reading(metric, at: cameraNow) == nil)
        }
        var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-90))
        run.ingest([cameraSample(run, date: cameraNow.addingTimeInterval(-5)), cameraSample(run, metric: metric, value: 42)],
                   validationOK: true, stationary: true, now: cameraNow)
        #expect(run.reading(metric, at: cameraNow)?.value == 42)
        #expect(run.reading(metric, at: cameraNow.addingTimeInterval(0.01)) == nil, "A still-fresh HRV sample cannot outlive its qualified pulse")
        for validationOK in [false, true] {
            var invalid = run
            invalid.ingest([], validationOK: validationOK, stationary: !validationOK, now: cameraNow)
            #expect(invalid.reading(metric, at: cameraNow) == nil)
        }
        run.stop()
        #expect(run.reading(metric, at: cameraNow) == nil)
    }
}

@Test func cameraHRVLatestReadingWinsAndRawZeroIsNotAnInventedBandOrPercent() {
    for metric in cameraHRVMetrics {
        var run = CameraVitalsRun(sessionID: UUID(), startedAt: cameraNow.addingTimeInterval(-90))
        run.ingest([cameraSample(run), cameraSample(run, metric: metric, value: 0, confidence: 100)],
                   validationOK: true, stationary: true, now: cameraNow)
        run.ingest([cameraSample(run, metric: metric, value: 80, date: cameraNow.addingTimeInterval(-1))],
                   validationOK: true, stationary: true, now: cameraNow)
        #expect(run.reading(metric, at: cameraNow)?.value == 0)
        #expect(run.reading(metric, at: cameraNow)?.metric == metric)
        #expect(run.reading(metric, at: cameraNow.addingTimeInterval(5))?.value == 0)
        #expect(run.reading(metric, at: cameraNow.addingTimeInterval(5.01)) == nil)
    }
}

@Test func restDemoHRVUsesExplicitProvenanceAndNeverAppearsInNormalOrWarmingDisplays() {
    let session = UUID()
    let demo = DisplayRestVitals(sessionID: session, watch: nil, camera: nil, now: cameraNow,
        previewEnabled: true, measurementUnavailable: true)
    #expect(demo.hrvRMSSD?.value == 42)
    #expect(demo.hrvSDNN?.value == 54)
    #expect(demo.meanNN?.value == 833)
    #expect(demo.stressIndex?.value == 65)
    #expect(demo.hrvRMSSD?.source == .demonstration)
    #expect(demo.stressIndex?.source == .demonstration)
    for (preview, unavailable) in [(false, true), (true, false)] {
        let display = DisplayRestVitals(sessionID: session, watch: nil, camera: nil, now: cameraNow,
            previewEnabled: preview, measurementUnavailable: unavailable)
        #expect(display.hrvRMSSD == nil && display.hrvSDNN == nil)
        #expect(display.meanNN == nil && display.stressIndex == nil)
    }
    var run = CameraVitalsRun(sessionID: session, startedAt: cameraNow.addingTimeInterval(-70))
    run.ingest([cameraSample(run), cameraSample(run, metric: .hrvRMSSD, value: 37)],
        validationOK: true, stationary: true, now: cameraNow)
    let observed = DisplayRestVitals(sessionID: session, watch: nil, camera: run, now: cameraNow,
        previewEnabled: true, measurementUnavailable: true)
    #expect(observed.hrvRMSSD?.value == 37)
    #expect(observed.hrvRMSSD?.source == .presage)
}
