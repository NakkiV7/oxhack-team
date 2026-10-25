import SwiftUI

struct WeeklyCoachPanel: View {
    let model: CoachModel
    let store: TrainingStore
    let profile: LocalProfile?
    let support: Set<String>
    let propose: (CoachWeekRequest) -> Void
    @State private var startDate = Date()
    @State private var available = Set(0...6)
    @State private var targetDays = 3
    @State private var selected = Set<String>()
    @State private var movedDates: [String: String] = [:]
    @State private var removingWeek = false
    @State private var initialised = false

    private var request: CoachWeekRequest? {
        try? CoachWeekRequest(startDate: Self.dateString(startDate), timeZone: TimeZone.current.identifier,
                              availableDays: available.sorted(), targetDays: targetDays)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("A week that fits.").font(.title2.bold())
                    Text("Choose your availability. Review every day before saving.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "calendar").font(.title2).foregroundStyle(Palette.blue)
            }
            DisclosureGroup("Plan your week") {
                VStack(alignment: .leading, spacing: 13) {
                    DatePicker("Starting", selection: $startDate, displayedComponents: .date).tint(Palette.blue)
                    Text("Available days").font(.caption.weight(.semibold))
                    if let dates = try? CoachWeekRequest(startDate: Self.dateString(startDate), timeZone: TimeZone.current.identifier, availableDays: Array(0...6), targetDays: 1).dates() {
                        ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                            Toggle(Self.dayTitle(date), isOn: Binding(get: { available.contains(index) }, set: { enabled in
                                if enabled { available.insert(index) } else { available.remove(index) }
                                targetDays = min(targetDays, max(1, available.count))
                            })).tint(Palette.blue).font(.subheadline)
                        }
                    }
                    Stepper("Up to \(targetDays) workout \(targetDays == 1 ? "day" : "days")", value: $targetDays, in: 1...max(1, available.count)).font(.subheadline)
                    Text("Dates use \(TimeZone.current.identifier). Calendar spacing does not establish recovery or medical readiness.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.font(.subheadline.weight(.medium)).disabled(model.isLoading)
            Button {
                if let request { propose(request) }
            } label: {
                Label("Propose my week", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(17).foregroundStyle(.white)
                    .background(request == nil ? Palette.muted : Palette.blue, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).disabled(model.isLoading || request == nil).accessibilityIdentifier("propose-week")
            if let proposal = model.weekProposal { review(proposal) }
            if let week = model.approvedWeek { saved(week) }
            Text("General exercise planning, not medical advice. Symptoms or treatment questions need a qualified healthcare professional.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if !initialised { targetDays = min(7, profile?.weeklyTarget ?? 3); initialised = true } }
        .onChange(of: startDate) { _, _ in invalidate() }
        .onChange(of: available) { _, _ in invalidate() }
        .onChange(of: targetDays) { _, _ in invalidate() }
        .onChange(of: model.weekProposal?.generationID) { _, _ in selected = []; movedDates = [:] }
        .alert("Remove saved week?", isPresented: $removingWeek) {
            Button("Remove week", role: .destructive) { model.removeApprovedWeek() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Completed sessions and your separate saved workout stay in your history and Coach.") }
    }

    private func review(_ proposal: CoachWeekProposal) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if let reason = proposal.reason {
                Label(reason == .urgent ? "Pause and get help" : "Let’s keep this appropriate", systemImage: reason == .urgent ? "exclamationmark.triangle" : "info.circle")
                    .font(.headline).foregroundStyle(reason == .urgent ? Palette.red : Palette.ink)
                Text(reason.message).font(.subheadline)
            } else {
                Text("Your proposed week").font(.title3.bold())
                if let rationale = proposal.rationale { Text(rationale.text).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(proposal.days) { day in
                    if let workout = day.workout {
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle(isOn: Binding(get: { selected.contains(day.date) }, set: { enabled in
                                if enabled { selected.insert(day.date) } else { selected.remove(day.date); movedDates.removeValue(forKey: day.date) }
                            })) { Text(Self.dayTitle(day.date)).font(.subheadline.weight(.semibold)) }.tint(Palette.blue)
                            ForEach(workout.items, id: \.exerciseID) { item in
                                Text("\(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID) · \(item.sets) × \(item.target) \(item.unit == .reps ? "reps" : "sec") · \(item.restSeconds)s rest")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if selected.contains(day.date), let request, let dates = try? request.dates() {
                                Picker("Move to", selection: Binding(get: { movedDates[day.date] ?? day.date }, set: { movedDates[day.date] = $0 })) {
                                    ForEach(request.availableDays.map { dates[$0] }, id: \.self) { date in Text(Self.dayTitle(date)).tag(date) }
                                }.font(.caption).tint(Palette.blue)
                            }
                        }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    } else {
                        HStack { Text(Self.dayTitle(day.date)); Spacer(); Label("Rest / no workout", systemImage: "moon") }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Approve & save selected days") {
                    model.approveWeek(selectedDates: selected, movedDates: movedDates, currentSupport: support)
                }.font(.subheadline.weight(.semibold)).foregroundStyle(selected.isEmpty ? Palette.muted : Palette.blue)
                    .disabled(selected.isEmpty || model.isLoading).accessibilityIdentifier("approve-week")
                Text("Nothing is selected by default. Saving a week does not start or record a workout. You can move selected workouts to different available days.").font(.caption).foregroundStyle(.secondary)
            }
            CoachGuidanceReferences(ids: proposal.guidanceIDs)
        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 19))
    }

    private func saved(_ week: CoachSavedWeek) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your saved week", systemImage: "checkmark.circle").font(.headline).foregroundStyle(Palette.green)
            Text("Week of \(week.weekStart) · \(week.timeZone)").font(.caption).foregroundStyle(.secondary)
            ForEach(week.days) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.dayTitle(day.date)).font(.subheadline.weight(.semibold))
                    ForEach(day.plan.items) { item in
                        Text("\(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID) · \(item.sets) × \(item.target) \(item.unit == .reps ? "reps" : "sec")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { store.startPlan(day.plan, availableSupport: support) } label: { Label("Start this workout", systemImage: "play.fill") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue).disabled(model.isLoading)
                }
            }
            Text("Start a day explicitly, then record only work you complete. Dates are a plan, not evidence of completed training or readiness.").font(.caption).foregroundStyle(.secondary)
            CoachGuidanceReferences(ids: week.guidanceIDs)
            Button("Remove saved week", role: .destructive) { removingWeek = true }.font(.subheadline).foregroundStyle(Palette.red)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 19))
    }
    private func invalidate() { selected = []; movedDates = [:]; model.invalidateContext() }
    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    private static func dayTitle(_ string: String) -> String {
        let parser = DateFormatter(); parser.calendar = Calendar(identifier: .gregorian); parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: string) else { return string }
        parser.dateFormat = "EEE d MMM"; return parser.string(from: date)
    }
}

private struct CoachGuidanceReferences: View {
    let ids: [String]
    var body: some View {
        if let registry = try? CoachGuidanceRegistry.bundled(), let sources = try? registry.sources(for: ids) {
            DisclosureGroup("Guidance & sources") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 5) {
                            if let url = URL(string: source.url) { Link(source.title, destination: url).font(.caption.weight(.semibold)).foregroundStyle(Palette.blue) }
                            Text(source.summary).font(.caption)
                            Text(source.audience).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.top, 10)
            }.font(.caption.weight(.medium))
        }
    }
}
