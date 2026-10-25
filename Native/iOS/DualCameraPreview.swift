import SwiftUI

/// Front camera is a preview; the side camera owns pose observations and counts.
struct DualCameraPreview: View {
    let store: TrainingStore
    let exercise: Exercise
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Palette.surface
                if case .camera = store.frontPreviewState, store.sessionPhase == .active {
                    CameraPreview(session: store.vision.capture)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera").font(.title2)
                        Text(frontMessage).font(.caption).multilineTextAlignment(.center)
                    }.foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                cameraLabel("Front", symbol: "camera")
            }.accessibilityIdentifier("front-camera-preview")
            ZStack(alignment: .topLeading) {
                Palette.surface
                if let image = store.image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video").font(.title2)
                        Text(store.sessionPhase == .paused ? "Paused" : "Waiting for side camera")
                            .font(.caption).multilineTextAlignment(.center)
                    }.foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let frame = store.frame { PoseOverlay(frame: frame, exercise: exercise) }
                cameraLabel("Side", symbol: "figure.strengthtraining.traditional")
            }.accessibilityIdentifier("side-camera-preview")
        }.frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Front preview on the left, side-camera form on the right")
    }
    private func cameraLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption2.weight(.semibold)).padding(8)
            .background(.white.opacity(0.9), in: Capsule()).padding(8)
    }
    private var frontMessage: String {
        if store.sessionPhase == .paused { return "Paused" }
        switch store.frontPreviewState {
        case .denied: return "Allow camera access in iPhone Settings"
        case .unavailable, .failed: return "Front camera unavailable"
        default: return "Front preview"
        }
    }
}
