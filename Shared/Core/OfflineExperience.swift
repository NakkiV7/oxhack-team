import Foundation

public struct LocalSkillStep: Identifiable, Sendable {
    public enum State: Sendable { case startingSkill, earned, current, locked }
    public let id: String
    public let state: State
}

public enum LocalSkillPath {
    public static func chain(family: ExerciseFamily) -> [String] {
        switch family {
        case .push: return ["wallPushup", "inclinePushup", "kneePushup", "pushup", "closeGripPushup"]
        case .legs: return ["supportedSquat", "halfSquat", "squat", "wideSquat", "reverseLunge", "splitSquat", "assistedSquat"]
        case .core: return ["deadBug", "plank", "sidePlank"]
        case .conditioning: return ["stepJack", "highKnees", "mountainClimber"]
        case .mobility: return ["catCow", "hipFlexorStretch"]
        case .balance: return ["singleLegBalance"]
        }
    }
    public static func make(family: ExerciseFamily, profile: LocalProfile?, history: [SessionRecord]) -> [LocalSkillStep] {
        let chain = chain(family: family)
        let startingIndex = chain.indices.filter { profile?.comfortableExercises.contains(chain[$0]) == true }.max() ?? -1
        let progress = SkillProgress.evaluate(history: history)
        func earned(_ id: String) -> Bool {
            guard let node = progress.node(exerciseID: id) else { return false }
            return node.qualifyingSets >= 3 && node.trainingDays >= 2
        }
        let firstPending = chain.indices.first { $0 > startingIndex && !earned(chain[$0]) } ?? chain.count
        return chain.enumerated().compactMap { index, id in
            guard index <= firstPending + 2 else { return nil }
            let state: LocalSkillStep.State = index < firstPending && earned(id) ? .earned :
                index <= startingIndex ? .startingSkill : index == firstPending ? .current : .locked
            return .init(id: id, state: state)
        }
    }
}

public struct QuantitativeInsights: Sendable {
    public let sessions: Int
    public let sets: Int
    public let reps: Int
    public let cameraReps: Int
    public let activeSeconds: Double
    public let trainingDays: Int
    public let averageRepSeconds: Double?
    public let lines: [String]

    public init(history: [SessionRecord], calendar: Calendar = .current) {
        var sessionIDs = Set<UUID>(), setIDs = Set<UUID>()
        let records = history.filter { $0.date.timeIntervalSince1970.isFinite && sessionIDs.insert($0.id).inserted }
        let reports = records.map { ($0.date, WorkoutReport(record: $0).sets.filter {
            $0.source != .video && ($0.reps > 0 || $0.holdSeconds > 0) && setIDs.insert($0.id).inserted
        }) }.filter { !$0.1.isEmpty }
        let work = reports.flatMap { $0.1 }
        sessions = reports.count; sets = work.count
        reps = work.reduce(0) { $0 + max(0, $1.reps) }
        cameraReps = work.filter { $0.source == .camera }.reduce(0) { $0 + max(0, $1.reps) }
        activeSeconds = work.reduce(0) { $0 + ($1.activeSeconds.isFinite ? max(0, $1.activeSeconds) : 0) }
        trainingDays = Set(reports.map { calendar.startOfDay(for: $0.0) }).count
        let durations = work.filter { $0.source == .camera }.flatMap(\.repDurations).filter { $0.isFinite && (0.2...15).contains($0) }
        averageRepSeconds = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        if work.isEmpty {
            lines = ["Your first finished set starts your insights.", "Only recorded work appears here. Planned sessions and video replays are left out."]
        } else {
            var result = ["You recorded \(sets) sets across \(trainingDays) training \(trainingDays == 1 ? "day" : "days").", "The camera counted \(cameraReps) of your \(reps) recorded reps."]
            if let averageRepSeconds { result.append(String(format: "Your mean observed rep time was %.1f seconds across %d timed reps.", averageRepSeconds, durations.count)) }
            if work.contains(where: { $0.reason == .discomfort }) { result.append("You reported discomfort. Choose a comfortable alternative and seek advice if it persists.") }
            lines = result
        }
    }
}

public struct SpokenRepCounter: Sendable {
    public private(set) var count: Int
    public init(initialCount: Int = 0) { count = max(0, initialCount) }
    public mutating func consume(_ transcript: String) -> Int? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["twenty":20, "thirty":30, "forty":40, "fifty":50, "sixty":60, "seventy":70, "eighty":80, "ninety":90]
        var values: [Int] = [], index = 0
        while index < words.count {
            let word = words[index]
            index += 1
            guard var value = Int(word) ?? units.firstIndex(of: word) ?? tens[word] else { continue }
            if value >= 20, value < 100, value % 10 == 0, index < words.count,
               let ones = units.firstIndex(of: words[index]), (1...9).contains(ones) {
                value += ones; index += 1
            }
            values.append(value)
        }
        let before = count
        for value in values {
            if value <= count { continue }
            guard value == count + 1, value <= 200 else { break }
            count = value
        }
        return count > before ? count : nil
    }
}

public enum TrainerTone: String, Codable, CaseIterable, Sendable {
    case gentle, encouraging, direct
    public var title: String { rawValue.capitalized }
}

public struct TrainerCueLibrary: Sendable {
    private var indices: [String: Int] = [:]
    public init() {}
    public static func lines(reason: CoachingReason, tone: TrainerTone) -> [String] {
        switch reason {
        case .discomfort: return ["Stop here. Take a comfortable rest. If pain continues, seek advice."]
        case .tracking: return ["I lost sight of the movement. Your progress is saved. Move back into view when you are ready.", "Your progress is safe. Give the camera a clear view of the movement so we can continue."]
        case .alignment: return ["Check your starting position. Keep the movement comfortable and controlled.", "Reset your position, then continue with control."]
        case .targetReached: return ["You reached your target. Finish when you are ready.", "Target reached. You can end this set and recover."]
        case .restReminder: return ["Take your time to recover before the next set.", "Relax your shoulders and breathe comfortably.", "Let your breathing settle. The next set can wait."]
        case .workoutCompleted: return ["You made time to move today. Well done.", "Session complete. Every bit of practice adds up.", "Your work is saved. See you next time."]
        case .slowerRep: return ["Your last rep took longer. Take a break whenever you need.", "Keep the movement comfortable. There is no need to rush.", "A steadier pace is fine. Finish the set if you need a rest."]
        default:
            switch tone {
            case .gentle: return ["One comfortable rep at a time.", "You are doing well. Keep breathing.", "Find the pace that feels right for you.", "A small step is still progress.", "Take all the time you need.", "Stay relaxed as you move.", "You can rest whenever you need.", "Nice and easy. Keep that control."]
            case .encouraging: return ["That is good control. Keep it going.", "You are building a steady rhythm.", "Each rep is another bit of practice.", "You showed up. Keep moving at your pace.", "Good effort. Stay with that smooth movement.", "You have found your rhythm.", "Keep breathing. You are doing well.", "That is another step forward."]
            case .direct: return ["Stay focused. Keep your reps controlled.", "Keep the same smooth pace.", "Control the lowering and the return.", "Breathe out as you press or rise.", "Make the next rep a controlled one.", "Stay steady. Finish with good control.", "Keep your position strong and comfortable.", "Focus on the movement in front of you."]
            }
        }
    }
    public mutating func next(reason: CoachingReason, tone: TrainerTone, exercise: Exercise? = nil) -> String {
        let key = reason.rawValue + tone.rawValue
        let original = Self.lines(reason: reason, tone: tone)
        let needsGeneric = exercise.map { !$0.isSquat && !$0.isPushup } ?? false
        let lines = needsGeneric && reason == .steadyRhythm ? original.filter { text in
            !["rep", "lowering", "press"].contains { text.lowercased().contains($0) }
        } : original
        let index = indices[key, default: 0] % lines.count
        indices[key] = index + 1
        return lines[index]
    }
}

public struct PoseProcessingClock: Sendable {
    private var lastInput: Double?
    private var lastTimestamp: Int?
    public init() {}
    public mutating func milliseconds(for time: Double) -> Int? {
        guard time.isFinite, (0...1_000_000_000_000).contains(time) else { return nil }
        let timestamp: Int
        if let lastInput, let lastTimestamp {
            let delta = time >= lastInput ? max(1, Int(((time - lastInput) * 1000).rounded())) : 1
            let addition = lastTimestamp.addingReportingOverflow(delta)
            guard !addition.overflow else { return nil }
            timestamp = addition.partialValue
        } else { timestamp = Int((time * 1000).rounded()) }
        lastInput = time; lastTimestamp = timestamp
        return timestamp
    }
}
