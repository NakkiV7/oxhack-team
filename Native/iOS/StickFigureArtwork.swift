import SwiftUI

struct StickFigureArtwork: View {
    let exercise: Exercise
    var body: some View {
        Canvas { context, size in
            let squat = exercise.isSquat
            let wall = exercise == .wallPushup
            let shallow = exercise == .halfSquat || exercise == .supportedSquat
            let points: [CGPoint] = squat ? [
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
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            func p(_ i: Int) -> CGPoint { .init(x: origin.x + points[i].x * side, y: origin.y + points[i].y * side) }
            if wall || exercise == .supportedSquat {
                var support = Path()
                let x = origin.x + side * 0.85
                support.move(to: .init(x: x, y: origin.y + side * 0.12))
                support.addLine(to: .init(x: x, y: origin.y + side * 0.92))
                context.stroke(support, with: .color(Palette.muted.opacity(0.5)), style: .init(lineWidth: side * 0.025, lineCap: .round))
            }
            for (a,b) in [(1,2),(2,3),(3,4),(1,5),(5,6)] {
                var line = Path(); line.move(to: p(a)); line.addLine(to: p(b))
                context.stroke(line, with: .color(Palette.ink), style: .init(lineWidth: max(3, side * 0.065), lineCap: .round, lineJoin: .round))
            }
            let head = p(0), radius = side * 0.075
            context.fill(Path(ellipseIn: .init(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)), with: .color(Palette.ink))
            let keyJoints = squat ? [2,3,4] : [1,5,6]
            for i in keyJoints {
                let point = p(i), r = max(2, side * 0.025)
                context.fill(Path(ellipseIn: .init(x: point.x-r, y: point.y-r, width: r*2, height: r*2)), with: .color(Palette.green))
            }
        }.accessibilityLabel(exercise.isSquat ? "Stick figure guide highlighting hip, knee and ankle" : "Stick figure guide highlighting shoulder, elbow and wrist")
    }
}
