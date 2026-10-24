import Foundation
import Testing
@testable import SpottrCore

@Test func filmingChecklistCoversTheCatalogueExactlyWithFullCycleAndFramingDirections() {
    let guides = ExerciseDemonstrationGuide.all
    #expect(guides.count == ExerciseCatalog.all.count)
    #expect(Set(guides.map(\.exerciseID)) == Set(ExerciseCatalog.all.map(\.id)))
    #expect(Set(guides.map(\.id)).count == guides.count)
    for guide in guides {
        #expect(!guide.cameraAngle.instructions.isEmpty)
        #expect(!guide.framing.isEmpty)
        #expect(guide.phases.count >= 3)
        #expect(!guide.recordingInstructions.isEmpty)
        #expect(!guide.sideInstructions.isEmpty)
    }
}

@Test func filmingDirectionsIdentifyBothSidesAndUsefulViewsWithoutClaimingTrackingCoverage() throws {
    let bilateralTakes: Set<String> = ["reverseLunge", "splitSquat", "assistedSquat", "deadBug", "sidePlank",
        "stepJack", "highKnees", "mountainClimber", "hipFlexorStretch", "singleLegBalance"]
    let guides = ExerciseDemonstrationGuide.all
    #expect(Set(guides.filter(\.requiresBothSides).map(\.exerciseID)) == bilateralTakes)
    #expect(guides.filter(\.requiresBothSides).allSatisfy { $0.sideInstructions.contains("both") })
    #expect(try #require(ExerciseDemonstrationGuide.find("singleLegBalance")).cameraAngle == .front)
    #expect(try #require(ExerciseDemonstrationGuide.find("deadBug")).cameraAngle == .frontOblique)
    #expect(try #require(ExerciseDemonstrationGuide.find("pushup")).cameraAngle == .side)
    #expect(try #require(ExerciseDemonstrationGuide.find("squat")).cameraAngle == .side)
    #expect(try #require(ExerciseDemonstrationGuide.find("plank")).framing.contains("floor"))
    #expect(ExerciseDemonstrationGuide.find("unknown") == nil)
}

@Test func filmingTakesDistinguishFullRepetitionsFromHoldsAndShowTheRequiredSupport() throws {
    #expect(try #require(ExerciseDemonstrationGuide.find("squat")).takeInstructions.contains("3 complete"))
    #expect(try #require(ExerciseDemonstrationGuide.find("plank")).takeInstructions.contains("hold"))
    #expect(try #require(ExerciseDemonstrationGuide.find("highKnees")).takeInstructions.contains("alternating"))
    #expect(try #require(ExerciseDemonstrationGuide.find("wallPushup")).support == "Wall")
    #expect(try #require(ExerciseDemonstrationGuide.find("pushup")).support == nil)
}
