import SwiftUI

/// "Build my training path": five short questions, an editable review, one Gemini plan (checked by the app, with the
/// catalogue path as the labelled fallback), and a preview of the path and what changes before anything is saved.
struct PathSurveyView: View {
    enum Step: Int, CaseIterable {
        case goal, start, equipment, routine, preferences, review
        var title: String { ["Goal", "Starting point", "Space", "Routine", "Preferences", "Review"][rawValue] }
    }
    private enum Phase { case questions, generating, preview(PathGenerator.Outcome) }

    @Bindable var store: TrainingStore
    let pathStore: TrainingPathStore
    @Environment(\.dismiss) private var dismiss
    @State private var answers: PathSurvey
    @State private var step: Step
    @State private var phase = Phase.questions
    @State private var fromReview = false
    @State private var saveError: String?

    init(store: TrainingStore, pathStore: TrainingPathStore, profile: LocalProfile?, startAtReview: Bool = false) {
        self.store = store; self.pathStore = pathStore
        let saved = pathStore.survey ?? PathSurvey(profile: profile)
        _answers = State(initialValue: saved)
        _step = State(initialValue: startAtReview ? .review : .goal)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .questions: questions
                case .generating: generating
                case .preview(let outcome): preview(outcome)
                }
            }
            .background(.white)
            .navigationTitle("Build my training path").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.accessibilityIdentifier("path-survey-close") } }
        }
        .onChange(of: answers) { _, value in pathStore.saveSurvey(value) }
    }

    // MARK: Questions

    private var questions: some View {
        VStack(spacing: 0) {
            progress.padding(.horizontal, 24).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .goal: goalStep
                    case .start: startStep
                    case .equipment: equipmentStep
                    case .routine: routineStep
                    case .preferences: preferencesStep
                    case .review: reviewStep
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule().fill(item.rawValue < step.rawValue ? Palette.green : item == step ? Palette.blue : Palette.surface).frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count): \(step.title)")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .goal {
                Button("Back") { go(Step(rawValue: step.rawValue - 1) ?? .goal) }
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 17)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).buttonStyle(.plain)
            }
            if step == .review {
                PrimaryButton(title: pathStore.active == nil ? "Build my path" : "Build a new version", symbol: "sparkles") { generate() }
                    .accessibilityIdentifier("path-build")
            } else {
                PrimaryButton(title: fromReview ? "Back to review" : "Continue", symbol: "arrow.right") {
                    go(fromReview && (step != .goal || answers.abilityKey != nil) ? .review : Step(rawValue: step.rawValue + 1) ?? .review)
                }
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.45).accessibilityIdentifier("path-continue")
            }
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.white)
    }

    private var canContinue: Bool {
        switch step {
        case .start: return answers.abilityKey != nil
        case .equipment: return answers.equipment != nil
        case .preferences: return answers.focus != nil && answers.coachingStyle != nil
        default: return true
        }
    }

    private func go(_ next: Step) {
        if next == .review { fromReview = false }
        step = next
    }

    private func heading(_ title: String, _ lede: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.8).accessibilityAddTraits(.isHeader)
            Text(lede).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.bottom, 4)
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("What do you want to work towards?", "Pick one path. You can change it later.")
            ForEach(PathGoal.allCases, id: \.self) { goal in
                let entry = ExerciseCatalog.find(goal.exerciseID)!
                OptionCard(title: goal.title, detail: goal == .squat ? "Camera-assessed lowering tempo" : "Camera-assessed rep time",
                           selected: answers.goal == goal, art: entry) {
                    if answers.goal != goal { answers.goal = goal; answers.abilityKey = nil; answers.avoid = [] }
                }
            }
            Note(text: "Further steps on each path are practice for now: the camera assesses squats and push-ups only.")
        }
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(answers.goal == .squat ? "Where are you with squats?" : "Where are you with push-ups?", "Choose the closest. “I’m not sure” is a good answer.")
            ForEach(answers.goal.abilityOptions, id: \.key) { option in
                OptionCard(title: option.label, detail: placementHint(option.band), selected: answers.abilityKey == option.key) { answers.abilityKey = option.key }
            }
            Note(text: "This places your starting step. It is not a strength score.")
        }
    }

    private func placementHint(_ band: PlacementBand) -> String {
        switch band {
        case .beginner: return "We start at the foundation"
        case .intermediate: return "We start at the camera movement"
        case .advanced: return "We start at the camera movement"
        case .unsure: return "We start at the foundation, and you can move on quickly"
        }
    }

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("What do you have nearby?", "Select all that apply. Steps that need something you don’t have are left out.")
            ForEach(PathSurvey.equipmentChoices, id: \.self) { name in
                OptionCard(title: name, detail: equipmentHint(name), selected: answers.equipment?.contains(name) == true, multiple: true, symbol: equipmentSymbol(name)) {
                    var set = answers.equipment ?? []
                    if set.contains(name) { set.remove(name) } else { set.insert(name) }
                    answers.equipment = set
                }
            }
            OptionCard(title: "None of these", detail: "Floor space only", selected: answers.equipment == [], multiple: true, symbol: "square.dashed") { answers.equipment = [] }
        }
    }
    private func equipmentHint(_ name: String) -> String {
        ExerciseCatalog.all.filter { PathSurvey.requiredEquipment(for: $0) == name }.map(\.name).joined(separator: ", ")
    }
    private func equipmentSymbol(_ name: String) -> String {
        name == "Wall" ? "rectangle.portrait" : name.contains("sofa") ? "sofa" : "chair"
    }

    private var routineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("How does training fit your week?", "This sets how much each step asks of you.")
            Text("Time per session").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([10, 20, 30, 45], id: \.self) { minutes in
                    ChoiceTile(title: "\(minutes) min", selected: answers.minutesPerSession == minutes) { answers.minutesPerSession = minutes }
                }
            }
            Text("Sessions per week").font(.headline).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([2, 3, 4, 5], id: \.self) { days in
                    ChoiceTile(title: "\(days)", selected: answers.sessionsPerWeek == days) { answers.sessionsPerWeek = days }
                        .accessibilityLabel("\(days) sessions per week")
                }
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("How would you like to train?", "Two quick choices, and anything you’d rather skip.")
            Text("Main focus").font(.headline)
            ForEach(PathFocus.allCases, id: \.self) { focus in
                OptionCard(title: focus.title, detail: nil, selected: answers.focus == focus) { answers.focus = focus }
            }
            Text("Coaching style").font(.headline).padding(.top, 6)
            HStack(spacing: 10) {
                ForEach(CoachingStyle.allCases, id: \.self) { style in
                    ChoiceTile(title: style.title, selected: answers.coachingStyle == style) { answers.coachingStyle = style }
                }
            }
            Text("Movements to leave out (optional)").font(.headline).padding(.top, 6)
            ForEach(answers.goal.avoidable, id: \.self) { id in
                Toggle(isOn: Binding(get: { answers.avoid.contains(id) }, set: { on in if on { answers.avoid.insert(id) } else { answers.avoid.remove(id) } })) {
                    Text(ExerciseCatalog.find(id)?.name ?? id).font(.subheadline)
                }.tint(Palette.blue)
            }
            Note(text: "Leaving a movement out simply removes it from your path. We don’t ask why.")
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Here’s what we’ll use", pathStore.active == nil ? "Edit anything before your path is built." : "Your earned progress carries over to the new version.")
            reviewRow(.goal, "Goal", answers.goal.title)
            reviewRow(.start, "Starting point", answers.goal.abilityOptions.first { $0.key == answers.abilityKey }?.label ?? "Not answered")
            reviewRow(.equipment, "Nearby", answers.equipment.map { $0.isEmpty ? "Floor space only" : $0.sorted().joined(separator: ", ") } ?? "Not answered")
            reviewRow(.routine, "Routine", "\(answers.minutesPerSession) min, \(answers.sessionsPerWeek) sessions a week")
            reviewRow(.preferences, "Focus and style", [answers.focus?.title, answers.coachingStyle?.title].compactMap { $0 }.joined(separator: ", ")
                + (answers.avoid.isEmpty ? "" : "; leave out \(answers.avoid.compactMap { ExerciseCatalog.find($0)?.name.lowercased() }.sorted().joined(separator: ", "))"))
            Note(text: "Gemini picks your steps, start and practice targets from the Spottr catalogue. The app checks every link, target and capability before you see it.")
        }
    }

    private func reviewRow(_ target: Step, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.isEmpty ? "Not answered" : value).font(.subheadline)
            }
            Spacer()
            Button("Edit") { fromReview = true; step = target }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue).accessibilityLabel("Edit \(label.lowercased())")
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    // MARK: Generation and preview

    private var generating: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Building your path…").font(.title3.bold())
            Text("Gemini is choosing your steps from the catalogue. Every link, target and capability is then checked by the app.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func generate(repair: [String] = []) {
        phase = .generating
        let survey = answers, client = try? CoachSettings.client()
        Task {
            let outcome = await PathGenerator.generate(survey: survey, repair: repair) { request in
                guard let client else { throw CoachGatewayError.configuration }
                return try await client.pathProposal(request)
            }
            phase = .preview(outcome)
        }
    }

    private func preview(_ outcome: PathGenerator.Outcome) -> some View {
        let skill = SkillProgress.evaluate(history: store.history)
        let status = PathStatus.evaluate(path: outcome.path, skill: skill, attempts: pathStore.attempts)
        let diff = PathDiff.between(pathStore.active?.path, outcome.path, skill: skill, attempts: pathStore.attempts)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pathStore.active == nil ? "Your path" : "Your new path, before saving").font(.system(size: 28, weight: .bold)).tracking(-0.8)
                    ProvenanceBadge(provenance: outcome.path.provenance)
                    if !outcome.problems.isEmpty {
                        Note(text: outcome.repairable.isEmpty ? "Gemini’s plan was unavailable, so this path is built from the catalogue with the same answers."
                             : "Gemini’s plan didn’t pass the app’s checks (\(outcome.problems.first ?? "")), so this path is built from the catalogue.")
                    }
                    PathMapView(path: outcome.path, status: status, skill: skill, animateIn: true) { _ in }
                        .frame(maxWidth: .infinity).accessibilityLabel("Preview of your path")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(outcome.path.rationale.startReason).font(.headline)
                        Text(outcome.path.rationale.text).font(.subheadline).foregroundStyle(.secondary)
                        Label(outcome.path.rationale.emphasis, systemImage: "scope").font(.subheadline).foregroundStyle(Palette.blue)
                    }
                    if pathStore.active != nil { DiffCard(diff: diff) }
                    if let saveError { Text(saveError).font(.caption).foregroundStyle(Palette.red) }
                }.padding(24)
            }
            HStack(spacing: 12) {
                Button("Adjust answers") { phase = .questions; step = .review }
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 17)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).buttonStyle(.plain)
                if !outcome.repairable.isEmpty {
                    Button("Ask Gemini to fix it") { generate(repair: outcome.repairable) }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 17).buttonStyle(.plain).foregroundStyle(Palette.blue)
                }
                PrimaryButton(title: pathStore.active == nil ? "Start my path" : "Save as version \((pathStore.active?.id ?? 0) + 1)", symbol: "checkmark") {
                    do { try pathStore.accept(outcome.path, survey: answers); dismiss() }
                    catch { saveError = "This path didn’t pass the app’s checks, so it wasn’t saved. Adjust your answers and try again." }
                }.accessibilityIdentifier("path-accept")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(.white)
        }
    }
}

// MARK: - Survey building blocks

private struct OptionCard: View {
    let title: String
    let detail: String?
    let selected: Bool
    var multiple = false
    var art: ExerciseEntry? = nil
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let art { ExerciseArtwork(entry: art).frame(width: 56, height: 56).accessibilityHidden(true) }
                else if let symbol { Image(systemName: symbol).font(.title3).foregroundStyle(Palette.blue).frame(width: 30) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (multiple ? "square" : "circle"))
                    .font(.title3).foregroundStyle(selected ? Palette.blue : Palette.muted.opacity(0.6))
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.blue.opacity(0.07) : Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(selected ? Palette.blue : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ChoiceTile: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(selected ? Palette.blue.opacity(0.07) : Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).stroke(selected ? Palette.blue : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
    }
}

struct ProvenanceBadge: View {
    let provenance: PathProvenance
    var body: some View {
        Label(provenance == .gemini ? "Personalised by Gemini, checked by the app" : "Built from the catalogue",
              systemImage: provenance == .gemini ? "sparkles" : "list.bullet.rectangle")
            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(provenance == .gemini ? Palette.blue : Palette.muted)
            .background((provenance == .gemini ? Palette.blue : Palette.muted).opacity(0.09), in: Capsule())
            .accessibilityElement(children: .combine).accessibilityIdentifier("path-provenance")
    }
}

private struct DiffCard: View {
    let diff: PathDiff
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What changes", systemImage: "arrow.triangle.branch").font(.headline)
            if diff.changesStart { bullet("Start moves from \(name(diff.startFrom)) to \(name(diff.startTo))") }
            if diff.changesGoal { bullet("Goal moves from \(name(diff.goalFrom)) to \(name(diff.goalTo))") }
            if !diff.added.isEmpty { bullet("New steps: \(diff.added.map(name).joined(separator: ", "))") }
            if !diff.removed.isEmpty { bullet("Leaving this version: \(diff.removed.map(name).joined(separator: ", "))") }
            if !diff.carried.isEmpty { bullet("Progress carried over: \(diff.carried.map(name).joined(separator: ", "))") }
            if !diff.keptInHistory.isEmpty { bullet("Kept in your history and level: \(diff.keptInHistory.map(name).joined(separator: ", "))") }
            if !diff.changesStart && !diff.changesGoal && diff.added.isEmpty && diff.removed.isEmpty { bullet("Same steps; wording and targets may differ.") }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func bullet(_ text: String) -> some View { Text("• \(text)").font(.subheadline) }
    private func name(_ id: String?) -> String { id.flatMap { ExerciseCatalog.find($0)?.name } ?? (id ?? "—") }
}
