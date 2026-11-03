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
        var permitsMeasurement: Bool { phase == .rest && frontEnabled && appActive }
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
            try await Task.sleep(for: .seconds(75))
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
        case .measuring: return "Measuring. Keep your face and chest still."
        case .completed: return "Check complete. Results below are from this measurement."
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
        if state == .completed {
            requestID = nil
            if ownsHook { vision.onSample = nil; ownsHook = false }
        } else if state != .starting && state != .measuring {
            requestID = nil
            if ownsHook { vision.onSample = nil; ownsHook = false }
        }
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

/// Examples appear only after five uninterrupted seconds of visible camera preview.
struct CameraExampleGate {
    private var visibleSince: TimeInterval?
    mutating func update(cameraVisible: Bool, at time: TimeInterval) {
        guard cameraVisible, time.isFinite else { visibleSince = nil; return }
        if visibleSince == nil { visibleSince = time }
    }
    func ready(at time: TimeInterval) -> Bool {
        guard let visibleSince, time.isFinite else { return false }
        return time - visibleSince >= 5
    }
}

@MainActor
struct PresageWorkoutPanel: View {
    let store: TrainingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PresageWorkoutModel
    @State private var allowSharing = false
    @State private var stationary = false
    private var exampleVitals: Bool { store.previewMode }
    @State private var exampleGate = CameraExampleGate()

    init(store: TrainingStore) {
        self.store = store
        _model = State(initialValue: PresageWorkoutModel(vision: store.vision, isCurrent: { [weak store] session, generation in
            guard let store, store.sessionPhase == .rest, store.restCameraEnabled,
                  case .camera = store.frontPreviewState else { return false }
            return (store.configured?.id ?? store.session.id) == session
                && (store.configured?.generation ?? store.session.generation) == generation
        }))
    }
    private var context: PresageWorkoutModel.Context {
        let ready: Bool
        if case .camera = store.frontPreviewState { ready = true } else { ready = false }
        return .init(sessionID: store.configured?.id ?? store.session.id,
                     generation: store.configured?.generation ?? store.session.generation,
                     phase: store.sessionPhase, frontEnabled: ready && store.restCameraEnabled,
                     appActive: scenePhase == .active)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rest camera check", systemImage: "waveform.path.ecg").font(.headline)
            HStack {
                Label(store.restCameraEnabled ? "Camera ON" : "Camera OFF", systemImage: store.restCameraEnabled ? "camera.fill" : "camera")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(store.restCameraEnabled ? "Turn camera OFF" : "Turn camera ON") {
                    let enabled = !store.restCameraEnabled
                    store.setRestCameraEnabled(enabled)
                    if !enabled { Task { await model.stop() } }
                }.buttonStyle(.bordered).disabled(store.sessionPhase != .rest)
                    .accessibilityIdentifier("presage-rest-camera-toggle")
            }
            if store.restCameraEnabled {
                if case .camera = store.frontPreviewState {
                    CameraPreview(session: store.vision.capture)
                        .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Front camera framing preview for face and chest")
                } else {
                    Text(store.frontPreviewState.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.restCameraEnabled {
            if !exampleVitals {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
            }
            if !exampleVitals, let guidance = model.controller.guidance {
                Label(guidance, systemImage: "viewfinder").font(.caption).foregroundStyle(Palette.blue)
            }
            if !exampleVitals {
                Text("Stay still with your face and chest visible. Pulse must be within Presage’s 40–110 bpm operating range.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let measuredAt = model.controller.completedAt ?? timeline.date
                let examplesReady = exampleGate.ready(at: ProcessInfo.processInfo.systemUptime)
                let terminal = examplesReady && (exampleVitals || model.controller.state == .unavailable || model.controller.state == .completed || !model.available)
                let sessionID = store.configured?.id ?? store.session.id
                let watch = (store.configured?.telemetry ?? store.session.telemetry).last { $0.heartRate != nil }
                let currentWatch = VitalsDisplay(sessionID: sessionID, watch: watch, camera: nil, now: timeline.date).heartRate
                let display = DisplayRestVitals(sessionID: sessionID, watch: nil, camera: model.controller.vitals,
                    now: measuredAt, previewEnabled: store.previewMode, measurementUnavailable: terminal)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        displayReading("Heart rate", value: currentWatch ?? display.heartRate, unit: "bpm")
                        Spacer()
                        displayReading("Breathing", value: display.breathingRate, unit: "/min")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                        displayReading("HRV · RMSSD", value: display.hrvRMSSD, unit: "ms", symbol: "waveform.path.ecg")
                        displayReading("HRV · SDNN", value: display.hrvSDNN, unit: "ms", symbol: "waveform.path.ecg")
                        displayReading("Mean beat interval", value: display.meanNN, unit: "ms", symbol: "heart.text.clipboard")
                        displayReading("Baevsky stress index", value: display.stressIndex, unit: "", symbol: "waveform.path")
                    }
                    if !exampleVitals {
                        Text("The stress index is unitless and needs your own baseline for comparison. It is not a stress diagnosis.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Label("Blood pressure requires a cuff. Presage’s waveform does not provide systolic or diastolic readings.", systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let completedAt = model.controller.completedAt {
                        Text("Measured at \(completedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !model.isRunning && !exampleVitals {
                Toggle("Share numeric metrics for Presage’s automatic AI insights", isOn: $allowSharing).font(.caption)
                Text("Your numeric vitals and session metadata are shared with Presage and its AI insights service. Raw camera images are excluded from this insights feature.")
                    .font(.caption2).foregroundStyle(.secondary)
                Link("Presage privacy policy", destination: URL(string: "https://api.physiology.presagetech.com/privacypolicy")!).font(.caption)
                Toggle("I am still, with my face and chest clearly visible", isOn: $stationary).font(.caption)
                Button("Start stationary measurement") {
                    Task { await model.start(allowAutomaticInsights: allowSharing, stationary: stationary) }
                }.buttonStyle(.borderedProminent)
                    .disabled(!model.available || !context.permitsMeasurement || !allowSharing || !stationary)
            } else if model.isRunning {
                Button("Stop measurement", role: .cancel) { Task { await model.stop() } }.buttonStyle(.bordered)
            }
            if !exampleVitals {
                Text("Camera estimates can be distorted by movement.").font(.caption2).foregroundStyle(.secondary)
            }
            } else {
                Text("Check pulse and breathing while you rest. Turning the camera on does not start a measurement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: context, initial: true) { _, next in
                exampleGate.update(cameraVisible: next.permitsMeasurement, at: ProcessInfo.processInfo.systemUptime)
                model.update(sessionID: next.sessionID, generation: next.generation, phase: next.phase,
                             frontEnabled: next.frontEnabled, appActive: next.appActive)
            }
            .onDisappear {
                exampleGate.update(cameraVisible: false, at: ProcessInfo.processInfo.systemUptime)
                store.setRestCameraEnabled(false)
                Task { await model.stop() }
            }
    }
    private func displayReading(_ title: String, value: DisplayVital?, unit: String, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol ?? (title == "Heart rate" ? "heart.fill" : "lungs.fill"))
                .font(.caption).foregroundStyle(title == "Heart rate" ? Palette.red : Palette.blue)
            Text(value.map { "\(Int($0.value.rounded())) \(unit)" } ?? "—")
                .font(.title2.bold()).monospacedDigit()
            if let value, value.source != .demonstration {
                Text(value.source == .watch ? "Apple Watch" : "Presage estimate")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier(title == "Heart rate" ? "rest-heart-rate" : (title == "Breathing" ? "rest-breathing-rate" : "rest-\(title)"))
    }
}
