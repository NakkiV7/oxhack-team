import Foundation

public struct MovementFigure: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }
    public let points: [Point]
    public let supports: [[Point]]
    public static let bones = [[0,1], [1,2], [1,3,4], [1,5,6], [2,7,8], [2,9,10]]
    public static func highlightedIndices(for id: String) -> [Int] {
        guard let exercise = Exercise(rawValue: id) else { return [1,2] }
        let mapping = [11:1,12:1,13:3,14:5,15:4,16:6,23:2,24:2,25:7,26:9,27:8,28:10,29:8,30:10,31:8,32:10]
        return Set(exercise.focusJointIndices.compactMap { mapping[$0] }).sorted()
    }
    public static func pose(for id: String, phase: MovementIllustration.Phase) -> Self {
        let t = phase == .standing ? 0.0 : phase == .lowered ? 1.0 : 0.5
        var p: [Point] = [.init(0.5,0.12),.init(0.5,0.25),.init(0.5,0.52),.init(0.37,0.4),.init(0.36,0.55),.init(0.63,0.4),.init(0.64,0.55),.init(0.43,0.7),.init(0.42,0.89),.init(0.57,0.7),.init(0.58,0.89)]
        var supports: [[Point]] = []
        let rail: [[Point]] = [[.init(0.85,0.3),.init(0.85,0.92)], [.init(0.78,0.92),.init(0.92,0.92)]]
        let chair: [[Point]] = [[.init(0.25,0.57),.init(0.58,0.57)], [.init(0.28,0.57),.init(0.28,0.91)], [.init(0.55,0.57),.init(0.55,0.91)], [.init(0.25,0.3),.init(0.25,0.57)]]
        switch id {
        case "frontArmRaise", "lateralArmRaise", "wallSlide", "standingBicepsCurl":
            if id == "standingBicepsCurl" {
                p[3] = .init(0.35,0.45); p[4] = .init(0.33,0.65-0.38*t)
            } else if id == "wallSlide" {
                p[3] = .init(0.3,0.3-0.12*t); p[4] = .init(0.3+0.08*t,0.12-0.05*t)
                p[5] = .init(0.7,0.3-0.12*t); p[6] = .init(0.7-0.08*t,0.12-0.05*t)
                supports = [[.init(0.12,0.06),.init(0.12,0.93)]]
            } else if id == "frontArmRaise" {
                p[3] = .init(0.51+0.16*t,0.4-0.15*t); p[4] = .init(0.52+0.32*t,0.55-0.3*t)
            } else {
                p[3] = .init(0.39-0.08*t,0.4-0.15*t); p[4] = .init(0.35-0.18*t,0.55-0.3*t)
                p[5] = .init(0.61+0.08*t,0.4-0.15*t); p[6] = .init(0.65+0.18*t,0.55-0.3*t)
            }
        case "seatedKneeExtension", "seatedMarch", "sitToStand":
            supports = chair
            p = [.init(0.35,0.13),.init(0.35,0.27),.init(0.35,0.53),.init(0.49,0.39),.init(0.56,0.52),.init(0.28,0.4),.init(0.3,0.53),.init(0.62,0.53),.init(0.64,0.86),.init(0.55,0.56),.init(0.56,0.88)]
            if id == "seatedKneeExtension" { p[8] = .init(0.64+0.24*t,0.86-0.33*t) }
            if id == "seatedMarch" { p[7] = .init(0.62,0.53-0.14*t); p[8] = .init(0.64,0.86-0.14*t) }
            if id == "sitToStand" {
                p[0] = .init(0.35+0.13*t,0.13-0.06*t); p[1] = .init(0.35+0.13*t,0.27-0.06*t)
                p[2] = .init(0.35+0.13*t,0.53-0.09*t); p[7] = .init(0.62-0.08*t,0.53+0.1*t); p[9] = .init(0.55,0.56+0.1*t)
            }
        case "gluteBridge", "deadBug":
            p = [.init(0.13,0.78),.init(0.24,0.79),.init(0.53,0.79),.init(0.33,0.84),.init(0.43,0.85),.init(0.28,0.86),.init(0.41,0.88),.init(0.7,0.55),.init(0.86,0.88),.init(0.63,0.57),.init(0.77,0.89)]
            if id == "gluteBridge" { p[2] = .init(0.53,0.79-0.24*t); p[8] = .init(0.86,0.9135); p[10] = .init(0.77,0.9135) }
            else { p[3] = .init(0.24-0.08*t,0.57+0.08*t); p[4] = .init(0.24-0.17*t,0.35+0.26*t); p[5] = .init(0.29,0.57); p[6] = .init(0.29,0.35); p[7] = .init(0.53+0.16*t,0.53+0.16*t); p[8] = .init(0.76+0.16*t,0.53+0.24*t) }
        case "birdDog", "catCow", "mountainClimber", "plank", "highPlank", "kneePlank", "sidePlank", "kneeSidePlank", "widePushup", "diamondPushup":
            p = [.init(0.17,0.38),.init(0.28,0.47),.init(0.58,0.5),.init(0.27,0.65),.init(0.27,0.83),.init(0.33,0.65),.init(0.33,0.83),.init(0.75,0.65),.init(0.91,0.82),.init(0.72,0.68),.init(0.88,0.85)]
            if ["plank","kneePlank","sidePlank","kneeSidePlank"].contains(id) { p[3] = .init(0.28,0.79); p[4] = .init(0.46,0.79); p[5] = .init(0.32,0.82); p[6] = .init(0.49,0.82) }
            if ["kneePlank","kneeSidePlank","birdDog","catCow"].contains(id) { p[7] = .init(0.6,0.81); p[8] = .init(0.83,0.83); p[9] = .init(0.65,0.84); p[10] = .init(0.86,0.86) }
            if id == "birdDog" {
                // Rounded support strokes meet the floor while the opposite limbs reach.
                p[4] = .init(0.27,0.9135); p[9] = .init(0.65,0.9135); p[10] = .init(0.86,0.9135)
                p[5] = .init(0.33-0.18*t,0.65-0.23*t); p[6] = .init(0.33-0.28*t,0.9135-0.5135*t)
                p[7] = .init(0.6+0.15*t,0.9135-0.4135*t); p[8] = .init(0.83+0.12*t,0.9135-0.4135*t)
            }
            if id == "catCow" { p[2] = .init(0.58,0.5-0.12*t); p[1] = .init(0.28,0.47-0.08*t) }
            if id == "mountainClimber" { p[7] = .init(0.75-0.33*t,0.65+0.08*t); p[8] = .init(0.91-0.35*t,0.82) }
            if id == "sidePlank" || id == "kneeSidePlank" { p[5] = .init(0.29,0.29); p[6] = .init(0.3,0.09) }
            if id == "widePushup" || id == "diamondPushup" { p[1] = .init(0.28,0.47+0.17*t); p[0] = .init(0.17,0.38+0.17*t); p[3] = .init(0.2,0.69); p[5] = .init(0.41,0.69); p[6] = .init(id == "widePushup" ? 0.53 : 0.31,0.83) }
            if ["plank","sidePlank","kneePlank","kneeSidePlank"].contains(id) {
                let knees = id == "kneePlank" || id == "kneeSidePlank"
                let endX = knees ? 0.72 : 0.91
                p[0] = .init(0.17,0.48); p[1] = .init(0.28,0.57)
                p[2] = .init(0.58,0.57 + (0.58-0.28)/(endX-0.28)*(0.9135-0.57))
                p[3] = .init(0.28,0.9135); p[4] = .init(0.46,0.9135)
                if id == "plank" || id == "kneePlank" { p[5] = .init(0.32,0.9135); p[6] = .init(0.49,0.9135) }
                if knees {
                    p[7] = .init(0.72,0.9135); p[8] = .init(0.9,0.79)
                    p[9] = .init(0.75,0.9135); p[10] = .init(0.93,0.82)
                } else {
                    p[7] = .init(0.75,0.57 + (0.75-0.28)/(endX-0.28)*(0.9135-0.57)); p[8] = .init(0.91,0.9135)
                    p[9] = .init(0.74,p[7].y); p[10] = .init(0.88,0.9135)
                }
            }
        case "wallPlank", "wallSit":
            supports = [[.init(id == "wallSit" ? 0.33 : 0.85,0.08),.init(id == "wallSit" ? 0.33 : 0.85,0.94)]]
            if id == "wallPlank" { p[0] = .init(0.58,0.12); p[1] = .init(0.57,0.25); p[3] = .init(0.7,0.29); p[4] = .init(0.84,0.33); p[5] = .init(0.72,0.33); p[6] = .init(0.84,0.37) }
            else { p[0] = .init(0.4,0.2); p[1] = .init(0.4,0.33); p[2] = .init(0.4,0.59); p[7] = .init(0.7,0.59); p[8] = .init(0.7,0.9); p[9] = .init(0.65,0.62); p[10] = .init(0.65,0.91) }
        case "singleLegBalance", "tandemBalance", "calfRaise", "standingKneeRaise", "highKnees", "standingHipAbduction", "standingHipExtension":
            if ["singleLegBalance","tandemBalance","calfRaise","standingHipAbduction","standingHipExtension"].contains(id) { supports = rail; p[5] = .init(0.69,0.38); p[6] = .init(0.85,0.32) }
            if id == "tandemBalance" { p[7] = .init(0.49,0.7); p[8] = .init(0.49,0.89); p[9] = .init(0.55,0.7); p[10] = .init(0.55,0.91) }
            else if id == "calfRaise" { p = p.enumerated().map { .init($0.element.x, $0.element.y - ($0.offset >= 8 ? 0.03 : 0.07)*t) } }
            else if id == "standingHipAbduction" || id == "standingHipExtension" { p[7] = .init(0.43-0.12*t,0.7-0.04*t); p[8] = .init(0.42-0.24*t,0.89-0.08*t) }
            else { let lift = id == "singleLegBalance" ? 1.0 : t; p[7] = .init(0.3,0.7-0.2*lift); p[8] = .init(0.31,0.89-0.2*lift) }
        case "stepJack":
            p[7] = .init(0.43-0.13*t,0.7); p[8] = .init(0.42-0.24*t,0.89)
            p[3] = .init(0.37-0.07*t,0.4-0.2*t); p[4] = .init(0.36-0.08*t,0.55-0.48*t)
            p[5] = .init(0.63+0.07*t,0.4-0.2*t); p[6] = .init(0.64+0.08*t,0.55-0.48*t)
        case "reverseLunge", "forwardLunge", "splitSquat", "supportedSplitSquat", "lateralLunge", "assistedSquat", "hipFlexorStretch":
            let depth = id == "hipFlexorStretch" ? 1.0 : t
            p[0] = .init(0.5,0.12+0.12*depth); p[1] = .init(0.5,0.25+0.12*depth); p[2] = .init(0.5,0.52+0.12*depth)
            p[7] = .init(0.32,0.7); p[8] = .init(0.26,0.9); p[9] = .init(0.66,0.72+0.15*depth); p[10] = .init(0.84,0.9)
            if id == "lateralLunge" { p[9] = .init(0.69,0.76); p[10] = .init(0.88,0.9) }
            if id == "assistedSquat" { p[9] = .init(0.7,0.61); p[10] = .init(0.86,0.68) }
            if id == "supportedSplitSquat" || id == "assistedSquat" { supports = rail; p[6] = .init(0.85,0.32) }
        default: break
        }
        return .init(points: p, supports: supports)
    }
}
