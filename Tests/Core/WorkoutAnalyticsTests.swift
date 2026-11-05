import Foundation
import Testing
@testable import SpottrCore

private let analyticDate = Date(timeIntervalSince1970: 1_800_000_000)
private func analyticRecord(_ values: [(Double,Double)], end: Double? = 40, timeline: [WorkoutPhaseMark] = []) -> SessionRecord {
    let id=UUID()
    return SessionRecord(id:id,date:analyticDate,sets:[],telemetry:values.map { offset,value in
        WatchTelemetry(sessionID:id,sentAt:analyticDate.addingTimeInterval(offset),heartRate:SensorReading(value:value,date:analyticDate.addingTimeInterval(offset)),accelerationG:nil,rotationRadiansPerSecond:nil)
    }, endedAt:end.map { analyticDate.addingTimeInterval($0) },timeline:timeline)
}
@Test func zonesRequireAnExplicitValidBasisAndNeverInventAnAge() throws {
    #expect(HeartRateZoneConfiguration.estimated(age:17)==nil)
    #expect(HeartRateZoneConfiguration.estimated(age:101)==nil)
    #expect(HeartRateZoneConfiguration.estimated(age:20)?.maximumHeartRate==200)
    #expect(HeartRateZoneConfiguration.estimated(age:20)?.isEstimated==true)
    #expect(throws:(any Error).self) { try HeartRateZoneConfiguration(maximumHeartRate:.nan) }
    #expect(throws:(any Error).self) { try HeartRateZoneConfiguration(maximumHeartRate:0) }
    let absent=WorkoutAnalytics(record:analyticRecord([]))
    #expect(absent.heart.average==nil)
    #expect(absent.heart.coverageFraction==nil)
    #expect(absent.heart.zones.isEmpty)
}
@Test func pulseZonesCountOnlyObservedIntervalsWithoutFillingGapsOrExtrapolating() throws {
    let report=WorkoutAnalytics(record:analyticRecord([(0,100),(5,120),(10,160),(30,180)]),zones:try HeartRateZoneConfiguration(maximumHeartRate:200))
    #expect(report.heart.observedSeconds==10)
    #expect(report.heart.eligibleSeconds==40)
    #expect(report.heart.coverageFraction==0.25)
    #expect(report.heart.average==110)
    #expect(report.heart.minimum==100)
    #expect(report.heart.maximum==180)
    #expect(report.heart.gapCount==1)
    #expect(report.heart.zones.map(\.seconds)==[5,5,0,0,0])
}
@Test func pausedTimeIsExcludedAndPulseIntervalsNeverBridgeAPause() {
    let marks:[WorkoutPhaseMark] = [.init(date:analyticDate,phase:.active),.init(date:analyticDate.addingTimeInterval(7),phase:.paused),.init(date:analyticDate.addingTimeInterval(13),phase:.active),.init(date:analyticDate.addingTimeInterval(20),phase:.finished)]
    let report=WorkoutAnalytics(record:analyticRecord([(0,100),(5,110),(10,120),(15,130),(20,140)],end:20,timeline:marks))
    #expect(report.pausedSeconds==6)
    #expect(report.heart.observedSeconds==10)
    #expect(report.heart.eligibleSeconds==14)
    #expect(report.heart.average==115)
}
@Test func legacyCoverageStatesItsSampleSpanAndSingleReadingsNeverClaimDuration() {
    let legacy=WorkoutAnalytics(record:analyticRecord([(3,100),(8,110)],end:nil))
    #expect(legacy.heart.eligibleSeconds==5)
    #expect(legacy.heart.coverageBasis.lowercased().contains("span"))
    let single=WorkoutAnalytics(record:analyticRecord([(5,100)]))
    #expect(single.heart.observedSeconds==0)
    #expect(single.heart.average==nil)
    #expect(single.heart.coverageFraction==nil)
}
@Test func foreignFutureStaleAndDuplicatePulsePacketsCannotInflateAnalytics() {
    let base=analyticRecord([(0,100),(5,120),(10,160)])
    let duplicate=base.telemetry[1]
    let foreign=WatchTelemetry(sessionID:UUID(),sentAt:analyticDate.addingTimeInterval(6),heartRate:.init(value:250,date:analyticDate.addingTimeInterval(6)),accelerationG:nil,rotationRadiansPerSecond:nil)
    let future=WatchTelemetry(sessionID:base.id,sentAt:analyticDate.addingTimeInterval(99),heartRate:.init(value:250,date:analyticDate.addingTimeInterval(99)),accelerationG:nil,rotationRadiansPerSecond:nil)
    let stale=WatchTelemetry(sessionID:base.id,sentAt:analyticDate.addingTimeInterval(35),heartRate:.init(value:250,date:analyticDate.addingTimeInterval(2)),accelerationG:nil,rotationRadiansPerSecond:nil)
    let record=SessionRecord(id:base.id,date:base.date,sets:[],telemetry:[future,foreign,stale]+base.telemetry+[duplicate],endedAt:base.endedAt)
    let report=WorkoutAnalytics(record:record)
    #expect(report.heart.samples.count==3)
    #expect(report.heart.observedSeconds==10)
    #expect(report.heart.maximum==160)
}
private func timedSet(_ exercise:Exercise = .squat, source:InputSource = .camera, times:[Double] = [2,2,2]) -> SetRecord {
    SetRecord(id:UUID(),exercise:exercise,number:1,reps:times.count,target:times.count,activeSeconds:times.reduce(0,+),source:source,reserve:nil,reason:.target,repDurations:times)
}
@Test func paceUsesCompleteCameraRepsAndDoesNotScoreOneRepOrMixedExercises() {
    let id=UUID()
    let report=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[timedSet(),timedSet(source:.manual),timedSet(source:.video)]))
    #expect(report.pace.timedReps==3)
    #expect(report.pace.averageSeconds==2)
    #expect(report.pace.repRatePerMinute==30)
    #expect(report.pace.variabilityPercent==0)
    let mixed=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[timedSet(),timedSet(.pushup,times:[1,1,1])]))
    #expect(mixed.pace.timedReps==6)
    #expect(mixed.pace.variabilityPercent==nil)
    let one=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[timedSet(times:[2])]))
    #expect(one.pace.variabilityPercent==nil)
}
@Test func energyCountsEachRecordingOnceAndFlagsCumulativeResets() {
    let id=UUID(),a=UUID(),b=UUID()
    let data:[(Double,UUID,Double)] = [(0,a,2),(5,a,5),(10,a,4),(20,a,8),(25,b,3),(30,b,6)]
    let samples=data.map { offset,recording,value in WatchTelemetry(sessionID:id,sentAt:analyticDate.addingTimeInterval(offset),heartRate:nil,accelerationG:nil,rotationRadiansPerSecond:nil,activeEnergy:.init(recordingID:recording,kilocalories:value,asOf:analyticDate.addingTimeInterval(offset))) }
    let report=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[],telemetry:samples,endedAt:analyticDate.addingTimeInterval(40)))
    #expect(report.activeKilocalories==14)
    #expect(report.energyResetCount==1)
}
@Test func motionRMSIsSampleWeightedAndOverlappingWindowsDoNotDoubleCount() {
    let id=UUID(),recording=UUID()
    let windows:[WatchMotionWindow] = [.init(recordingID:recording,start:analyticDate,end:analyticDate.addingTimeInterval(1),sampleCount:10,rmsAccelerationG:1,peakAccelerationG:2,meanRotationRadiansPerSecond:1,peakRotationRadiansPerSecond:2),.init(recordingID:recording,start:analyticDate.addingTimeInterval(1),end:analyticDate.addingTimeInterval(2),sampleCount:30,rmsAccelerationG:3,peakAccelerationG:4,meanRotationRadiansPerSecond:3,peakRotationRadiansPerSecond:4)]
    let samples=(windows+[windows[0]]).map { w in WatchTelemetry(sessionID:id,sentAt:w.end,heartRate:nil,accelerationG:nil,rotationRadiansPerSecond:nil,motionWindow:w) }
    let report=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[],telemetry:samples,endedAt:analyticDate.addingTimeInterval(3)))
    #expect(report.motion.windowCount==2)
    #expect(report.motion.sampleCount==40)
    #expect(abs((report.motion.rmsAccelerationG ?? 0)-sqrt(7))<0.000001)
    #expect(report.motion.meanRotationRadiansPerSecond==2.5)
    #expect(report.motion.observedSeconds==2)
}
@Test func motionChartsNeverJoinDistinctWatchRecordings() {
    let id=UUID()
    let windows=(0..<2).map { index in WatchMotionWindow(recordingID:UUID(),start:analyticDate.addingTimeInterval(Double(index)),end:analyticDate.addingTimeInterval(Double(index+1)),sampleCount:10,rmsAccelerationG:1,peakAccelerationG:1,meanRotationRadiansPerSecond:1,peakRotationRadiansPerSecond:1) }
    let packets=windows.map { WatchTelemetry(sessionID:id,sentAt:$0.end,heartRate:nil,accelerationG:nil,rotationRadiansPerSecond:nil,motionWindow:$0) }
    let report=WorkoutAnalytics(record:.init(id:id,date:analyticDate,sets:[],telemetry:packets,endedAt:analyticDate.addingTimeInterval(3)))
    #expect(report.motion.accelerationSamples.map(\.segment)==[0,1])
}
@Test func pulseChartsNeverDrawThroughPausedIntervals() {
    let marks:[WorkoutPhaseMark] = [.init(date:analyticDate,phase:.active),.init(date:analyticDate.addingTimeInterval(7),phase:.paused),.init(date:analyticDate.addingTimeInterval(13),phase:.active)]
    let report=WorkoutAnalytics(record:analyticRecord([(0,100),(5,110),(15,120),(20,130)],end:20,timeline:marks))
    #expect(report.heart.samples.map(\.segment)==[0,0,1,1])
}
@Test func dayHeartAveragesWeightActualObservedTimeRatherThanAveragingAverages() {
    let short=analyticRecord([(0,100),(5,100)],end:20)
    let long=analyticRecord([(0,200),(10,200),(15,200)],end:20)
    #expect(WorkoutAnalytics.averageHeartRate(in:[short,long])==175)
}
