import Foundation

// Mirrors the JSON the Mac page publishes (see publish() in pushup/index.html).
struct PushupState: Decodable, Equatable {
    var running: Bool
    var variation: String
    var label: String
    var count: Int
    var good: Int
    var total: Int
    var feedback: String
    var tone: String // "ok" | "warn" | "bad"
    var phase: String // "unknown" | "up" | "down"
    var elbow: Double?
    var line: Double?
    var up: Double
    var down: Double
    var minLine: Double
    var aspect: Double
    var pose: Pose?
    var reps: [Rep]

    var lineOK: Bool { (line ?? 0) >= minLine }
}

/// Normalized (0-1) image coordinates of the tracked side of the body.
struct Pose: Decodable, Equatable {
    var shoulder: [Double]?
    var elbow: [Double]?
    var wrist: [Double]?
    var hip: [Double]?
    var ref: [Double]? // ankle, or knee for knee push-ups
}

struct Rep: Decodable, Equatable {
    var n: Int
    var counted: Bool
    var good: Bool
    var minElbow: Int
    var minLine: Int
    var issue: String?
}

/// A pep talk or tip from the Gemini coach (generated on the Mac, see maybeCoach() in pushup/server.mjs).
struct CoachMessage: Decodable, Equatable, Identifiable {
    var id: Int
    var time: Double // ms since 1970
    var text: String
    var reps: Int // total reps when it was written

    var date: Date { Date(timeIntervalSince1970: time / 1000) }
}

/// An official source the answer is based on (links come from the Mac's fixed table, never from the model's text).
struct Source: Decodable, Equatable, Identifiable {
    var id: Int
    var title: String
    var url: String
}

struct AskResponse: Decodable {
    var answer: String?
    var sources: [Source]?
    var error: String?
}

/// One question the user typed and the coach's answer.
struct QA: Identifiable, Equatable {
    let id = UUID()
    let time = Date()
    let question: String
    var answer: String?
    var sources: [Source] = []
    var failed = false // `answer` then holds the error text
    var pending: Bool { answer == nil }
}

let maxQuestionLength = 256
