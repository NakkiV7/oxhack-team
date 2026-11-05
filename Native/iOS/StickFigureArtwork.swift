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
            if let exercise, !MovementIllustration.usesVector(exercise) {
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
            let pose = MovementFigure.pose(for: exerciseID, phase: phase)
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width-side)/2, y: (size.height-side)/2)
            func point(_ p: MovementFigure.Point) -> CGPoint { .init(x: origin.x+p.x*side, y: origin.y+p.y*side) }
            func stroke(_ points: [MovementFigure.Point], color: Color, width: CGFloat) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: point(first))
                for p in points.dropFirst() { path.addLine(to: point(p)) }
                context.stroke(path, with: .color(color), style: .init(lineWidth: side*width, lineCap: .round, lineJoin: .round))
            }
            stroke([.init(0.06,0.95),.init(0.94,0.95)], color: Palette.muted.opacity(0.2), width: 0.012)
            for support in pose.supports { stroke(support, color: Color(white: 0.65), width: 0.025) }
            for bone in MovementFigure.bones {
                let points = bone.map { pose.points[$0] }
                stroke(points, color: Color(white: 0.83), width: 0.073)
                stroke(points, color: Color(white: 0.14), width: 0.052)
            }
            for index in MovementFigure.highlightedIndices(for: exerciseID) {
                let p = point(pose.points[index])
                context.fill(Path(ellipseIn: CGRect(x:p.x-side*0.022,y:p.y-side*0.022,width:side*0.044,height:side*0.044)), with: .color(Palette.green))
            }
            let head = point(pose.points[0])
            context.fill(Path(ellipseIn: CGRect(x:head.x-side*0.047,y:head.y-side*0.047,width:side*0.094,height:side*0.094)), with: .color(Color(white:0.14)))
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
