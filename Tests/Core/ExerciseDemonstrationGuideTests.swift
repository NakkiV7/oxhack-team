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
        "stepJack", "highKnees", "mountainClimber", "hipFlexorStretch", "singleLegBalance", "birdDog", "seatedKneeExtension", "forwardLunge", "lateralLunge", "supportedSplitSquat", "standingKneeRaise", "seatedMarch", "standingHipAbduction", "standingHipExtension", "kneeSidePlank", "tandemBalance", "frontArmRaise", "lateralArmRaise", "standingBicepsCurl"]
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

@Test func everyCameraGuideUsesItsActualProfileViewAndSpecificPhases() throws {
    for entry in ExerciseCatalog.all {
        let guide = try #require(ExerciseDemonstrationGuide.find(entry.id))
        if let exercise = entry.tracking { #expect(guide.cameraAngle.rawValue == exercise.cameraView.rawValue) }
        #expect(!guide.phases.contains("Show the full movement"), "Missing movement-specific guide: \(entry.id)")
    }
}

@Test func sidePlankGuidesExplainForearmAndStraightArmAlternatives() throws {
    for id in ["sidePlank","kneeSidePlank"] {
        let phases=try #require(ExerciseDemonstrationGuide.find(id)).phases.joined(separator:" ")
        #expect(phases.contains("forearm"))
        #expect(phases.contains("straight arm"))
    }
}
