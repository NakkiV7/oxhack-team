import XCTest
@testable import SpottrCore

final class CoachWeekPlanTests: XCTestCase {
    private let context = CoachValidationContext(generationID: "week-1", suppliedFactIDs: ["context"], availableSupport: [])
    private var request: CoachWeekRequest { get throws { try CoachWeekRequest(startDate: "2026-10-25", timeZone: "Europe/London", availableDays: [0, 2, 4], targetDays: 3) } }
    private var guidance: CoachGuidanceRegistry { get throws { try CoachGuidanceRegistry(data: Data(#"{"version":1,"sources":[{"id":"nhs-strength","title":"Strength","url":"https://www.nhs.uk/live-well/exercise/how-to-improve-strength-flexibility/","summary":"Build up gradually.","audience":"General guidance, not personal readiness."}]}"#.utf8)) } }
    private func fixture() -> [String: Any] {
        let grounded: [String: Any] = ["text": "A suggestion, not measured readiness.", "factIDs": ["context"]]
        let workout: [String: Any] = ["generationID": "week-1", "items": [["exerciseID": "squat", "sets": 2, "target": 8, "unit": "reps", "restSeconds": 60, "factIDs": ["context"]]], "rationale": grounded]
        return ["generationID": "week-1", "status": "proposed", "weekStart": "2026-10-25", "timeZone": "Europe/London", "days": (25...31).map { day in ["date": "2026-10-\(day)", "kind": day == 25 ? "workout" : "rest", "workout": day == 25 ? workout : NSNull()] as [String: Any] }, "rationale": grounded, "guidanceIDs": ["nhs-strength"]]
    }
    private func parse(_ value: [String: Any]) throws -> CoachWeekProposal {
        try CoachWeekContracts.parse(JSONSerialization.data(withJSONObject: value), request: request, context: context, guidance: guidance)
    }
    func testSevenLocalDatesAcrossClockChangeAndExplicitSelectionBeforeApproval() throws {
        let proposal = try parse(fixture())
        XCTAssertEqual(try request.dates(), (25...31).map { "2026-10-\($0)" })
        XCTAssertEqual(proposal.days.count, 7)
        XCTAssertThrowsError(try CoachSavedWeek(proposal: proposal, selectedDates: [], movedDates: [:], context: context, request: request, guidance: guidance))
        let approved = try CoachSavedWeek(proposal: proposal, selectedDates: ["2026-10-25"], movedDates: ["2026-10-25": "2026-10-27"], context: context, request: request, guidance: guidance)
        XCTAssertEqual(approved.days.map(\.date), ["2026-10-27"])
        XCTAssertEqual(approved.days.first?.plan.items.first?.target, 8)
        XCTAssertEqual(approved.days.first?.plan.items.first?.sets, 2)
        let reopened = try CoachSavedWeek.decode(JSONEncoder().encode(approved))
        XCTAssertEqual(reopened.days.map(\.date), approved.days.map(\.date))
        XCTAssertEqual(reopened.version, 1)
    }
    func testInvalidWeekAndUnsupportedOrUngroundedWorkoutAreRejected() throws {
        for mutate in [
            { (p: inout [String: Any]) in p["guidanceIDs"] = ["invented"] },
            { p in p["timeZone"] = "UTC" },
            { p in p["extra"] = true },
            { p in p["generationID"] = "stale" },
            { p in var days = p["days"] as! [[String: Any]]; days[1]["date"] = "2026-10-25"; p["days"] = days },
            { p in var days = p["days"] as! [[String: Any]]; var plan = days[0]["workout"] as! [String: Any]; var items = plan["items"] as! [[String: Any]]; items[0]["target"] = 31; plan["items"] = items; days[0]["workout"] = plan; p["days"] = days },
            { p in var days = p["days"] as! [[String: Any]]; var plan = days[0]["workout"] as! [String: Any]; var items = plan["items"] as! [[String: Any]]; items[0]["factIDs"] = ["invented"]; plan["items"] = items; days[0]["workout"] = plan; p["days"] = days }
        ] {
            var value = fixture(); mutate(&value); XCTAssertThrowsError(try parse(value))
        }
        XCTAssertThrowsError(try CoachWeekRequest(startDate: "2026-02-30", timeZone: "Europe/London", availableDays: [0], targetDays: 1))
        XCTAssertThrowsError(try CoachWeekRequest(startDate: "2026-10-25", timeZone: "Made/Up", availableDays: [0], targetDays: 1))
        XCTAssertThrowsError(try CoachWeekRequest(startDate: "2026-10-25", timeZone: "UTC", availableDays: [0, 0], targetDays: 1))
    }
    func testWeekCannotInventSourceURLsOrOmitUrgentGuidance() throws {
        var value = fixture()
        value["rationale"] = ["text": "See HTTPS://invented.example for NHS advice.", "factIDs": ["context"]]
        XCTAssertThrowsError(try parse(value))
        XCTAssertThrowsError(try parse(["generationID": "week-1", "status": "declined", "reason": "urgent", "guidanceIDs": ["nhs-strength"]]))
    }
    func testTypedDeclineCannotCarryAWorkoutOrUnknownGuidance() throws {
        let declined: [String: Any] = ["generationID": "week-1", "status": "declined", "reason": "medical", "guidanceIDs": ["nhs-strength"]]
        XCTAssertEqual(try parse(declined).reason, .medical)
        var missingReason = declined; missingReason["reason"] = NSNull()
        XCTAssertThrowsError(try parse(missingReason))
        var invalid = declined; invalid["days"] = []
        XCTAssertThrowsError(try parse(invalid))
    }
}
