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
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
        }
    }
}

struct WatchTrainingView: View {
    private enum Page: Hashable { case metrics, controls }
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
                    }.tabViewStyle(.verticalPage)
                        .containerBackground(.black, for: .tabView)
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
                    .accessibilityValue(quantity(snapshot) == "—" ? "No count entered. Target \(snapshot.target) reps." : "\(quantity(snapshot)) of \(snapshot.target) \(snapshot.configured?.unit == .seconds ? "seconds" : "reps")")
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
                    Text(store.status ?? store.recordingState.message).font(.caption2).foregroundStyle(.secondary)
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
                            Button(snapshot.phase == .paused ? "Resume" : "Pause", systemImage: snapshot.phase == .paused ? "play.fill" : "pause.fill") {
                                store.command(snapshot.phase == .paused ? .resume : .pause)
                            }.buttonStyle(.borderedProminent).tint(snapshot.phase == .paused ? .green : .orange)
                            Button("End set", systemImage: "checkmark") { store.command(.endSet) }.buttonStyle(.bordered)
                                .disabled(snapshot.configured?.canEndSet == false || (snapshot.configured == nil && snapshot.source == .manual && snapshot.reps == 0))
                        }
                        Button("End session", systemImage: "xmark") { store.command(.finish) }
                            .buttonStyle(.bordered).tint(.red).accessibilityIdentifier("watch-end-session")
                    }.disabled(!store.reachable)
                    if !store.reachable { Text("Open iPhone to reconnect.").font(.caption2).foregroundStyle(.secondary) }
                }
                recordingControl(snapshot)
                if store.recording, store.heart?.heartRate(at: now) == nil {
                    Text("No recent heart-rate reading. Check Watch fit and Health access.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session details").font(.headline)
                    Text(exerciseName(snapshot)).font(.body)
                    Text(setDescription(snapshot)).font(.body)
                    if snapshot.phase == .finished {
                        Text("Session complete. Your review is on iPhone.").font(.body)
                    } else {
                        Text(quantity(snapshot) == "—" ? "No count entered. Target \(snapshot.target) reps." : "\(quantity(snapshot)) / \(snapshot.target) \(snapshot.configured?.unit == .seconds ? "seconds" : "reps")")
                            .font(.title3).monospacedDigit()
                        let heartRate = store.heart?.heartRate(at: now)
                        Label(heartRate.map { "\(Int($0.rounded())) BPM" } ?? "No recent heart-rate reading", systemImage: "heart.fill")
                            .font(.body).foregroundStyle(heartRate == nil ? Color.gray : Color.red)
                        Text(instruction(snapshot)).font(.body)
                            .foregroundStyle(snapshot.configured?.stoppedForDiscomfort == true ? Color.red : Color.white)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("watch-session-details")
            }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
        }.accessibilityIdentifier("watch-controls-page")
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
        if configured.unit == .seconds { return "\(Int(configured.activeSeconds))" }
        if configured.source == .camera { return "\(snapshot.reps)" }
        return configured.enteredReps.map(String.init) ?? "—"
    }
    private func instruction(_ snapshot: CompanionSnapshot) -> String {
        if let manual = snapshot.manualRepInstruction { return manual }
        guard let configured = snapshot.configured else {
            if snapshot.phase == .rest { return "Take a breather." }
            return shortCue(snapshot.cue)
        }
        if configured.stoppedForDiscomfort { return "Stop here. Finish this session and recover." }
        if configured.currentWasSkipped == true { return "Set skipped. Check in on iPhone." }
        if snapshot.phase == .rest { return "Rest \(Int(configured.restElapsed ?? 0)) s · suggested \(configured.restTarget) s" }
        if !configured.hasStarted { return "Start when ready." }
        if snapshot.phase == .paused { return "Paused. Resume when you’re ready." }
        if configured.source == .camera { return shortCue(snapshot.cue) }
        return configured.unit == .reps ? "Enter reps on iPhone." : "Hold timer running."
    }
    private func shortCue(_ cue: Cue) -> String {
        switch cue {
        case .ready, .tracking: return "Show your full body."
        case .lower: return "Lower with control."
        case .rise: return "Drive back up."
        case .alignment: return "Brace a straight body."
        case .controlled: return "Strong rep. Stay steady."
        case .paused: return "Paused. Take a breath."
        }
    }
}
