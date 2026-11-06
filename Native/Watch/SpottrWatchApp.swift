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
    @State private var crownReps = 0.0
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize: CGFloat = 42
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if let journal = store.journal {
                    TabView(selection: $page) {
                        localMetrics(journal, now: context.date).tag(Page.metrics)
                        localControls(journal).tag(Page.controls)
                        localVitals(now: context.date).tag(Page.vitals)
                    }.tabViewStyle(.verticalPage).containerBackground(.black, for: .tabView)
                } else if let snapshot = store.state.snapshot, snapshot.phase != .idle && snapshot.phase != .finished {
                    TabView(selection: $page) {
                        metrics(snapshot, now: context.date).tag(Page.metrics)
                        controls(snapshot, now: context.date).tag(Page.controls)
                        vitals(snapshot, now: context.date).tag(Page.vitals)
                    }.tabViewStyle(.verticalPage).containerBackground(.black, for: .tabView)
                } else { cachedWorkouts(now: context.date) }
            }.background { Color.black.ignoresSafeArea() }
        }.foregroundStyle(.white).tint(.blue)
            .onChange(of: store.journal?.id) { _, id in if id != nil { page = .metrics; crownReps = Double(store.journal?.reps ?? 0) } }
            .alert("End this session?", isPresented: Binding(get: { store.pendingFinish != nil || store.pendingLocalFinish }, set: { if !$0 { store.cancelFinish() } })) {
                Button("End session", role: .destructive) { store.confirmFinish() }
                Button("Cancel", role: .cancel) { store.cancelFinish() }
            } message: {
                Text(store.journal != nil ? "Completed sets are saved on Watch. The current unfinished set will be discarded."
                     : store.state.snapshot?.configured != nil
                     ? "Ended sets and skipped steps are saved separately. The current unfinished set will be discarded."
                     : "Finish this session and save your completed work on iPhone.")
            }
    }
    private func cachedWorkouts(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your workouts").font(.headline)
                if let completed = store.lastCompleted {
                    Text("Saved on Watch · \(completed.completed.count) sets").font(.caption).foregroundStyle(.green)
                }
                ForEach(store.programme?.choices ?? []) { choice in
                    Button {
                        store.startCached(choiceID: choice.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.date, format: .dateTime.weekday().day().month()).font(.headline)
                            Text(choice.plan.items.compactMap { ExerciseCatalog.find($0.exerciseID)?.name }.joined(separator: ", "))
                                .font(.caption2).multilineTextAlignment(.leading)
                            Text(Calendar.current.isDate(choice.date, inSameDayAs: now) ? "Start whole workout" : "Repeat as practice today")
                                .font(.caption2)
                        }
                    }.buttonStyle(.bordered).disabled(!store.canStartCached)
                }
                if !store.canStartCached {
                    Text("Open your training profile on iPhone to refresh Watch sharing, setup and membership.").font(.caption2).foregroundStyle(.secondary)
                }
                if let status = store.status { Text(status).font(.caption2).foregroundStyle(.orange) }
                Text(store.telemetryStatusText).font(.caption2).foregroundStyle(.secondary)
                Button("Reconnect") { store.link.request() }.buttonStyle(.bordered)
            }.padding(.horizontal, 12)
        }.accessibilityIdentifier("watch-cached-workouts")
    }
    private func localMetrics(_ journal: WatchWorkoutJournal, now: Date) -> some View {
        VStack(spacing: 6) {
            Text(ExerciseCatalog.find(journal.current.exerciseID)?.name ?? "Workout").font(.headline).lineLimit(2)
            Text("Set \(journal.setNumber) · \(journal.index + 1) of \(journal.items.count)").font(.caption2).foregroundStyle(.secondary)
            Text(journal.current.unit == .seconds ? "\(Int(journal.activeSeconds)) s" : journal.reps.map(String.init) ?? "—")
                .font(.system(size: min(countFontSize, 48), weight: .semibold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("watch-local-quantity")
            if !journal.policyRestricted { Text("Target \(journal.current.target) \(journal.current.unit == .seconds ? "seconds" : "reps")").font(.caption2).foregroundStyle(.secondary) }
            Text(journal.current.unit == .seconds ? "Manual active timer" : "Manual reps").font(.caption2)
            if journal.phase == .rest { Text("Rest · \(max(0, journal.current.restSeconds - Int(journal.restSeconds))) s").font(.caption) }
            else if journal.phase == .paused { Text("Paused").font(.caption) }
            else if !journal.hasStarted { Text("Start when ready").font(.caption) }
            if journal.current.unit == .reps, [.active, .paused].contains(journal.phase) {
                HStack {
                    Button("−") { store.setLocalReps(max(0, (journal.reps ?? 0) - 1)) }.accessibilityLabel("Decrease actual reps")
                    Button("+") { store.setLocalReps(min(200, (journal.reps ?? 0) + 1)) }.accessibilityLabel("Increase actual reps")
                }.buttonStyle(.bordered)
            }
            if let heart = store.heart?.heartRate(at: now) { Text("\(Int(heart.rounded())) BPM").font(.caption).foregroundStyle(.red) }
            else { Text(journal.grant.age?.allowsHealthIntegration == true && !journal.policyRestricted ? "No recent pulse" : "Health collection off").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.horizontal, 12).focusable()
            .digitalCrownRotation($crownReps, from: 0, through: 200, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crownReps) { _, value in
                guard journal.current.unit == .reps, [.active, .paused].contains(journal.phase) else { return }
                store.setLocalReps(Int(value))
            }
            .onChange(of: journal.reps) { _, value in crownReps = Double(value ?? 0) }
            .accessibilityIdentifier("watch-local-metrics")
    }
    private func localControls(_ journal: WatchWorkoutJournal) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Workout controls").font(.headline)
                if journal.policyRestricted {
                    Text("Profile or sharing changed. Save your actual work here; review the next workout on iPhone.").font(.caption2)
                }
                if !journal.hasStarted && journal.phase == .active && !journal.policyRestricted {
                    Button("Start set") { store.beginLocalSet() }.buttonStyle(.borderedProminent)
                } else if [.active, .paused].contains(journal.phase) && journal.hasStarted {
                    if journal.phase == .active { Button("Pause") { store.pauseLocal() }.buttonStyle(.bordered) }
                    else if !journal.policyRestricted { Button("Resume") { store.resumeLocal() }.buttonStyle(.borderedProminent) }
                    Button("End set") { store.endLocalSet() }.buttonStyle(.bordered).disabled(!journal.canEndSet)
                } else if journal.phase == .rest {
                    Text("How did that set feel?").font(.caption)
                    ForEach(SetEffort.allCases, id: \.rawValue) { effort in
                        Button(effort.title) { store.setEffort(journal.completed.last?.effort == effort ? nil : effort) }
                            .buttonStyle(.bordered).tint(journal.completed.last?.effort == effort ? .green : .blue)
                    }
                    if journal.index + 1 < journal.items.count && !journal.policyRestricted {
                        Button("Next set ready") { store.nextLocalSet() }.buttonStyle(.bordered)
                        Text("Your next set becomes ready after rest. Start it when you are ready.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Finish workout", role: .destructive) { store.requestLocalFinish() }.buttonStyle(.bordered)
                Text(store.status ?? store.recordingState.message).font(.caption2).foregroundStyle(.secondary)
                if store.recordingBusy { Button("Stop Health collection") { store.stopLocalRecording() }.buttonStyle(.bordered) }
                Text(store.telemetryStatusText).font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 12)
        }.accessibilityIdentifier("watch-local-controls")
    }
    private func localVitals(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Watch readings").font(.headline)
                let heart = store.heart?.heartRate(at: now)
                Text(heart.map { "\(Int($0.rounded())) BPM" } ?? "No recent pulse").font(.title2)
                metric("Wrist acceleration", reading: store.acceleration, unit: "g", now: now)
                metric("Angular speed", reading: store.rotation, unit: "rad/s", now: now)
                Text(store.recordingState.message).font(.caption2)
                Text("Readings come from Watch sensors. Manual reps and timer values remain separate.").font(.caption2).foregroundStyle(.secondary)
                if heart == nil { Text("Check Watch fit and Health access in Settings if you want readings.").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12)
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
                    Text(snapshot.quantityText).font(.system(size: min(countFontSize, 48), weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text("/ \(snapshot.target)\(snapshot.configured?.unit == .seconds ? " s" : "")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.accessibilityIdentifier("watch-quantity")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Quantity and target")
                    .accessibilityValue(snapshot.quantityAccessibilityValue)
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
            if let origin = snapshot.quantityOriginLabel {
                Text(origin).font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watch-quantity-origin")
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
                    }.disabled(!store.reachable || !snapshot.isFresh(at: now))
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
    private func recordingControl(_ snapshot: CompanionSnapshot, compact: Bool = false) -> some View {
        Text(store.recordingState.message).font(compact ? .system(size: 9) : .caption2)
            .foregroundStyle(.secondary).lineLimit(compact ? 2 : nil)
            .accessibilityIdentifier("watch-automatic-recording-status")
    }
    private func exerciseName(_ snapshot: CompanionSnapshot) -> String {
        snapshot.configured.flatMap { ExerciseCatalog.find($0.exerciseID)?.name } ?? snapshot.exercise?.title ?? "Workout"
    }
    private func setDescription(_ snapshot: CompanionSnapshot) -> String {
        "Set \(snapshot.setNumber) of \(snapshot.configured?.totalSets ?? 3)"
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
