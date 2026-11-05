import SwiftUI

struct StickFigureArtwork: View {
    let exerciseID: String
    let phase: MovementIllustration.Phase
    private var exercise: Exercise? { Exercise(rawValue: exerciseID) }
    init(exercise: Exercise, phase: MovementIllustration.Phase = .lowering) {
        exerciseID = exercise.rawValue
        self.phase = phase
    }
    init(exerciseID: String) {
        self.exerciseID = exerciseID
        phase = .lowering
    }
    private var timingLabel: String? {
        if exercise?.minimumLoweringSeconds == 3 { return "3 sec lower" }
        if exercise?.minimumBottomHoldSeconds == 2 { return "2 sec hold" }
        return nil
    }
    var body: some View {
        Group {
            if let exercise {
                Image(MovementIllustration.assetName(for: exercise, phase: phase))
                    .resizable().scaledToFit()
                    .background {
                        if exercise == .supportedSquat { squatSupport }
                    }
            } else {
                manualFigure
            }
        }
        .overlay(alignment: .bottom) {
            if let timingLabel {
                Text(timingLabel).font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.blue).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.blue.opacity(0.08), in: Capsule())
            }
        }
        .accessibilityLabel("Faceless stick figure guide: \(ExerciseCatalog.find(exerciseID)?.name ?? exerciseID). Highlighted joints show the movement; illustration is not a camera measurement.")
    }

    private var squatSupport: some View {
        Canvas { context, size in
            let scale = min(size.width / 420, size.height / 492)
            let origin = CGPoint(x: (size.width - 420 * scale) / 2, y: (size.height - 492 * scale) / 2)
            let hand = phase == .standing ? CGPoint(x: 304, y: 149) : CGPoint(x: 351, y: 206)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            var rail = Path()
            rail.move(to: point(hand.x, hand.y - 12))
            rail.addLine(to: point(hand.x, 435))
            rail.move(to: point(hand.x - 22, 435))
            rail.addLine(to: point(hand.x + 36, 435))
            context.stroke(rail, with: .color(Color(white: 0.6)), style: .init(lineWidth: 12 * scale, lineCap: .round, lineJoin: .round))
            context.stroke(rail, with: .color(Color(white: 0.83)), style: .init(lineWidth: 8 * scale, lineCap: .round, lineJoin: .round))
        }
    }

    private var manualFigure: some View {
        Canvas { context, size in
            let figure = Color(white: 0.14)
            let edging = Color(white: 0.83)
            let joint = Color(red: 0, green: 0.9, blue: 0.55)
            let basePoints: [CGPoint] = [
                .init(x: 0.19, y: 0.35), .init(x: 0.27, y: 0.4), .init(x: 0.56, y: 0.48),
                .init(x: 0.72, y: 0.54), .init(x: 0.9, y: 0.61),
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
            if ["wallSit", "calfRaise"].contains(exerciseID) {
                var support = Path()
                let x = origin.x + side * (exerciseID == "wallSit" ? 0.25 : 0.85)
                support.move(to: .init(x: x, y: origin.y + side * 0.12))
                support.addLine(to: .init(x: x, y: origin.y + side * 0.92))
                context.stroke(support, with: .color(Palette.muted.opacity(0.5)), style: .init(lineWidth: side * 0.025, lineCap: .round))
            }
            func segment(_ start: CGPoint, _ end: CGPoint, color: Color, width: CGFloat, outlined: Bool = false) {
                var line = Path()
                line.move(to: .init(x: origin.x + start.x * side, y: origin.y + start.y * side))
                line.addLine(to: .init(x: origin.x + end.x * side, y: origin.y + end.y * side))
                if outlined {
                    context.stroke(line, with: .color(edging), style: .init(lineWidth: width + side * 0.022, lineCap: .round))
                }
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
                    segment(a, b, color: figure, width: max(3, side * 0.05), outlined: true)
                }
            }
            if exerciseID == "calfRaise" {
                segment(points[4], .init(x: 0.65, y: 0.91), color: figure, width: max(3, side * 0.05), outlined: true)
            }
            if ["widePushup", "diamondPushup"].contains(exerciseID) {
                let wrist = CGPoint(x: exerciseID == "widePushup" ? 0.63 : 0.4, y: 0.72)
                segment(points[1], .init(x: 0.45, y: 0.58), color: figure, width: max(3, side * 0.045), outlined: true)
                segment(.init(x: 0.45, y: 0.58), wrist, color: figure, width: max(3, side * 0.045), outlined: true)
            }
            for (a,b) in [(0,1),(1,2),(2,3),(3,4),(1,5),(5,6)] {
                var line = Path(); line.move(to: p(a)); line.addLine(to: p(b))
                context.stroke(line, with: .color(edging), style: .init(lineWidth: max(4, side * 0.09), lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(figure), style: .init(lineWidth: max(3, side * 0.065), lineCap: .round, lineJoin: .round))
            }
            let head = p(0), radius = side * 0.075
            context.fill(Path(ellipseIn: .init(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)), with: .color(figure))
            let keyJoints = [1,2,3,4,5,6]
            for i in keyJoints {
                let point = p(i), r = max(2, side * 0.025)
                context.fill(Path(ellipseIn: .init(x: point.x-r, y: point.y-r, width: r*2, height: r*2)), with: .color(joint))
            }
        }
    }
}

struct MovementDemonstration: View {
    let exercise: Exercise
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = MovementIllustration.Phase.lowering
    @State private var isVisible = false

    private var shouldAnimate: Bool { isActive && isVisible && scenePhase == .active && !reduceMotion }

    var body: some View {
        StickFigureArtwork(exercise: exercise, phase: phase)
            .id(phase).transition(.opacity)
            .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
            .onDisappear { isVisible = false }
            .task(id: shouldAnimate) {
                guard shouldAnimate else { phase = .lowering; return }
                phase = .standing
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1.4)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = MovementIllustration.nextPhase(after: phase, isActive: shouldAnimate, reduceMotion: reduceMotion)
                    }
                }
            }
    }
}
