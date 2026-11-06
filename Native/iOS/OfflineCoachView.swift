import SwiftUI

@MainActor struct CoachProgrammeActions {
    let store: TrainingStore
    let profile: NativeProfileStore
    enum Failure: LocalizedError {
        case changed, unavailable, unchanged
        var errorDescription: String? {
            switch self {
            case .changed: "Your plan changed. Review it and choose again."
            case .unavailable: "Choose an unstarted training day. Recorded and active work stays protected."
            case .unchanged: "This workout is already as short or gentle as this adjustment allows."
            }
        }
    }
    var days: [TrainingProgramme.Day] {
        guard profile.permitsPolicyCallbacks, store.historyAvailable, let programme = store.programme,
              (profile.profile?.effectiveProgrammePreferences.ageContext?.ageYears ?? 0) >= 5 else { return [] }
        return programme.current?.days.filter {
            $0.date >= programme.localCalendar.startOfDay(for: programme.referenceDate) && !store.protectedProgrammeDayIDs.contains($0.id)
        } ?? []
    }
    func replacements(for item: CoachSavedPlan.Item, day: TrainingProgramme.Day) -> [ExerciseEntry] {
        guard let preferences = profile.profile?.programmePreferences, preferences.ageContext != nil,
              let old = ExerciseCatalog.find(item.exerciseID) else { return [] }
        return ExerciseCatalog.all.filter { entry in
            entry.family == old.family && preferences.canUse(entry) && !(day.plan?.items.contains { $0.exerciseID == entry.id } ?? true)
        }
    }
    func apply(_ action: ProgrammeArchive.Adjustment, dayID: String, revision: Int) throws {
        guard let programme = store.programme, programme.current?.revision == revision else { throw Failure.changed }
        guard let day = days.first(where: { $0.id == dayID }), let plan = day.plan else { throw Failure.unavailable }
        switch action {
        case .easier:
            guard plan.items.contains(where: { $0.target > 1 || $0.restSeconds < 60 }) else { throw Failure.unchanged }
        case .shorter:
            guard plan.items.count > 1 || plan.items.contains(where: { $0.sets > 1 }) else { throw Failure.unchanged }
        case .swap(let id, let replacement):
            guard let item = plan.items.first(where: { $0.exerciseID == id }), replacements(for: item, day: day).contains(where: { $0.id == replacement }) else { throw Failure.unavailable }
        case .move(let destination):
            guard destination != dayID, days.contains(where: { $0.id == destination }) else { throw Failure.unavailable }
        case .rest: break
        }
        try programme.adjust(dayID: dayID, action: action, history: store.history, protecting: store.protectedProgrammeDayIDs)
    }
}

struct OfflineCoachView: View {
    let store: TrainingStore
    let profileStore: NativeProfileStore
    var openProgress: () -> Void = {}
    @State private var selectedID: String?
    @State private var message: String?
    @State private var error: String?
    private var actions: CoachProgrammeActions { .init(store: store, profile: profileStore) }
    private var day: TrainingProgramme.Day? {
        actions.days.first { $0.id == selectedID && $0.plan != nil } ?? actions.days.first { $0.plan != nil }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeading(title: "Your plan, your pace", subtitle: "Small adjustments for the days ahead.")
                    if let previews = store.voicePreviews {
                        NavigationLink { VoiceCoachSettingsView(previews: previews, repVoice: store.repVoice) } label: {
                            HStack(spacing: 14) {
                                TrainerPortrait(voice: previews.preference).frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(previews.preference.title).font(.headline)
                                    Text("Voice and coaching style").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(SpottrPressStyle())
                    }
                    if let day, let plan = day.plan, let week = store.programme?.current {
                        VStack(alignment: .leading, spacing: 14) {
                            Menu {
                                ForEach(actions.days.filter { $0.plan != nil }) { option in
                                    Button(option.date.formatted(date: .complete, time: .omitted)) { selectedID = option.id; message = nil; error = nil; SpottrHaptics.selection() }
                                }
                            } label: {
                                Label(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)), systemImage: "calendar")
                            }.buttonStyle(.bordered).accessibilityIdentifier("coach-training-day")
                            ForEach(plan.items) { item in
                                if let entry = ExerciseCatalog.find(item.exerciseID) {
                                    HStack(spacing: 12) {
                                        ExerciseArtwork(entry: entry).frame(width: 48, height: 58)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.name).font(.subheadline.weight(.semibold))
                                            Text("\(item.sets) \(item.sets == 1 ? "set" : "sets") of \(item.target) \(item.unit.rawValue), with \(item.restSeconds) seconds rest.").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                            if store.programme?.day()?.id == day.id {
                                PrimaryButton(title: "Open today's workout", symbol: "play") { store.launchPlanned(dayID: day.id, origin: .coach) }
                                    .accessibilityIdentifier("coach-open-workout")
                            }
                        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        VStack(spacing: 12) {
                            action("Make it easier", detail: "Lower the targets and allow more rest.", symbol: "leaf", id: "easier") { apply(.easier, day: day, revision: week.revision, message: "Lower targets are saved for this day.") }
                            action("Shorten this workout", detail: "Reduce the number of movements and sets.", symbol: "clock", id: "shorter") { apply(.shorter, day: day, revision: week.revision, message: "Your shorter workout is saved.") }
                            NavigationLink { CoachSwapView(actions: actions, day: day, revision: week.revision) } label: {
                                CoachActionLabel(title: "Swap a movement", detail: "Choose another movement in the same family.", symbol: "arrow.triangle.swap")
                            }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("coach-swap")
                            NavigationLink { CoachMoveDayView(actions: actions, day: day, revision: week.revision) } label: {
                                CoachActionLabel(title: "Move training day", detail: "Exchange this plan with another unstarted day.", symbol: "calendar.badge.clock")
                            }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("coach-move")
                            action("Take a recovery day", detail: "Replace this workout with rest.", symbol: "moon", id: "rest") { apply(.rest, day: day, revision: week.revision, message: "Rest is saved for \(day.date.formatted(.dateTime.weekday(.wide))).") }
                        }
                    } else {
                        Text("No unstarted workouts are available to adjust. Review your week in Today or complete your training setup in Profile.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let message { Label(message, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Palette.green).accessibilityIdentifier("coach-result") }
                    if let error { Text(error).font(.subheadline).foregroundStyle(Palette.red).accessibilityIdentifier("coach-error") }
                    action("Review progress", detail: "Open your actual sets, effort and session reports.", symbol: "chart.xyaxis.line", id: "progress", perform: openProgress)
                }.padding(24)
            }.background(.white).navigationTitle("Coach").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: Binding(get: { store.launchCoordinator?.needsAttention == true && store.launchCoordinator?.pendingOrigin == .coach }, set: { if !$0 { store.launchCoordinator?.cancel() } })) {
                    if let launch = store.launchCoordinator { WorkoutLaunchAccessView(launch: launch) }
                }
        }
    }
    private func action(_ title: String, detail: String, symbol: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { CoachActionLabel(title: title, detail: detail, symbol: symbol) }
            .buttonStyle(SpottrPressStyle()).accessibilityIdentifier("coach-\(id)")
    }
    private func apply(_ action: ProgrammeArchive.Adjustment, day: TrainingProgramme.Day, revision: Int, message: String) {
        do { try actions.apply(action, dayID: day.id, revision: revision); error = nil; self.message = message; SpottrHaptics.success() }
        catch { self.error = error.localizedDescription; self.message = nil }
    }
}

private struct CoachActionLabel: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.blue).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.blue.opacity(0.2)))
    }
}

private struct CoachSwapView: View {
    let actions: CoachProgrammeActions
    let day: TrainingProgramme.Day
    let revision: Int
    @State private var message: String?
    @State private var saved = false
    var body: some View {
        List {
            ForEach(day.plan?.items ?? []) { item in
                Section(ExerciseCatalog.find(item.exerciseID)?.name ?? "Movement") {
                    let replacements = actions.replacements(for: item, day: day)
                    if replacements.isEmpty { Text("No other movement in this family matches your current support and preferences.").font(.subheadline) }
                    ForEach(replacements) { entry in
                        Button {
                            do { try actions.apply(.swap(exerciseID: item.exerciseID, replacementID: entry.id), dayID: day.id, revision: revision); message = "\(entry.name) is saved in your plan."; saved = true; SpottrHaptics.success() }
                            catch { message = error.localizedDescription }
                        } label: { Label(entry.name, systemImage: "arrow.triangle.swap") }.buttonStyle(.bordered).disabled(saved)
                    }
                }
            }
            if let message { Text(message).accessibilityIdentifier("coach-swap-result") }
        }.navigationTitle("Swap a movement").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoachMoveDayView: View {
    let actions: CoachProgrammeActions
    let day: TrainingProgramme.Day
    let revision: Int
    @State private var message: String?
    @State private var saved = false
    var body: some View {
        List {
            Text("Choose a day to exchange with \(day.date.formatted(.dateTime.weekday(.wide))). Both plans stay complete.")
            ForEach(actions.days.filter { $0.id != day.id }) { destination in
                Button {
                    do { try actions.apply(.move(toDayID: destination.id), dayID: day.id, revision: revision); message = "Your workout is saved for \(destination.date.formatted(.dateTime.weekday(.wide)))."; saved = true; SpottrHaptics.success() }
                    catch { message = error.localizedDescription }
                } label: {
                    Label(destination.date.formatted(date: .complete, time: .omitted), systemImage: destination.plan == nil ? "moon" : "figure.strengthtraining.traditional")
                }.buttonStyle(.bordered).disabled(saved)
            }
            if let message { Text(message).accessibilityIdentifier("coach-move-result") }
        }.navigationTitle("Move training day").navigationBarTitleDisplayMode(.inline)
    }
}
