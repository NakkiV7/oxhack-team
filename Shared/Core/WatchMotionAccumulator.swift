import Foundation

public struct WatchMotionAccumulator: Sendable {
    private let recordingID: UUID
    private var start: Date?
    private var end: Date?
    private var count = 0
    private var rms = 0.0
    private var accelerationPeak = 0.0
    private var rotationMean = 0.0
    private var rotationPeak = 0.0

    public init(recordingID: UUID) { self.recordingID = recordingID }

    public mutating func append(accelerationG: Double, rotationRadiansPerSecond: Double, at date: Date) -> WatchMotionWindow? {
        guard date.timeIntervalSince1970.isFinite, accelerationG.isFinite, accelerationG >= 0,
              rotationRadiansPerSecond.isFinite, rotationRadiansPerSecond >= 0 else { return flush() }
        if let end, date <= end { return nil }
        let boundary = start.map { date.timeIntervalSince($0) >= 1 } ?? false
        let gap = end.map { date.timeIntervalSince($0) > 0.3 } ?? false
        let completed = boundary || gap || count >= 10 ? flush() : nil
        start = start ?? date; end = date
        let nextCount = Double(count + 1), previousWeight = Double(count) / nextCount
        rms = hypot(rms * sqrt(previousWeight), accelerationG / sqrt(nextCount))
        rotationMean = rotationMean * previousWeight + rotationRadiansPerSecond / nextCount
        accelerationPeak = max(accelerationPeak, accelerationG)
        rotationPeak = max(rotationPeak, rotationRadiansPerSecond)
        count += 1
        return completed
    }

    public mutating func flush() -> WatchMotionWindow? {
        guard count > 0, let start, let end else { return nil }
        let window = WatchMotionWindow(recordingID: recordingID, start: start, end: end, sampleCount: count,
                                       rmsAccelerationG: rms, peakAccelerationG: accelerationPeak,
                                       meanRotationRadiansPerSecond: rotationMean, peakRotationRadiansPerSecond: rotationPeak)
        self.start = nil; self.end = nil; count = 0
        rms = 0; accelerationPeak = 0; rotationMean = 0; rotationPeak = 0
        return window
    }
}
