import Foundation

public enum WorkoutCategory: String, CaseIterable, Sendable {
    case upperBody = "Upper body", lowerBody = "Lower body", core = "Core"
    case conditioning = "Conditioning", mobility = "Mobility", balance = "Balance"
    case fullBody = "Full body", other = "Other", empty = "No exercises"

    public init(family: ExerciseFamily) {
        switch family {
        case .push: self = .upperBody
        case .legs: self = .lowerBody
        case .core: self = .core
        case .conditioning: self = .conditioning
        case .mobility: self = .mobility
        case .balance: self = .balance
        }
    }
}

public struct ReportSet: Identifiable, Sendable {
    public let id: UUID
    public let exerciseID: String
    public let exerciseName: String
    public let category: WorkoutCategory
    public let reps: Int
    public let holdSeconds: Double
    public let activeSeconds: Double
    public let source: InputSource
    public let reserve: Int?
    public let reason: StopReason
    public let repDurations: [Double]
    public let restSecondsBefore: Double?
    public let quantityOrigin: LoggedSet.QuantityOrigin?
    public var sourceLabel: String {
        if quantityOrigin == .activeTimer { return "Manual hold timer" }
        switch source {
        case .manual: return "Manual self-report"
        case .camera: return "Camera"
        case .video: return "Video"
        }
    }
    public var averageRepSeconds: Double? { repDurations.isEmpty ? nil : repDurations.reduce(0, +) / Double(repDurations.count) }
    public var quantityText: String { holdSeconds > 0 ? "\(Int(holdSeconds)) sec" : "\(reps) reps" }
}

public struct WorkoutReport: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let sets: [ReportSet]
    public let heartRate: ReportSignal
    public let acceleration: ReportSignal
    public let rotation: ReportSignal
    public var timedRepCount: Int { sets.reduce(0) { $0 + $1.repDurations.count } }
    public var averageRepSeconds: Double? {
        guard timedRepCount > 0 else { return nil }
        return sets.flatMap(\.repDurations).reduce(0, +) / Double(timedRepCount)
    }
    public var setCount: Int { sets.count }
    public var reps: Int { sets.reduce(0) { $0 + $1.reps } }
    public var holdSeconds: Double { sets.reduce(0) { $0 + $1.holdSeconds } }
    public var activeSeconds: Double { sets.reduce(0) { $0 + $1.activeSeconds } }
    public var recordedRestSeconds: Double? {
        let rests = sets.compactMap(\.restSecondsBefore)
        return rests.isEmpty ? nil : rests.reduce(0, +)
    }
    public var category: WorkoutCategory {
        let categories = Set(sets.map(\.category))
        return categories.count > 1 ? .fullBody : categories.first ?? .empty
    }

    public init(record: SessionRecord) {
        id = record.id; date = record.date
        heartRate = ReportSignal(record: record, keyPath: \.heartRate, validRange: 1...300)
        acceleration = ReportSignal(record: record, keyPath: \.accelerationG, validRange: 0...Double.greatestFiniteMagnitude)
        rotation = ReportSignal(record: record, keyPath: \.rotationRadiansPerSecond, validRange: 0...Double.greatestFiniteMagnitude)
        let projectedSets = record.sets.map { set in
            let entry = ExerciseCatalog.find(set.exercise.rawValue)
            return ReportSet(id: set.id, exerciseID: set.exercise.rawValue,
                exerciseName: entry?.name ?? set.exercise.title,
                category: entry.map { WorkoutCategory(family: $0.family) } ?? .other,
                reps: set.reps, holdSeconds: 0, activeSeconds: set.activeSeconds,
                source: set.source, reserve: set.reserve, reason: set.reason,
                repDurations: Self.recordedRepDurations(for: set),
                restSecondsBefore: set.restSecondsBefore.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }, quantityOrigin: nil)
        } + record.loggedSets.map { set in
            let entry = ExerciseCatalog.find(set.exerciseID)
            return ReportSet(id: set.id, exerciseID: set.exerciseID,
                exerciseName: entry?.name ?? "Unknown exercise",
                category: entry.map { WorkoutCategory(family: $0.family) } ?? .other,
                reps: set.reps, holdSeconds: set.seconds, activeSeconds: set.activeSeconds ?? set.seconds,
                source: set.source, reserve: set.reserve, reason: set.reason, repDurations: Self.recordedRepDurations(for: set),
                restSecondsBefore: set.restSecondsBefore.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }, quantityOrigin: set.quantityOrigin)
        }
        sets = projectedSets.reduce(into: [ReportSet]()) { unique, set in
            if !unique.contains(where: { $0.id == set.id }) { unique.append(set) }
        }
    }

    private static func recordedRepDurations(for set: SetRecord) -> [Double] {
        guard let durations = set.repDurations, set.reps > 0, durations.count == set.reps,
              durations.allSatisfy({ $0.isFinite && (0.6...15).contains($0) }) else { return [] }
        return durations
    }
    private static func recordedRepDurations(for set: LoggedSet) -> [Double] {
        guard set.source == .camera, Exercise(rawValue: set.exerciseID) != nil,
              set.seconds == 0, set.quantityOrigin == nil,
              let durations = set.repDurations, set.reps > 0, durations.count == set.reps,
              durations.allSatisfy({ $0.isFinite && (0.6...15).contains($0) }) else { return [] }
        return durations
    }
}

public struct ReportDay: Identifiable, Sendable {
    public let date: Date
    public let setCount: Int
    public var id: Date { date }
}

public struct CategoryReport: Identifiable, Sendable {
    public let category: WorkoutCategory
    public let setCount: Int
    public let reps: Int
    public let holdSeconds: Double
    public var id: String { category.rawValue }
}

public struct WeekReport: Sendable {
    public let interval: DateInterval
    public let sessions: [WorkoutReport]
    public let days: [ReportDay]
    public let categories: [CategoryReport]
    public var setCount: Int { sessions.reduce(0) { $0 + $1.setCount } }
    public var reps: Int { sessions.reduce(0) { $0 + $1.reps } }
    public var holdSeconds: Double { sessions.reduce(0) { $0 + $1.holdSeconds } }
    public var activeSeconds: Double { sessions.reduce(0) { $0 + $1.activeSeconds } }

    public init(history: [SessionRecord], containing date: Date = Date(), calendar: Calendar = .current) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86400)
        self.interval = interval
        let unique = history.reduce(into: [UUID: SessionRecord]()) { records, record in
            if records[record.id] == nil { records[record.id] = record }
        }
        let sessions = unique.values.filter { $0.date >= interval.start && $0.date < interval.end }
            .map(WorkoutReport.init).sorted { $0.date > $1.date }
        self.sessions = sessions
        days = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let count = sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.setCount }
            return ReportDay(date: day, setCount: count)
        }
        let sets = sessions.flatMap(\.sets)
        categories = WorkoutCategory.allCases.compactMap { category in
            let matching = sets.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }
            return CategoryReport(category: category, setCount: matching.count,
                reps: matching.reduce(0) { $0 + $1.reps }, holdSeconds: matching.reduce(0) { $0 + $1.holdSeconds })
        }
    }
}

public struct ReportSample: Identifiable, Sendable {
    public let date: Date
    public let value: Double
    public let segment: Int
    public var id: Date { date }
}

public struct ReportSignal: Sendable {
    public let samples: [ReportSample]
    public var average: Double? { samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.value } / Double(samples.count) }
    public var minimum: Double? { samples.map(\.value).min() }
    public var maximum: Double? { samples.map(\.value).max() }

    init(record: SessionRecord, keyPath: KeyPath<WatchTelemetry, SensorReading?>, validRange: ClosedRange<Double>) {
        let readings = record.telemetry.filter { $0.sessionID == record.id }.compactMap { message -> SensorReading? in
            guard let reading = message[keyPath: keyPath], reading.value.isFinite,
                  reading.date.timeIntervalSince1970.isFinite, message.sentAt.timeIntervalSince1970.isFinite,
                  validRange.contains(reading.value) else { return nil }
            let age = message.sentAt.timeIntervalSince(reading.date)
            return (-2...12).contains(age) ? reading : nil
        }
        let unique = readings.reduce(into: [Date: SensorReading]()) { values, reading in
            if values[reading.date] == nil { values[reading.date] = reading }
        }.values.sorted { $0.date < $1.date }
        samples = unique.reduce(into: [ReportSample]()) { points, reading in
            let previous = points.last
            let gap = previous.map { reading.date.timeIntervalSince($0.date) > 12 } ?? false
            let segment = (previous?.segment ?? 0) + (gap ? 1 : 0)
            points.append(ReportSample(date: reading.date, value: reading.value, segment: segment))
        }
    }
}
