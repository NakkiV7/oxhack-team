import SwiftUI

struct StreakCard: View {
    let protectedStreak: Int
    let actualTrainingDays: Int
    let trainedToday: Bool
    let remainingFreezes: Int
    let trainingDaysThisWeek: Int
    let weeklyTarget: Int
    let baseXP: Int
    let bonusXP: Int
    let totalXP: Int
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    streakStatus
                    Spacer(minLength: 8)
                    weeklyProgress
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 16) {
                    streakStatus
                    weeklyProgress
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image("streak-freeze").resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                        Text("\(remainingFreezes) freezes left").font(.caption.weight(.semibold))
                    }
                    Text("\(actualTrainingDays) actual training \(actualTrainingDays == 1 ? "day" : "days")")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image("xp-double").resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                        Text("\(totalXP) XP").font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    Text("\(baseXP) base + \(bonusXP) bonus").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
            }
            Button("Training rewards", action: onManage).font(.caption.weight(.semibold))
                .accessibilityIdentifier("manage-training-rewards")
        }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("training-rewards-card")
    }

    private var streakStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(trainedToday || protectedStreak > 0 ? "streak-complete" : "streak-incomplete")
                .resizable().scaledToFit().frame(width: 38, height: 42)
                .hueRotation(.degrees(!trainedToday && protectedStreak > 0 ? -115 : 0))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(protectedStreak) \(protectedStreak == 1 ? "day" : "days")")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text("Protected streak").font(.caption).foregroundStyle(.secondary)
                Text(trainedToday ? "Training logged today" : protectedStreak > 0 ? "Active · train when you’re ready" : "No training logged today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(trainedToday ? Palette.green : protectedStreak > 0 ? Palette.amber : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(protectedStreak) \(protectedStreak == 1 ? "day" : "days") protected streak")
            .accessibilityValue(trainedToday ? "Training logged today." : protectedStreak > 0 ? "Active streak. No training logged today." : "No active streak. No training logged today.")
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("today-streak-status")
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Weekly target", systemImage: "calendar")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text("\(trainingDaysThisWeek) / \(weeklyTarget) days")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly target")
            .accessibilityValue("\(trainingDaysThisWeek) of \(weeklyTarget) training days this week")
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("today-weekly-target")
    }
}

struct XPWindowSettingsView: View {
    let todayWindow: DateInterval?
    let tomorrowEffectiveAt: Date
    let timeZone: TimeZone
    let intervalForHour: (Int) -> DateInterval?
    let saveTomorrow: (Int) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedHour: Int
    @State private var saved = false
    @State private var error: String?

    init(todayWindow: DateInterval?, tomorrowStartHour: Int, tomorrowEffectiveAt: Date,
         timeZone: TimeZone, intervalForHour: @escaping (Int) -> DateInterval?,
         saveTomorrow: @escaping (Int) throws -> Void) {
        self.todayWindow = todayWindow
        self.tomorrowEffectiveAt = tomorrowEffectiveAt
        self.timeZone = timeZone
        self.intervalForHour = intervalForHour
        self.saveTomorrow = saveTomorrow
        _selectedHour = State(initialValue: tomorrowStartHour)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("xp-double").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text("Your two-hour bonus window").font(.headline)
                    }
                    Text("Eligible base XP earned when you finish a workout in the window receives an equal bonus. Train at a comfortable time; the window is optional.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Today") {
                    Text(intervalText(todayWindow, empty: "No bonus window today."))
                        .font(.subheadline).accessibilityIdentifier("today-bonus-window")
                    Text("Today’s window is fixed. Changes start tomorrow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Tomorrow") {
                    Picker("Start time", selection: $selectedHour) {
                        ForEach(0...22, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("bonus-start-hour")
                    Text(intervalText(intervalForHour(selectedHour), empty: "This window is unavailable. Choose another start time."))
                        .font(.subheadline).accessibilityIdentifier("tomorrow-bonus-window")
                    Text("Preview only until you save. Today’s window stays unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Takes effect \(dateText(tomorrowEffectiveAt, format: "EEEE d MMMM")) in \(timeZone.identifier).")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Two hours of elapsed time. Daylight-saving changes may shift the displayed clock times.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save for tomorrow", action: save)
                        .disabled(intervalForHour(selectedHour) == nil).accessibilityIdentifier("save-bonus-window")
                    if saved { Text("Saved for tomorrow.").font(.caption).foregroundStyle(Palette.green) }
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                }
                Section {
                    HStack(spacing: 12) {
                        Image("streak-freeze").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
                        Text("Two streak freezes").font(.subheadline.weight(.semibold))
                    }
                    Text("Freezes protect missed days in an active streak while available. Planned rest days don’t spend a freeze. Neither counts as exercise or earns XP.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("XP and streaks are game progress, not a measure of physical ability. Rest when you need to.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Training rewards").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: selectedHour) { _, _ in saved = false; error = nil }
        }
    }

    private func save() {
        do { try saveTomorrow(selectedHour); saved = true; error = nil }
        catch {
            saved = false
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn’t save your window. Try again."
        }
    }

    private func intervalText(_ interval: DateInterval?, empty: String) -> String {
        guard let interval else { return empty }
        return "\(dateText(interval.start, format: "EEE d MMM, HH:mm zzz")) – \(dateText(interval.end, format: "EEE d MMM, HH:mm zzz"))"
    }

    private func dateText(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct TrainingRewardsSettingsView: View {
    let store: NativeRewardsStore
    @Environment(\.dismiss) private var dismiss
    @State private var openedAt = Date()

    var body: some View {
        let calendar = store.ledger.calendar
        if let issue = store.loadError {
            NavigationStack {
                ContentUnavailableView("Rewards unavailable", systemImage: "exclamationmark.circle", description: Text(issue))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: openedAt)) {
            XPWindowSettingsView(todayWindow: store.ledger.window(at: openedAt)?.interval(on: openedAt, calendar: calendar),
                                 tomorrowStartHour: store.ledger.window(at: tomorrow)?.startHour ?? 10,
                                 tomorrowEffectiveAt: tomorrow, timeZone: calendar.timeZone,
                                 intervalForHour: { hour in
                                     (try? DailyXPWindow(startHour: hour))?.interval(on: tomorrow, calendar: calendar)
                                 }, saveTomorrow: { hour in
                                     let now = Date()
                                     guard calendar.isDate(now, inSameDayAs: openedAt) else { throw WindowError.dayChanged }
                                     try store.schedule(startHour: hour, at: now)
                                 })
        }
    }

    private enum WindowError: LocalizedError {
        case dayChanged
        var errorDescription: String? { "The day has changed. Close and reopen Training rewards before saving." }
    }
}
