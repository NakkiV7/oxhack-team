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
    // Added later; optional so an older Mac page still decodes.
    var clockMs: Double?   // workout time (frozen while paused or stopped)
    var avgSecs: Double?   // average seconds per counted rep
    var pace: String?      // "slowing" | "faster" | "steady" (needs 6 timed reps)
    var active: Bool?      // a workout is running or paused (so Pause / Stop make sense)
    var paused: Bool?
    var canPause: Bool?    // only an uploaded video can be paused, not the live camera
    var summary: WorkoutSummary? // non-nil while the Mac shows the end-of-workout summary
    var rule: RuleInfo?    // which rule judges the workout (default, or the personal one learned from past data)
    var sync: SyncInfo?    // cloud save status of the last finished workout (nil until a workout ends)

    var lineOK: Bool { (line ?? 0) >= minLine }
}

/// The rule judging form: "default" (fixed thresholds) or "personal" (learned from the user's past data). See ruleInfo() in pushup/index.html.
struct RuleInfo: Decodable, Equatable {
    var mode: String // "default" | "personal"
    var text: String
    var isPersonal: Bool { mode == "personal" }
}

/// Cloud save of the finished workout to Tiger Data. See setSync() in pushup/index.html.
struct SyncInfo: Decodable, Equatable {
    var status: String // "saving" | "saved" | "failed" | "info"
    var text: String
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
    var secs: Double?  // seconds from starting to lower until back up
    var pace: String?  // "slow" | "fast" vs the average of earlier reps (nil = about average or too early to tell)
}

/// End-of-workout numbers, computed on the Mac (see summaryStats() in pushup/index.html).
struct WorkoutSummary: Decodable, Equatable {
    var timeMs: Double
    var reps: Int
    var good: Int
    var avg: Double?
    var fastest: Double?
    var slowest: Double?
    var notCounted: Int
    var label: String
    var topIssue: String?
    var topIssueCount: Int
    var rule: String? // "default" | "personal": the rule the workout was judged by
}

/// "05:07", or "1:05:07" past an hour. Same format as the Mac page.
func formatClock(_ ms: Double) -> String {
    let s = Int((ms / 1000).rounded()), h = s / 3600
    let mmss = String(format: "%02d:%02d", (s / 60) % 60, s % 60)
    return h > 0 ? "\(h):\(mmss)" : mmss
}

func formatSeconds(_ v: Double?) -> String { v.map { String(format: "%.1f s", $0) } ?? "–" }

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
    var id: Int? // set when the Mac logged the question (so it arrives through the shared chat instead)
}

/// One question and the coach's answer. Lives on the Mac server, so it shows on every device (see `event: qa`).
struct QA: Decodable, Identifiable, Equatable {
    let id: Int
    let time: Double // ms since 1970
    let question: String
    var answer: String?
    var sources: [Source] = []
    var failed = false // `answer` then holds the error text
    var date: Date { Date(timeIntervalSince1970: time / 1000) }
    var pending: Bool { answer == nil }
}

let maxQuestionLength = 256
