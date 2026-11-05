import Foundation
import Testing
@testable import SpottrCore

private func pose(_ values: [(Int,Double,Double)], time: Double = 0, mirrored: Bool = false) -> PoseFrame {
    var points = Array(repeating: PosePoint(x:0,y:0,confidence:0), count:33)
    for (index,x,y) in values {
        let i = mirrored && index >= 11 ? (index % 2 == 1 ? index + 1 : index - 1) : index
        points[i] = .init(x:mirrored ? 1-x : x,y:y,confidence:1)
    }
    return .init(time:time,width:1000,height:1000,points:points)
}
private let standing: [(Int,Double,Double)] = [
    (11,0.4,0.2),(12,0.6,0.2),(13,0.4,0.35),(14,0.6,0.35),(15,0.4,0.48),(16,0.6,0.48),
    (23,0.43,0.5),(24,0.57,0.5),(25,0.43,0.7),(26,0.57,0.7),(27,0.43,0.9),(28,0.57,0.9),
    (29,0.41,0.92),(30,0.55,0.92),(31,0.46,0.92),(32,0.6,0.92)]
private func changed(_ base: [(Int,Double,Double)], _ updates: [(Int,Double,Double)]) -> [(Int,Double,Double)] {
    base.filter { old in !updates.contains { $0.0 == old.0 } } + updates
}

@Test(arguments: ["standingKneeRaise", "highKnees", "standingHipAbduction", "standingHipExtension", "frontArmRaise", "lateralArmRaise", "standingBicepsCurl", "wallSlide", "calfRaise"])
func standingProfilesMeasureTheirOwnExcursionAndRejectLyingOrMissingJoints(id: String) throws {
    let exercise = try #require(Exercise(rawValue:id))
    let updates: [(Int,Double,Double)]
    switch id {
    case "standingKneeRaise", "highKnees": updates = [(25,0.43,0.4),(27,0.43,0.65)]
    case "standingHipAbduction", "standingHipExtension": updates = [(25,0.255,0.7),(27,0.08,0.9)]
    case "frontArmRaise": updates = [(13,0.55,0.2),(15,0.7,0.2)]
    case "lateralArmRaise": updates = [(13,0.25,0.2),(15,0.1,0.2)]
    case "standingBicepsCurl": updates = [(15,0.28,0.27)]
    case "wallSlide": updates = [(13,0.38,0.05),(15,0.36,0.01),(14,0.62,0.05),(16,0.64,0.01)]
    default: updates = [(29,0.41,0.86),(30,0.55,0.86),(27,0.43,0.84),(28,0.57,0.84)]
    }
    let neutral = id == "wallSlide" ? changed(standing, [(13,0.25,0.2),(15,0.25,0.05),(14,0.75,0.2),(16,0.75,0.05)]) : standing
    for mirror in [false,true] {
        let start = try #require(PoseGeometry.measure(pose(neutral,mirrored:mirror),exercise:exercise))
        let end = try #require(PoseGeometry.measure(pose(changed(standing,updates),mirrored:mirror),exercise:exercise))
        #expect(start.angle >= 160)
        #expect(end.angle <= exercise.bottomAngle)
        if !exercise.isTimed {
            var counter=RepCounter(exercise:exercise)
            for (t,active) in [(0.0,false),(0.2,false),(0.6,true),(0.8,true),(1.2,false),(1.4,false)] {
                let frame=pose(active ? changed(standing,updates) : neutral,time:t,mirrored:mirror)
                _ = counter.consume(try #require(PoseGeometry.measure(frame,exercise:exercise)))
            }
            #expect(counter.reps == 1)
        }
        let lying = changed(standing, [(11,0.1,0.5),(12,0.2,0.5)])
        #expect(PoseGeometry.measure(pose(lying,mirrored:mirror),exercise:exercise) == nil)
        #expect(PoseGeometry.measure(pose([],mirrored:mirror),exercise:exercise) == nil)
    }
}

@Test func reliableWorldAnglesRemainCoupledToVisibleImageLandmarks() throws {
    let frame = pose(standing)
    var world = Array(repeating: PoseWorldPoint(x:0,y:0,z:0,confidence:0),count:33)
    world[23] = .init(x:0,y:0,z:0,confidence:1)
    world[25] = .init(x:0,y:0.4,z:0,confidence:1)
    world[27] = .init(x:0.4,y:0.4,z:0,confidence:1)
    let measured = try #require(PoseGeometry.measure(.init(time:0,width:1000,height:1000,points:frame.points,worldPoints:world),exercise:.squat))
    #expect(abs(measured.angle - 90) < 1e-8)
    #expect(measured.provenance == .jointAngle3D)
    var hidden = frame.points
    hidden[25] = .init(x:0.43,y:0.7,confidence:0)
    hidden[26] = .init(x:0.57,y:0.7,confidence:0)
    #expect(PoseGeometry.measure(.init(time:0,width:1000,height:1000,points:hidden,worldPoints:world),exercise:.squat) == nil)
    world[25] = .init(x:.nan,y:0.4,z:0,confidence:1)
    let fallback = try #require(PoseGeometry.measure(.init(time:0,width:1000,height:1000,points:frame.points,worldPoints:world),exercise:.squat))
    #expect(fallback.provenance == .jointAngle2D)
    #expect(fallback.angle > 170)
}

private func floorFixture(_ id: String, active: Bool) -> [(Int,Double,Double)] {
    let bird: [(Int,Double,Double)] = [(11,0.3,0.4),(12,0.32,0.43),(13,0.3,0.55),(14,0.32,0.56),
        (15,0.3,0.7),(16,0.32,0.7),(23,0.6,0.4),(24,0.62,0.43),(25,0.6,0.65),(26,0.62,0.68),
        (27,0.8,0.65),(28,0.82,0.68)]
    if id == "birdDog" { return active ? changed(bird,[(25,0.75,0.4),(27,0.9,0.4),(14,0.17,0.43),(16,0.02,0.43)]) : bird }
    if id == "deadBug" {
        let rest = changed(bird,[(11,0.3,0.65),(12,0.32,0.68),(23,0.6,0.65),(24,0.62,0.68),
            (13,0.3,0.5),(14,0.32,0.5),(15,0.3,0.3),(16,0.32,0.3),
            (25,0.6,0.4),(26,0.62,0.4),(27,0.8,0.4),(28,0.82,0.4)])
        return active ? changed(rest,[(25,0.75,0.65),(27,0.9,0.65),(14,0.17,0.68),(16,0.02,0.68)]) : rest
    }
    if id == "gluteBridge" {
        let rest = changed(bird,[(11,0.15,0.7),(12,0.17,0.72),(23,0.45,0.7),(24,0.47,0.72),
            (25,0.65,0.5),(26,0.67,0.52),(27,0.75,0.8),(28,0.77,0.82)])
        return active ? changed(rest,[(23,0.45,0.5),(24,0.47,0.52)]) : rest
    }
    let rest = changed(bird,[(25,0.75,0.4),(26,0.77,0.43),(27,0.9,0.4),(28,0.92,0.43)])
    return active ? changed(rest,[(25,0.4,0.55),(27,0.55,0.65)]) : rest
}

@Test(arguments: ["gluteBridge", "deadBug", "birdDog", "mountainClimber"])
func floorProfilesWitnessRangeReturnAndRejectUprightSubstitutes(id: String) throws {
    let exercise = try #require(Exercise(rawValue:id))
    for mirror in [false,true] {
        var counter = RepCounter(exercise:exercise)
        for (t,active) in [(0.0,false),(0.2,false),(0.6,true),(0.8,true),(1.2,false),(1.4,false)] {
            let sample = try #require(PoseGeometry.measure(pose(floorFixture(id,active:active),time:t,mirrored:mirror),exercise:exercise))
            #expect(active ? sample.angle <= exercise.bottomAngle : sample.angle >= 160)
            _ = counter.consume(sample)
        }
        #expect(counter.reps == 1)
        #expect(PoseGeometry.measure(pose(standing,mirrored:mirror),exercise:exercise) == nil)
    }
}

@Test(arguments: ["seatedKneeExtension", "seatedMarch"])
func seatedProfilesRequireSeatedThighAndAlternatingVisibleLegs(id: String) throws {
    let exercise = try #require(Exercise(rawValue:id))
    let rest = changed(standing,[(11,0.3,0.2),(12,0.34,0.2),(23,0.3,0.5),(24,0.34,0.5),
        (25,0.55,0.5),(26,0.59,0.5),(27,0.55,0.8),(28,0.59,0.8)])
    let active = changed(rest,id == "seatedMarch" ? [(25,0.5,0.35),(27,0.5,0.6)] : [(27,0.8,0.5)])
    for mirror in [false,true] {
        var counter = RepCounter(exercise:exercise)
        for (t,values) in [(0.0,rest),(0.2,rest),(0.6,active),(0.8,active),(1.2,rest),(1.4,rest)] {
            let sample = try #require(PoseGeometry.measure(pose(values,time:t,mirrored:mirror),exercise:exercise))
            _ = counter.consume(sample)
        }
        #expect(counter.reps == 1)
        #expect(PoseGeometry.measure(pose(standing,mirrored:mirror),exercise:exercise) == nil)
    }
}

@Test(arguments: ["reverseLunge", "forwardLunge", "lateralLunge", "splitSquat", "supportedSplitSquat", "assistedSquat", "stepJack"])
func steppedProfilesRejectIdleAndCountOnlyFullExcursions(id: String) throws {
    let exercise = try #require(Exercise(rawValue:id))
    var rest=standing
    var active=changed(standing,[(25,0.63,0.5),(27,0.63,0.9),(26,0.335,0.7),(28,0.1,0.9)])
    if id == "splitSquat" || id == "supportedSplitSquat" {
        rest=changed(standing,[(25,0.565,0.7),(27,0.7,0.9),(26,0.385,0.7),(28,0.2,0.9)])
    }
    if id == "lateralLunge" {
        rest=changed(standing,[(25,0.265,0.7),(27,0.1,0.9),(26,0.735,0.7),(28,0.9,0.9)])
        active=changed(rest,[(25,0.1,0.5)])
    }
    if id == "assistedSquat" {
        rest=changed(standing,[(26,0.57,0.4),(28,0.57,0.6)])
        active=changed(rest,[(25,0.63,0.5),(27,0.63,0.9)])
    }
    if id == "stepJack" {
        active=changed(standing,[(25,0.275,0.7),(27,0.12,0.9),(13,0.275,0.115),(15,0.15,0.03),
            (14,0.725,0.115),(16,0.85,0.03)])
    }
    for mirror in [false,true] {
        var counter=RepCounter(exercise:exercise)
        for (t,values) in [(0.0,rest),(0.2,rest),(0.6,active),(0.8,active),(1.2,rest),(1.4,rest)] {
            let sample = try #require(PoseGeometry.measure(pose(values,time:t,mirrored:mirror),exercise:exercise))
            _ = counter.consume(sample)
        }
        #expect(counter.reps == 1)
    }
}

private func holdFixture(_ id: String) -> [(Int,Double,Double)] {
    if id == "singleLegBalance" { return changed(standing,[(26,0.57,0.4),(28,0.57,0.65)]) }
    if id == "tandemBalance" {
        return changed(standing,[(12,0.43,0.2),(24,0.46,0.5),(26,0.5,0.7),(28,0.55,0.9),
            (29,0.4,0.92),(31,0.48,0.92),(30,0.49,0.92),(32,0.57,0.92)])
    }
    if id == "wallSit" || id == "hipFlexorStretch" {
        let seated=changed(standing,[(12,0.43,0.2),(24,0.46,0.5),(25,0.65,0.5),(27,0.65,0.8),
            (26,0.68,0.5),(28,0.68,0.8)])
        return id == "wallSit" ? seated : changed(seated,[(26,0.46,0.8),(28,0.16,0.8)])
    }
    if id == "wallPlank" {
        return changed(standing,[(12,0.43,0.2),(24,0.46,0.5),(13,0.55,0.2),(15,0.7,0.2),
            (14,0.58,0.2),(16,0.73,0.2)])
    }
    var base=floorFixture("mountainClimber",active:false)
    if id != "highPlank" { base=changed(base,[(13,0.3,0.6),(15,0.5,0.6),(14,0.32,0.63),(16,0.52,0.63)]) }
    if id == "sidePlank" || id == "kneeSidePlank" {
        base=changed(base,[(12,0.3,0.15),(24,0.6,0.15)])
    }
    if id == "kneePlank" || id == "kneeSidePlank" { base=changed(base,[(27,0.75,0.2),(28,0.77,0.23)]) }
    return base
}

@Test(arguments: ["plank","kneePlank","highPlank","wallPlank","sidePlank","kneeSidePlank","wallSit","singleLegBalance","tandemBalance","hipFlexorStretch"])
func timedProfilesOnlyQualifyTheirVisiblePosture(id: String) throws {
    let exercise = try #require(Exercise(rawValue:id))
    #expect(exercise.isTimed)
    #expect(!exercise.focusJointIndices.isEmpty)
    for mirror in [false,true] {
        var hold=PoseHoldCounter(exercise:exercise)
        for t in [0.0,0.1,0.2] {
            let measured=try #require(PoseGeometry.measure(pose(holdFixture(id),time:t,mirrored:mirror),exercise:exercise))
            #expect(measured.holdQualification == .staticHold)
            _ = hold.consume(measured)
        }
        #expect(abs(hold.observedSeconds-0.2)<1e-8)
        #expect(PoseGeometry.measure(pose(standing,mirrored:mirror),exercise:exercise) == nil)
        #expect(PoseGeometry.measure(pose([],mirrored:mirror),exercise:exercise) == nil)
    }
}

@Test func directionalRaisesAndSquatSetupRejectWrongViewsOrUnseenTorso() throws {
    let backwards = changed(standing,[(13,0.25,0.2),(15,0.1,0.2)])
    let backwardSample=PoseGeometry.measure(pose(backwards),exercise:.frontArmRaise,preferredSide:0,allowSideFallback:false)
    #expect(backwardSample == nil)
    let crossBody=changed(standing,[(13,0.55,0.2),(15,0.7,0.2)])
    #expect(PoseGeometry.measure(pose(crossBody),exercise:.lateralArmRaise,preferredSide:0,allowSideFallback:false) == nil)
    let unseen=standing.filter { $0.0 != 11 && $0.0 != 12 }
    #expect(PoseGeometry.measure(pose(unseen),exercise:.squat) == nil)
    let front=changed(standing,[(11,0.1,0.2),(12,0.9,0.2),(23,0.1,0.5),(24,0.9,0.5)])
    #expect(PoseGeometry.measure(pose(front),exercise:.squat) == nil)
}

@Test(arguments: Exercise.allCases.filter { $0.isSquat || $0.isPushup })
func angularProfilesPreserveImageAspectAndMirroredVisibility(exercise: Exercise) throws {
    let values: [(Int,Double,Double)]
    if exercise.isSquat { values=changed(standing,[(25,0.63,0.5),(27,0.63,0.9)]) }
    else if exercise == .wallPushup {
        values=changed(standing,[(13,0.6,0.2),(15,0.6,0.4)])
    } else { values=changed(floorFixture("mountainClimber",active:false),[(13,0.3,0.6),(15,0.5,0.6)]) }
    for mirror in [false,true] {
        for dimensions in [(1000.0,1000.0),(2000,1000),(1000,2000)] {
            let base=pose(values,mirrored:mirror)
            let points=base.points.map { PosePoint(x:$0.x*1000/dimensions.0,y:$0.y*1000/dimensions.1,confidence:$0.confidence) }
            let frame=PoseFrame(time:0,width:dimensions.0,height:dimensions.1,points:points)
            let sample=try #require(PoseGeometry.measure(frame,exercise:exercise,preferredSide:mirror ? 1 : 0,allowSideFallback:false))
            #expect(abs(sample.angle-90)<1e-8)
            #expect(sample.provenance == .jointAngle2D)
            let hidden=points.map { PosePoint(x:$0.x,y:$0.y,confidence:0.59) }
            #expect(PoseGeometry.measure(.init(time:0,width:dimensions.0,height:dimensions.1,points:hidden),exercise:exercise) == nil)
        }
    }
}

@Test func kneeSupportedHoldsRequireBentVisibleKneesAndFullHoldsRequireLongLegs() {
    let full=holdFixture("plank")
    let knee=changed(full,[(27,0.75,0.2),(28,0.77,0.23)])
    #expect(PoseGeometry.measure(pose(full),exercise:.kneePlank) == nil)
    #expect(PoseGeometry.measure(pose(knee),exercise:.plank) == nil)
    #expect(PoseGeometry.measure(pose(knee),exercise:.kneePlank) != nil)
    let missing=knee.filter { $0.0 != 27 && $0.0 != 28 }
    #expect(PoseGeometry.measure(pose(missing),exercise:.kneePlank) == nil)
}

@Test func seatedStartRiseCountsThroughThePublicGeometryPipeline() throws {
    let seated=changed(standing,[(25,0.63,0.5),(27,0.63,0.9)])
    let rising=changed(standing,[(25,0.48,0.7)])
    for mirror in [false,true] {
        var counter=RepCounter(exercise:.sitToStand)
        for (t,values) in [(0.0,seated),(0.2,seated),(0.6,rising),(0.9,standing),(1.1,standing)] {
            let sample=try #require(PoseGeometry.measure(pose(values,time:t,mirrored:mirror),exercise:.sitToStand,
                preferredSide:mirror ? 1 : 0,allowSideFallback:false))
            _ = counter.consume(sample)
        }
        #expect(counter.reps == 1)
        #expect(counter.lastRepDuration == nil)
        #expect(counter.lastRepPhases == nil)
    }
}

@Test func fixedSeatedImageCannotCreateAnExtensionByTogglingWorldPoints() throws {
    let seated=changed(standing,[(11,0.3,0.2),(12,0.34,0.2),(23,0.3,0.5),(24,0.34,0.5),
        (25,0.55,0.5),(26,0.59,0.5),(27,0.55,0.8),(28,0.59,0.8)])
    for mirror in [false,true] {
        let side=mirror ? 1 : 0
        var world=Array(repeating:PoseWorldPoint(x:0,y:0,z:0,confidence:0),count:33)
        world[23+side] = .init(x:0,y:0,z:0,confidence:1)
        world[25+side] = .init(x:0.3,y:0,z:0,confidence:1)
        world[27+side] = .init(x:0.6,y:0,z:0,confidence:1)
        var counter=RepCounter(exercise:.seatedKneeExtension)
        for (t,useWorld) in [(0.0,false),(0.2,false),(0.6,true),(0.8,true),(1.2,false),(1.4,false)] {
            let image=pose(seated,time:t,mirrored:mirror)
            let frame=PoseFrame(time:t,width:image.width,height:image.height,points:image.points,worldPoints:useWorld ? world : nil)
            let sample=try #require(PoseGeometry.measure(frame,exercise:.seatedKneeExtension))
            #expect(sample.provenance == .normalizedJointExcursion)
            #expect(sample.angle >= 160)
            _ = counter.consume(sample)
        }
        #expect(counter.reps == 0)
        #expect(counter.lastRepPhases == nil)
    }
}
