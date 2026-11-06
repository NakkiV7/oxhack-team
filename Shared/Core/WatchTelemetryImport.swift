import Foundation

public enum WatchTelemetryImportError: Error { case lifetime, foreignSession, bounds, empty, capacity, identity }
public enum WatchTelemetryImporter {
    public static func merge(_ samples:[WatchTelemetry],into record:SessionRecord,through now:Date,allowsOpenSession:Bool=false) throws -> SessionRecord {
        guard record.date.timeIntervalSince1970.isFinite,now.timeIntervalSince1970.isFinite,
              let end=record.endedAt ?? (allowsOpenSession ? now:nil),end.timeIntervalSince1970.isFinite,
              (0...86_400).contains(end.timeIntervalSince(record.date)) else { throw WatchTelemetryImportError.lifetime }
        guard !samples.isEmpty,samples.count <= 60 else { throw WatchTelemetryImportError.bounds }
        var values=Dictionary(record.telemetry.map { ($0.sentAt,$0) },uniquingKeysWith: { _,last in last })
        var accepted = 0
        for packet in samples {
            guard packet.sessionID==record.id else { throw WatchTelemetryImportError.foreignSession }
            guard packet.sentAt.timeIntervalSince1970.isFinite,packet.sentAt >= record.date.addingTimeInterval(-2),packet.sentAt <= end.addingTimeInterval(2),packet.sentAt <= now.addingTimeInterval(2) else { continue }
            func clean(_ reading:SensorReading?,range:ClosedRange<Double>) -> SensorReading? {
                guard let reading,reading.value.isFinite,range.contains(reading.value),reading.date.timeIntervalSince1970.isFinite,
                      reading.date >= record.date.addingTimeInterval(-2),reading.date <= end.addingTimeInterval(2),(-2...12).contains(packet.sentAt.timeIntervalSince(reading.date)) else { return nil }
                return reading
            }
            let heart=clean(packet.heartRate,range:1...300),acceleration=clean(packet.accelerationG,range:0...64),rotation=clean(packet.rotationRadiansPerSecond,range:0...1000)
            let energy=packet.activeEnergy.flatMap { energy -> ActiveEnergy? in
                energy.isValid(at:packet.sentAt) && energy.kilocalories <= 100_000 && energy.asOf >= record.date.addingTimeInterval(-2) && energy.asOf <= end.addingTimeInterval(2) ? energy:nil
            }
            let window=packet.motionWindow.flatMap { window -> WatchMotionWindow? in
                guard window.start.timeIntervalSince1970.isFinite,window.end.timeIntervalSince1970.isFinite,
                      window.start >= record.date.addingTimeInterval(-2),window.end <= end.addingTimeInterval(2),
                      (0...5).contains(window.end.timeIntervalSince(window.start)),(-2...12).contains(packet.sentAt.timeIntervalSince(window.end)),(1...1000).contains(window.sampleCount),
                      window.rmsAccelerationG.isFinite,(0...64).contains(window.rmsAccelerationG),window.peakAccelerationG.isFinite,(window.rmsAccelerationG...64).contains(window.peakAccelerationG),
                      window.meanRotationRadiansPerSecond.isFinite,(0...1000).contains(window.meanRotationRadiansPerSecond),window.peakRotationRadiansPerSecond.isFinite,(window.meanRotationRadiansPerSecond...1000).contains(window.peakRotationRadiansPerSecond),energy.map({ $0.recordingID==window.recordingID }) ?? true else { return nil }
                return window
            }
            guard heart != nil || acceleration != nil || rotation != nil || energy != nil || window != nil else { continue }
            accepted += 1
            let previous=values[packet.sentAt]
            func newest(_ old:SensorReading?,_ new:SensorReading?) -> SensorReading? {
                guard let new else { return old }
                guard let old else { return new }
                return old.date > new.date ? old:new
            }
            values[packet.sentAt]=WatchTelemetry(sessionID:record.id,sentAt:packet.sentAt,heartRate:newest(previous?.heartRate,heart),accelerationG:newest(previous?.accelerationG,acceleration),rotationRadiansPerSecond:newest(previous?.rotationRadiansPerSecond,rotation),activeEnergy:energy ?? previous?.activeEnergy,motionWindow:window ?? previous?.motionWindow)
        }
        guard accepted > 0 else { throw WatchTelemetryImportError.empty }
        let telemetry=Array(values.values.sorted { $0.sentAt < $1.sentAt }.suffix(7200))
        return SessionRecord(id:record.id,date:record.date,sets:record.sets,telemetry:telemetry,loggedSets:record.loggedSets,skippedSets:record.skippedSets,endedAt:record.endedAt,timeline:record.timeline,plannedWorkoutID:record.plannedWorkoutID)
    }
}

public struct WatchTelemetryInbox: Sendable {
    private struct Batch: Codable { let id:UUID; let samples:[WatchTelemetry] }
    public let url: URL
    public init(url:URL) { self.url=url }
    private func load() throws -> [Batch] {
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        return try JSONDecoder().decode([Batch].self,from:Data(contentsOf:url))
    }
    private func write(_ batches:[Batch]) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try ProtectedLocalStorage.write(JSONEncoder().encode(batches), to: url)
    }
    public func store(id:UUID,samples:[WatchTelemetry]) throws {
        guard !samples.isEmpty,samples.count <= 60,Set(samples.map(\.sessionID)).count==1 else { throw WatchTelemetryImportError.bounds }
        let batches=try load()
        if let previous=batches.first(where: { $0.id==id }) {
            guard previous.samples==samples else { throw WatchTelemetryImportError.identity }
            return
        }
        let next=batches+[Batch(id:id,samples:samples)]
        guard next.reduce(0,{ $0+$1.samples.count }) <= 7200 else { throw WatchTelemetryImportError.capacity }
        try write(next)
    }
    public func samples(for sessionID:UUID) throws -> [WatchTelemetry] {
        let samples=try load().flatMap(\.samples).filter { $0.sessionID==sessionID }
        return Dictionary(samples.map { ($0.sentAt,$0) },uniquingKeysWith: { _,last in last }).values.sorted { $0.sentAt < $1.sentAt }
    }
    public func remove(sessionID:UUID) throws { try write(try load().filter { $0.samples.first?.sessionID != sessionID }) }
    public func clear() throws { if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } }
}
