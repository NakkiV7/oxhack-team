import Foundation

public struct LoggedSet: Codable, Identifiable, Equatable, Sendable {
    public enum QuantityOrigin: String, Codable, Sendable { case selfReport, activeTimer }
    public let id: UUID
    public let exerciseID: String
    public let reps: Int
    public let seconds: Double
    public let source: InputSource
    public var reason: StopReason
    public var number: Int? = nil
    public var target: Int? = nil
    public var activeSeconds: Double? = nil
    public var restSecondsBefore: Double? = nil
    public var reserve: Int? = nil
    public var quantityOrigin: QuantityOrigin? = nil
    public var repDurations: [Double]? = nil
}
public enum LoggedWorkout {
    public enum Invalid: Error { case quantity }
    public static func make(exerciseID: String, count: Int, sets: Int, date: Date = Date(), reason: StopReason = .voluntary) throws -> SessionRecord {
        guard let entry = ExerciseCatalog.find(exerciseID), (1...10).contains(sets),
              (1...(entry.unit == .reps ? 200 : 600)).contains(count), date.timeIntervalSince1970.isFinite else { throw Invalid.quantity }
        let logs = (0..<sets).map { _ in
            LoggedSet(id: UUID(), exerciseID: exerciseID, reps: entry.unit == .reps ? count : 0,
                      seconds: entry.unit == .seconds ? Double(count) : 0, source: .manual, reason: reason)
        }
        return .init(id: UUID(), date: date, sets: [], loggedSets: logs)
    }
}
