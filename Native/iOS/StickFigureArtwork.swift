import SwiftUI

struct StickFigureArtwork: View {
    let exerciseID: String
    private var exercise: Exercise? { Exercise(rawValue: exerciseID) }
    init(exercise: Exercise) { exerciseID = exercise.rawValue }
    init(exerciseID: String) { self.exerciseID = exerciseID }
    private var timingLabel: String? {
        if exercise?.minimumLoweringSeconds == 3 { return "3 sec lower" }
        if exercise?.minimumBottomHoldSeconds == 2 { return "2 sec hold" }
        return nil
    }
    var body: some View {
        Canvas { context, size in
            let squat = exercise?.isSquat == true
            let wall = exercise == .wallPushup
            let shallow = exercise == .halfSquat || exercise == .supportedSquat
            let basePoints: [CGPoint] = squat ? [
                .init(x: 0.45, y: shallow ? 0.14 : 0.24), .init(x: 0.45, y: shallow ? 0.3 : 0.4),
                .init(x: 0.34, y: shallow ? 0.51 : 0.6), .init(x: 0.6, y: 0.68), .init(x: 0.5, y: 0.88),
                .init(x: 0.64, y: 0.34), .init(x: 0.82, y: 0.32)
            ] : wall ? [
                .init(x: 0.46, y: 0.1), .init(x: 0.46, y: 0.25), .init(x: 0.36, y: 0.51),
                .init(x: 0.28, y: 0.68), .init(x: 0.2, y: 0.88), .init(x: 0.63, y: 0.4), .init(x: 0.81, y: 0.3)
            ] : [
                .init(x: 0.19, y: 0.35), .init(x: 0.27, y: 0.4), .init(x: 0.56, y: 0.48),
                .init(x: 0.72, y: exercise == .kneePushup ? 0.65 : 0.54), .init(x: 0.9, y: 0.61),
                .init(x: 0.25, y: 0.61), .init(x: 0.44, y: 0.7)
            ]
            let manualPoints: [CGPoint]?
            switch exerciseID {
            case "wallSit": manualPoints = [.init(x: 0.35, y: 0.13), .init(x: 0.35, y: 0.28), .init(x: 0.35, y: 0.58), .init(x: 0.68, y: 0.58), .init(x: 0.68, y: 0.87), .init(x: 0.48, y: 0.46), .init(x: 0.61, y: 0.55)]
            case "calfRaise": manualPoints = [.init(x: 0.45, y: 0.12), .init(x: 0.45, y: 0.28), .init(x: 0.45, y: 0.53), .init(x: 0.47, y: 0.69), .init(x: 0.54, y: 0.83), .init(x: 0.65, y: 0.4), .init(x: 0.82, y: 0.36)]
            case "seatedKneeExtension": manualPoints = [.init(x: 0.3, y: 0.13), .init(x: 0.3, y: 0.28), .init(x: 0.3, y: 0.58), .init(x: 0.59, y: 0.58), .init(x: 0.86, y: 0.58), .init(x: 0.42, y: 0.43), .init(x: 0.51, y: 0.55)]
            case "birdDog": manualPoints = [.init(x: 0.22, y: 0.36), .init(x: 0.32, y: 0.46), .init(x: 0.57, y: 0.46), .init(x: 0.61, y: 0.69), .init(x: 0.78, y: 0.71), .init(x: 0.3, y: 0.61), .init(x: 0.3, y: 0.76)]
            default: manualPoints = nil
            }
            let points = manualPoints ?? basePoints
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            func p(_ i: Int) -> CGPoint { .init(x: origin.x + points[i].x * side, y: origin.y + points[i].y * side) }
            if wall || exercise == .supportedSquat || ["wallSit", "calfRaise"].contains(exerciseID) {
                var support = Path()
                let x = origin.x + side * (exerciseID == "wallSit" ? 0.25 : 0.85)
                support.move(to: .init(x: x, y: origin.y + side * 0.12))
                support.addLine(to: .init(x: x, y: origin.y + side * 0.92))
                context.stroke(support, with: .color(Palette.muted.opacity(0.5)), style: .init(lineWidth: side * 0.025, lineCap: .round))
            }
            func segment(_ start: CGPoint, _ end: CGPoint, color: Color, width: CGFloat) {
                var line = Path()
                line.move(to: .init(x: origin.x + start.x * side, y: origin.y + start.y * side))
                line.addLine(to: .init(x: origin.x + end.x * side, y: origin.y + end.y * side))
                context.stroke(line, with: .color(color), style: .init(lineWidth: width, lineCap: .round))
            }
            segment(.init(x: 0.08, y: 0.93), .init(x: 0.92, y: 0.93), color: Palette.muted.opacity(0.18), width: max(1, side * 0.012))
            if exerciseID == "seatedKneeExtension" {
                for (a, b) in [(CGPoint(x: 0.22, y: 0.64), CGPoint(x: 0.56, y: 0.64)), (.init(x: 0.25, y: 0.64), .init(x: 0.25, y: 0.89)), (.init(x: 0.52, y: 0.64), .init(x: 0.52, y: 0.89))] {
                    segment(a, b, color: Palette.muted.opacity(0.45), width: max(2, side * 0.025))
                }
            }
            if exerciseID == "birdDog" {
                for (a, b) in [(points[1], CGPoint(x: 0.06, y: 0.4)), (points[2], CGPoint(x: 0.9, y: 0.37))] {
                    segment(a, b, color: Palette.blue.opacity(0.65), width: max(3, side * 0.05))
                }
            }
            if exerciseID == "calfRaise" {
                segment(points[4], .init(x: 0.65, y: 0.91), color: Palette.ink, width: max(3, side * 0.05))
            }
            if ["widePushup", "diamondPushup"].contains(exerciseID) {
                let wrist = CGPoint(x: exerciseID == "widePushup" ? 0.63 : 0.4, y: 0.72)
                segment(points[1], .init(x: 0.45, y: 0.58), color: Palette.blue.opacity(0.6), width: max(3, side * 0.045))
                segment(.init(x: 0.45, y: 0.58), wrist, color: Palette.blue.opacity(0.6), width: max(3, side * 0.045))
            }
            for (a,b) in [(1,2),(2,3),(3,4),(1,5),(5,6)] {
                var line = Path(); line.move(to: p(a)); line.addLine(to: p(b))
                context.stroke(line, with: .color(Palette.ink), style: .init(lineWidth: max(3, side * 0.065), lineCap: .round, lineJoin: .round))
            }
            let head = p(0), radius = side * 0.075
            context.fill(Path(ellipseIn: .init(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)), with: .color(Palette.ink))
            let keyJoints = squat || ["wallSit", "calfRaise", "seatedKneeExtension"].contains(exerciseID) ? [2,3,4] : [1,5,6]
            for i in keyJoints {
                let point = p(i), r = max(2, side * 0.025)
                context.fill(Path(ellipseIn: .init(x: point.x-r, y: point.y-r, width: r*2, height: r*2)), with: .color(Palette.green))
            }
        }
        .overlay(alignment: .bottom) {
            if let timingLabel {
                Text(timingLabel).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.blue).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.blue.opacity(0.08), in: Capsule())
            }
        }
        .accessibilityLabel("Faceless stick figure guide: \(ExerciseCatalog.find(exerciseID)?.name ?? exerciseID). Highlighted joints show the movement; illustration is not a camera measurement.")
    }
}
