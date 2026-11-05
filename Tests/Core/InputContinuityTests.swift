import Foundation
import Testing
@testable import SpottrCore

@Test func switchingCameraToManualAndBackKeepsRepsElapsedAndSets() {
    var session = TrainingSession()
    session.start(at: 0)
    session.switchInput(source: .manual, at: 5)
    session.setManualReps(7)
    let oldGeneration = session.generation
    session.switchInput(source: .camera, at: 10)
    #expect(session.actualReps == 7)
    #expect(session.elapsed(at: 15) == 15)
    #expect(session.generation != oldGeneration)
    session.pause(at: 15)
    session.switchInput(source: .manual, at: 20)
    #expect(session.phase == .paused)
    #expect(session.actualReps == 7)
    #expect(session.elapsed(at: 25) == 15)
    session.resume(at: 25)
    session.endSet(at: 30)
    #expect(session.sets.first?.reps == 7)
    #expect(session.sets.first?.activeSeconds == 20)
    #expect(session.sets.first?.source == .manual)
    #expect(session.sets.first?.repDurations == nil)
}

@Test func configurableInputSwitchKeepsLiveAndCompletedWork() throws {
    let plan = try CoachSavedPlan.catalogue(exerciseID: "halfSquat", sets: 2, target: 8, restSeconds: 30, availableSupport: [])
    var run = try ConfigurableSession(plan: plan, availableSupport: [])
    run.start(at: 0); run.beginSet(at: 1); run.setReps(5)
    let cameraChanged = run.switchInput(source: .camera, at: 9)
    #expect(cameraChanged)
    #expect(run.hasStarted)
    #expect(run.actualReps == 5)
    #expect(run.elapsed(at: 11) == 10)
    let manualChanged = run.switchInput(source: .manual, at: 12)
    #expect(manualChanged)
    #expect(run.actualReps == 5)
    let ended = run.endSet(at: 13)
    #expect(ended)
    run.nextSet(at: 20)
    #expect(run.completed.first?.reps == 5)
    #expect(run.completed.first?.source == .manual)
    #expect(run.completed.first?.repDurations == nil)
    #expect(run.index == 1)
}

@Test func inputChangesRejectNonFiniteTimeAndUnsupportedCamera() throws {
    let plan = try CoachSavedPlan.catalogue(exerciseID: "plank", sets: 1, target: 20, restSeconds: 30, availableSupport: [])
    var run = try ConfigurableSession(plan: plan, availableSupport: [])
    run.start(at: 0)
    let invalidCamera = run.switchInput(source: .camera, at: 1)
    #expect(!invalidCamera)
    let invalidTime = run.switchInput(source: .manual, at: .nan)
    #expect(!invalidTime)
}

@Test func videoReplayCountsCannotBeTransferredToRealWorkoutInput() {
    var session = TrainingSession()
    session.start(at: 0); session.restartSet(source: .video, at: 0)
    for (t,a) in [(0.0,170.0),(0.2,170),(0.6,90),(0.8,90),(1.2,170),(1.4,170)] {
        session.consume(.init(time: t, angle: a), generation: session.generation)
    }
    #expect(session.actualReps == 1)
    session.switchInput(source: .manual, at: 2)
    #expect(session.source == .video)
    session.switchInput(source: .camera, at: 3)
    #expect(session.source == .video)
}
