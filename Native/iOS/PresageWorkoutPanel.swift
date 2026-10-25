import CoreMedia
import Observation
import SwiftUI

@MainActor @Observable
final class PresageWorkoutModel {
    struct Context: Equatable {
        let sessionID: UUID
        let generation: UUID
        let phase: SessionPhase
        let frontEnabled: Bool
        let appActive: Bool
        var permitsMeasurement: Bool { phase == .active && frontEnabled && appActive }
    }
    let controller: PresageCaptureController
    private let vision: VisionWorker
    private let injected: Bool
    private let isCurrent: (UUID, UUID) -> Bool
    private var context: Context?
    private var requestID: UUID?
    private var ownsHook = false
    private var stopping: Task<Void, Never>?

    init(vision: VisionWorker, controller: PresageCaptureController? = nil,
         isCurrent: @escaping (UUID, UUID) -> Bool = { _, _ in true }) {
        self.vision = vision; self.injected = controller != nil; self.isCurrent = isCurrent
        self.controller = controller ?? PresageCaptureController(waitForDeadline: {
            try await Task.sleep(for: .seconds(45))
        }) { session, measurement in
            guard let key = PresageWorkoutConfiguration.key() else { throw CocoaError(.fileNoSuchFile) }
            return try SmartSpectraDriver(apiKey: key, sessionID: session, measurementID: measurement)
        }
    }
    var isRunning: Bool { requestID != nil && (controller.state == .starting || controller.state == .measuring) }
    var available: Bool { injected || SmartSpectraDriver.isAvailable && PresageWorkoutConfiguration.key() != nil }
    var message: String {
        if !injected && !SmartSpectraDriver.isAvailable { return "Presage is not included in this build." }
        if !available { return "Presage key is missing from this build." }
        switch controller.state {
        case .idle: return "Optional stationary camera estimates. No measurement has started."
        case .disclosureRequired: return "Agree to numeric data sharing before starting."
        case .stationaryRequired: return "Confirm that you are still, with your face and chest visible."
        case .starting: return "Starting Presage measurement…"
        case .measuring: return "45-second check. Stay still; results may remain unavailable."
        case .unavailable: return "Presage could not start or stopped. Check setup, then explicitly try again."
        }
    }
    func update(sessionID: UUID, generation: UUID, phase: SessionPhase, frontEnabled: Bool, appActive: Bool) {
        let next = Context(sessionID: sessionID, generation: generation, phase: phase, frontEnabled: frontEnabled, appActive: appActive)
        guard next != context else { return }
        context = next
        invalidate()
    }
    func start(allowAutomaticInsights: Bool, stationary: Bool) async {
        guard let expected = context, expected.permitsMeasurement, requestID == nil else { return }
        let request = UUID()
        requestID = request
        await stopping?.value
        guard requestID == request, context == expected else { return }
        await controller.start(sessionID: expected.sessionID, allowAutomaticInsights: allowAutomaticInsights, stationary: stationary)
        guard requestID == request, context == expected else { return }
        guard controller.state == .measuring else { requestID = nil; return }
        ownsHook = true
        vision.onSample = { [weak self] sample, generation, done in
            Task { @MainActor [weak self] in
                defer { done() }
                guard let self, self.requestID == request, self.context == expected,
                      generation == expected.generation, self.isRunning,
                      self.isCurrent(expected.sessionID, expected.generation) else { return }
                _ = self.controller.submit(sample)
            }
        }
        observeState(request: request)
    }
    func stop() async { invalidate(); await stopping?.value }
    private func invalidate() {
        requestID = nil
        if ownsHook { vision.onSample = nil; ownsHook = false }
        let previous = stopping, controller = controller
        stopping = Task { await previous?.value; await controller.stop() }
    }
    private func observeState(request: UUID) {
        guard requestID == request else { return }
        let state = withObservationTracking { controller.state } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeState(request: request) }
        }
        if state != .starting && state != .measuring { invalidate() }
    }
}

private enum PresageWorkoutConfiguration {
    private struct Configuration: Decodable { let apiKey: String }
    static func key() -> String? {
        guard let url = Bundle.main.url(forResource: "SpottrPresage", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 16_384,
              let value = try? JSONDecoder().decode(Configuration.self, from: data),
              !value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.apiKey
    }
}

@MainActor
struct PresageWorkoutPanel: View {
    let store: TrainingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PresageWorkoutModel
    @State private var allowSharing = false
    @State private var stationary = false

    init(store: TrainingStore) {
        self.store = store
        _model = State(initialValue: PresageWorkoutModel(vision: store.vision, isCurrent: { [weak store] session, generation in
            guard let store, store.sessionPhase == .active, store.source == .camera else { return false }
            return (store.configured?.id ?? store.session.id) == session
                && (store.configured?.generation ?? store.session.generation) == generation
                && (!store.usingSecondaryCamera || store.frontCameraEnabled)
        }))
    }
    private var context: PresageWorkoutModel.Context {
        let frontState = store.usingSecondaryCamera ? store.frontPreviewState : store.visionState
        let ready: Bool
        if case .camera = frontState { ready = true } else { ready = false }
        return .init(sessionID: store.configured?.id ?? store.session.id,
                     generation: store.configured?.generation ?? store.session.generation,
                     phase: store.sessionPhase, frontEnabled: ready && store.source == .camera,
                     appActive: scenePhase == .active)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Presage camera estimates", systemImage: "waveform.path.ecg").font(.headline)
            Text(model.message).font(.caption).foregroundStyle(.secondary)
            Text("Pulse needs at least 12 seconds; breathing needs at least 30. Neither is guaranteed before this 45-second check ends.")
                .font(.caption2).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(alignment: .top) {
                    reading("Pulse", sample: model.controller.vitals?.pulse(at: timeline.date), unit: "bpm")
                    Spacer()
                    reading("Breathing", sample: model.controller.vitals?.breathing(at: timeline.date), unit: "/min")
                }
            }
            if !model.isRunning {
                Toggle("Share numeric metrics for Presage’s automatic AI insights", isOn: $allowSharing).font(.caption)
                Text("Presage sends numeric metric series and session/request metadata to its Analytics Gateway and an LLM. The reviewed docs do not identify that LLM or its retention; raw images are excluded from this insights feature.")
                    .font(.caption2).foregroundStyle(.secondary)
                Link("Presage privacy policy", destination: URL(string: "https://api.physiology.presagetech.com/privacypolicy")!).font(.caption)
                Toggle("I am still, with my face and chest clearly visible", isOn: $stationary).font(.caption)
                Button("Start stationary measurement") {
                    Task { await model.start(allowAutomaticInsights: allowSharing, stationary: stationary) }
                }.buttonStyle(.borderedProminent)
                    .disabled(!model.available || !context.permitsMeasurement || !allowSharing || !stationary)
            } else {
                Button("Stop measurement", role: .cancel) { Task { await model.stop() } }.buttonStyle(.bordered)
            }
            Text("Estimated values only. Movement can distort results. Apple Watch readings remain separate; unavailable values stay blank.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: context, initial: true) { _, next in
                model.update(sessionID: next.sessionID, generation: next.generation, phase: next.phase,
                             frontEnabled: next.frontEnabled, appActive: next.appActive)
            }
            .onDisappear { Task { await model.stop() } }
    }
    private func reading(_ title: String, sample: CameraVitalSample?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption)
            Text(sample.map { "\($0.value.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? "—").font(.title3.monospacedDigit())
            if let sample {
                Text("Presage estimate · \(sample.confidence.formatted(.number.precision(.fractionLength(0))))% confidence")
                Text(sample.date, style: .time)
            }
        }.font(.caption2)
    }
}
