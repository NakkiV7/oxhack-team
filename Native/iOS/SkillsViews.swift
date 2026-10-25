import SwiftUI

struct SkillsView: View {
    @Bindable var store: TrainingStore
    var profile: LocalProfile? = nil
    @AppStorage("skills.layout") private var layout = "grid"
    @State private var expanded = false
    @State private var previewUnlock = false

    var body: some View {
        let progress = SkillProgress.evaluate(history: store.history)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your skill tree.").font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("\(progress.nodes.filter(\.isComplete).count) of \(ExerciseCatalog.all.count) challenges earned")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(TrainingAttribute.allCases, id: \.self) { attribute in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(attribute.title).font(.caption).foregroundStyle(.secondary)
                                    Text("\(progress.points(for: attribute)) XP").font(.title3.weight(.semibold)).monospacedDigit()
                                }
                                Spacer(minLength: 4)
                                Image(systemName: attributeSymbol(attribute)).font(.title3).foregroundStyle(.secondary)
                            }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    Picker("Skill view", selection: $layout) {
                        Text("Grid").tag("grid")
                        Text("Linear").tag("linear")
                    }.pickerStyle(.segmented).accessibilityIdentifier("skill-layout")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("TestFlight preview access", isOn: $previewUnlock)
                            .font(.subheadline.weight(.medium)).tint(Palette.green)
                            .accessibilityIdentifier("skill-preview-access")
                        Text(previewUnlock ? "Preview access · no achievements earned" : "Explore locked paths without changing your earned progress.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if layout == "grid" {
                        Button {
                            expanded.toggle()
                        } label: {
                            Label(expanded ? "Collapse skill tree" : "Expand skill tree",
                                  systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline.weight(.semibold))
                        }.foregroundStyle(Palette.blue).accessibilityIdentifier("skill-grid-expand")
                        SkillGraphView(store: store, progress: progress, previewUnlock: previewUnlock)
                            .frame(height: expanded ? 640 : 360)
                        Text("Scroll across for branches and down for later challenges.").font(.caption).foregroundStyle(.secondary)
                    }
                    else { linearTree(progress: progress) }
                    if let profile, let baseline = profile.baselineAbility {
                        practiceIdeas(progress: progress, profile: profile, baseline: baseline)
                    }
                    Text("Earn each challenge with 3 goal sets across 2 days. Connected challenges unlock together. You can practise every exercise at any time.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Each goal set earns 10 XP, up to 3 sets per exercise each day. Manual and camera sets count; video replays don’t. XP and unlocks are game progress.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(.white).navigationTitle("Skills").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func linearTree(progress: SkillProgress) -> some View {
        ForEach(ExerciseFamily.allCases, id: \.self) { family in
            VStack(alignment: .leading, spacing: 14) {
                Text(family.title).font(.title3.bold())
                ForEach(ExerciseCatalog.all.filter { $0.family == family }) { entry in
                    NavigationLink { ExerciseDetailView(store: store, entry: entry) } label: {
                        SkillRow(entry: entry, node: progress.node(exerciseID: entry.id))
                        if progress.access(exerciseID: entry.id, previewUnlock: previewUnlock) == .preview {
                            Text("Preview access").font(.caption).foregroundStyle(Palette.blue)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("skill-\(entry.id)")
                }
            }
        }
    }

    private func practiceIdeas(progress: SkillProgress, profile: LocalProfile, baseline: LocalProfile.BaselineAbility) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice ideas · \(baseline.title)").font(.headline)
            Text("Based on your self-reported starting point and goals. Choose a comfortable variation; these ideas don’t award XP or complete challenges.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(progress.suggestedChallengeIDs(profile: profile), id: \.self) { id in
                if let entry = ExerciseCatalog.find(id) {
                    NavigationLink { ExerciseDetailView(store: store, entry: entry) } label: {
                        HStack(spacing: 12) {
                            ExerciseArtwork(entry: entry).frame(width: 42, height: 48)
                            Text(entry.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityIdentifier("suggested-\(id)")
                }
            }
        }
    }

    private func attributeSymbol(_ attribute: TrainingAttribute) -> String {
        switch attribute {
        case .strength: return "dumbbell"
        case .stamina: return "bolt.heart"
        case .mobility: return "figure.flexibility"
        case .balance: return "figure.mind.and.body"
        }
    }
}

private struct SkillGraphView: View {
    let store: TrainingStore
    let progress: SkillProgress
    let previewUnlock: Bool
    private let column = 154.0
    private let row = 174.0
    private let nodeWidth = 132.0
    private let nodeHeight = 146.0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 22) {
                    ForEach(ExerciseFamily.allCases, id: \.self) { family in
                        Text(family.title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1)
                            .frame(width: nodeWidth).padding(.vertical, 10)
                            .background(Palette.surface, in: Capsule())
                    }
                }
                ZStack(alignment: .topLeading) {
                    ForEach(SkillGraph.edges, id: \.self) { edge in
                        let from = position(edge.from)
                        let to = position(edge.to)
                        SkillGraphEdge(start: CGPoint(x: from.x + nodeWidth / 2, y: from.y + nodeHeight),
                                       end: CGPoint(x: to.x + nodeWidth / 2, y: to.y),
                                       unlocked: progress.access(exerciseID: edge.to, previewUnlock: previewUnlock) != .locked)
                    }
                    ForEach(ExerciseCatalog.all) { entry in
                        let point = position(entry.id)
                        NavigationLink { ExerciseDetailView(store: store, entry: entry) } label: {
                            SkillGraphNode(entry: entry, node: progress.node(exerciseID: entry.id),
                                           access: progress.access(exerciseID: entry.id, previewUnlock: previewUnlock) ?? .locked)
                                .frame(width: nodeWidth, height: nodeHeight)
                        }.buttonStyle(.plain).accessibilityIdentifier("skill-\(entry.id)")
                            .offset(x: point.x, y: point.y)
                    }
                }.frame(width: column * Double(ExerciseFamily.allCases.count) - 22,
                         height: row * Double((ExerciseCatalog.all.map { SkillGraph.tier(of: $0.id) }.max() ?? 0) + 1) - 28)
            }.padding(.vertical, 4)
        }.scrollIndicators(.visible).accessibilityIdentifier("skill-graph")
    }

    private func position(_ id: String) -> CGPoint {
        guard let entry = ExerciseCatalog.find(id), let index = ExerciseFamily.allCases.firstIndex(of: entry.family) else { return .zero }
        return CGPoint(x: Double(index) * column, y: Double(SkillGraph.tier(of: id)) * row)
    }
}

private struct SkillGraphEdge: View {
    let start: CGPoint
    let end: CGPoint
    let unlocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Path { path in
            path.move(to: start)
            let bend = (start.y + end.y) / 2
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: bend), control2: CGPoint(x: end.x, y: bend))
        }.stroke(unlocked ? Palette.green : Palette.muted.opacity(0.6),
                 style: StrokeStyle(lineWidth: unlocked ? 2.5 : 2, lineCap: .round))
            .opacity(unlocked && !reduceMotion && !pulse ? 0.5 : 1)
            .animation(unlocked && !reduceMotion ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : nil, value: pulse)
            .onAppear { pulse = unlocked && !reduceMotion }
            .onChange(of: unlocked) { _, value in pulse = value && !reduceMotion }
            .onChange(of: reduceMotion) { _, value in pulse = unlocked && !value }
            .accessibilityHidden(true)
    }
}

private struct SkillGraphNode: View {
    let entry: ExerciseEntry
    let node: SkillNodeProgress?
    let access: SkillAccess
    private var complete: Bool { node?.isComplete == true }
    private var tint: Color { complete ? Palette.green : (access == .locked ? Palette.ink : Palette.blue) }
    private var status: String {
        switch access {
        case .earned: return "complete"
        case .available: return "available"
        case .preview: return "preview access, not earned"
        case .locked: return "prerequisites pending"
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            ExerciseArtwork(entry: entry).frame(height: 60).padding(.top, 8)
            Text(entry.levelName).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(entry.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            if access == .preview { Text("PREVIEW").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.blue) }
            Text(complete ? "COMPLETE" : "\(min(3, node?.qualifyingSets ?? 0))/3 sets · \(min(2, node?.trainingDays ?? 0))/2 days")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(complete ? Palette.green.opacity(0.07) : (access == .locked ? Palette.surface : .white), in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.55), lineWidth: complete ? 2 : 1.5) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: complete ? "checkmark.circle.fill" : (access == .locked ? "lock.fill" : (access == .preview ? "lock.open" : "circle.fill")))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(tint).padding(10)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.levelName), \(entry.name), \(status), \(node?.qualifyingSets ?? 0) goal sets")
    }
}

private struct SkillRow: View {
    let entry: ExerciseEntry
    let node: SkillNodeProgress?

    private var tint: Color {
        if node?.isComplete == true { return Palette.green }
        return node?.isAvailable == true ? Palette.blue : Palette.muted
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

struct ExerciseArtwork: View {
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
                DemonstrationComparisonView(exerciseID: entry.id)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(node?.isComplete == true ? Palette.green : (node?.isAvailable == true ? Palette.blue : Palette.muted))
                    Text("Manual: \(node?.manualSets ?? 0) sets").font(.caption).foregroundStyle(.secondary)
                    Text("Camera: \(node?.cameraSets ?? 0) sets").font(.caption).foregroundStyle(.secondary)
                    if node?.isComplete == true { Label("Challenge complete", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.green) }
                    let parents = SkillGraph.prerequisites(for: entry.id)
                    if !parents.isEmpty {
                        Text("Builds on").font(.caption.weight(.semibold)).padding(.top, 6)
                        ForEach(parents, id: \.self) { id in
                            if let parent = ExerciseCatalog.find(id) {
                                let parentComplete = SkillProgress.evaluate(history: store.history).node(exerciseID: id)?.isComplete == true
                                Label(parent.name, systemImage: parentComplete ? "checkmark.circle.fill" : "circle")
                                    .font(.caption).foregroundStyle(parentComplete ? Palette.green : Palette.muted)
                            }
                        }
                    }
                    let next = SkillGraph.dependents(of: entry.id)
                    if !next.isEmpty {
                        Text("Opens the path to").font(.caption.weight(.semibold)).padding(.top, 6)
                        Text(next.compactMap { ExerciseCatalog.find($0)?.name }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if node?.isAvailable == false {
                        Text("Complete the connected challenges to earn this achievement. You can practise and log this exercise now.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Only goal-meeting sets without pain or discomfort count toward the challenge.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                NavigationLink {
                    CatalogueWorkoutSetupView(store: store, entry: entry)
                } label: {
                    Label("Start workout", systemImage: "play")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(19)
                        .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain).accessibilityIdentifier("catalogue-workout-setup")
                PrimaryButton(title: "Log manually", symbol: "plus") { manualPresented = true }
                if entry.unit == .seconds {
                    Button { timerPresented = true } label: {
                        Label("Start hold timer", systemImage: "timer").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(17)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                }
                Text(entry.tracking == nil ? "Manual self-report\(entry.unit == .seconds ? " or a hold timer" : ""). Camera tracking hasn’t been validated for this variation." : "Start workout, then choose Manual, iPhone camera or Pi side camera. Manual entries are labelled separately.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Stop if you feel pain or discomfort.", systemImage: "hand.raised").font(.caption).foregroundStyle(Palette.red)
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
                        Text("\(sets) \(Int(sets) == 1 ? "set" : "sets") · \(quantity) \(entry.unit == .reps ? (Int(quantity) == 1 ? "rep" : "reps") : "sec") per set")
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
