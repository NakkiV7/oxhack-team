import SwiftUI

struct ConfiguredSessionView: View {
    @Bindable var store: TrainingStore
    @State private var ending = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if store.configured?.phase == .finished { store.presented = false }
                    else { ending = true }
                } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Finish custom session")
                Spacer()
                if let run = store.configured {
                    VStack(spacing: 4) {
                        Text(run.phase == .finished ? "Your session" : run.current.entry.name).font(.headline)
                        if run.phase != .finished {
                            Text("Set \(run.current.number) of \(run.current.totalSets) · \(run.index + 1) of \(run.steps.count) planned")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.multilineTextAlignment(.center)
                }
                Spacer()
                Image(systemName: "list.bullet.clipboard").frame(width: 44, height: 44)
            }.padding(.horizontal, 14).padding(.top, 8)
            if let run = store.configured {
                switch run.phase {
                case .active, .paused: ConfiguredLiveSetView(store: store).id(run.current.id)
                case .rest: ConfiguredRecoveryView(store: store).id(run.current.id)
                case .finished: ConfiguredFinishedView(store: store)
                case .idle: ProgressView()
                }
            }
        }.background(.white).foregroundStyle(Palette.ink)
            .confirmationDialog("Finish this session?", isPresented: $ending) {
                Button("Finish and save ended sets") { store.finish() }
                Button("Keep training", role: .cancel) {}
            } message: { Text("Only sets you explicitly ended are saved. The current unended set and remaining plan are left out.") }
    }
}

private struct ConfiguredLiveSetView: View {
    @Bindable var store: TrainingStore
    @State private var quantity = ""
    @FocusState private var enteringReps: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if let run = store.configured {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(run.current.unit == .seconds ? clockText(run.elapsed(at: store.now)) : run.manualReps.map(String.init) ?? "—")
                                .font(.system(size: 66, weight: .semibold, design: .rounded)).monospacedDigit()
                                .accessibilityIdentifier("configured-quantity")
                            Text("/ \(run.current.target) \(run.current.unit == .seconds ? "sec" : "reps")").foregroundStyle(.secondary)
                            Spacer()
                            Label(store.heartRate(at: context.date), systemImage: "heart").font(.caption)
                        }
                        Group {
                            if UIImage(named: run.current.entry.art) != nil {
                                Image(run.current.entry.art).resizable().scaledToFit()
                            } else {
                                Image(systemName: "figure.strengthtraining.traditional").resizable().scaledToFit().padding(30)
                            }
                        }.frame(maxWidth: .infinity).frame(height: 210).padding(20)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 23))
                            .accessibilityLabel(run.current.entry.name)
                        Text(run.current.entry.instruction).font(.headline)
                        Label(run.current.unit == .seconds ? "Manual hold · active timer" : "Manual self-report", systemImage: "hand.tap")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(status(run)).font(.subheadline).accessibilityIdentifier("configured-status")
                        if run.hasStarted, run.current.unit == .reps {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Actual completed reps").font(.subheadline.weight(.semibold))
                                TextField("Enter reps", text: $quantity).keyboardType(.numberPad).focused($enteringReps)
                                    .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityIdentifier("configured-reps")
                                    .onChange(of: quantity) { _, value in store.setConfiguredReps(Int(value)) }
                                if enteringReps { Button("Done entering reps") { enteringReps = false }.font(.caption) }
                                Text("Enter 1–200 reps you actually completed. Your target is not filled in for you.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if run.hasStarted {
                            Text("Active set time: \(clockText(run.elapsed(at: store.now)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Stop for pain or discomfort") { enteringReps = false; store.stopConfiguredForDiscomfort() }
                            .font(.subheadline).foregroundStyle(Palette.red)
                    }.padding(24)
                }.scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 12) {
                            if !run.hasStarted {
                                PrimaryButton(title: run.current.unit == .seconds ? "Start hold" : "Start set", symbol: "play", action: store.beginConfiguredSet)
                                    .accessibilityIdentifier("configured-start")
                            } else {
                                Button(run.phase == .paused ? "Resume" : "Pause") { run.phase == .paused ? store.resume() : store.pause() }
                                    .font(.subheadline.weight(.medium)).padding(18)
                                PrimaryButton(title: "End set", symbol: "checkmark") { enteringReps = false; store.endSet() }
                                    .disabled(!run.canEndSet(at: store.now)).accessibilityIdentifier("configured-end")
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 12).background(.white)
                    }
            }
        }
    }
    private func status(_ run: ConfigurableSession) -> String {
        if !run.hasStarted { return "Get into position, then start. Preparation time is left out." }
        if run.phase == .paused { return "Your set is paused. Resume when you’re ready." }
        if run.current.unit == .seconds { return "Only active hold seconds count. Pause whenever you stop holding. End the set yourself." }
        return "Complete your reps, enter the actual count, then end this set."
    }
}

private struct ConfiguredRecoveryView: View {
    @Bindable var store: TrainingStore
    @State private var reserve: Int?
    @State private var reason: StopReason = .voluntary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let run = store.configured, let rest = run.restElapsed(at: store.now) {
                        VStack(spacing: 9) {
                            Text("Suggested rest · \(run.current.restSeconds) sec").font(.caption).foregroundStyle(.secondary)
                            Text(clockText(max(0, Double(run.current.restSeconds) - rest)))
                                .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("\(Int(rest)) seconds of actual rest · take longer if needed").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                if store.configured?.stoppedForDiscomfort == true {
                    Label("Stop here. Finish this session and give yourself time to recover.", systemImage: "hand.raised")
                        .font(.headline).accessibilityIdentifier("configured-stop")
                } else {
                    if store.configured?.current.unit == .reps {
                        Text("How many clean reps were left?").font(.headline)
                        HStack {
                            ForEach(0..<4) { count in
                                Button(count == 3 ? "3+" : "\(count)") { reserve = count; feedback() }
                                    .padding(16).background(reserve == count ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(reserve == count ? .white : Palette.ink)
                            }
                            Button("Skip") { reserve = nil; feedback() }.font(.caption)
                        }
                    }
                    Picker("Why did you stop?", selection: $reason) {
                        ForEach(StopReason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.onChange(of: reason) { _, _ in feedback() }
                    PrimaryButton(title: isLast ? "Review session" : "Ready for next set", symbol: "arrow.right", action: store.next)
                        .accessibilityIdentifier("configured-next")
                    Text("The next set starts only when you choose Start. Rest timing never starts a set automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Finish session", action: store.finish).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
            }.padding(24)
        }.onAppear { reason = store.configured?.completed.last?.reason ?? .voluntary }
    }
    private var isLast: Bool { store.configured.map { $0.index + 1 == $0.steps.count } ?? false }
    private func feedback() { store.feedback(reserve: reserve, reason: reason) }
}

private struct ConfiguredFinishedView: View {
    let store: TrainingStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                if let run = store.configured {
                    Text("That’s your session.").font(.system(size: 32, weight: .bold)).padding(.top, 25)
                    Text(run.completed.isEmpty ? "No ended sets to save." : (store.error == nil ? "Session saved on this iPhone." : "Save interrupted."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Metric(value: "\(run.completed.count)", title: "Sets ended", symbol: "square.3.layers.3d")
                        Metric(value: "\(run.record.reps)", title: "Reps", symbol: "repeat")
                        Metric(value: clockText(run.record.activeSeconds), title: "Active time", symbol: "clock")
                    }
                    ForEach(run.completed) { set in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(ExerciseCatalog.find(set.exerciseID)?.name ?? set.exerciseID) · Set \(set.number ?? 1)").font(.headline)
                            Text("\(set.seconds > 0 ? "\(Int(set.seconds)) sec" : "\(set.reps) reps") · \(set.quantityOrigin == .activeTimer ? "active hold timer" : "manual self-report")")
                                .font(.subheadline)
                            Text(set.reason.title).font(.caption).foregroundStyle(.secondary)
                            if let rest = set.restSecondsBefore { Text("\(Int(rest)) sec recorded rest before this set").font(.caption).foregroundStyle(.secondary) }
                        }
                        Divider()
                    }
                }
                if let error = store.error {
                    Text(error).font(.caption).foregroundStyle(Palette.red)
                    PrimaryButton(title: "Retry save", symbol: "arrow.clockwise", action: store.save)
                }
                PrimaryButton(title: "Done", symbol: "checkmark") { store.presented = false }
            }.padding(24)
        }
    }
}
