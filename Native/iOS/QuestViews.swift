import SwiftUI

struct QuestCardsView: View {
    let store: TrainingStore
    let quests: QuestStore
    @State private var weekly = false
    @State private var selection = 0
    @State private var error: String?
    @State private var accessPresented = false
    @State private var dateRevision = 0
    @Environment(\.scenePhase) private var scenePhase
    private var options: [Quest] {
        _ = dateRevision
        return quests.choices(history: store.history, weekly: weekly)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Palette.blue)
                Text("Your quests").font(.title3.bold())
                Spacer()
                Text("\(quests.archive.totalXP) quest XP").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Quest period", selection: $weekly) {
                Text("Today").tag(false); Text("This week").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("quest-period")
            if !options.isEmpty {
                Picker("Choose a quest", selection: $selection) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, quest in Text(quest.title).tag(index) }
                }.pickerStyle(.menu).accessibilityIdentifier("quest-choice")
                let quest = options[min(selection, options.count - 1)]
                let evidence = quests.progress(quest, history: store.history)
                let claimed = quests.archive.claims.contains { $0.id == quest.periodID }
                Text(quest.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text("Choose one reward per \(weekly ? "week" : "day"). Recovery and reflection count too.")
                    .font(.caption).foregroundStyle(.secondary)
                if claimed {
                    Label("Quest reward earned", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.green)
                } else if quests.archive.retiredPeriods.contains(quest.periodID) {
                    Text("This reward was removed with its evidence.").font(.caption).foregroundStyle(.secondary)
                } else if evidence.isComplete {
                    Button("Claim \(quest.xp) XP") { act { _ = try quests.claim(quest, history: store.history) } }
                        .buttonStyle(.borderedProminent).tint(Palette.blue).accessibilityIdentifier("quest-claim")
                } else if quest.exerciseID == nil {
                    Button(quest.kind == .familyActivity ? "We played together" : quest.kind == .reflection ? "Record reflection check-in" : "Record recovery check-in") {
                        act { try quests.checkIn(quest, history: store.history) }
                    }.buttonStyle(.bordered).tint(Palette.blue).accessibilityIdentifier("quest-check-in")
                    Text("\(evidence.completedDays) of \(quest.requiredDays) days checked in").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(evidence.completedDays) of \(quest.requiredDays) practice days recorded").font(.caption).foregroundStyle(.secondary)
                    if let day = store.programme?.day(), day.plan != nil, !store.history.contains(where: { $0.plannedWorkoutID == day.id }) {
                        Button("Open today’s workout") {
                            store.launchPlanned(dayID: day.id, origin: .quest)
                            accessPresented = store.launchCoordinator?.needsAttention == true
                        }.buttonStyle(.bordered).tint(Palette.blue).accessibilityIdentifier("quest-start-workout")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            } else {
                Text("Complete your local training profile to see suitable quests.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = quests.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityIdentifier("quest-card")
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in dateRevision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in dateRevision += 1 }
            .onChange(of: scenePhase) { _, phase in if phase == .active { dateRevision += 1 } }
            .onChange(of: weekly) { _, _ in selection = 0; error = nil }
            .onChange(of: options.map(\.id)) { _, _ in selection = 0 }
            .onChange(of: store.history) { _, _ in act { try quests.reconcile(history: store.history) } }
            .onAppear { act { try quests.reconcile(history: store.history) } }
            .sheet(isPresented: $accessPresented) {
                if let launch = store.launchCoordinator {
                    NavigationStack { WorkoutLaunchAccessView(launch: launch) }
                        .onDisappear { if launch.pendingOrigin == .quest { launch.cancel() } }
                }
            }
    }
    private func act(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = "This quest changed or couldn’t be saved. Reopen it and try again." }
    }
}

struct TrainingRewardWidget: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var manage = false
    @State private var checkIns = false
    @Environment(\.scenePhase) private var scenePhase
    private var now: Date { store.programme?.referenceDate ?? .now }
    private var calendar: Calendar { store.programme?.localCalendar ?? .current }
    private var adult: Bool { profile?.programmePreferences?.ageContext?.allowsTimePressureRewards == true && store.rewards.allowsTimePressureRewards }
    var body: some View {
        let summary = store.rewards.summary(history: store.history, at: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(adult ? "Your rewards" : "Your progress").font(.title3.bold())
                Spacer()
                Text("\(store.rewards.totalXP(history: store.history) + (store.quests?.archive.totalXP ?? 0)) XP").font(.title3.weight(.semibold)).monospacedDigit()
            }
            if adult {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { numbers(summary) }
                    VStack(alignment: .leading, spacing: 12) { numbers(summary) }
                }
                if let next = nextWindow {
                    Label("Next bonus window: \(next.start.formatted(date: .abbreviated, time: .shortened))", systemImage: "sparkles")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                } else { Text("No bonus window selected").font(.subheadline).foregroundStyle(.secondary) }
                Button("Manage rewards & reminders") { manage = true }.font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("manage-training-rewards")
            } else {
                Text("\(summary.actualTrainingDays) days of recorded practice. Small comfortable steps count; rest whenever you need it.").font(.subheadline)
            }
            if store.quests != nil {
                Button("Review check-ins") { checkIns = true }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("quest-checkin-history")
            }
            Text("Rewards reflect recorded practice and check-ins, not physical ability.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Palette.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
            .accessibilityIdentifier("training-rewards-widget")
            .sheet(isPresented: $manage) { TrainingRewardsSettingsView(store: store.rewards, reminders: store.rewardReminders, programme: store.programme) }
            .sheet(isPresented: $checkIns) { if let quests = store.quests { QuestCheckInHistory(store: store, quests: quests) } }
            .task { await store.rewardReminders?.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.rewardReminders?.refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in Task { await store.rewardReminders?.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await store.rewardReminders?.refresh() } }
    }
    @ViewBuilder private func numbers(_ summary: GamificationSummary) -> some View {
        Label("\(summary.protectedStreak) day streak", systemImage: "flame").font(.subheadline.weight(.semibold))
        Label("\(summary.remainingFreezes) freezes", systemImage: "snowflake").font(.subheadline.weight(.semibold))
    }
    private var nextWindow: DateInterval? {
        (0...2).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .compactMap { store.rewards.ledger.window(at: $0)?.interval(on: $0, calendar: calendar) }
            .first { $0.end > now }
    }
}
private struct QuestCheckInHistory: View {
    let store: TrainingStore
    let quests: QuestStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if quests.archive.checkIns.isEmpty { Text("No check-ins yet. Check-ins never create workout sets.") }
                ForEach(quests.archive.checkIns.sorted { $0.date > $1.date }) { check in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(check.kind == .familyActivity ? "Family play" : check.kind == .recovery ? "Recovery" : "Reflection").font(.headline)
                        Text(check.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        Button("Delete check-in", role: .destructive) {
                            do { try quests.removeCheckIn(id: check.id, history: store.history) }
                            catch { self.error = "The check-in couldn’t be removed." }
                        }
                    }
                }
                Text("Deleting evidence also removes any quest reward that relies on it. Workout history stays separate.").font(.caption)
                if let error { Text(error) }
            }.navigationTitle("Your check-ins")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
