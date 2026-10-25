import SwiftUI

/// One tab for looking back: the training calendar, every session report, the weekly review and the research library.
/// Everything here is read from the history on this phone, so it works offline; only the Gemini weekly summary needs the
/// gateway.
struct InsightsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case calendar = "Calendar", reports = "Reports", weekly = "Weekly", research = "Research"
        var id: String { rawValue }
    }
    @Bindable var store: TrainingStore
    var profile: LocalProfile? = nil
    var previewMode = false
    @AppStorage("insights.section") private var section = Section.calendar.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insights.").font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("Your training, looked back on.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Insights section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("insights-section")
                    switch Section(rawValue: section) ?? .calendar {
                    case .calendar: CalendarSection(store: store, profile: profile)
                    case .reports: ReportsSection(store: store, profile: profile)
                    case .weekly: WeeklySection(store: store, profile: profile, previewMode: previewMode)
                    case .research: ResearchSection()
                    }
                }.padding(24)
            }
            .background(.white).navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Calendar

private struct CalendarSection: View {
    @Bindable var store: TrainingStore
    let profile: LocalProfile?
    @State private var month = Date.now
    @State private var selected: Date? = Calendar.current.startOfDay(for: .now)
    /// Sample days keep the calendar full for presentations; real training always shows as itself.
    @AppStorage("insights.sampleCalendar") private var sampleDays = true
    private let calendar = Calendar.current

    var body: some View {
        let history = sampleDays ? store.history + TrainingCalendar.sampleHistory(now: .now, excluding: store.history, calendar: calendar) : store.history
        let days = TrainingCalendar.days(history: history, calendar: calendar)
        let streaks = TrainingCalendar.streaks(trainingDays: Set(days.keys), today: .now, calendar: calendar)
        let monthDays = days.values.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 14) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").padding(10).foregroundStyle(Palette.blue) }.accessibilityLabel("Previous month")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").padding(10).foregroundStyle(Palette.blue) }.accessibilityLabel("Next month")
                        .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                }.buttonStyle(.plain).tint(Palette.blue)
                HStack(spacing: 0) {
                    ForEach(Array(TrainingCalendar.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }.accessibilityHidden(true)
                ForEach(Array(TrainingCalendar.monthGrid(containing: month, calendar: calendar).enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            if let date { DayCell(date: date, day: days[date], selected: selected == date, today: calendar.isDateInToday(date)) { selected = date } }
                            else { Color.clear.frame(maxWidth: .infinity, minHeight: 42) }
                        }
                    }
                }
                HStack(spacing: 14) {
                    legend(Palette.blue, "Camera tracked"); legend(Palette.green, "Logged"); legend(nil, "Today")
                }.font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if sampleDays { Text("Faded days are sample training, not recorded on this phone.") }
                    Spacer(minLength: 4)
                    Button(sampleDays ? "Hide samples" : "Show samples") { sampleDays.toggle() }.fontWeight(.semibold).foregroundStyle(Palette.blue)
                        .accessibilityIdentifier("calendar-samples")
                }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
            }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))

            if let selected { DayDetail(date: selected, records: history.filter { calendar.isDate($0.date, inSameDayAs: selected) }, profile: profile, history: history) }

            HStack(spacing: 10) {
                Tile(value: "\(streaks.current)", unit: streaks.current == 1 ? "day" : "days", title: "Current streak")
                Tile(value: "\(streaks.longest)", unit: streaks.longest == 1 ? "day" : "days", title: "Longest streak")
                Tile(value: "\(monthDays.count)", unit: monthDays.count == 1 ? "day" : "days", title: "Trained this month")
            }
            Heatmap(days: days, calendar: calendar)
        }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next; selected = nil }
    }
    private func legend(_ color: Color?, _ text: String) -> some View {
        HStack(spacing: 5) {
            if let color { Circle().fill(color).frame(width: 9, height: 9) } else { Circle().stroke(Palette.ink, lineWidth: 1.5).frame(width: 9, height: 9) }
            Text(text)
        }
    }
}

private struct DayCell: View {
    let date: Date
    let day: TrainingCalendar.Day?
    let selected: Bool
    let today: Bool
    let action: () -> Void
    var body: some View {
        let tint = day?.kind == .camera ? Palette.blue : Palette.green
        let sample = day?.isSample == true
        Button(action: action) {
            Text(date.formatted(.dateTime.day())).font(.subheadline.weight(day == nil ? .regular : .semibold)).monospacedDigit()
                .foregroundStyle(day == nil || sample ? Palette.ink : .white)
                .frame(width: 36, height: 36)
                .background { if day != nil { Circle().fill(sample ? tint.opacity(0.22) : tint) } }
                .overlay { if sample { Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) } }
                .overlay { if today { Circle().stroke(Palette.ink, lineWidth: 1.5).padding(-3) } }
                .overlay { if selected { Circle().stroke(Palette.blue.opacity(0.45), lineWidth: 3).padding(-5) } }
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (day.map { ", \($0.reps) reps, \($0.isSample ? "sample" : $0.kind == .camera ? "camera tracked" : "logged")" } ?? ", no training"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendar-day-\(Calendar.current.component(.day, from: date))")
    }
}

private struct DayDetail: View {
    let date: Date
    let records: [SessionRecord]
    let profile: LocalProfile?
    let history: [SessionRecord]
    var body: some View {
        let reports = records.map(WorkoutReport.init(record:)).filter { !$0.sets.isEmpty }.sorted { $0.date < $1.date }
        let sets = reports.flatMap(\.sets).filter { $0.source != .video }
        let heart = reports.compactMap(\.heartRate.average)
        let sample = records.contains { TrainingCalendar.isSample($0.id) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                Spacer()
                if !sets.isEmpty {
                    let tint = sample ? Palette.muted : sets.contains { $0.source == .camera } ? Palette.blue : Palette.green
                    Text(sample ? "Sample" : tint == Palette.blue ? "Camera tracked" : "Logged").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(tint).background(tint.opacity(0.1), in: Capsule())
                }
            }
            if sample { Text("Sample training for the demo, not recorded on this phone.").font(.caption).foregroundStyle(.secondary) }
            if sets.isEmpty {
                Text("No training recorded on this day.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Tile(value: "\(sets.reduce(0) { $0 + $1.reps })", unit: "reps", title: "Total")
                    let active = sets.reduce(0) { $0 + $1.activeSeconds }
                    Tile(value: active > 0 ? clockText(active) : "—", unit: "", title: active > 0 ? "Active time" : "Not timed")
                    Tile(value: heart.isEmpty ? "—" : "\(Int((heart.reduce(0, +) / Double(heart.count)).rounded()))", unit: heart.isEmpty ? "" : "bpm",
                         title: heart.isEmpty ? "No Watch readings" : "Avg Watch HR")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(sets.count) \(sets.count == 1 ? "set" : "sets")").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 22, height: 22).background(Palette.surface, in: Circle())
                            Text(set.exerciseName).font(.subheadline)
                            Spacer()
                            Text(set.quantityText).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Image(systemName: set.source == .camera ? "camera.fill" : "hand.tap").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel(set.source == .camera ? "Camera" : "Manual")
                        }
                    }
                }
                ForEach(records.filter { !$0.sets.isEmpty || !$0.loggedSets.isEmpty }) { record in
                    NavigationLink { SessionReportView(record: record, profile: profile, history: history) } label: {
                        Label("Open the \(record.date.formatted(date: .omitted, time: .shortened)) \(sample ? "sample" : "session") report", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }.foregroundStyle(Palette.blue)
                }
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(Palette.surface, lineWidth: 2) }
    }
}

private struct Heatmap: View {
    let days: [Date: TrainingCalendar.Day]
    let calendar: Calendar
    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let dates = (0..<35).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        VStack(alignment: .leading, spacing: 10) {
            Text("Last five weeks").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    let reps = days[date]?.reps ?? 0
                    RoundedRectangle(cornerRadius: 6).fill(reps == 0 ? Palette.surface : Palette.blue.opacity(reps >= 60 ? 1 : reps >= 25 ? 0.65 : 0.35))
                        .frame(height: 26)
                        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(reps) reps")
                }
            }
            HStack { Text("Rest").font(.caption2).foregroundStyle(.secondary); Spacer(); Text("More reps").font(.caption2).foregroundStyle(.secondary) }
        }.padding(18).background(Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Reports

private struct ReportsSection: View {
    @Bindable var store: TrainingStore
    let profile: LocalProfile?
    var body: some View {
        let records = store.history.filter { !$0.sets.isEmpty || !$0.loggedSets.isEmpty }.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 10) {
            if records.isEmpty {
                Empty(symbol: "doc.text", title: "No session reports yet", detail: "Each workout you finish becomes a report: sets, tempo, Watch readings and coaching.")
            }
            ForEach(records) { record in
                let report = WorkoutReport(record: record)
                NavigationLink { SessionReportView(record: record, profile: profile, history: store.history) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: report.sets.contains { $0.source == .camera } ? "camera.fill" : "hand.tap.fill")
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(report.sets.contains { $0.source == .camera } ? Palette.blue : Palette.green, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).font(.subheadline.weight(.semibold))
                            Text(Array(Set(report.sets.map(\.exerciseName))).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(report.reps) reps").font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text("\(report.setCount) \(report.setCount == 1 ? "set" : "sets")").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityIdentifier("insights-report")
            }
        }
    }
}

// MARK: - Weekly review

private struct WeeklySection: View {
    @Bindable var store: TrainingStore
    let profile: LocalProfile?
    let previewMode: Bool
    @State private var pathStore: TrainingPathStore
    init(store: TrainingStore, profile: LocalProfile?, previewMode: Bool) {
        self.store = store; self.profile = profile; self.previewMode = previewMode
        _pathStore = State(initialValue: TrainingPathStore(preview: previewMode))
    }

    var body: some View {
        let week = TrainingCalendar.weekComparison(history: store.history, now: .now)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week of \(week.thisWeek.start.formatted(.dateTime.day().month(.wide)))").font(.title3.bold())
                Text("This week so far, against last week.").font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Comparison(title: "Training days", now: week.trainingDays.now, before: week.trainingDays.before, target: profile?.weeklyTarget)
                Comparison(title: "Sessions", now: week.sessions.now, before: week.sessions.before)
                Comparison(title: "Sets", now: week.sets.now, before: week.sets.before)
                Comparison(title: "Reps", now: week.reps.now, before: week.reps.before)
            }
            if let now = week.averageRepSeconds.now {
                Label("Average rep time \(String(format: "%.1f", now)) s" + (week.averageRepSeconds.before.map { String(format: ", %.1f s last week", $0) } ?? ""), systemImage: "metronome")
                    .font(.subheadline)
            }
            Text("Coach’s review").font(.headline).padding(.top, 4)
            CoachSummaryCard(history: store.history, kind: .weekly, profile: profile)
            Text("Next week’s quests").font(.headline).padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(quests, id: \.self) { quest in
                    Label(quest, systemImage: "flag.fill").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }

    /// Concrete quests from the training path and the weekly target. Nothing here is generated.
    private var quests: [String] {
        var list: [String] = []
        if let profile { list.append("Train on \(profile.weeklyTarget) \(profile.weeklyTarget == 1 ? "day" : "days") this week.") }
        if let version = pathStore.active {
            let skill = SkillProgress.evaluate(history: store.history)
            let status = PathStatus.evaluate(path: version.path, skill: skill, attempts: pathStore.attempts)
            if let id = status.current, let node = version.path.node(id), let entry = node.entry, let step = status.step(id) {
                if let target = node.practiceTarget {
                    list.append("Practise \(entry.name.lowercased()) on \(target.perWeek) days: \(target.sets) × \(target.target) \(entry.unit == .reps ? "reps" : "sec").")
                }
                let sets = max(0, 3 - step.qualifyingSets), days = max(0, 2 - step.trainingDays)
                if sets > 0 || days > 0 {
                    list.append("Earn \(entry.name.lowercased()): \(sets) more goal \(sets == 1 ? "set" : "sets") of \(entry.goal)\(days > 0 ? " over \(days) more \(days == 1 ? "day" : "days")" : "").")
                }
            }
        } else {
            list.append("Build your training path in Skills to get a quest for each step.")
        }
        return list
    }
}

private struct Comparison: View {
    let title: String
    let now: Int
    let before: Int
    var target: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(now)").font(.title2.weight(.semibold)).monospacedDigit()
                if let target { Text("/ \(target)").font(.subheadline).foregroundStyle(.secondary) }
            }
            Text(delta).font(.caption.weight(.semibold)).foregroundStyle(now > before ? Palette.green : now < before ? Palette.amber : .secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .combine)
    }
    /// No percentage from a zero week: a change from nothing is "new this week".
    private var delta: String {
        if now == before { return "Same as last week" }
        if before == 0 { return "New this week" }
        return "\(now > before ? "+" : "−")\(abs(now - before)) vs last week"
    }
}

// MARK: - Research

private struct ResearchSection: View {
    var body: some View {
        let registry = try? CoachGuidanceRegistry.bundled()
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviewed guidance the coach can cite. General education for the population each source names; it is not individual medical advice.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let registry {
                ForEach(registry.sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.title).font(.subheadline.weight(.semibold))
                        Text(source.summary).font(.subheadline)
                        Label(source.audience, systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: source.url) {
                            Link(destination: url) { Label("Read the source", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold)) }
                                .foregroundStyle(Palette.blue)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                        .accessibilityElement(children: .contain)
                }
            } else {
                Empty(symbol: "books.vertical", title: "The guidance library couldn’t be read", detail: "Reinstall the app to restore it.")
            }
        }
    }
}

// MARK: - Shared pieces

private struct Tile: View {
    let value: String
    let unit: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .combine)
    }
}

private struct Empty: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(Palette.blue)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: .infinity).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
