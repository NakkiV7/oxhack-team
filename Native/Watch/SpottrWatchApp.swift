import SwiftUI

@main
struct SpottrWatchApp: App {
    @State private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            WatchTrainingView(store: store).preferredColorScheme(.light)
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
    let store: WatchStore
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize: CGFloat = 36
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(spacing: 7) {
                        if let snapshot = store.state.snapshot, snapshot.isFresh(at: context.date), snapshot.phase != .idle {
                            content(snapshot, now: context.date)
                        } else {
                            Text("Spottr").font(.system(size: 15, weight: .bold, design: .rounded))
                            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 33, weight: .light)).padding(.vertical, 10)
                            Text("Open Spottr on iPhone").font(.headline)
                            Button("Reconnect") { store.link.request() }.buttonStyle(.bordered)
                        }
                        if let status = store.status { Text(status).font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 10).padding(.bottom, 15)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let snapshot = store.state.snapshot, snapshot.isFresh(at: context.date),
                       [.active, .paused, .rest].contains(snapshot.phase) {
                        HStack(spacing: 5) {
                            if snapshot.configured?.stoppedForDiscomfort == true {
                                Button("Finish") { store.command(.finish) }.buttonStyle(.borderedProminent).foregroundStyle(.white)
                            } else if snapshot.phase == .rest {
                                Button("Next set") { store.command(.nextSet) }.buttonStyle(.borderedProminent).foregroundStyle(.white)
                            } else if snapshot.configured?.hasStarted == false {
                                Button("Start set") { store.command(.startSet) }.buttonStyle(.borderedProminent).foregroundStyle(.white)
                            } else {
                                Button(snapshot.phase == .paused ? "Resume" : "Pause") { store.command(snapshot.phase == .paused ? .resume : .pause) }
                                    .buttonStyle(.borderedProminent).foregroundStyle(.white)
                                Button("End set") { store.command(.endSet) }.buttonStyle(.bordered)
                                    .disabled(snapshot.configured?.canEndSet == false)
                            }
                        }.font(.caption2).disabled(!store.reachable).padding(.horizontal, 6).padding(.vertical, 4).background(.white)
                    }
                }.foregroundStyle(.black).containerBackground(.white, for: .navigation)
            }
        }.tint(.black)
    }
    @ViewBuilder private func content(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        if snapshot.phase == .finished {
            Text("Spottr").font(.system(size: 15, weight: .bold, design: .rounded))
            Image(systemName: "checkmark.circle").font(.largeTitle)
            Text("Session complete").font(.headline)
            Text("Your review is on iPhone.").font(.caption)
        } else {
            let exerciseName = snapshot.configured.flatMap { ExerciseCatalog.find($0.exerciseID)?.name } ?? snapshot.exercise?.title ?? "Workout"
            VStack(spacing: 3) {
                Text("Spottr · \(exerciseName)").font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(quantity(snapshot)).font(.system(size: countFontSize, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("/ \(snapshot.target)\(snapshot.configured?.unit == .seconds ? " s" : "")").font(.subheadline).foregroundStyle(.secondary)
                }
                Label(store.heart?.heartRate(at: now).map { "\(Int($0.rounded())) bpm" } ?? "— bpm", systemImage: "heart").font(.caption)
                Text(instruction(snapshot)).font(.caption2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !store.recording {
                    Button("Record workout") { store.record() }.font(.caption).buttonStyle(.bordered)
                }
                if snapshot.configured != nil, snapshot.configured?.stoppedForDiscomfort != true {
                    Button("Finish session") { store.command(.finish) }.font(.caption2)
                    Text("Only ended sets are saved.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func quantity(_ snapshot: CompanionSnapshot) -> String {
        guard let configured = snapshot.configured else { return "\(snapshot.reps)" }
        if configured.unit == .seconds { return "\(Int(configured.activeSeconds))" }
        return configured.enteredReps.map(String.init) ?? "—"
    }
    private func instruction(_ snapshot: CompanionSnapshot) -> String {
        guard let configured = snapshot.configured else { return snapshot.phase == .rest ? "Take a breather." : snapshot.cue.text }
        if configured.stoppedForDiscomfort { return "Stop here. Finish this session and recover." }
        if snapshot.phase == .rest { return "Rest \(Int(configured.restElapsed ?? 0)) s · suggested \(configured.restTarget) s" }
        if !configured.hasStarted { return "Start when you’re in position." }
        if snapshot.phase == .paused { return "Paused. Resume when you’re ready." }
        return configured.unit == .reps ? "Enter actual reps on iPhone before ending this set." : "Active hold timer. End the set when you stop."
    }
}
