import SwiftUI

struct DemoCoachView: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var selected = DemoCoachTranscript.defaultSelection
    @State private var support = Set<String>()
    @State private var approved = false
    @State private var error: String?

    init(store: TrainingStore, profile: LocalProfile? = nil) {
        self.store = store
        self.profile = profile
    }

    private var missingSupport: Set<String> {
        DemoCoachTranscript.requiredSupport(selected: selected).subtracting(support)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    message(role: "OMAR · SAMPLE", text: "It's been a while since I've been to the gym. Can you put together a full week for me? I'd like to rebuild strength and get moving again.", user: true)
                        .accessibilityIdentifier("demo-coach-user-message")
                    workflow
                    message(role: "SPOTTR COACH · SAMPLE", text: "Let's make the first week achievable. We'll use two short strength sessions with recovery between them, gentle mobility and room to rest. Bodyweight work is enough to begin; the only required support here is a wall.")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your comeback week").font(.title2.bold())
                        Text("A conservative example, ready for your review.").font(.subheadline).foregroundStyle(.secondary)
                        Text("Start with a gentle warm-up. Use one easy set per selected exercise and 60 seconds between sets. Stop if an exercise causes pain; seek appropriate advice for symptoms or an existing condition.")
                            .font(.subheadline)
                        Text("I–V are Spottr's catalogue difficulty levels within each exercise family. They are not a medical readiness score. This restart stays at I–II; III–V can wait.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(DemoCoachTranscript.days) { day in dayCard(day) }
                    supportReview
                    message(role: "WHY THIS SHAPE?", text: "Two separated strength days give you a repeatable rhythm without filling every day with hard work. The NHS advises building up gradually; WHO includes strength work on at least two days in its adult guidance. This sample is a starting week, not the full long-term activity target.")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next week: earn the next step").font(.headline)
                        Text("If the week feels comfortable and you recover well, repeat it or add one or two reps to one exercise. Change one thing at a time. Keep the same level while learning the movement; no automatic jump to harder variations.")
                            .font(.subheadline)
                        Text("For the stretch, alternate sides between comfortable 15-second holds. Dead-bug reps count each side; a cat-cow rep is one gentle cycle.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    references
                    Text("This prewritten example does not assess your health or use your real profile. Approving it stays on this screen. Only work you explicitly start and finish can be recorded in the preview workspace.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.subheadline).foregroundStyle(Palette.red).accessibilityIdentifier("demo-coach-error") }
                }.padding(24)
            }
            .background(Color(.systemBackground))
            .accessibilityIdentifier("demo-coach-conversation")
            .safeAreaInset(edge: .bottom) { approvalBar }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("TestFlight preview", systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Palette.blue.opacity(0.08), in: Capsule())
                .accessibilityIdentifier("demo-coach-preview-badge")
            Text("A fresh start.\nA week that fits.").font(.largeTitle.bold())
            Text("Explore a prepared Coach conversation. No live AI request is made.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func message(role: String, text: String, user: Bool = false) -> some View {
        HStack {
            if user { Spacer(minLength: 20) }
            VStack(alignment: .leading, spacing: 8) {
                Text(role).font(.caption2.bold()).tracking(0.8)
                Text(text).font(.body).textSelection(.enabled)
            }
            .padding(18)
            .foregroundStyle(user ? Color.white : Color.primary)
            .background(user ? Palette.ink : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            if !user { Spacer(minLength: 8) }
        }
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sample planning workflow · prepared").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(["Reviewing goals", "Balancing recovery", "Checking guidance"].enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    Text("\(index + 1)").font(.caption.bold()).frame(width: 24, height: 24)
                        .background(Palette.blue.opacity(0.10), in: Circle())
                    Text(title).font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green).accessibilityLabel("Prepared")
                }
            }
        }.padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("demo-coach-workflow")
    }

    private func dayCard(_ day: DemoCoachTranscript.Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(day.title).font(.headline); Spacer(); dayKind(day) }
                VStack(alignment: .leading) { Text(day.title).font(.headline); dayKind(day) }
            }
            Text(day.note).font(.subheadline).foregroundStyle(.secondary)
            ForEach(day.exerciseIDs, id: \.self) { id in
                if let entry = ExerciseCatalog.find(id) {
                    Toggle(isOn: selectionBinding(id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).font(.subheadline.weight(.semibold))
                            Text("\(entry.levelName) · 1 × \(DemoCoachTranscript.target(exerciseID: id)) \(entry.unit == .reps ? "reps" : "sec")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(entry.instruction).font(.caption).foregroundStyle(.secondary)
                            Text(entry.support.map { "Support: \($0)" } ?? "No equipment needed").font(.caption)
                        }
                    }.tint(Palette.blue).accessibilityIdentifier("demo-coach-exercise-\(day.id)-\(id)")
                }
            }
            if approved && !day.exerciseIDs.filter({ selected.contains($0) }).isEmpty {
                Button { start(day) } label: { Label("Start \(day.title) workout", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(Palette.blue)
                    .accessibilityIdentifier("demo-coach-start-\(day.id)")
            }
        }.padding(18).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("demo-coach-day-\(day.id)")
    }

    private func dayKind(_ day: DemoCoachTranscript.Day) -> some View {
        Text(day.kind.rawValue).font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
            .padding(.horizontal, 9).padding(.vertical, 5).background(Palette.blue.opacity(0.08), in: Capsule())
    }

    private var supportReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check your space").font(.headline)
            Toggle("I have a clear, stable wall for wall push-ups", isOn: Binding(get: { support.contains("Wall") }, set: { value in
                support = value ? ["Wall"] : []
                approved = false
            })).tint(Palette.blue).accessibilityIdentifier("demo-coach-support-wall")
            if !missingSupport.isEmpty {
                Text("Confirm the wall, or deselect wall push-ups, before approving.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Changes apply to every day containing that exercise and require approval again.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var approvalBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(selected.count) of 7 exercises selected").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("demo-coach-selection-count")
            Button(approved ? "Week approved · choose a day above" : "Approve selected week") {
                approved = true
                error = nil
            }
            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(14)
            .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 14))
            .disabled(selected.isEmpty || !missingSupport.isEmpty || approved)
            .accessibilityIdentifier("demo-coach-approve")
        }.padding(.horizontal, 24).padding(.vertical, 12).background(.regularMaterial)
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Read the guidance").font(.headline)
            Text("General guidance informs the example; the exact doses and schedule are illustrative.").font(.caption).foregroundStyle(.secondary)
            Link(destination: URL(string: "https://www.nhs.uk/live-well/exercise/strength-exercises/")!) {
                Label("NHS · gentle strength exercises", systemImage: "arrow.up.right.square")
            }.accessibilityIdentifier("demo-coach-link-nhs-strength")
            Link(destination: URL(string: "https://www.nhs.uk/live-well/exercise/how-to-improve-strength-flexibility/")!) {
                Label("NHS · strength and flexibility", systemImage: "arrow.up.right.square")
            }.accessibilityIdentifier("demo-coach-link-nhs-flexibility")
            Link(destination: URL(string: "https://www.who.int/initiatives/behealthy/physical-activity/")!) {
                Label("WHO · physical activity", systemImage: "arrow.up.right.square")
            }.accessibilityIdentifier("demo-coach-link-who")
        }.font(.subheadline).tint(Palette.blue)
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { value in
            selected = value ? selected.union([id]) : selected.subtracting([id])
            approved = false
            error = nil
        })
    }

    private func start(_ day: DemoCoachTranscript.Day) {
        guard approved else { return }
        do {
            let plan = try DemoCoachTranscript.plan(dayID: day.id, selected: selected, support: support)
            store.startPlan(plan, availableSupport: support)
            error = store.error
        } catch {
            self.error = "Select at least one exercise for this day and confirm its required support."
        }
    }
}
