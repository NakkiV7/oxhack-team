import Foundation
import Testing
@testable import SpottrCore

@Test func manualWorkoutPreservesUnitsAndSource() throws {
    let record = try LoggedWorkout.make(exerciseID: "kneePushup", count: 8, sets: 3, date: Date(timeIntervalSince1970: 1000))
    #expect(record.reps == 24)
    #expect(record.setCount == 3)
    #expect(record.loggedSets.allSatisfy { $0.source == .manual && $0.exerciseID == "kneePushup" })
    let plank = try LoggedWorkout.make(exerciseID: "plank", count: 30, sets: 1)
    #expect(plank.reps == 0)
    #expect(plank.loggedSets.first?.seconds == 30)
    #expect(throws: LoggedWorkout.Invalid.self) { try LoggedWorkout.make(exerciseID: "unknown", count: 8, sets: 1) }
    #expect(throws: LoggedWorkout.Invalid.self) { try LoggedWorkout.make(exerciseID: "kneePushup", count: 0, sets: 1) }
}

@Test func historyRetainsEarnedProgressBeyondOneHundredSessionsAndReplacesRepeatedSaves() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 2, date: date)
    let second = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 1, date: date.addingTimeInterval(86400))
    try store.save(first)
    try store.save(second)
    let earned = SkillProgress.evaluate(history: try store.load(), calendar: calendar)
    #expect(earned.points(for: .strength) == 30)
    #expect(earned.node(exerciseID: "wallPushup")?.isComplete == true)

    for day in 2...100 {
        let practice = try LoggedWorkout.make(exerciseID: "catCow", count: 1, sets: 1,
                                              date: date.addingTimeInterval(Double(day) * 86400))
        try store.save(practice)
    }
    let reopened = HistoryStore(url: store.url)
    let history = try reopened.load()
    #expect(history.count == 101)
    #expect(history.contains { $0.id == first.id })
    let retained = SkillProgress.evaluate(history: history, calendar: calendar)
    #expect(retained.points(for: .strength) == 30)
    #expect(retained.node(exerciseID: "wallPushup")?.isComplete == true)
    #expect(retained.node(exerciseID: "inclinePushup")?.isAvailable == true)

    let replacementSets = try LoggedWorkout.make(exerciseID: "wallPushup", count: 8, sets: 3, date: date).loggedSets
    let replacement = SessionRecord(id: first.id, date: first.date, sets: [], loggedSets: replacementSets)
    try reopened.save(replacement)
    try reopened.save(replacement)
    let replaced = try reopened.load()
    #expect(replaced.count == 101)
    #expect(replaced.filter { $0.id == first.id }.count == 1)
    #expect(replaced.first { $0.id == first.id }?.loggedSets == replacementSets)
    let updated = SkillProgress.evaluate(history: replaced, calendar: calendar)
    #expect(updated.points(for: .strength) == 40)
    #expect(updated.node(exerciseID: "wallPushup")?.isComplete == true)
}
