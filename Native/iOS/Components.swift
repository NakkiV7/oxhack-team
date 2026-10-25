import SwiftUI
import AVFoundation

enum Palette {
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let surface = Color(red: 0.961, green: 0.961, blue: 0.957)
    static let blue = Color(red: 36 / 255, green: 95 / 255, blue: 199 / 255)
    static let muted = Color(red: 98 / 255, green: 103 / 255, blue: 110 / 255)
    static let green = Color(red: 0.149, green: 0.455, blue: 0.353)
    static let amber = Color(red: 138 / 255, green: 97 / 255, blue: 22 / 255)
    static let red = Color(red: 0.675, green: 0.208, blue: 0.208)

    static func coaching(_ decision: CoachingDecision?, cue: Cue) -> Color {
        if let decision {
            switch decision.reason {
            case .discomfort: return red
            case .tracking, .alignment, .slowerRep: return amber
            case .targetReached: return green
            case .restReminder: return ink
            }
        }
        switch cue {
        case .tracking, .alignment: return amber
        case .controlled: return green
        default: return ink
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.up.right"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Image(systemName: symbol) }
                .font(.system(size: 16, weight: .semibold)).padding(19)
                .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct KeyboardDismissBar: View {
    let identifier: String
    let dismiss: () -> Void
    var body: some View {
        HStack {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 32, height: 4)
                .accessibilityHidden(true)
            Spacer()
            Button(action: dismiss) {
                Label("Done", systemImage: "keyboard.chevron.compact.down").padding(.vertical, 12)
            }.font(.subheadline.weight(.semibold)).accessibilityIdentifier(identifier)
                .accessibilityHint("Dismisses the keyboard without saving.")
        }.padding(.horizontal, 20).background(.regularMaterial)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height > 12, value.translation.height > abs(value.translation.width) { dismiss() }
            })
            .accessibilityElement(children: .contain).accessibilityIdentifier("keyboard-dismiss-bar")
    }
}

struct Metric: View {
    let value: String
    let title: String
    let symbol: String
    var symbolColor: Color = Palette.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(value) } icon: {
                Image(systemName: symbol).foregroundStyle(symbolColor)
            }.font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func clockText(_ seconds: Double) -> String {
    let seconds = max(0, Int(seconds))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

struct PoseOverlay: View {
    let frame: PoseFrame
    let exercise: Exercise
    var body: some View {
        Canvas { context, size in
            let edges = [(11,13),(13,15),(12,14),(14,16),(11,23),(12,24),(23,25),(25,27),(24,26),(26,28),(11,12),(23,24)]
            let scale = min(size.width / frame.width, size.height / frame.height)
            let offset = CGPoint(x: (size.width - frame.width * scale) / 2, y: (size.height - frame.height * scale) / 2)
            let measurement = PoseGeometry.measure(frame, exercise: exercise)
            for (a, b) in edges {
                guard frame.points.indices.contains(a), frame.points.indices.contains(b) else { continue }
                let p = frame.points[a], q = frame.points[b]
                guard p.confidence >= 0.6, q.confidence >= 0.6,
                      p.x.isFinite, p.y.isFinite, q.x.isFinite, q.y.isFinite else { continue }
                let from = CGPoint(x: p.x * frame.width * scale + offset.x, y: p.y * frame.height * scale + offset.y)
                let to = CGPoint(x: q.x * frame.width * scale + offset.x, y: q.y * frame.height * scale + offset.y)
                let bodyEdge = [23,24].contains(b) || [23,24].contains(a)
                let color: Color = edgeColor(measurement, bodyEdge: bodyEdge)
                var path = Path(); path.move(to: from); path.addLine(to: to)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: from.x - 3, y: from.y - 3, width: 6, height: 6)), with: .color(.white))
            }
        }.accessibilityHidden(true)
    }
    private func edgeColor(_ sample: MovementSample?, bodyEdge: Bool) -> Color {
        guard let sample else { return .gray }
        guard exercise == .pushup, bodyEdge else { return Palette.green }
        switch sample.bodyLine {
        case .unknown: return .gray
        case .steady: return Palette.green
        case .adjust: return Palette.amber
        case .reset: return Palette.red
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = preview.connection else { return }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.preview.session = session; view.preview.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: Preview, context: Context) {}
}
