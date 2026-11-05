import Foundation

public struct WorkoutPhaseMark: Codable, Equatable, Sendable {
    public let date: Date
    public let phase: SessionPhase
    public init(date: Date, phase: SessionPhase) { self.date = date; self.phase = phase }
}

public struct HeartRateZoneConfiguration: Codable, Equatable, Sendable {
    public enum Invalid: LocalizedError { case maximum
        public var errorDescription: String? { "Enter a maximum heart rate from 60 to 260 bpm." }
    }
    public let maximumHeartRate: Double
    public let isEstimated: Bool
    public init(maximumHeartRate: Double, isEstimated: Bool = false) throws {
        guard maximumHeartRate.isFinite, (60...260).contains(maximumHeartRate) else { throw Invalid.maximum }
        self.maximumHeartRate = maximumHeartRate; self.isEstimated = isEstimated
    }
    public static func estimated(age: Int) -> Self? {
        guard (18...100).contains(age) else { return nil }
        return try? Self(maximumHeartRate: Double(220-age), isEstimated: true)
    }
    private enum CodingKeys: String, CodingKey { case maximumHeartRate, isEstimated }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(maximumHeartRate: values.decode(Double.self, forKey: .maximumHeartRate), isEstimated: values.decode(Bool.self, forKey: .isEstimated))
    }
}

public struct HeartRateZoneDuration: Identifiable, Equatable, Sendable {
    public let id: Int
    public let lowerBPM: Double
    public let upperBPM: Double
    public let seconds: Double
}
public struct HeartRateAnalysis: Sendable {
    public let samples: [ReportSample]
    public let minimum: Double?
    public let maximum: Double?
    public let average: Double?
    public let observedSeconds: Double
    public let eligibleSeconds: Double
    public let coverageFraction: Double?
    public let coverageBasis: String
    public let gapCount: Int
    public let zones: [HeartRateZoneDuration]
    public let belowZoneSeconds: Double
    public let aboveMaximumSeconds: Double
}
public struct MotionAnalysis: Sendable {
    public let rmsAccelerationG: Double?
    public let peakAccelerationG: Double?
    public let meanRotationRadiansPerSecond: Double?
    public let peakRotationRadiansPerSecond: Double?
    public let variationPercent: Double?
    public let windowCount: Int
    public let sampleCount: Int
    public let observedSeconds: Double
    public let accelerationSamples: [ReportSample]
    public let rotationSamples: [ReportSample]
}
public struct RepPaceAnalysis: Sendable {
    public let recordedCameraReps: Int
    public let timedReps: Int
    public let averageSeconds: Double?
    public let fastestSeconds: Double?
    public let slowestSeconds: Double?
    public let variabilityPercent: Double?
    public let repRatePerMinute: Double?
    public let durations: [Double]
}
public struct WorkoutAnalytics: Sendable {
    public let heart: HeartRateAnalysis
    public let motion: MotionAnalysis
    public let pace: RepPaceAnalysis
    public let activeSeconds: Double
    public let restSeconds: Double?
    public let workRestRatio: Double?
    public let elapsedSeconds: Double?
    public let pausedSeconds: Double
    public let activeKilocalories: Double?
    public let energyResetCount: Int

    public init(record: SessionRecord, zones: HeartRateZoneConfiguration? = nil) {
        let cleaned = Self.boundedRecord(record)
        let report = WorkoutReport(record: cleaned)
        let end = Self.validEnd(record)
        let timeline = record.timeline.filter { $0.date.timeIntervalSince1970.isFinite && $0.date >= record.date && $0.date <= (end ?? .distantFuture) }.sorted { $0.date < $1.date }
        let paused = end.map { Self.pausedDuration(timeline, start: record.date, end: $0) } ?? 0
        elapsedSeconds = end.map { $0.timeIntervalSince(record.date) }
        pausedSeconds = paused
        let active = report.sets.map(\.activeSeconds).filter { $0.isFinite && $0 >= 0 }.reduce(0,+)
        activeSeconds = active
        restSeconds = report.recordedRestSeconds
        workRestRatio = restSeconds.flatMap { $0 > 0 ? active/$0 : nil }
        heart = Self.heartAnalysis(report.heartRate.samples, record: cleaned, timeline: timeline, paused: paused, zones: zones)
        motion = Self.motionAnalysis(cleaned, report: report)
        pace = Self.paceAnalysis(report.sets)
        let energy = Self.energyAnalysis(cleaned)
        activeKilocalories = energy.total; energyResetCount = energy.resets
    }
    public static func averageHeartRate(in records: [SessionRecord]) -> Double? {
        let distinct=Dictionary(records.map { ($0.id,$0) },uniquingKeysWith: { _,last in last })
        let observations=distinct.values.map { WorkoutAnalytics(record:$0).heart }.filter { $0.average != nil && $0.observedSeconds > 0 }
        let duration=observations.reduce(0) { $0+$1.observedSeconds }
        return duration > 0 ? observations.reduce(0) { $0+($1.average ?? 0)*$1.observedSeconds }/duration:nil
    }
    private static func validEnd(_ record: SessionRecord) -> Date? {
        guard record.date.timeIntervalSince1970.isFinite, let end=record.endedAt, end.timeIntervalSince1970.isFinite,
              (0...86_400).contains(end.timeIntervalSince(record.date)) else { return nil }
        return end
    }
    private static func boundedRecord(_ record: SessionRecord) -> SessionRecord {
        let end=validEnd(record)
        let messages=record.telemetry.filter { sample in
            sample.sessionID==record.id && record.date.timeIntervalSince1970.isFinite && sample.sentAt.timeIntervalSince1970.isFinite && sample.sentAt >= record.date.addingTimeInterval(-2) && (end.map({ sample.sentAt <= $0.addingTimeInterval(2) }) ?? true)
        }
        return SessionRecord(id:record.id,date:record.date,sets:record.sets,telemetry:messages,loggedSets:record.loggedSets,skippedSets:record.skippedSets,endedAt:end,timeline:record.timeline)
    }
    private static func pausedDuration(_ marks: [WorkoutPhaseMark], start: Date, end: Date) -> Double {
        var total=0.0
        for (index,mark) in marks.enumerated() where mark.phase == .paused {
            let next=index+1 < marks.count ? marks[index+1].date : end
            total += max(0,min(end,next).timeIntervalSince(max(start,mark.date)))
        }
        return total
    }
    private static func heartAnalysis(_ samples:[ReportSample], record:SessionRecord, timeline:[WorkoutPhaseMark], paused:Double,zones:HeartRateZoneConfiguration?) -> HeartRateAnalysis {
        let end=validEnd(record)
        let span=samples.first.flatMap { first in samples.last.map { max(0,$0.date.timeIntervalSince(first.date)) } } ?? 0
        let eligible=end.map { max(0,$0.timeIntervalSince(record.date)-paused) } ?? span
        let thresholds=zones.map { config in [50,60,70,80,90,100].map { config.maximumHeartRate*Double($0)/100 } } ?? []
        var durations=Array(repeating:0.0,count:5),observed=0.0,weighted=0.0,below=0.0,above=0.0,gaps=0
        for (first,last) in zip(samples,samples.dropFirst()) {
            let delta=last.date.timeIntervalSince(first.date)
            if delta > 12 { gaps += 1; continue }
            guard delta > 0 else { continue }
            let phase=timeline.last(where: { $0.date <= first.date })?.phase
            guard phase != .paused && phase != .idle && phase != .finished else { continue }
            guard !timeline.contains(where: { $0.date > first.date && $0.date < last.date && [.paused,.idle,.finished].contains($0.phase) }) else { continue }
            let from=max(record.date,first.date),to=min(end ?? last.date,last.date)
            let seconds=max(0,to.timeIntervalSince(from))
            observed += seconds; weighted += first.value*seconds
            if let maximum=zones?.maximumHeartRate {
                if first.value < thresholds[0] { below += seconds }
                else if first.value > maximum { above += seconds }
                else if let index=(0..<5).first(where: { first.value >= thresholds[$0] && (first.value < thresholds[$0+1] || $0==4) }) { durations[index] += seconds }
            }
        }
        var chartSegment=0
        let chartSamples=samples.enumerated().map { index,point in
            if index > 0 {
                let previous=samples[index-1]
                let phase=timeline.last(where: { $0.date <= previous.date })?.phase
                let interrupted=timeline.contains { $0.date > previous.date && $0.date < point.date && [.paused,.idle,.finished].contains($0.phase) }
                if point.date.timeIntervalSince(previous.date)>12 || [.paused,.idle,.finished].contains(where: { $0 == phase }) || interrupted { chartSegment += 1 }
            }
            return ReportSample(date:point.date,value:point.value,segment:chartSegment)
        }
        let bands=zones == nil ? [] : (0..<5).map { HeartRateZoneDuration(id:$0+1,lowerBPM:thresholds[$0],upperBPM:thresholds[$0+1],seconds:durations[$0]) }
        return HeartRateAnalysis(samples:chartSamples,minimum:samples.map(\.value).min(),maximum:samples.map(\.value).max(),average:observed > 0 ? weighted/observed:nil,observedSeconds:observed,eligibleSeconds:eligible,coverageFraction:observed > 0 && eligible > 0 ? min(1,observed/eligible):nil,coverageBasis:end == nil ? "Reading-span coverage" : "Session coverage excluding pauses",gapCount:gaps,zones:bands,belowZoneSeconds:below,aboveMaximumSeconds:above)
    }
    private static func coefficient(_ values:[Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let mean=values.reduce(0,+)/Double(values.count)
        guard mean > 0 else { return nil }
        return sqrt(values.reduce(0) { $0+pow($1-mean,2) }/Double(values.count))/mean*100
    }
    private static func paceAnalysis(_ sets:[ReportSet]) -> RepPaceAnalysis {
        let camera=sets.filter { $0.source == .camera && $0.reps > 0 }
        let measured=camera.filter { !$0.repDurations.isEmpty && $0.repDurations.count <= $0.reps }
        let values=measured.flatMap(\.repDurations)
        let average=values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)
        return RepPaceAnalysis(recordedCameraReps:camera.reduce(0) { $0+$1.reps },timedReps:values.count,averageSeconds:average,fastestSeconds:values.min(),slowestSeconds:values.max(),variabilityPercent:Set(measured.map(\.exerciseID)).count==1 ? coefficient(values):nil,repRatePerMinute:average.flatMap { $0 > 0 ? 60/$0:nil },durations:values)
    }
    private static func motionAnalysis(_ record:SessionRecord,report:WorkoutReport) -> MotionAnalysis {
        let candidates=record.telemetry.compactMap { message -> WatchMotionWindow? in
            guard let w=message.motionWindow,w.start.timeIntervalSince1970.isFinite,w.end.timeIntervalSince1970.isFinite,
                  w.start >= record.date.addingTimeInterval(-2),w.end <= message.sentAt.addingTimeInterval(2),message.sentAt.timeIntervalSince(w.end) <= 12,
                  (0...5).contains(w.end.timeIntervalSince(w.start)),(1...1000).contains(w.sampleCount),
                  w.rmsAccelerationG.isFinite,w.peakAccelerationG.isFinite,w.meanRotationRadiansPerSecond.isFinite,w.peakRotationRadiansPerSecond.isFinite,
                  (0...64).contains(w.rmsAccelerationG),(w.rmsAccelerationG...64).contains(w.peakAccelerationG),
                  (0...1000).contains(w.meanRotationRadiansPerSecond),(w.meanRotationRadiansPerSecond...1000).contains(w.peakRotationRadiansPerSecond),
                  message.activeEnergy.map({ $0.recordingID==w.recordingID }) ?? true else { return nil }
            return w
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var windows:[WatchMotionWindow]=[],seen=Set<String>()
        for window in candidates {
            let key="\(window.recordingID)-\(window.start.timeIntervalSince1970)-\(window.end.timeIntervalSince1970)"
            guard !seen.contains(key), windows.last.map({ window.start >= $0.end }) ?? true else { continue }
            seen.insert(key); windows.append(window)
        }
        let count=windows.reduce(0) { $0+$1.sampleCount }
        let rms=count > 0 ? sqrt(windows.reduce(0) { $0+$1.rmsAccelerationG*$1.rmsAccelerationG*Double($1.sampleCount) }/Double(count)):nil
        let rotation=count > 0 ? windows.reduce(0) { $0+$1.meanRotationRadiansPerSecond*Double($1.sampleCount) }/Double(count):nil
        func points(_ value:(WatchMotionWindow)->Double) -> [ReportSample] {
            var segment=0
            return windows.enumerated().map { index,window in
                if index > 0, window.recordingID != windows[index-1].recordingID || window.start.timeIntervalSince(windows[index-1].end) > 2 { segment += 1 }
                return ReportSample(date:window.end,value:value(window),segment:segment)
            }
        }
        return MotionAnalysis(rmsAccelerationG:rms,peakAccelerationG:windows.map(\.peakAccelerationG).max() ?? report.acceleration.maximum,meanRotationRadiansPerSecond:rotation ?? report.rotation.average,peakRotationRadiansPerSecond:windows.map(\.peakRotationRadiansPerSecond).max() ?? report.rotation.maximum,variationPercent:coefficient(windows.map(\.rmsAccelerationG)),windowCount:windows.count,sampleCount:count,observedSeconds:windows.reduce(0) { $0+max(0,$1.end.timeIntervalSince($1.start)) },accelerationSamples:windows.isEmpty ? report.acceleration.samples:points(\.rmsAccelerationG),rotationSamples:windows.isEmpty ? report.rotation.samples:points(\.meanRotationRadiansPerSecond))
    }
    private static func energyAnalysis(_ record:SessionRecord) -> (total:Double?,resets:Int) {
        var runs:[UUID:[Date:Double]]=[:]
        for message in record.telemetry.sorted(by: { $0.sentAt < $1.sentAt }) {
            guard let energy=message.activeEnergy,energy.isValid(at:message.sentAt),energy.asOf >= record.date.addingTimeInterval(-2),validEnd(record).map({ energy.asOf <= $0.addingTimeInterval(2) }) ?? true else { continue }
            runs[energy.recordingID,default:[:]][energy.asOf]=energy.kilocalories
        }
        var total=0.0,resets=0
        for run in runs.values {
            let values=run.sorted { $0.key < $1.key }.map(\.value)
            for (first,next) in zip(values,values.dropFirst()) where next < first { resets += 1 }
            total += values.max() ?? 0
        }
        return (runs.isEmpty ? nil:total,resets)
    }
}
