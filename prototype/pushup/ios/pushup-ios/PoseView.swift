import SwiftUI

/// Draws the tracked side of the body (shoulder-hip-ankle line and the arm) like the Mac overlay.
/// The dashed grey line is the ideal straight line from shoulder to ankle; the solid line is the real body.
struct PoseView: View {
    let state: PushupState?
    var image: UIImage? = nil

    var body: some View {
        Canvas { context, size in
            let frame = fitted(aspect: state?.aspect ?? 4.0 / 3.0, in: size)
            context.fill(Path(roundedRect: frame, cornerRadius: 14), with: .color(.black.opacity(0.6)))
            if let image {
                context.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: frame, cornerRadius: 14))
                    layer.draw(Image(uiImage: image), in: frame)
                }
            }
            guard let state, let pose = state.pose else { return }

            func point(_ p: [Double]?) -> CGPoint? {
                guard let p, p.count == 2 else { return nil }
                return CGPoint(x: frame.minX + p[0] * frame.width, y: frame.minY + p[1] * frame.height)
            }
            func line(_ pts: [CGPoint?], color: Color, dashed: Bool = false, width: CGFloat = 6) {
                let valid = pts.compactMap { $0 }
                guard valid.count == pts.count, let first = valid.first else { return }
                var path = Path()
                path.move(to: first)
                valid.dropFirst().forEach { path.addLine(to: $0) }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                                                  dash: dashed ? [8, 8] : []))
            }

            let shoulder = point(pose.shoulder), hip = point(pose.hip), ref = point(pose.ref)
            line([shoulder, ref], color: .white.opacity(0.35), dashed: true, width: 3)
            line([shoulder, hip, ref], color: state.lineOK ? .green : .red)
            line([shoulder, point(pose.elbow), point(pose.wrist)], color: .blue)

            for p in [shoulder, point(pose.elbow), point(pose.wrist), hip, ref].compactMap({ $0 }) {
                context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white))
            }
        }
        .aspectRatio(state?.aspect ?? 4.0 / 3.0, contentMode: .fit)
    }

    private func fitted(aspect: Double, in size: CGSize) -> CGRect {
        var w = size.width, h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}
