import SwiftUI

struct SkillsView: View {
    @Bindable var store: TrainingStore
    var profile: LocalProfile? = nil
    var previewMode = false
    @State private var progress: SkillCurriculum.Progress?
    @State private var selectedChapter: String?
    @State private var expanded = false
    @State private var selected: ExerciseEntry?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var current: SkillCurriculum.Node? {
        progress?.nodes.first { $0.isUsable && $0.state != .earned && $0.state != .placed && $0.state != .locked }
    }
    private var currentChapter: SkillCurriculum.Chapter {
        SkillCurriculum.chapters.first { $0.exerciseIDs.contains(current?.id ?? "") } ?? SkillCurriculum.chapters[0]
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ScreenHeading(title: "One journey, every movement", subtitle: "53 skills · Six chapters · Your own pace")
                        HStack {
                            Text("\(progress?.nodes.filter { $0.state == .earned }.count ?? 0) earned").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Jump to current") {
                                selectedChapter = nil; expanded = false
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(currentChapter.id, anchor: .top) }
                            }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("skills-jump-current")
                        }
                        ForEach(SkillCurriculum.chapters) { chapter in
                            chapterSection(chapter).id(chapter.id)
                        }
                        if let quests = store.quests { QuestCardsView(store: store, quests: quests) }
                        TrainingRewardWidget(store: store, profile: profile)
                        NavigationLink("Browse every exercise") { ExerciseLibraryView(store: store) }
                            .font(.subheadline.weight(.semibold))
                        Text("Chapters help you explore. Progress in one movement family never blocks another. Placement is self-reported and earns no XP.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24)
                }.background(.white).navigationTitle("Skills").navigationBarTitleDisplayMode(.inline)
                    .onChange(of: selectedChapter) { _, chapter in
                        Task { @MainActor in
                            await Task.yield()
                            guard selectedChapter == chapter else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(chapter ?? currentChapter.id, anchor: .top)
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                selectedChapter = nil; expanded = false
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(currentChapter.id, anchor: .top) }
                            } label: { Image(systemName: "location.north.line") }
                            .accessibilityLabel("Jump to current").accessibilityIdentifier("skills-toolbar-current")
                        }
                    }
            }
        }
        .sheet(item: $selected) { entry in
            if let profile, let node = progress?.node(entry.id) { CurriculumPracticeSheet(store: store, profile: profile, entry: entry, node: node) }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.history) { _, _ in refresh() }
        .onChange(of: profile) { _, _ in refresh() }
    }
    private func refresh() {
        progress = profile.map { SkillCurriculum.evaluate(profile: $0, history: store.history, calendar: store.programme?.localCalendar ?? .current) }
    }
    private func chapterSection(_ chapter: SkillCurriculum.Chapter) -> some View {
        let open = (selectedChapter ?? currentChapter.id) == chapter.id
        let earned = chapter.exerciseIDs.filter { progress?.node($0)?.state == .earned }.count
        return VStack(alignment: .leading, spacing: 16) {
            Button {
                selectedChapter = open ? nil : chapter.id; expanded = false
            } label: {
                HStack(spacing: 12) {
                    Text(String((SkillCurriculum.chapters.firstIndex { $0.id == chapter.id } ?? 0) + 1))
                        .font(.caption.bold()).frame(width: 32, height: 32).background(Palette.blue.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chapter.title).font(.title3.bold())
                        Text("\(earned) of \(chapter.exerciseIDs.count) earned").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.foregroundStyle(Palette.ink)
            }.buttonStyle(.plain).accessibilityIdentifier("skills-chapter-\(chapter.id)")
            if open {
                let focus = chapter.exerciseIDs.firstIndex(of: current?.id ?? "") ?? 0
                let start = expanded ? 0 : max(0, focus - 1)
                let ids = expanded ? chapter.exerciseIDs : Array(chapter.exerciseIDs.dropFirst(start).prefix(5))
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if let entry = ExerciseCatalog.find(id), let node = progress?.node(id) {
                        VStack(spacing: 0) {
                            if index > 0 {
                                Capsule().fill(progress?.node(ids[index - 1])?.state == .earned ? Palette.green : Palette.blue.opacity(0.18))
                                    .frame(width: 4, height: 24).frame(maxWidth: .infinity).accessibilityHidden(true)
                            }
                            Button { selected = entry } label: {
                                nodeLabel(entry: entry, node: node, focused: id == current?.id)
                            }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("skill-\(id)")
                                .accessibilityLabel("\(entry.name), level \(entry.level), \(stateLabel(node)), \(node.qualifyingSets) qualifying sets across \(node.trainingDays) days")
                                .accessibilityHint("Opens practice details. Achievement locks do not block suitable practice.")
                        }
                    }
                }
                if ids.count < chapter.exerciseIDs.count {
                    Button("Show all \(chapter.exerciseIDs.count) skills in \(chapter.title)") { expanded = true }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
        }.padding(open ? 16 : 14).background(open ? Palette.blue.opacity(0.035) : Palette.surface, in: RoundedRectangle(cornerRadius: 24))
    }
    private func nodeLabel(entry: ExerciseEntry, node: SkillCurriculum.Node, focused: Bool) -> some View {
        let tint = node.state == .earned ? Palette.green : focused ? Palette.blue : Palette.muted
        return VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                StickFigureArtwork(exerciseID: entry.id).padding(14).frame(width: 96, height: 96)
                    .background(.white, in: Circle()).overlay { Circle().stroke(tint.opacity(0.4), lineWidth: focused ? 4 : 2) }
                Image(systemName: node.state == .earned ? "checkmark.circle.fill" : node.state == .locked ? "lock.circle.fill" : "circle.fill")
                    .foregroundStyle(tint).background(.white, in: Circle()).accessibilityHidden(true)
            }.accessibilityHidden(true)
            Text(entry.name).font(.headline).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text("Level \(entry.level) · \(stateLabel(node))").font(.caption.weight(.semibold)).foregroundStyle(tint)
            if focused { Text("Explore this movement").font(.caption.weight(.semibold)).foregroundStyle(Palette.blue) }
        }.padding(.vertical, 10).frame(maxWidth: .infinity).contentShape(Rectangle())
    }
    private func stateLabel(_ node: SkillCurriculum.Node) -> String {
        if !node.isUsable { return "Outside your current setup" }
        switch node.state { case .earned: return "Earned"; case .placed: return "Comfortable starting point"; case .available: return "Ready to explore"; case .locked: return "Achievement ahead" }
    }
}

private struct CurriculumPracticeSheet: View {
    let store: TrainingStore
    let profile: LocalProfile
    let entry: ExerciseEntry
    let node: SkillCurriculum.Node
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    private var age: Int { profile.programmePreferences?.ageContext?.ageYears ?? 0 }
    private var target: Int { min(entry.goal, age < 13 ? (entry.unit == .reps ? 6 : 10) : age < 18 ? (entry.unit == .reps ? 10 : 20) : entry.goal) }
    var body: some View {
        NavigationStack {
            Group {
                if let launch = store.launchCoordinator, launch.needsAttention, launch.pendingOrigin == .skills {
                    WorkoutLaunchAccessView(launch: launch)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            StickFigureArtwork(exerciseID: entry.id).frame(height: 140).frame(maxWidth: .infinity).accessibilityHidden(true)
                            Text(entry.instruction).font(.subheadline)
                            if age >= 5 && node.isUsable {
                                Label("One comfortable set · \(target) \(entry.unit == .reps ? "reps" : "seconds")", systemImage: "figure.strengthtraining.traditional").font(.headline)
                            }
                            if age >= 18 {
                                Text("Earn this skill with three sets of \(entry.goal) \(entry.unit == .reps ? "reps" : "seconds") over two days. Manual and camera practice both count.").font(.subheadline)
                                Text("\(node.qualifyingSets) qualifying sets · \(node.trainingDays) days · \(node.manualSets) manual · \(node.cameraSets) camera").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Comfortable practice is progress. Your daily practice quest celebrates your own age-appropriate target; adult benchmarks stay separate.").font(.subheadline)
                            }
                            if let support = PathSurvey.requiredEquipment(for: entry) { Label(support, systemImage: "checkmark.shield").font(.subheadline) }
                            if !node.isUsable { Text("This movement is outside your current age, support or movement preferences. Choose a suitable movement from your programme.").font(.subheadline) }
                            Text("Stop for pain or discomfort. Illustration is a guide, not a camera observation.").font(.caption).foregroundStyle(.secondary)
                            if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                        }.padding(24)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if node.isUsable && age >= 5 {
                            PrimaryButton(title: "Practise this movement", symbol: "play") {
                                do {
                                    let plan = try CoachSavedPlan.catalogue(exerciseID: entry.id, sets: 1, target: target, restSeconds: 60, availableSupport: profile.effectiveProgrammePreferences.availableSupport)
                                    store.startPlan(plan, availableSupport: profile.effectiveProgrammePreferences.availableSupport, origin: .skills)
                                } catch { self.error = "This practice couldn’t be prepared. Review your programme settings." }
                            }.accessibilityIdentifier("skill-practice-start").padding(20).background(.regularMaterial)
                        }
                    }
                }
            }.navigationTitle(entry.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.onDisappear { if store.launchCoordinator?.pendingOrigin == .skills { store.launchCoordinator?.cancel() } }
    }
}

private extension SkillAccess {
    var title: String {
        switch self {
        case .earned: return "Earned"
        case .available: return "Available"
        case .preview: return "Available"
        case .locked: return "Locked"
        }
    }
    var symbol: String {
        switch self {
        case .earned: return "checkmark.seal.fill"
        case .available: return "circle"
        case .preview: return "circle"
        case .locked: return "lock.fill"
        }
    }
    var tint: Color {
        switch self {
        case .earned: return Palette.green
        case .available, .preview: return Palette.blue
        case .locked: return Palette.ink
        }
    }
    var background: Color {
        switch self {
        case .earned: return Palette.green.opacity(0.08)
        case .available, .preview: return .white
        case .locked: return Palette.ink.opacity(0.10)
        }
    }
}

private struct SkillLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { states }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { states }
        }.font(.caption.weight(.medium))
    }
    private var states: some View {
        Group {
            Label("Earned", systemImage: SkillAccess.earned.symbol).foregroundStyle(Palette.green)
            Label("Available", systemImage: SkillAccess.available.symbol).foregroundStyle(Palette.blue)
            Label("Locked", systemImage: SkillAccess.locked.symbol).foregroundStyle(Palette.ink)
        }
    }
}

private struct SkillGraphView: View {
    let store: TrainingStore
    let progress: SkillProgress
    let previewMode: Bool
    @ScaledMetric(relativeTo: .caption) private var nodeWidth = 156.0
    @ScaledMetric(relativeTo: .caption) private var nodeHeight = 190.0
    private var column: Double { nodeWidth + 22 }
    private var row: Double { nodeHeight + 28 }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 22) {
                    ForEach(ExerciseFamily.allCases, id: \.self) { family in
                        Text(family.title).font(.caption.weight(.bold))
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
                                       unlocked: progress.isConnectionEarned(from: edge.from, to: edge.to))
                    }
                    ForEach(ExerciseCatalog.all) { entry in
                        let point = position(entry.id)
                        NavigationLink { ExerciseDetailView(store: store, entry: entry) } label: {
                            SkillGraphNode(entry: entry, progress: progress,
                                           access: progress.access(exerciseID: entry.id, previewUnlock: previewMode) ?? .locked)
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

    var body: some View {
        Path { path in
            path.move(to: start)
            let bend = (start.y + end.y) / 2
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: bend), control2: CGPoint(x: end.x, y: bend))
        }.stroke(unlocked ? Palette.green : Palette.muted.opacity(0.6),
                 style: StrokeStyle(lineWidth: unlocked ? 2.5 : 2, lineCap: .round))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: unlocked)
            .accessibilityHidden(true)
    }
}

private struct SkillGraphNode: View {
    let entry: ExerciseEntry
    let progress: SkillProgress
    let access: SkillAccess
    private var node: SkillNodeProgress? { progress.node(exerciseID: entry.id) }
    private var pending: String { progress.pendingPrerequisiteIDs(for: entry.id).compactMap { ExerciseCatalog.find($0)?.name }.joined(separator: ", ") }

    var body: some View {
        VStack(spacing: 6) {
            ExerciseArtwork(entry: entry).frame(height: 58).accessibilityHidden(true)
            Text(entry.levelName).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.85)
            Text(entry.name).font(.caption).multilineTextAlignment(.center).lineLimit(2)
            Label(access.title, systemImage: access.symbol).font(.caption2.weight(.semibold)).foregroundStyle(access.tint)
            Text("\(min(3, node?.qualifyingSets ?? 0))/3 sets, \(min(2, node?.trainingDays ?? 0))/2 days")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(access.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(access.tint.opacity(0.55), lineWidth: access == .earned ? 2 : 1.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.levelName), \(entry.name), \(access.title), \(min(3, node?.qualifyingSets ?? 0))/3 sets, \(min(2, node?.trainingDays ?? 0))/2 days")
            .accessibilityValue("Manual: \(node?.manualSets ?? 0) sets. Camera: \(node?.cameraSets ?? 0) sets.")
            .accessibilityHint(pending.isEmpty ? "Open instructions and training options." : "Earn first: \(pending). You can practise now.")
    }
}

private struct SkillRow: View {
    let entry: ExerciseEntry
    let progress: SkillProgress
    let access: SkillAccess
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var node: SkillNodeProgress? { progress.node(exerciseID: entry.id) }
    private var pending: String { progress.pendingPrerequisiteIDs(for: entry.id).compactMap { ExerciseCatalog.find($0)?.name }.joined(separator: ", ") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ExerciseArtwork(entry: entry).frame(width: 48, height: 60).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.levelName).font(.subheadline.weight(.semibold))
                Text(entry.name).font(.caption).foregroundStyle(.secondary)
                Text(entry.goalText).font(.caption2).foregroundStyle(.secondary)
                Label(access.title, systemImage: access.symbol).font(.caption.weight(.semibold)).foregroundStyle(access.tint)
                Text("\(min(3, node?.qualifyingSets ?? 0))/3 sets, \(min(2, node?.trainingDays ?? 0))/2 days")
                    .font(.caption).foregroundStyle(.secondary)
                if !pending.isEmpty {
                    Text("Earn first: \(pending). Practice is always available.").font(.caption).foregroundStyle(Palette.ink)
                }
                Text("Manual: \(node?.manualSets ?? 0), Camera: \(node?.cameraSets ?? 0) goal sets")
                    .font(.caption2).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(access.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(access.tint.opacity(0.35), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

struct ExerciseLibraryView: View {
    @Bindable var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ScreenHeading(title: "Find your movement")
                    ForEach(ExerciseFamily.allCases, id: \.self) { family in
                        let entries = ExerciseCatalog.all.filter {
                            $0.family == family && (search.isEmpty || "\($0.name) \($0.levelName)".localizedCaseInsensitiveContains(search))
                        }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(family.title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
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
                                        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                                    }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("library-\(entry.id)")
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
            if let exercise = entry.tracking {
                StickFigureArtwork(exercise: exercise)
            } else if entry.art.hasPrefix("stick-") {
                StickFigureArtwork(exerciseID: entry.id)
            } else if UIImage(named: entry.art) != nil {
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
                    Text("\(min(3, node?.qualifyingSets ?? 0))/3 goal sets, \(min(2, node?.trainingDays ?? 0))/2 days")
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
                        Text(next.compactMap { ExerciseCatalog.find($0)?.name }.joined(separator: ", "))
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
                Text(entry.tracking == nil ? "Manual self-report\(entry.unit == .seconds ? " or a hold timer" : ""). Camera tracking hasn’t been validated for this variation." : "Start workout, then choose Manual or iPhone camera. Manual entries are labelled separately.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Stop if you feel pain or discomfort.", systemImage: "hand.raised").font(.caption).foregroundStyle(Palette.red)
            }.padding(24)
        }.background(.white).navigationTitle(entry.levelName).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $manualPresented) { ManualWorkoutView(store: store, entry: entry, initialCount: entry.goal, initialSets: 3) }
            .sheet(isPresented: $timerPresented) { HoldTimerView(store: store, entry: entry) }
    }
}

struct ManualWorkoutView: View {
    private enum Field: Hashable { case quantity, sets }
    @Bindable var store: TrainingStore
    let entry: ExerciseEntry
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: String
    @State private var sets: String
    @State private var reason: StopReason = .voluntary
    @State private var saved = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

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
                        Text("\(sets) \(Int(sets) == 1 ? "set" : "sets"), \(quantity) \(entry.unit == .reps ? (Int(quantity) == 1 ? "rep" : "reps") : "sec") per set")
                        Text("Manual self-report").font(.caption).foregroundStyle(.secondary)
                        PrimaryButton(title: "Done", symbol: "checkmark") { dismiss() }
                    }.padding(28)
                } else {
                    Form {
                        Section(entry.name) {
                            Text("Log only the sets you completed. For different quantities, save them separately.").font(.subheadline).foregroundStyle(.secondary)
                                .contentShape(Rectangle()).onTapGesture { focusedField = nil }
                            HStack {
                                Text(entry.unit == .reps ? "Reps per set" : "Seconds per set")
                                Spacer()
                                TextField(entry.unit == .reps ? "Reps per set" : "Seconds per set", text: $quantity)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                    .focused($focusedField, equals: .quantity)
                                    .accessibilityIdentifier(entry.unit == .reps ? "Reps per set" : "Seconds per set")
                            }
                            HStack {
                                Text("Number of sets"); Spacer()
                                TextField("Number of sets", text: $sets).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                    .focused($focusedField, equals: .sets)
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
                    }.scrollDismissesKeyboard(.immediately)
                }
            }.navigationTitle(saved ? "Saved" : "Log exercise").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if focusedField != nil { KeyboardDismissBar(identifier: "manual-workout-keyboard-done") { focusedField = nil } }
                }
                .toolbar {
                    if !saved {
                        ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { focusedField = nil; dismiss() } }
                    }
                }
        }
    }

    private func save() {
        focusedField = nil
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
