import SwiftUI
import UniformTypeIdentifiers

struct SessionView: View {
    @Bindable var store: TrainingStore
    var body: some View {
        Group {
            if store.configured != nil { ConfiguredSessionView(store: store) }
            else { legacySession }
        }
    }
    private var legacySession: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if store.session.phase == .finished { store.presented = false }
                    else { store.finish() }
                } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                    .accessibilityLabel("Finish session now")
                Spacer()
                VStack(spacing: 4) {
                    Text(title).font(.headline)
                    if store.session.phase == .active || store.session.phase == .paused {
                        Text("Set \(store.session.setNumber) of 3").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: store.session.phase == .rest ? "wind" : "figure.strengthtraining.traditional").frame(width: 40, height: 40)
            }.padding(.horizontal, 14).padding(.top, 8)
            if store.session.phase == .active || store.session.phase == .paused || store.session.phase == .rest {
                WorkoutVoiceControls(store: store, identifier: "voice-feedback-toggle")
            }
            switch store.session.phase {
            case .active, .paused: LiveSetView(store: store)
            case .rest: RecoveryView(store: store)
            case .finished: FinishedView(store: store)
            case .idle: Color.white
            }
        }.background(.white).foregroundStyle(Palette.ink)
    }
    private var title: String {
        switch store.session.phase {
        case .rest: return "Take a breather."
        case .finished: return "Your session"
        default: return store.session.exercise.title
        }
    }
}

struct LiveSetView: View {
    @Bindable var store: TrainingStore
    @State private var guide = "top"
    @State private var importing = false
    @State private var pendingImport: URL?
    @State private var replaceCamera = false
    @State private var replaceSecondaryCamera = false
    @State private var pairingPresented = false
    @State private var pendingManualFallback: UUID?
    @State private var manualQuantity = ""
    @FocusState private var enteringReps: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.session.actualReps.map { String(format: "%02d", $0) } ?? "—").font(.system(size: 70, weight: .semibold, design: .rounded)).tracking(-3).monospacedDigit()
                            .accessibilityIdentifier("rep-count")
                        Text("/ \(store.session.exercise.target)").foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Label(store.heartRate(at: Date()), systemImage: "heart.fill").font(.caption.weight(.medium))
                            Label(clockText(store.session.elapsed(at: store.now)), systemImage: "stopwatch").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if store.usingSecondaryCamera {
                    DualCameraPreview(store: store, exercise: store.session.exercise)
                } else {
                ZStack(alignment: .topLeading) {
                    Palette.surface
                    if case .camera = store.visionState, store.session.phase == .active, !store.usingSecondaryCamera {
                        CameraPreview(session: store.vision.capture)
                    } else if let image = store.image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Image("\(store.session.exercise.rawValue)-\(guide)").resizable().scaledToFit().padding(27)
                    }
                    if let frame = store.frame { PoseOverlay(frame: frame, exercise: store.session.exercise) }
                    Text(store.session.phase == .paused ? "Paused" : (store.source == .manual ? "Manual self-report" : (store.hasInput ? inputStatus : "Movement guide")))
                        .font(.caption.weight(.medium)).padding(8).background(.white.opacity(0.9), in: Capsule()).padding(12)
                }.frame(height: 295).clipShape(RoundedRectangle(cornerRadius: 23))
                }
                if SmartSpectraDriver.isAvailable, store.hasInput, store.source == .camera {
                    PresageWorkoutPanel(store: store)
                }
                if !store.hasInput {
                    Picker("Movement phase", selection: $guide) {
                        Text("Top").tag("top"); Text("Middle").tag("mid"); Text("Bottom").tag("bottom")
                    }.pickerStyle(.segmented)
                }
                HStack(spacing: 14) {
                    Button("Use camera", systemImage: "camera") {
                        if store.hasInput || store.source == .manual { replaceCamera = true; return }
                        store.camera()
                    }
                    Spacer()
                    Button("Import video", systemImage: "film") { importing = true }
                }.font(.subheadline.weight(.medium)).buttonStyle(.plain)
                Menu {
                    Toggle("Show front camera", isOn: Binding(get: { store.frontCameraEnabled }, set: store.setFrontCameraEnabled))
                        .accessibilityIdentifier("front-camera-toggle")
                    Button(store.usingSecondaryCamera ? "Reconnect side camera" : "Start side camera", systemImage: "video") {
                        if store.usingSecondaryCamera { store.secondaryCamera(); return }
                        if store.hasInput || store.source == .manual || store.session.counter.reps > 0 { replaceSecondaryCamera = true; return }
                        store.secondaryCamera()
                    }
                    Button("Pair side camera", systemImage: "link") {
                        store.pause()
                        pairingPresented = true
                    }
                } label: {
                    Label("Side camera", systemImage: "network").font(.subheadline.weight(.medium))
                }.accessibilityIdentifier("secondary-camera-menu")
                if case .failed(let message) = store.visionState {
                    Text(message).font(.caption).foregroundStyle(Palette.red)
                        .accessibilityIdentifier("camera-tracking-error")
                } else if !store.hasInput && store.source != .manual {
                    Text(store.visionState.message).font(.caption).foregroundStyle(.secondary)
                }
                if store.source == .manual {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actual completed reps").font(.subheadline.weight(.semibold))
                        TextField("Enter reps", text: $manualQuantity)
                            .keyboardType(.numberPad).focused($enteringReps)
                            .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("legacy-manual-reps")
                            .onChange(of: manualQuantity) { _, value in store.setManualReps(Int(value)) }
                        if enteringReps { Button("Done entering reps") { enteringReps = false }.font(.caption) }
                        Text("Enter 1–200 reps you actually completed. Camera counts and targets are not filled in for you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Use manual reps", systemImage: "hand.tap") {
                        store.pause()
                        pendingManualFallback = store.session.generation
                    }.font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("legacy-manual-fallback")
                }
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: store.session.phase == .paused ? "pause" : "arrow.down")
                        .padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.source == .manual ? "Enter the reps you actually complete." : (store.coachingEvent?.decision.text ?? store.session.cue.text))
                            .font(.system(size: 19, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coaching-cue")
                        Text(store.session.phase == .paused ? "Your set is on hold." : "\(store.session.exercise.guide)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Metric(value: store.heartRate(at: context.date), title: "Apple Watch", symbol: "heart")
                    }
                    Metric(value: store.session.counter.lastRepDuration.map { String(format: "%.1f s", $0) } ?? "—", title: "Last rep", symbol: "speedometer")
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    store.session.phase == .paused ? store.resume() : store.pause()
                } label: {
                    Label(store.session.phase == .paused ? "Resume" : "Pause", systemImage: store.session.phase == .paused ? "play" : "pause")
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(19)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.12)))
                }.buttonStyle(.plain)
                PrimaryButton(title: "End set", symbol: "checkmark") { enteringReps = false; store.endSet() }
                    .disabled(store.source == .manual && (validManualQuantity == nil || validManualQuantity != store.session.manualReps))
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.white)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: store.source) { _, source in
            manualQuantity = source == .manual ? store.session.manualReps.map(String.init) ?? "" : ""
            enteringReps = false
        }
        .alert("Restart this set with manual reps?", isPresented: Binding(get: { pendingManualFallback != nil }, set: { if !$0 { pendingManualFallback = nil } })) {
            Button("Reset and use manual reps", role: .destructive) {
                if pendingManualFallback == store.session.generation { store.switchToManualReps() }
                pendingManualFallback = nil
            }
            Button("Cancel", role: .cancel) { pendingManualFallback = nil }
        } message: {
            Text("This set’s unfinished camera count and active time will be discarded. Ended sets stay saved. A fresh manual set starts when you confirm; enter only reps you actually complete.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            guard case .success(let url) = result else { return }
            if store.hasInput || store.source == .manual || store.session.counter.reps > 0 { pendingImport = url; return }
            store.video(url)
        }
        .confirmationDialog("Start a fresh set with this video?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Start fresh set") { if let url = pendingImport { store.video(url) }; pendingImport = nil }
        } message: { Text("The current set’s count will reset.") }
        .confirmationDialog("Start a fresh camera set?", isPresented: $replaceCamera) {
            Button("Start fresh set") { store.camera() }
        } message: { Text("The current set’s count will reset.") }
        .confirmationDialog("Start a fresh side camera set?", isPresented: $replaceSecondaryCamera) {
            Button("Start fresh set") { store.secondaryCamera() }
        } message: { Text("The current set’s count will reset.") }
        .sheet(isPresented: $pairingPresented) { SecondaryCameraSettingsView(preview: store.previewMode) }
    }
    private var validManualQuantity: Int? {
        Int(manualQuantity).flatMap { (1...200).contains($0) ? $0 : nil }
    }
    private var inputStatus: String {
        guard store.usingSecondaryCamera else { return store.visionState.message }
        switch store.secondaryVision.state {
        case .starting: return "Connecting to side camera…"
        case .tracking: return "Side camera"
        case .idle: return store.visionState.message
        case .failed(let message): return message
        }
    }
}

struct RecoveryView: View {
    @Bindable var store: TrainingStore
    @State private var reserve: Int?
    @State private var reason: StopReason = .voluntary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 9) {
                        Text("Suggested rest").font(.caption).foregroundStyle(.secondary)
                        Text(clockText(max(0, 45 - (store.actualRestElapsed() ?? 0))))
                            .font(.system(size: 69, weight: .medium, design: .rounded)).tracking(-3).monospacedDigit()
                        Text("Take longer if you need it.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("How many more could you do?").font(.headline)
                    Text("Think clean reps, with the same form.").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(0..<4) { number in
                            Button {
                                reserve = number; feedback()
                            } label: {
                                Text(number == 3 ? "3+" : "\(number)").frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .foregroundStyle(reserve == number ? .white : Palette.ink)
                                    .background(reserve == number ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("\(number) reps in reserve")
                        }
                        Button("Skip") { reserve = nil; feedback() }.font(.caption).padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why did you stop?").font(.headline)
                    Picker("Why did you stop?", selection: $reason) {
                        ForEach(StopReason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(store.reportedDiscomfort)
                        .pickerStyle(.menu).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if let text = store.coachingEvent?.decision.text ?? (store.reportedDiscomfort ? "Call it here. Give yourself time to recover." : nil) {
                    Label(text, systemImage: store.reportedDiscomfort ? "hand.raised" : "wind")
                        .font(.subheadline).accessibilityIdentifier("coaching-cue")
                }
                if reason != .discomfort && !store.reportedDiscomfort {
                    PrimaryButton(title: store.session.sets.count == 6 ? "Review session" : "Ready for the next set", symbol: "arrow.right") { feedback(); store.next() }
                }
                Button("Finish session") { feedback(); store.finish() }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 15)
            }.padding(24)
        }
        .onAppear { reason = store.session.sets.last?.reason ?? .voluntary }
        .onChange(of: reason) { _, _ in feedback() }
    }
    private func feedback() { store.feedback(reserve: reserve, reason: reason) }
}

struct FinishedView: View {
    let store: TrainingStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label(store.error == nil ? "Session saved" : "Save interrupted", systemImage: store.error == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(store.error == nil ? Palette.green : Palette.red).padding(.top, 35)
                Text("That’s your session.").font(.system(size: 33, weight: .bold)).tracking(-1)
                Label(clockText(store.session.record.activeSeconds), systemImage: "clock").foregroundStyle(.secondary)
                HStack {
                    Metric(value: "\(store.session.record.reps)", title: "Reps", symbol: "figure.strengthtraining.traditional")
                    Metric(value: "\(store.session.sets.count)", title: "Sets", symbol: "square.3.layers.3d")
                }
                Divider()
                ForEach(store.session.sets) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(set.exercise.title) · Set \(set.number)").font(.headline)
                            Text(set.reason.title).font(.caption).foregroundStyle(.secondary)
                            if set.source == .manual {
                                Label("Manual self-report", systemImage: "hand.tap").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(); Text("\(set.reps) reps").font(.subheadline)
                    }
                }
                if let error = store.error {
                    Text(error).font(.subheadline).foregroundStyle(Palette.red)
                    PrimaryButton(title: "Retry save", symbol: "arrow.clockwise", action: store.save)
                }
                PrimaryButton(title: "Done", symbol: "checkmark") { store.presented = false }
            }.padding(24)
        }
    }
}
