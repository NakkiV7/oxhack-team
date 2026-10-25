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
                        controls(snapshot).tag(Page.controls)
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
                     ? "Only ended sets are saved. The current unfinished set will be discarded."
                     : "Finish this session and save your completed work on iPhone.")
            }
    }
    private func metrics(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        ScrollView {
            VStack(spacing: 9) {
                Text(snapshot.configured.flatMap { ExerciseCatalog.find($0.exerciseID)?.name } ?? snapshot.exercise?.title ?? "Workout")
                    .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                if snapshot.phase == .finished {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("Session complete").font(.headline)
                    Text("Your review is on iPhone.").font(.caption)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(quantity(snapshot)).font(.system(size: countFontSize, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("/ \(snapshot.target)\(snapshot.configured?.unit == .seconds ? " s" : "")").font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("watch-quantity")
                    let heartRate = store.heart?.heartRate(at: now)
                    Label(heartRate.map { "\(Int($0.rounded())) BPM" } ?? "— BPM", systemImage: "heart.fill")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(heartRate == nil ? Color.gray : Color.red)
                        .accessibilityIdentifier("watch-heart-rate")
                    Text(instruction(snapshot)).font(.caption2).multilineTextAlignment(.center)
                        .foregroundStyle(snapshot.configured?.stoppedForDiscomfort == true ? Color.red : Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Set \(snapshot.setNumber)\(snapshot.configured.map { " of \($0.totalSets)" } ?? " of 3")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
        }.accessibilityIdentifier("watch-metrics-page")
    }
    private func controls(_ snapshot: CompanionSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 11) {
                Text("Controls").font(.headline)
                if [.active, .paused, .rest].contains(snapshot.phase) {
                    VStack(spacing: 10) {
                        if snapshot.configured?.stoppedForDiscomfort == true {
                            Text("Stop here and recover.").font(.caption).foregroundStyle(.red)
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
                    if !store.recordingBusy {
                        Button("Record workout", systemImage: "heart") { store.record() }
                            .buttonStyle(.bordered).disabled(snapshot.phase == .paused)
                    }
                }
                Text(store.status ?? store.recordingState.message).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if store.recording, store.heart?.heartRate(at: Date()) == nil {
                    Text("No recent heart-rate reading. Check Watch fit and Health access.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 6)
        }.accessibilityIdentifier("watch-controls-page")
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
