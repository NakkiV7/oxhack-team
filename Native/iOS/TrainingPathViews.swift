import SwiftUI

/// The Skills tab. Until a path is built it shows the existing challenge tree with a card to build one; afterwards it
/// shows the personalised path, and the full tree stays one tap away under "All challenges".
struct PathSkillsView: View {
    @Bindable var store: TrainingStore
    var profile: LocalProfile? = nil
    var previewMode = false
    @State private var pathStore: TrainingPathStore
    @State private var surveyPresented = false
    @State private var surveyAtReview = false

    init(store: TrainingStore, profile: LocalProfile? = nil, previewMode: Bool = false) {
        self.store = store; self.profile = profile; self.previewMode = previewMode
        _pathStore = State(initialValue: TrainingPathStore(preview: previewMode))   // preview mode keeps its own path
    }

    var body: some View {
        // One stable root: swapping one navigation stack for another inside a tab makes the tab bar jump back to Today, so
        // the existing tree stays mounted underneath and the path screen covers it once a path exists.
        ZStack {
            SkillsView(store: store, profile: profile, previewMode: previewMode)
                .safeAreaInset(edge: .bottom) {
                    if pathStore.active == nil { BuildPathBanner(error: pathStore.loadError) { surveyAtReview = false; surveyPresented = true } }
                }
                .opacity(pathStore.active == nil ? 1 : 0)
                .accessibilityHidden(pathStore.active != nil)
                .allowsHitTesting(pathStore.active == nil)
            if let version = pathStore.active {
                PathHomeView(store: store, pathStore: pathStore, version: version, previewMode: previewMode) { surveyAtReview = true; surveyPresented = true }
            }
        }
        .fullScreenCover(isPresented: $surveyPresented) {
            PathSurveyView(store: store, pathStore: pathStore, profile: profile, startAtReview: surveyAtReview)
        }
    }
}

private struct BuildPathBanner: View {
    let error: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Palette.blue, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build your training path").font(.subheadline.weight(.semibold))
                    Text(error ?? "Five questions, then a route through these challenges made for you.").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").foregroundStyle(Palette.blue)
            }
            .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(Palette.blue.opacity(0.25)) }
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 6)
        .accessibilityIdentifier("path-build-banner").accessibilityHint("Opens five questions to build a personalised path")
    }
}

// MARK: - Path home

private struct PathHomeView: View {
    @Bindable var store: TrainingStore
    let pathStore: TrainingPathStore
    let version: PathHistory.Version
    var previewMode = false
    let adjust: () -> Void
    @State private var selected: SelectedStep?
    @State private var workout: SelectedStep?
    @State private var pendingWorkout: SelectedStep?
    @State private var showList = false
    @State private var allChallenges = false

    struct SelectedStep: Identifiable, Hashable { let id: String }

    var body: some View {
        let path = version.path, skill = SkillProgress.evaluate(history: store.history)
        let status = PathStatus.evaluate(path: path, skill: skill, attempts: pathStore.attempts)
        let verifications = path.nodes.map { status.step($0.id)?.verification ?? .none }
        let level = PathLevel(xp: PathLevel.xp(skill: skill, verifications: verifications))
        let attributes = MeasuredAttributes.evaluate(attempts: pathStore.attempts, history: store.history,
                                                     plannedSessions: version.survey.sessionsPerWeek, now: .now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your path.").font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("\(path.goal.title) · goal: \(ExerciseCatalog.find(path.goalNode)?.name ?? path.goalNode)").font(.subheadline).foregroundStyle(.secondary)
                        ProvenanceBadge(provenance: path.provenance)
                    }
                    PlayerCard(level: level, path: path, status: status) { id in selected = .init(id: id) }
                    Picker("Path view", selection: $showList) { Text("Map").tag(false); Text("List").tag(true) }
                        .pickerStyle(.segmented).accessibilityIdentifier("path-view-mode")
                    if showList {
                        PathListView(path: path, status: status) { selected = .init(id: $0) }
                    } else {
                        PathMapView(path: path, status: status, skill: skill) { selected = .init(id: $0) }.frame(maxWidth: .infinity)
                        PathLegend()
                    }
                    AttributesCard(attributes: attributes)
                    HStack(spacing: 10) {
                        Button(action: adjust) { Label("Adjust my path", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity).padding(16) }
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).accessibilityIdentifier("path-adjust")
                        Button { allChallenges = true } label: { Label("All challenges", systemImage: "square.grid.2x2").frame(maxWidth: .infinity).padding(16) }
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).accessibilityIdentifier("path-all-challenges")
                    }.font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                    Text("Version \(version.id) · saved \(version.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(.white).navigationTitle("Skills").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $workout) { step in
                if let entry = ExerciseCatalog.find(step.id) { CatalogueWorkoutSetupView(store: store, entry: entry) }
            }
        }
        .sheet(item: $selected, onDismiss: { if let pendingWorkout { workout = pendingWorkout; self.pendingWorkout = nil } }) { step in
            PathStepSheet(store: store, path: path, status: status, stepID: step.id,
                          select: { selected = .init(id: $0) }, startWorkout: { pendingWorkout = .init(id: $0); selected = nil })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $allChallenges) { SkillsView(store: store, previewMode: previewMode) }
    }
}

private struct PlayerCard: View {
    let level: PathLevel
    let path: TrainingPath
    let status: PathStatus
    let open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Path level").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(level.level)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            }
            ProgressView(value: level.fraction).tint(Palette.amber)
                .accessibilityLabel("XP towards level \(level.level + 1)").accessibilityValue("\(level.xp) of \(level.next) XP")
            HStack {
                Text("\(level.xp) XP").font(.caption).monospacedDigit()
                Spacer()
                Text("\(level.next - level.xp) XP to level \(level.level + 1)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text("A game score from practice and verified milestones, not a fitness rating.").font(.caption2).foregroundStyle(.secondary)
            Divider()
            if let current = status.current, let node = path.node(current), let entry = node.entry {
                Button { open(current) } label: {
                    HStack(spacing: 14) {
                        ExerciseArtwork(entry: entry).frame(width: 54, height: 54).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CURRENT QUEST").font(.caption2.weight(.bold)).foregroundStyle(Palette.blue).tracking(0.6)
                            Text(entry.name).font(.headline)
                            Text(node.practiceTarget.map { "\($0.sets) × \($0.target) \(entry.unit == .reps ? "reps" : "sec") · \($0.perWeek)× a week" } ?? entry.goalText)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.blue)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("path-current-quest").accessibilityHint("Opens the current step")
            } else {
                Label("Path complete. Adjust your path for a new goal.", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(Palette.green)
            }
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
    }
}

private struct AttributesCard: View {
    let attributes: [MeasuredAttribute]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Measured").font(.headline); Spacer(); Text("from saved sessions").font(.caption).foregroundStyle(.secondary) }
            ForEach(attributes, id: \.key) { attribute in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(attribute.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(attribute.value.map { "\($0) / 100" } ?? "Not assessed yet").font(.subheadline).monospacedDigit()
                            .foregroundStyle(attribute.value == nil ? .secondary : Palette.ink)
                    }
                    ProgressView(value: Double(attribute.value ?? 0), total: 100).tint(Palette.blue)
                        .accessibilityLabel(attribute.title).accessibilityValue(attribute.value.map { "\($0) out of 100" } ?? "Not assessed yet")
                    Text(attribute.detail).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("How is this calculated?") {
                        Text("\(attribute.method) Scope: \(attribute.scope).").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }.font(.caption.weight(.semibold)).tint(Palette.blue)
                }
            }
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
    }
}

// MARK: - The map

/// Draws a path with the shared deterministic layout: the main chain top to bottom, side steps in their own lanes.
struct PathMapView: View {
    let path: TrainingPath
    let status: PathStatus
    let skill: SkillProgress
    var animateIn = false
    let select: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        let layout = PathMapLayout.make(path: path, orientation: .vertical, step: 150, lane: 104, padding: 58, wave: 14)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in layout.edges {
                    guard let a = layout.positions[edge.from], let b = layout.positions[edge.to],
                          let from = path.node(edge.from), let to = path.node(edge.to) else { continue }
                    let ra = PathNodeView.size(PathMapLayout.role(of: from, in: path)) / 2, rb = PathNodeView.size(PathMapLayout.role(of: to, in: path)) / 2
                    var line = Path()
                    if edge.kind == .support {
                        // Side branch: a short dashed link between the two nodes, clear of both.
                        let direction: Double = b.x > a.x ? 1 : -1
                        line.move(to: CGPoint(x: a.x + direction * (ra + 6), y: a.y))
                        line.addLine(to: CGPoint(x: b.x - direction * (rb + 6), y: b.y))
                    } else {
                        // Leave below the step's name and arrive at the top of the next step, so lines never cross labels.
                        let start = CGPoint(x: a.x, y: a.y + ra + 44), end = CGPoint(x: b.x, y: b.y - rb - 6)
                        line.move(to: start)
                        line.addCurve(to: end, control1: CGPoint(x: start.x, y: (start.y + end.y) / 2), control2: CGPoint(x: end.x, y: (start.y + end.y) / 2))
                    }
                    let (color, width, dash) = style(edge)
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
                }
            }
            ForEach(Array(layout.order.enumerated()), id: \.element) { index, id in
                if let position = layout.positions[id], let node = path.node(id), let step = status.step(id) {
                    PathNodeView(node: node, step: step, role: PathMapLayout.role(of: node, in: path), isStart: id == path.start, current: id == status.current) { select(id) }
                        .position(x: position.x, y: position.y)
                        .accessibilitySortPriority(Double(layout.order.count - index))
                        .opacity(revealed || !animateIn ? 1 : 0)
                        .scaleEffect(revealed || !animateIn ? 1 : 0.7)
                        .animation(reduceMotion ? nil : .spring(duration: 0.5).delay(Double(index) * 0.08), value: revealed)
                }
            }
        }
        .frame(width: layout.width, height: layout.height + 46)
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: 28).fill(Palette.surface.opacity(0.6)).padding(-10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Training path map")
        .onAppear { revealed = true }
    }

    private func style(_ edge: PathMapLayout.Edge) -> (Color, CGFloat, [CGFloat]) {
        if edge.kind == .support { return (Palette.muted.opacity(0.55), 2, [5, 6]) }
        let from = status.step(edge.from), to = status.step(edge.to)
        if from?.isPassed == true && to?.isPassed == true { return (Palette.green, 3.5, []) }
        if from?.isPassed == true { return (Palette.blue, 3.5, []) }
        return (Palette.muted.opacity(0.3), 2.5, [])
    }
}

private struct PathNodeView: View {
    let node: PathNode
    let step: PathStepStatus
    let role: PathMapLayout.Role
    let isStart: Bool
    let current: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    static func size(_ role: PathMapLayout.Role) -> CGFloat { role == .goal ? 78 : role == .milestone ? 72 : role == .optional ? 54 : 66 }
    private var size: CGFloat { Self.size(role) }
    private var tint: Color {
        switch step.state {
        case .earned: return Palette.green
        case .current, .available: return Palette.blue
        case .notRequired, .locked: return Palette.muted
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: current ? 11 : 6) {
                ZStack {
                    if current {
                        NodeShape(role: role).fill(Palette.blue.opacity(0.16)).frame(width: size + 14, height: size + 14)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                    }
                    NodeShape(role: role).fill(step.state == .earned ? Palette.green.opacity(0.12) : step.state == .locked ? Palette.surface : .white)
                    NodeShape(role: role).stroke(tint, style: StrokeStyle(lineWidth: current ? 3.5 : 2, dash: step.state == .notRequired || role == .optional ? [5, 4] : []))
                    if let entry = node.entry {
                        ExerciseArtwork(entry: entry).padding(size * 0.17).opacity(step.state == .locked ? 0.35 : 1)
                    }
                }
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) { badge.offset(x: 6, y: -4) }
                .overlay(alignment: .bottomLeading) {
                    if PathCapability.of(node.id) == .cameraAssessment {
                        Image(systemName: "camera.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Palette.ink, in: Circle()).offset(x: -4, y: 4)
                    }
                }
                Text(node.entry?.name ?? node.id).font(.system(size: 12.5, weight: .semibold)).multilineTextAlignment(.center)
                    .lineLimit(2).frame(width: 104).foregroundStyle(step.state == .locked ? Palette.muted : Palette.ink)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(current ? Palette.blue : .secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens step details")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("path-node-\(node.id)")
        .onAppear { if current { pulse = true } }
    }

    @ViewBuilder private var badge: some View {
        let symbol: String? = step.verification != .none ? "star.fill" : step.state == .earned ? "checkmark" : step.state == .locked ? "lock.fill" : step.state == .notRequired ? "arrow.turn.down.right" : nil
        if let symbol {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(step.verification != .none ? Palette.amber : tint, in: Circle())
        }
    }
    private var subtitle: String {
        if role == .goal { return "Goal · \(step.title)" }
        if role == .optional { return "Optional · \(step.title)" }
        return step.state == .notRequired ? "Not required" : step.title
    }
    private var accessibilityText: String {
        var parts = [node.entry?.name ?? node.id, step.title, PathCapability.of(node.id).title]
        if role == .goal { parts.append("Path goal") }
        if role == .optional { parts.append("Optional branch") }
        if isStart { parts.append("Starting point") }
        parts.append("\(min(3, step.qualifyingSets)) of 3 goal sets, \(min(2, step.trainingDays)) of 2 days")
        return parts.joined(separator: ". ")
    }
}

/// Crest for the goal, hexagon for camera steps, circle for practice steps.
private struct NodeShape: Shape {
    let role: PathMapLayout.Role
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, mid = CGPoint(x: rect.midX, y: rect.midY)
        switch role {
        case .goal:
            var p = Path()
            p.move(to: CGPoint(x: mid.x, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.2))
            p.addLine(to: CGPoint(x: rect.maxX - w * 0.08, y: rect.minY + h * 0.62))
            p.addQuadCurve(to: CGPoint(x: mid.x, y: rect.maxY), control: CGPoint(x: rect.maxX - w * 0.2, y: rect.minY + h * 0.9))
            p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.62), control: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.9))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.2))
            p.closeSubpath()
            return p
        case .milestone:
            var p = Path()
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3 - .pi / 2
                let point = CGPoint(x: mid.x + w / 2 * cos(angle), y: mid.y + h / 2 * sin(angle))
                i == 0 ? p.move(to: point) : p.addLine(to: point)
            }
            p.closeSubpath()
            return p
        case .standard, .optional:
            return Path(ellipseIn: rect)
        }
    }
}

private struct PathLegend: View {
    var body: some View {
        let items: [(String, Color, String)] = [("circle.fill", Palette.blue, "Current or open"), ("checkmark.circle.fill", Palette.green, "Earned"),
                                                ("star.circle.fill", Palette.amber, "AI-verified"), ("lock.circle.fill", Palette.muted, "Locked"),
                                                ("camera.circle.fill", Palette.ink, "Camera assessment")]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.2) { item in
                Label { Text(item.2).font(.caption) } icon: { Image(systemName: item.0).foregroundStyle(item.1) }
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("Legend: current, earned, AI-verified, locked, camera assessment")
    }
}

private struct PathListView: View {
    let path: TrainingPath
    let status: PathStatus
    let select: (String) -> Void
    var body: some View {
        let layout = PathMapLayout.make(path: path)
        VStack(spacing: 10) {
            ForEach(layout.order, id: \.self) { id in
                if let node = path.node(id), let entry = node.entry, let step = status.step(id) {
                    Button { select(id) } label: {
                        HStack(spacing: 14) {
                            ExerciseArtwork(entry: entry).frame(width: 52, height: 52).opacity(step.state == .locked ? 0.4 : 1).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).font(.subheadline.weight(.semibold))
                                Text([step.title, PathCapability.of(id).title, node.optional ? "optional" : nil, id == path.goalNode ? "goal" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain).accessibilityIdentifier("path-row-\(id)")
                }
            }
        }
    }
}

// MARK: - Step sheet

private struct PathStepSheet: View {
    @Bindable var store: TrainingStore
    let path: TrainingPath
    let status: PathStatus
    let stepID: String
    let select: (String) -> Void
    let startWorkout: (String) -> Void
    @State private var manualPresented = false

    var body: some View {
        if let node = path.node(stepID), let entry = node.entry, let step = status.step(stepID) {
            let capability = PathCapability.of(stepID)
            let blocking = node.prerequisites.first { status.step($0)?.isPassed != true }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        ExerciseArtwork(entry: entry).frame(width: 76, height: 76).accessibilityHidden(true)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.levelName.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.6)
                            Text(entry.name).font(.system(size: 24, weight: .bold)).tracking(-0.6)
                            HStack(spacing: 6) { Pill(text: step.title, tint: stepTint(step)); Pill(text: capability.title, tint: Palette.ink) }
                        }
                    }
                    section("Why this step?") { Text(node.why).font(.subheadline) }
                    section("What you’ll practise") {
                        Text(entry.instruction).font(.subheadline)
                        if let target = node.practiceTarget {
                            HStack(spacing: 8) {
                                Pill(text: "\(target.sets) sets", tint: Palette.blue)
                                Pill(text: "\(target.target) \(entry.unit == .reps ? "reps" : "sec") each", tint: Palette.blue)
                                Pill(text: "\(target.perWeek)× a week", tint: Palette.blue)
                            }
                        }
                    }
                    section("To earn it") {
                        Text("3 sets of \(entry.goal) \(entry.unit == .reps ? "reps" : "seconds") across at least 2 training days. Manual and camera sets both count; sets with pain or discomfort don’t.")
                            .font(.subheadline)
                        Text("\(min(3, step.qualifyingSets))/3 goal sets · \(min(2, step.trainingDays))/2 days · manual \(step.manualSets), camera \(step.cameraSets)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(stepTint(step))
                        if let target = node.practiceTarget, target.target < entry.goal {
                            Text("Your practice target builds towards it; only sets of \(entry.goal) or more count.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !node.prerequisites.isEmpty {
                        section("Before this") {
                            ForEach(node.prerequisites, id: \.self) { id in
                                HStack {
                                    Label(ExerciseCatalog.find(id)?.name ?? id, systemImage: status.step(id)?.isPassed == true ? "checkmark.circle.fill" : "circle")
                                        .font(.subheadline).foregroundStyle(status.step(id)?.isPassed == true ? Palette.green : Palette.ink)
                                    Spacer()
                                    Button("Go") { select(id) }.font(.subheadline.weight(.semibold))
                                        .accessibilityLabel("Go to \(ExerciseCatalog.find(id)?.name ?? id)")
                                }
                            }
                        }
                    }
                    section("Assessment") {
                        Text(capability.detail).font(.subheadline)
                        if step.verification != .none {
                            Label(step.verification == .consistent ? "AI-verified on two days" : "AI-verified", systemImage: "star.fill").font(.subheadline).foregroundStyle(Palette.amber)
                        }
                    }
                    section("Rewards") {
                        Text("10 XP per goal set, up to 3 a day.\(capability == .cameraAssessment ? " +50 XP the first time the camera verifies it, +100 more on a second day." : "")")
                            .font(.subheadline)
                        let unlocks = path.nodes.filter { $0.prerequisites.contains(stepID) }.compactMap { $0.entry?.name }
                        if !unlocks.isEmpty { Text("Unlocks \(unlocks.joined(separator: ", ")).").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if step.state == .locked, let blocking {
                        PrimaryButton(title: "Go to \(ExerciseCatalog.find(blocking)?.name ?? blocking)", symbol: "arrow.turn.up.left") { select(blocking) }
                            .accessibilityIdentifier("path-step-goto")
                    } else {
                        PrimaryButton(title: "Start workout", symbol: "play") { startWorkout(stepID) }.accessibilityIdentifier("path-step-start")
                    }
                    Button { manualPresented = true } label: {
                        Label("Log manually", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(16)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue).accessibilityIdentifier("path-step-log")
                    Label("Stop if you feel pain or discomfort.", systemImage: "hand.raised").font(.caption).foregroundStyle(Palette.red)
                }.padding(24)
            }
            .sheet(isPresented: $manualPresented) { ManualWorkoutView(store: store, entry: entry, initialCount: entry.goal, initialSets: 3) }
        }
    }

    private func stepTint(_ step: PathStepStatus) -> Color {
        switch step.state {
        case .earned: return Palette.green
        case .current, .available: return Palette.blue
        case .notRequired, .locked: return Palette.muted
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct Pill: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(tint).background(tint.opacity(0.1), in: Capsule())
    }
}
