import Foundation
import Testing
@testable import SpottrCore

@Test func wristWindowsAggregateAllSamplesRatherThanTheLastInstant() throws {
    let run = UUID(), start = Date(timeIntervalSince1970: 100)
    var accumulator = WatchMotionAccumulator(recordingID: run)
    for index in 0..<10 {
        let early = accumulator.append(accelerationG: index % 2 == 0 ? 1 : 3,
                                       rotationRadiansPerSecond: Double(index), at: start.addingTimeInterval(Double(index) / 10))
        #expect(early == nil)
    }
    let completed = accumulator.append(accelerationG: 2, rotationRadiansPerSecond: 20, at: start.addingTimeInterval(1))
    let window = try #require(completed)
    #expect(window.recordingID == run && window.start == start && window.end == start.addingTimeInterval(0.9))
    #expect(window.sampleCount == 10)
    #expect(abs(window.rmsAccelerationG - sqrt(5)) < 1e-10)
    #expect(window.peakAccelerationG == 3)
    #expect(window.meanRotationRadiansPerSecond == 4.5 && window.peakRotationRadiansPerSecond == 9)
    let tail = accumulator.flush()
    let last = try #require(tail)
    #expect(last.sampleCount == 1 && last.start == start.addingTimeInterval(1) && last.end == last.start)
    #expect(last.rmsAccelerationG == 2 && last.peakRotationRadiansPerSecond == 20)
    let empty = accumulator.flush()
    #expect(empty == nil)
}

@Test func wristWindowsDoNotJoinPausesGapsInvalidReadingsOrDuplicateTimes() throws {
    let start = Date(timeIntervalSince1970: 100)
    var accumulator = WatchMotionAccumulator(recordingID: UUID())
    _ = accumulator.append(accelerationG: 1, rotationRadiansPerSecond: 2, at: start)
    _ = accumulator.append(accelerationG: 99, rotationRadiansPerSecond: 99, at: start)
    _ = accumulator.append(accelerationG: 99, rotationRadiansPerSecond: 99, at: start.addingTimeInterval(-1))
    let gap = accumulator.append(accelerationG: 3, rotationRadiansPerSecond: 4, at: start.addingTimeInterval(2))
    let beforeGap = try #require(gap)
    #expect(beforeGap.sampleCount == 1 && beforeGap.rmsAccelerationG == 1)
    let invalid = accumulator.append(accelerationG: .nan, rotationRadiansPerSecond: 1, at: start.addingTimeInterval(2.1))
    let beforeInvalid = try #require(invalid)
    #expect(beforeInvalid.sampleCount == 1 && beforeInvalid.rmsAccelerationG == 3)
    let emptyBefore = accumulator.flush()
    #expect(emptyBefore == nil)
    for invalid in [-1, Double.infinity, Double.nan] {
        let ignored = accumulator.append(accelerationG: 1, rotationRadiansPerSecond: invalid, at: start.addingTimeInterval(3))
        #expect(ignored == nil)
    }
    let emptyAfter = accumulator.flush()
    #expect(emptyAfter == nil)
}
