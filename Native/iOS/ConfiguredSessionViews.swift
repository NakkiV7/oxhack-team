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
            if let run = store.configured, run.source == .camera, [.active, .paused, .rest].contains(run.phase) {
                Toggle("Voice feedback", isOn: Binding(get: { store.voiceFeedbackEnabled }, set: { store.setVoiceFeedback($0) }))
                    .font(.caption).accessibilityIdentifier("configured-voice-toggle")
                    .padding(.horizontal, 24).padding(.vertical, 6)
            }
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
                Button(store.configured?.skippedSets.isEmpty == false ? "Finish and save session" : "Finish and save ended sets") { store.finish() }
                Button("Keep training", role: .cancel) {}
            } message: { Text("Only sets you explicitly ended count as completed work. Skipped steps are saved separately. The current unended set and remaining plan are left out.") }
    }
}

private struct ConfiguredLiveSetView: View {
    @Bindable var store: TrainingStore
    @State private var quantity = ""
    @State private var pendingInput: TrainingStore.ConfiguredInput?
    @State private var pairingPresented = false
    @FocusState private var enteringReps: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if let run = store.configured {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(run.current.unit == .seconds ? clockText(run.elapsed(at: store.now)) : run.actualReps.map(String.init) ?? "—")
                                .font(.system(size: 66, weight: .semibold, design: .rounded)).monospacedDigit()
                                .accessibilityIdentifier("configured-quantity")
                            Text("/ \(run.current.target) \(run.current.unit == .seconds ? "sec" : (run.current.target == 1 ? "rep" : "reps"))").foregroundStyle(.secondary)
                            Spacer()
                            let heartRate = store.heartRate(at: context.date)
                            Label { Text(heartRate) } icon: {
                                Image(systemName: "heart").foregroundStyle(heartRate == "—" ? Palette.muted : Palette.red)
                            }.font(.caption)
                        }
                        inputControl(run)
                        preview(run)
                        Text(run.current.entry.instruction).font(.headline)
                        Label(run.source == .camera ? "Camera observation" : (run.current.unit == .seconds ? "Manual hold · active timer" : "Manual self-report"), systemImage: run.source == .camera ? "camera" : "hand.tap")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(status(run)).font(.subheadline).accessibilityIdentifier("configured-status")
                        if run.source == .camera, run.hasStarted {
                            Text(store.visionState.message).font(.caption).foregroundStyle(.secondary)
                            Text(store.coachingEvent?.decision.text ?? run.cue.text)
                                .font(.headline).foregroundStyle(Palette.coaching(store.coachingEvent?.decision, cue: run.cue))
                                .accessibilityIdentifier("configured-coaching-cue")
                            Text("Observed reps stay separate from your target. End this set yourself.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if run.source == .manual, run.hasStarted, run.current.unit == .reps {
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
                        VStack(spacing: 8) {
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
                        }
                        if run.canSkipSet(at: store.now) {
                            Button("Skip set / stop here") { enteringReps = false; store.skipConfiguredSet() }
                                .font(.subheadline.weight(.medium)).foregroundStyle(Palette.blue)
                                .accessibilityIdentifier("configured-skip")
                        }
                        }.padding(.horizontal, 24).padding(.vertical, 12).background(.white)
                    }
                    .onChange(of: run.generation) { _, _ in
                        if !run.hasStarted { quantity = ""; enteringReps = false }
                    }
            }
        }
        .alert("Reset this unfinished set?", isPresented: Binding(get: { pendingInput != nil }, set: { if !$0 { pendingInput = nil } })) {
            if let input = pendingInput {
                Button("Reset and switch", role: .destructive) {
                    store.selectConfiguredInput(input)
                    pendingInput = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingInput = nil }
        } message: { Text("This set’s unsaved reps and active time will be discarded. Ended sets stay saved. Start the new input when you’re ready.") }
        .sheet(isPresented: $pairingPresented) { SecondaryCameraSettingsView() }
    }
    @ViewBuilder private func inputControl(_ run: ConfigurableSession) -> some View {
        if run.trackingExercise != nil {
            Menu {
                ForEach(TrainingStore.ConfiguredInput.allCases, id: \.self) { input in
                    Button(input.title) {
                        guard input != store.configuredInput else { return }
                        enteringReps = false
                        if run.hasStarted { pendingInput = input }
                        else { store.selectConfiguredInput(input) }
                    }.accessibilityIdentifier("configured-input-\(input.rawValue)")
                }
                Divider()
                Button("Pair side camera", systemImage: "link") { store.pause(); pairingPresented = true }
            } label: {
                Label(store.configuredInput.title, systemImage: run.source == .camera ? "camera" : "hand.tap")
                    .font(.subheadline.weight(.medium))
            }.accessibilityIdentifier("configured-input-menu")
        }
    }
    private func preview(_ run: ConfigurableSession) -> some View {
        ZStack {
            Palette.surface
            if run.source == .camera, run.hasStarted, run.phase == .active,
               case .camera = store.visionState, !store.usingSecondaryCamera {
                CameraPreview(session: store.vision.capture)
            } else if let image = store.image, run.source == .camera {
                Image(uiImage: image).resizable().scaledToFit()
            } else if UIImage(named: run.current.entry.art) != nil {
                Image(run.current.entry.art).resizable().scaledToFit().padding(20)
            } else {
                Image(systemName: "figure.strengthtraining.traditional").resizable().scaledToFit().padding(30)
            }
            if let frame = store.frame, let exercise = run.trackingExercise, run.source == .camera {
                PoseOverlay(frame: frame, exercise: exercise)
            }
        }.frame(maxWidth: .infinity).frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 23))
            .accessibilityLabel(run.current.entry.name)
    }
    private func status(_ run: ConfigurableSession) -> String {
        if !run.hasStarted {
            return run.source == .camera ? "Get your full body in view, then Start to open the selected camera. Preparation time is left out." : "Get into position, then start. Preparation time is left out."
        }
        if run.phase == .paused { return "Your set is paused. Resume when you’re ready, or switch input to reset this unfinished set." }
        if run.current.unit == .seconds { return "Only active hold seconds count. Pause whenever you stop holding. End the set yourself." }
        return run.source == .camera ? "Keep your full body visible for camera form tracking." : "Complete your reps, enter the actual count, then end this set."
    }
}

struct ConfiguredRecoveryView: View {
    @Bindable var store: TrainingStore
    @State private var reserve: Int?
    @State private var reason: StopReason = .voluntary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let run = store.configured, !run.currentWasSkipped, let rest = run.restElapsed(at: store.now) {
                        VStack(spacing: 9) {
                            Text("Suggested rest · \(run.current.restSeconds) sec").font(.caption).foregroundStyle(.secondary)
                            Text(clockText(max(0, Double(run.current.restSeconds) - rest)))
                                .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("\(Int(rest)) seconds of actual rest · take longer if needed").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                if store.configured?.currentWasSkipped == true {
                    Label("It’s okay to stop here.", systemImage: "hand.raised").font(.headline)
                    Text(continuationGuidance).font(.subheadline).foregroundStyle(.secondary)
                    PrimaryButton(title: "Finish session", symbol: "checkmark", action: store.finish)
                    if !isLast {
                        Button("Choose the next planned set", action: store.next)
                            .font(.subheadline.weight(.medium)).foregroundStyle(Palette.blue)
                            .accessibilityIdentifier("configured-next-after-skip")
                        Text("Only continue if you choose to. The next set still needs an explicit Start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if store.configured?.stoppedForDiscomfort == true {
                    Label("Stop here. Finish this session and give yourself time to recover.", systemImage: "hand.raised")
                        .font(.headline).foregroundStyle(Palette.red).accessibilityIdentifier("configured-stop")
                } else {
                    if store.configured?.canReduceRemainingRepTargets == true {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("One rep recorded. You can stop here.").font(.headline)
                            Text("If you choose to continue, you can make the remaining sets of this exercise one rep each. No sets are added and no workout starts automatically.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Use 1 rep for remaining \(store.configured?.current.entry.name ?? "exercise") sets") {
                                store.useOneRepForRemainingConfiguredSets()
                            }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue)
                                .accessibilityIdentifier("configured-one-rep-targets")
                        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if store.configured?.current.unit == .reps {
                        Text("How many clean reps were left?").font(.headline)
                        HStack {
                            ForEach(0..<4) { count in
                                Button(count == 3 ? "3+" : "\(count)") { reserve = count; feedback() }
                                    .padding(16).background(reserve == count ? Palette.blue : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
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
                    Text(continuationGuidance)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.configured?.currentWasSkipped != true {
                    Button("Finish session", action: store.finish).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                }
            }.padding(24)
        }.onAppear { reason = store.configured?.completed.last?.reason ?? .voluntary }
    }
    var continuationGuidance: String {
        if store.configured?.currentWasSkipped == true {
            return "Nothing was added as a completed set. This skipped step is saved locally when you finish. Missing entries or camera observations do not prove you did no exercise."
        }
        if isLast, store.configured?.skippedSets.isEmpty == false {
            return "Your planned steps are finished. Review your completed work and skipped steps."
        }
        return isLast ? "All planned sets are ended. Review your session to save the work you completed."
            : "The next set starts only when you choose Start. Rest timing never starts a set automatically."
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
                    Text(run.completed.isEmpty && run.skippedSets.isEmpty ? "No ended sets to save." : (store.error == nil ? (run.completed.isEmpty ? "Skipped steps saved locally. No completed sets." : "Session saved on this iPhone.") : "Save interrupted."))
                        .font(.subheadline).foregroundStyle(store.error != nil ? Palette.red : (run.completed.isEmpty ? Palette.muted : Palette.green))
                    HStack {
                        Metric(value: "\(run.completed.count)", title: "Sets ended", symbol: "square.3.layers.3d")
                        Metric(value: "\(run.record.reps)", title: "Reps", symbol: "repeat")
                        Metric(value: clockText(run.record.activeSeconds), title: "Active time", symbol: "clock")
                    }
                    if !run.skippedSets.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("\(run.skippedSets.count) skipped \(run.skippedSets.count == 1 ? "step" : "steps") · not completed sets")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            ForEach(run.skippedSets) { skipped in
                                Text("\(ExerciseCatalog.find(skipped.exerciseID)?.name ?? skipped.exerciseID) · planned set \(skipped.number) · skipped by choice")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Skip details stay in local history and exports. Cloud upload includes completed sets only.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(run.completed) { set in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(ExerciseCatalog.find(set.exerciseID)?.name ?? set.exerciseID) · Set \(set.number ?? 1)").font(.headline)
                            Text("\(set.seconds > 0 ? "\(Int(set.seconds)) sec" : "\(set.reps) \(set.reps == 1 ? "rep" : "reps")") · \(set.source == .camera ? "camera observation" : (set.quantityOrigin == .activeTimer ? "active hold timer" : "manual self-report"))")
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
