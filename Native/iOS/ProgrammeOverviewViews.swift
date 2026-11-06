import SwiftUI

struct ProgrammeTodayCard: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    let openSetup: () -> Void
    let openLibrary: () -> Void
    @State private var selectedID: String?
    private var date: Date { store.programme?.referenceDate ?? .now }
    private var calendar: Calendar { store.programme?.localCalendar ?? .current }
    @State private var error: String?
    @State private var progress: [ProgrammeInsights.DayProgress] = []
    @Environment(\.scenePhase) private var scenePhase
    private var week: TrainingProgramme? { store.programme?.current }
    private var day: TrainingProgramme.Day? {
        week?.days.first { $0.id == selectedID } ?? week?.days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    private var ongoing: Bool { store.sessionPhase != .idle && store.sessionPhase != .finished }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let week {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(week.days) { value in
                            Button { selectedID = value.id; SpottrHaptics.selection() } label: {
                                VStack(spacing: 7) {
                                    Text(value.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                    Text(value.date.formatted(.dateTime.day())).font(.headline)
                                    Image(systemName: progress.first { $0.id == value.id }?.completed == true ? "checkmark.circle.fill" : value.kind == .rest ? "moon" : "circle")
                                        .font(.caption)
                                }.frame(minWidth: 42, minHeight: 76).padding(4)
                                    .foregroundStyle(value.id == day?.id ? .white : Palette.ink)
                                    .background(value.id == day?.id ? Palette.blue : .white, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(value.date.formatted(date: .complete, time: .omitted)), \(title(value)), \(progress.first { $0.id == value.id }?.recordedSets ?? 0) recorded sets")
                                .accessibilityAddTraits(value.id == day?.id ? .isSelected : [])
                                .accessibilityIdentifier("programme-day-\(value.localDate)")
                        }
                    }
                }.accessibilityIdentifier("programme-week")
                if let day {
                    Text(title(day)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if day.kind == .familyMovement {
                        Text("With a guardian nearby, try reaching for a soft toy, moving to a favourite song or exploring a safe play space. Follow their interest and take breaks together.")
                            .font(.subheadline)
                        Text("Play ideas, with no formal sets, camera test or workout target.").font(.caption).foregroundStyle(.secondary)
                    } else if let plan = day.plan {
                        Text("\(plan.items.count) movements · \(plan.items.reduce(0) { $0 + $1.sets }) planned sets")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(plan.items) { item in
                            HStack(alignment: .center, spacing: 12) {
                                if let entry = ExerciseCatalog.find(item.exerciseID) {
                                    ExerciseArtwork(entry: entry).frame(width: 58, height: 70).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name).font(.subheadline.weight(.semibold))
                                        Text("\(item.sets) × \(item.target) \(item.unit.rawValue) · \(item.restSeconds)s rest")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.accessibilityElement(children: .combine)
                        }
                        if let actual = progress.first(where: { $0.id == day.id }), actual.recordedSets > 0 {
                            Text("\(actual.recordedSets) of \(actual.plannedSets) planned sets recorded · \(actual.recordedReps) actual reps")
                                .font(.subheadline.weight(.medium)).accessibilityIdentifier("programme-actual-progress")
                        }
                    } else {
                        Text("A day to rest. Gentle everyday movement is optional. Your next planned workout stays ready for its scheduled day.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if ongoing {
                        PrimaryButton(title: "Continue your workout", symbol: "play") { store.presented = true }
                    } else if day.plan != nil && calendar.isDate(day.date, inSameDayAs: date) && !store.history.contains(where: { $0.plannedWorkoutID == day.id }) {
                        PrimaryButton(title: day.kind == .recovery ? "Start gentle session" : "Start whole workout", action: { store.launchPlanned(dayID: day.id) })
                            .accessibilityIdentifier("today-start-session")
                    } else if day.plan != nil && !calendar.isDate(day.date, inSameDayAs: date) {
                        Text("Planned for \(day.date.formatted(.dateTime.weekday(.wide)))").font(.caption.weight(.semibold))
                    }
                    if day.kind != .familyMovement, !store.protectedProgrammeDayIDs.contains(day.id), day.date >= calendar.startOfDay(for: date) {
                        Menu("Adjust this day") {
                            if day.plan != nil {
                                Button("Make it easier") { adjust(.easier, day: day) }
                                Button("Shorten this workout") { adjust(.shorter, day: day) }
                            }
                            Button("Take a rest day") { adjust(.rest, day: day) }
                        }.buttonStyle(.bordered).accessibilityIdentifier("programme-adjust")
                    }
                }
            } else {
                Text("Prepare your week").font(.title2.bold())
                Text("Your goals, activity days and movement choices shape a complete programme.")
                    .font(.subheadline).foregroundStyle(.secondary)
                PrimaryButton(title: "Complete your training profile", action: openSetup)
            }
            if profileStore.profile?.programmePreferences?.ageContext?.allowsCloudPlanSync == true, let sync = store.programme?.sync {
                NavigationLink("Optional programme sync") { ProgrammeSyncView(sync: sync) }.font(.subheadline)
            }
            if let error = error ?? store.programme?.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            if (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) >= 5 {
                Button(action: openLibrary) { Label("Practise one movement", systemImage: "square.grid.2x2") }
                    .buttonStyle(.bordered).accessibilityIdentifier("today-library")
            }
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
            .onAppear { refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .onChange(of: profileStore.profile) { _, _ in refresh() }
            .onChange(of: store.history) { _, _ in updateProgress() }
            .onChange(of: store.programme?.current) { _, _ in updateProgress() }
    }
    private func refresh() {
        guard let profile = profileStore.profile, profile.programmePreferences?.ageContext != nil else { return }
        do { try store.programme?.reconcile(profile: profile, history: store.history, protecting: store.protectedProgrammeDayIDs, at: date); error = nil; updateProgress() }
        catch { self.error = error.localizedDescription }
    }
    private func updateProgress() { progress = week.map { ProgrammeInsights.progress(week: $0, history: store.history) } ?? [] }
    private func adjust(_ action: ProgrammeArchive.Adjustment, day: TrainingProgramme.Day) {
        do { try store.programme?.adjust(dayID: day.id, action: action, history: store.history, protecting: store.protectedProgrammeDayIDs); error = nil }
        catch { self.error = "This day is protected by recorded or active work. Choose an unstarted day." }
    }
    private func title(_ day: TrainingProgramme.Day) -> String {
        switch day.kind {
        case .workout: return "Your whole workout"
        case .recovery: return "A gentler session"
        case .rest: return "Time to recover"
        case .familyMovement: return "Move and play together"
        }
    }
}
