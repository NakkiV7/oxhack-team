import SwiftUI

struct SkillsView: View {
    @Bindable var store: TrainingStore
    private var progress: SkillProgress { .evaluate(history: store.history) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Build your real-life stats.").font(.system(size: 31, weight: .bold)).tracking(-1)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(TrainingAttribute.allCases, id: \.self) { attribute in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(attribute.title).font(.caption).foregroundStyle(.secondary)
                                Text("\(progress.points(for: attribute)) XP").font(.title2.weight(.semibold)).monospacedDigit()
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    Text("Game points earned through training. They aren’t a measurement of physical capability.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ExerciseFamily.allCases, id: \.self) { family in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(family.title).font(.title3.bold())
                            ForEach(ExerciseCatalog.all.filter { $0.family == family }) { entry in
                                NavigationLink {
                                    ExerciseDetailView(store: store, entry: entry)
                                } label: {
                                    SkillRow(entry: entry, node: progress.node(exerciseID: entry.id))
                                }.buttonStyle(.plain).accessibilityIdentifier("skill-\(entry.id)")
                            }
                        }
                    }
                    Text("Each goal-meeting set earns 10 XP, up to 3 sets per exercise each day. Manual and camera sets count. Video replay points are paused until replay identity is supported.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(.white).navigationTitle("Skills").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SkillRow: View {
    let entry: ExerciseEntry
    let node: SkillNodeProgress?

    private var tint: Color {
        if node?.isComplete == true { return Palette.green }
        return node?.isAvailable == true ? Palette.amber : Palette.ink
    }

    var body: some View {
        HStack(spacing: 15) {
            ExerciseArtwork(entry: entry).frame(width: 68, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.levelName).font(.subheadline.weight(.semibold))
                Text(entry.name).font(.caption).foregroundStyle(.secondary)
                Text(entry.goalText).font(.caption2).foregroundStyle(.secondary)
                Text(node?.isComplete == true ? "Complete" : "\(min(3, node?.qualifyingSets ?? 0))/3 sets · \(min(2, node?.trainingDays ?? 0))/2 days")
                    .font(.caption.weight(.medium)).foregroundStyle(tint)
            }
            Spacer(minLength: 0)
            Image(systemName: node?.isComplete == true ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(tint)
        }.padding(15).background(node?.isComplete == true ? Palette.green.opacity(0.08) : Palette.surface,
                                  in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ExerciseLibraryView: View {
    @Bindable var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("Move with what you have.").font(.system(size: 28, weight: .bold)).tracking(-0.7)
                    Text("Bodyweight exercises, with household support where shown. Every level is available to practise.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(ExerciseFamily.allCases, id: \.self) { family in
                        let entries = ExerciseCatalog.all.filter {
                            $0.family == family && (search.isEmpty || "\($0.name) \($0.levelName)".localizedCaseInsensitiveContains(search))
                        }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(family.title).font(.headline)
                                ForEach(entries) { entry in
                                    NavigationLink {
                                        ExerciseDetailView(store: store, entry: entry)
                                    } label: {
                                        HStack(spacing: 15) {
                                            ExerciseArtwork(entry: entry).frame(width: 65, height: 70)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(entry.name).font(.subheadline.weight(.semibold))
                                                Text(entry.levelName).font(.caption).foregroundStyle(.secondary)
                                                Text(entry.tracking == nil ? (entry.unit == .seconds ? "Timed or manual" : "Manual reps") : "Camera or manual")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption)
                                        }.padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                                    }.buttonStyle(.plain).accessibilityIdentifier("library-\(entry.id)")
                                }
                            }
                        }
                    }
                }.padding(24)
            }.background(.white).navigationTitle("Exercise library").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "Find an exercise")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ExerciseArtwork: View {
    let entry: ExerciseEntry
    var body: some View {
        Group {
            if UIImage(named: entry.art) != nil {
                Image(entry.art).resizable().scaledToFit()
            } else {
                Image(systemName: "figure.strengthtraining.traditional").resizable().scaledToFit().padding(15).foregroundStyle(.secondary)
            }
        }.accessibilityLabel(entry.name)
    }
}

private struct ExerciseDetailView: View {
    @Bindable var store: TrainingStore
    let entry: ExerciseEntry
    @State private var manualPresented = false
    @State private var timerPresented = false
    private var node: SkillNodeProgress? { SkillProgress.evaluate(history: store.history).node(exerciseID: entry.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ExerciseArtwork(entry: entry).frame(maxWidth: .infinity).frame(height: 200)
                    .padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 23))
                VStack(alignment: .leading, spacing: 9) {
                    Text(entry.name).font(.system(size: 28, weight: .bold)).tracking(-0.8)
                    Label(entry.attribute.title, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    Text(entry.instruction).font(.subheadline).foregroundStyle(.secondary)
                    if let support = entry.support { Label(support, systemImage: "house").font(.caption) }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Challenge").font(.headline)
                    Text("3 sets of \(entry.goal) \(entry.unit == .reps ? "reps" : "seconds") across at least 2 training days.")
                        .font(.subheadline)
                    Text("\(min(3, node?.qualifyingSets ?? 0))/3 goal sets · \(min(2, node?.trainingDays ?? 0))/2 days")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(node?.isComplete == true ? Palette.green : Palette.amber)
                    Text("Manual: \(node?.manualSets ?? 0) sets").font(.caption).foregroundStyle(.secondary)
                    Text("Camera: \(node?.cameraSets ?? 0) sets").font(.caption).foregroundStyle(.secondary)
                    if node?.isComplete == true { Label("Challenge complete", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.green) }
                    if node?.isAvailable == false {
                        Text("Complete the previous level to earn this achievement. You can practise and log this exercise now.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Only goal-meeting sets without pain or discomfort count toward the challenge.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                PrimaryButton(title: "Log manually", symbol: "plus") { manualPresented = true }
                if entry.unit == .seconds {
                    Button { timerPresented = true } label: {
                        Label("Start hold timer", systemImage: "timer").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(17)
                    }.buttonStyle(.plain)
                }
                Text(entry.tracking == nil ? "Manual self-report\(entry.unit == .seconds ? " or a hold timer" : ""). Camera tracking hasn’t been validated for this variation." : "Camera tracking is available for this variation in your live session. Manual entries are labelled separately.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Stop if you feel pain or discomfort.", systemImage: "hand.raised").font(.caption)
            }.padding(24)
        }.background(.white).navigationTitle(entry.levelName).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $manualPresented) { ManualWorkoutView(store: store, entry: entry, initialCount: entry.goal, initialSets: 3) }
            .sheet(isPresented: $timerPresented) { HoldTimerView(store: store, entry: entry) }
    }
}

struct ManualWorkoutView: View {
    @Bindable var store: TrainingStore
    let entry: ExerciseEntry
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: String
    @State private var sets: String
    @State private var reason: StopReason = .voluntary
    @State private var saved = false
    @State private var error: String?

    init(store: TrainingStore, entry: ExerciseEntry, initialCount: Int, initialSets: Int) {
        self.store = store; self.entry = entry
        _quantity = State(initialValue: String(initialCount)); _sets = State(initialValue: String(initialSets))
    }

    var body: some View {
        NavigationStack {
            Group {
                if saved {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle").font(.system(size: 48, weight: .light)).foregroundStyle(Palette.green)
                        Text("Workout saved").font(.title2.bold())
                        Text("\(sets) sets · \(quantity) \(entry.unit == .reps ? "reps" : "sec") per set")
                        Text("Manual self-report").font(.caption).foregroundStyle(.secondary)
                        PrimaryButton(title: "Done", symbol: "checkmark") { dismiss() }
                    }.padding(28)
                } else {
                    Form {
                        Section(entry.name) {
                            Text("Log only the sets you completed. For different quantities, save them separately.").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text(entry.unit == .reps ? "Reps per set" : "Seconds per set")
                                Spacer()
                                TextField(entry.unit == .reps ? "Reps per set" : "Seconds per set", text: $quantity)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                    .accessibilityIdentifier(entry.unit == .reps ? "Reps per set" : "Seconds per set")
                            }
                            HStack {
                                Text("Number of sets"); Spacer()
                                TextField("Number of sets", text: $sets).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                    .accessibilityIdentifier("Number of sets")
                            }
                            Picker("Why did you stop?", selection: $reason) {
                                ForEach(StopReason.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                        }
                        Section {
                            Text("Source: Manual self-report").font(.caption)
                            PrimaryButton(title: "Save workout", symbol: "checkmark", action: save)
                            if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                        }
                    }
                }
            }.navigationTitle(saved ? "Saved" : "Log exercise").navigationBarTitleDisplayMode(.inline)
                .toolbar { if !saved { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } } }
        }
    }

    private func save() {
        guard let count = Int(quantity), let number = Int(sets) else { error = "Enter whole numbers for quantity and sets."; return }
        do {
            let record = try LoggedWorkout.make(exerciseID: entry.id, count: count, sets: number, reason: reason)
            store.persist(record)
            guard store.history.contains(where: { $0.id == record.id }) else { error = store.error ?? "Couldn’t save this workout. Try again."; return }
            saved = true
        } catch {
            self.error = "Use 1–10 sets and \(entry.unit == .reps ? "1–200 reps" : "1–600 seconds") per set."
        }
    }
}

private struct HoldTimerView: View {
    @Bindable var store: TrainingStore
    let entry: ExerciseEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = ManualHoldClock()
    @State private var hasStarted = false
    @State private var completedSeconds: Int?
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        Group {
            if let completedSeconds {
                ManualWorkoutView(store: store, entry: entry, initialCount: completedSeconds, initialSets: 1)
            } else {
                NavigationStack {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        VStack(spacing: 25) {
                            ExerciseArtwork(entry: entry).frame(height: 170)
                            Text(entry.name).font(.title2.bold())
                            Text(clockText(clock.elapsed(at: now))).font(.system(size: 62, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(!hasStarted ? "Ready when you are" : (clock.isRunning ? "Hold in progress" : "Hold paused"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Start when you’re in position. Only active timer seconds are logged. Pause whenever you stop holding.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            PrimaryButton(title: clock.isRunning ? "Pause hold" : (hasStarted ? "Resume hold" : "Start hold"), symbol: clock.isRunning ? "pause" : "play") {
                                if clock.isRunning { clock.pause(at: now) }
                                else { hasStarted = true; clock.start(at: now) }
                            }
                            Button("Finish hold") {
                                clock.pause(at: now)
                                completedSeconds = min(600, Int(clock.elapsed(at: now)))
                            }.font(.subheadline.weight(.semibold)).disabled(clock.elapsed(at: now) < 1)
                            Text("You’ll review the hold before saving. Stop if you feel pain or discomfort.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(28)
                    }.navigationTitle("Hold timer").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
                }
            }
        }.onChange(of: scenePhase) { _, phase in if phase != .active { clock.pause(at: now) } }
    }
}
