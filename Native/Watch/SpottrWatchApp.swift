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
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(spacing: 7) {
                        Text("Spottr").font(.system(size: 15, weight: .bold, design: .rounded))
                        if let snapshot = store.state.snapshot, snapshot.isFresh(at: context.date), snapshot.phase != .idle {
                            content(snapshot, now: context.date)
                        } else {
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
                            if snapshot.phase == .rest {
                                Button("Next set") { store.command(.nextSet) }.buttonStyle(.borderedProminent)
                            } else {
                                Button(snapshot.phase == .paused ? "Resume" : "Pause") { store.command(snapshot.phase == .paused ? .resume : .pause) }
                                    .buttonStyle(.borderedProminent)
                                Button("End set") { store.command(.endSet) }.buttonStyle(.bordered)
                            }
                        }.font(.caption2).disabled(!store.reachable).padding(.horizontal, 6).padding(.vertical, 4).background(.white)
                    }
                }.foregroundStyle(.black).containerBackground(.white, for: .navigation)
            }
        }.tint(.black)
    }
    @ViewBuilder private func content(_ snapshot: CompanionSnapshot, now: Date) -> some View {
        if snapshot.phase == .finished {
            Image(systemName: "checkmark.circle").font(.largeTitle)
            Text("Session complete").font(.headline)
            Text("Your review is on iPhone.").font(.caption)
        } else {
            Text(snapshot.exercise.title).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.reps)").font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("/ \(snapshot.target)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(snapshot.phase == .rest ? "Take a breather." : snapshot.cue.text).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
            Label(store.heart?.heartRate(at: now).map { "\(Int($0.rounded())) bpm" } ?? "— bpm", systemImage: "heart").font(.caption)
            if !store.recording {
                Button("Record workout") { store.record() }.font(.caption).buttonStyle(.bordered)
            }
        }
    }
}
