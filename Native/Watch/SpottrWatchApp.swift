import SwiftUI

@main
struct SpottrWatchApp: App {
    @State private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            WatchTrainingView(store: store).preferredColorScheme(.dark)
                .task {
                    while !Task.isCancelled {
                        store.tick()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
        }
    }
}

struct WatchTrainingView: View {
    private enum Page: Hashable { case metrics, controls, vitals }
    let store: WatchStore
    @State private var page = Page.metrics
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize: CGFloat = 42
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if let snapshot = store.state.snapshot, snapshot.isFresh(at: context.date), snapshot.phase != .idle {
                    TabView(selection: $page) {
                        metrics(snapshot, now: context.date).tag(Page.metrics)
                        controls(snapshot, now: context.date).tag(Page.controls)
                        vitals(snapshot, now: context.date).tag(Page.vitals)
                    }.tabViewStyle(.verticalPage)
                        .containerBackground(.black, for: .tabView)
                } else if store.recordingBusy {
                    disconnectedRecording(now: context.date)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            Image(systemName: "iphone.and.arrow.forward").font(.largeTitle)
                            Text("Open Spottr on iPhone").font(.headline)
                            Text("Connect to see your current session.").font(.caption2).foregroundStyle(.secondary)
                            Button("Reconnect") { store.link.request() }.buttonStyle(.bordered)
                        }.padding(.horizontal, 12)
                    }
                }
            }.background { Color.black.ignoresSafeArea() }
        }.foregroundStyle(.white).tint(.blue)
            .onChange(of: store.state.snapshot?.sessionID) { _, _ in page = .metrics }
            .onChange(of: store.state.snapshot?.phase) { _, phase in
                if phase == .finished { page = .metrics }
            }
            .alert("End this session?", isPresented: Binding(get: { store.pendingFinish != nil }, set: { if !$0 { store.cancelFinish() } })) {
                Button("End session", role: .destructive) { store.confirmFinish() }
                Button("Cancel", role: .cancel) { store.cancelFinish() }
            } message: {
                Text(store.state.snapshot?.configured != nil
                     ? "Ended sets and skipped steps are saved separately. The current unfinished set will be discarded."
                     : "Finish this session and save your completed work on iPhone.")
            }
    }
    private func disconnectedRecording(now: Date) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.largeTitle)
                Text(store.recordingState.message).font(.headline)
                Text(store.recordingState == .recording
                     ? "iPhone session state is unavailable. Established Watch collection continues; phone controls wait for a fresh connection."
                     : store.recordingState == .paused
                     ? "Watch collection is paused. Open iPhone to confirm the current session state."
                     : "Open iPhone for current session controls. Watch workout status is shown above.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let heart = store.heart?.heartRate(at: now) {
                    Label("\(Int(heart.rounded())) BPM", systemImage: "heart.fill").foregroundStyle(.red)
                }
                Text(store.telemetryStatusText).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Reconnect") { store.link.request() }.buttonStyle(.bordered)
                if store.recordingState != .saving {
                    Button("Stop Watch recording", systemImage: "stop.circle") { store.stopLocalRecording() }
                        .buttonStyle(.bordered).tint(.orange).accessibilityIdentifier("watch-stop-local-recording")
                    Text("Your iPhone session stays open.").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12)
        }.accessibilityIdentifier("watch-disconnected-recording")
    }

    private func metrics(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(exerciseName(snapshot)).font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(snapshot.setNumber)/\(snapshot.configured?.totalSets ?? 3)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityLabel(setDescription(snapshot))
            }
            if snapshot.phase == .finished {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Session complete").font(.headline)
                Text("Your review is on iPhone.").font(.caption)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(quantity(snapshot)).font(.system(size: min(countFontSize, 48), weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text("/ \(snapshot.target)\(snapshot.configured?.unit == .seconds ? " s" : "")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.accessibilityIdentifier("watch-quantity")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Quantity and target")
                    .accessibilityValue(quantity(snapshot) == "—" ? "No quantity entered. Target \(snapshot.target) \(snapshot.configured?.unit == .seconds ? "seconds" : "reps")." : "\(quantity(snapshot)) of \(snapshot.target) \(snapshot.configured?.unit == .seconds ? "seconds" : "reps")")
                HStack(spacing: 6) {
                    let heartRate = store.heart?.heartRate(at: now)
                    Label(heartRate.map { "\(Int($0.rounded())) BPM" } ?? "— BPM", systemImage: "heart.fill")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().lineLimit(1)
                        .foregroundStyle(heartRate == nil ? Color.gray : Color.red)
                        .accessibilityLabel(heartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "No recent heart-rate reading")
                        .accessibilityIdentifier("watch-heart-rate")
                    Spacer(minLength: 0)
                    recordingControl(snapshot, compact: true)
                }
                Text(instruction(snapshot)).font(.system(size: 11)).multilineTextAlignment(.center).lineLimit(2)
                    .foregroundStyle(snapshot.configured?.stoppedForDiscomfort == true ? Color.red : Color.white)
                    .accessibilityLabel(instruction(snapshot))
            }
        }.padding(.horizontal, 12).padding(.vertical, 4).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("watch-metrics-page")
    }
    private func controls(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        ScrollView {
            VStack(spacing: 11) {
                Text("Controls").font(.headline)
                if snapshot.configured?.stoppedForDiscomfort != true, snapshot.configured?.currentWasSkipped != true {
                    Text(snapshot.cameraRecoveryState?.message ?? store.status ?? store.recordingState.message).font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                if [.active, .paused, .rest].contains(snapshot.phase) {
                    VStack(spacing: 10) {
                        if snapshot.configured?.stoppedForDiscomfort == true {
                            Text("Stop here and recover.").font(.caption).foregroundStyle(.red)
                        } else if snapshot.configured?.currentWasSkipped == true {
                            Text("Set skipped. Check in on iPhone.").font(.caption)
                        } else if snapshot.phase == .rest {
                            Button("Next set", systemImage: "forward.end.fill") { store.command(.nextSet) }.buttonStyle(.borderedProminent)
                        } else if snapshot.configured?.hasStarted == false {
                            Button("Start set", systemImage: "play.fill") { store.command(.startSet) }.buttonStyle(.borderedProminent)
                        } else {
                            Button(snapshot.pauseResumeTitle, systemImage: snapshot.phase == .paused || snapshot.cameraRecoveryState == .needsResume ? "play.fill" : "pause.fill") {
                                store.command(snapshot.phase == .paused || snapshot.cameraRecoveryState == .needsResume ? .resume : .pause)
                            }.buttonStyle(.borderedProminent).tint(snapshot.phase == .paused || snapshot.cameraRecoveryState == .needsResume ? .green : .orange)
                            Button("End set", systemImage: "checkmark") { store.command(.endSet) }.buttonStyle(.bordered)
                                .disabled(snapshot.configured?.canEndSet == false || (snapshot.configured == nil && snapshot.source == .manual && snapshot.reps == 0))
                        }
                        Button("End session", systemImage: "xmark") { store.command(.finish) }
                            .buttonStyle(.bordered).tint(.red).accessibilityIdentifier("watch-end-session")
                    }.disabled(!store.reachable)
                    if !store.reachable { Text("Open iPhone to reconnect.").font(.caption2).foregroundStyle(.secondary) }
                }
                recordingControl(snapshot)
                if store.recordingBusy, store.recordingState != .saving {
                    Button("Stop Watch recording", systemImage: "stop.circle") { store.stopLocalRecording() }
                        .buttonStyle(.bordered).tint(.orange).accessibilityIdentifier("watch-stop-local-recording")
                    Text("Stops Watch collection. Your iPhone session stays open.").font(.caption2).foregroundStyle(.secondary)
                }
                Text(store.telemetryStatusText).font(.caption2).foregroundStyle(.secondary)
                if store.recording, store.heart?.heartRate(at: now) == nil {
                    Text("No recent heart-rate reading. Check Watch fit and Health access.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

            }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
        }.accessibilityIdentifier("watch-controls-page")
    }
    private func vitals(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live vitals").font(.headline)
                let heart = store.heart?.heartRate(at: now)
                Label(heart.map { "\(Int($0.rounded())) bpm" } ?? "No recent pulse", systemImage: "heart.fill")
                    .font(.title2.bold()).foregroundStyle(heart == nil ? .gray : .red)
                let energy = store.activeEnergy.flatMap { $0.isValid(at: now) && now.timeIntervalSince($0.asOf) <= 12 ? $0.kilocalories : nil }
                Label(energy.map { "\(Int($0.rounded())) active kcal" } ?? "No recent energy", systemImage: "flame")
                    .font(.body).foregroundStyle(.orange)
                metric("Instant wrist acceleration", reading: store.acceleration, unit: "g", now: now)
                metric("Instant angular speed", reading: store.rotation, unit: "rad/s", now: now)
                if let window = store.latestMotionWindow, (-2...12).contains(now.timeIntervalSince(window.end)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wrist window · \(window.sampleCount) samples").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "RMS %.2f g · peak %.2f g", window.rmsAccelerationG, window.peakAccelerationG)).font(.caption)
                        Text(String(format: "Mean %.2f rad/s", window.meanRotationRadiansPerSecond)).font(.caption)
                    }
                }
                Text(store.recordingState.message).font(.caption2).foregroundStyle(.secondary)
                Text(store.telemetryStatusText).font(.caption2).foregroundStyle(.secondary)
                Text("Energy is cumulative for this Watch recording. Missing or old readings stay blank.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !store.recordingBusy { recordingControl(snapshot) }
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }.accessibilityIdentifier("watch-vitals-page")
    }
    private func metric(_ title: String, reading: SensorReading?, unit: String, now: Date) -> some View {
        let value = reading.flatMap { reading in
            reading.value.isFinite && reading.value >= 0 && (-2...12).contains(now.timeIntervalSince(reading.date)) ? reading.value : nil
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f %@", $0, unit) } ?? "—").font(.body).monospacedDigit()
        }
    }
    @ViewBuilder private func recordingControl(_ snapshot: CompanionSnapshot, compact: Bool = false) -> some View {
        if snapshot.configured?.stoppedForDiscomfort != true, snapshot.configured?.currentWasSkipped != true {
            if store.recordingBusy {
                if compact {
                    Text(store.recording ? (store.recordingState == .paused ? "Paused" : "Recording") : (store.recordingState == .saving ? "Saving…" : "Starting…"))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityLabel(store.recordingState.message)
                }
            } else if [.active, .rest].contains(snapshot.phase) {
                Button(compact ? "Record" : "Start Watch workout", systemImage: "heart") {
                    store.record()
                    if compact { page = .controls }
                }
                    .buttonStyle(.bordered).controlSize(.small).font(compact ? .system(size: 11) : .caption2)
                    .accessibilityLabel("Start Watch workout")
                    .accessibilityIdentifier(compact ? "watch-start-workout" : "watch-start-workout-controls")
            }
        }
    }
    private func exerciseName(_ snapshot: CompanionSnapshot) -> String {
        snapshot.configured.flatMap { ExerciseCatalog.find($0.exerciseID)?.name } ?? snapshot.exercise?.title ?? "Workout"
    }
    private func setDescription(_ snapshot: CompanionSnapshot) -> String {
        "Set \(snapshot.setNumber) of \(snapshot.configured?.totalSets ?? 3)"
    }
    private func quantity(_ snapshot: CompanionSnapshot) -> String {
        guard let configured = snapshot.configured else {
            return snapshot.source == .manual && snapshot.reps == 0 ? "—" : "\(snapshot.reps)"
        }
        if configured.unit == .seconds { return configured.displaySeconds.map { "\(Int($0))" } ?? "—" }
        if configured.source == .camera { return "\(snapshot.reps)" }
        return configured.enteredReps.map(String.init) ?? "—"
    }
    private func instruction(_ snapshot: CompanionSnapshot) -> String {
        if let manual = snapshot.manualRepInstruction { return manual }
        guard let configured = snapshot.configured else {
            if snapshot.phase == .rest { return "Take a breather." }
            return snapshot.exercise.map { MovementFeedback.text(snapshot.cue, exercise: $0) } ?? shortCue(snapshot.cue)
        }
        if configured.stoppedForDiscomfort { return "Stop here. Finish this session and recover." }
        if configured.currentWasSkipped == true { return "Set skipped. Check in on iPhone." }
        if snapshot.phase == .rest { return "Rest \(Int(configured.restElapsed ?? 0)) s, suggested \(configured.restTarget) s" }
        if !configured.hasStarted { return "Start when ready." }
        if snapshot.phase == .paused { return "Paused. Resume when you’re ready." }
        if configured.source == .camera, let exercise = Exercise(rawValue: configured.exerciseID) { return MovementFeedback.text(snapshot.cue, exercise: exercise) }
        return configured.unit == .reps ? "Enter reps on iPhone." : "Hold timer running."
    }
    private func shortCue(_ cue: Cue) -> String {
        switch cue {
        case .ready, .tracking: return "Show your full body."
        case .lower: return "Lower with control."
        case .rise: return "Drive back up."
        case .hold: return "Hold at depth. Stay steady."
        case .alignment: return "Brace a straight body."
        case .controlled: return "Strong rep. Stay steady."
        case .paused: return "Paused. Take a breath."
        }
    }
}
