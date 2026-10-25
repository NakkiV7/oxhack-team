import SwiftUI

/// One tab for looking back: the training calendar, session reports, the weekly review and the research the coach cites.
/// Everything is computed from the saved history on this phone; the only network call is the optional Gemini summary.
struct InsightsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case calendar, reports, weekly, research
        var id: String { rawValue }
        var title: String { ["Calendar", "Reports", "Week", "Research"][Self.allCases.firstIndex(of: self)!] }
    }
    let store: TrainingStore
    var profile: LocalProfile? = nil
    @AppStorage("insights.section") private var section = Section.calendar.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insights.").font(.system(size: 32, weight: .bold)).tracking(-1).accessibilityAddTraits(.isHeader)
                        Text("Every session, every day: your calendar, reports, weekly review and the research behind your coach.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Insights section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("insights-section")
                    switch Section(rawValue: section) ?? .calendar {
                    case .calendar: CalendarSection(store: store, profile: profile)
                    case .reports: ReportsSection(store: store, profile: profile)
                    case .weekly: WeeklyReviewSection(store: store, profile: profile)
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
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var month = Date()
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private let calendar = Calendar.current

    var body: some View {
        let data = TrainingMonth(containing: month, history: store.history, calendar: calendar)
        let comparison = WeekComparison(history: store.history, now: .now, calendar: calendar)
        let strip = ConsistencyStrip(history: store.history, now: .now, calendar: calendar)
        let day = data.days.first { calendar.isDate($0.date, inSameDayAs: selected) }
            ?? TrainingMonth(containing: selected, history: store.history, calendar: calendar).days.first { calendar.isDate($0.date, inSameDayAs: selected) }
        VStack(alignment: .leading, spacing: 18) {
            InsightCard {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workout calendar").font(.headline)
                        Text("Select a day to see its sessions").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                        .accessibilityLabel("Previous month").accessibilityIdentifier("calendar-previous")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold)).accessibilityIdentifier("calendar-month")
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                        .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                        .accessibilityLabel("Next month").accessibilityIdentifier("calendar-next")
                }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(data.weekdaySymbols, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true) }
                    ForEach(data.days) { cell in
                        DayCell(day: cell, today: calendar.isDateInToday(cell.date), selected: calendar.isDate(cell.date, inSameDayAs: selected))
                            .onTapGesture { selected = cell.date }
                    }
                }
                HStack(spacing: 14) {
                    LegendDot(color: Palette.green, text: "Camera counted")
                    LegendDot(color: Palette.amber, text: "Logged by you")
                    Label { Text("Today").font(.caption2) } icon: { RoundedRectangle(cornerRadius: 3).stroke(Palette.ink, lineWidth: 1.5).frame(width: 9, height: 9) }
                }.foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }
            if let day { DayInspector(day: day, store: store, profile: profile) }
            WeekComparisonCard(comparison: comparison)
            ConsistencyCard(strip: strip) { selected = $0; month = $0 }
        }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let today: Bool
    let selected: Bool
    private var number: String { day.date.formatted(.dateTime.day()) }
    var body: some View {
        VStack(spacing: 3) {
            Text(number).font(.system(size: 14, weight: day.trained ? .bold : .regular)).monospacedDigit()
            Circle().fill(day.hasCameraSets ? Palette.green : day.hasManualSets ? Palette.amber : .clear).frame(width: 6, height: 6)
            Text(day.trained ? "\(day.reps + Int(day.holdSeconds))" : " ").font(.system(size: 9, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .foregroundStyle(selected ? .white : day.inMonth ? Palette.ink : Palette.muted.opacity(0.5))
        .background(selected ? Palette.ink : day.trained ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay { if today && !selected { RoundedRectangle(cornerRadius: 10).stroke(Palette.ink, lineWidth: 1.5) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendar-day-\(day.date.formatted(.iso8601.year().month().day()))")
    }
    private var accessibilityText: String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard day.trained else { return "\(date), no workout" }
        let source = day.hasCameraSets && day.hasManualSets ? "camera and logged" : day.hasCameraSets ? "camera counted" : "logged by you"
        return "\(date), \(day.setCount) sets, \(day.reps) reps, \(source)"
    }
}

private struct DayInspector: View {
    let day: CalendarDay
    let store: TrainingStore
    let profile: LocalProfile?
    var body: some View {
        InsightCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(badge).font(.caption2.weight(.bold)).tracking(0.6).padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(badgeColor).background(badgeColor.opacity(0.1), in: Capsule())
                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).font(.title3.bold())
                }
                Spacer()
            }
            if day.trained {
                HStack(spacing: 10) {
                    Tile(value: "\(day.reps)", title: day.holdSeconds > 0 ? "Reps · \(Int(day.holdSeconds)) s held" : "Total reps")
                    Tile(value: duration(day.activeSeconds), title: "Session time")
                    Tile(value: day.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—", title: day.averageHeartRate == nil ? "Watch HR not recorded" : "Avg Watch bpm",
                         tint: day.averageHeartRate == nil ? Palette.muted : Palette.red)
                }
                Text("Set breakdown").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                ForEach(day.reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(report.sets.enumerated()), id: \.element.id) { index, set in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.exerciseName).font(.subheadline.weight(.semibold))
                                    Text([set.sourceLabel, set.averageRepSeconds.map { String(format: "%.1f s per rep", $0) },
                                          index == report.sets.count - 1 ? nil : set.restSecondsBefore.map { "rest \(Int($0)) s" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(set.quantityText).font(.subheadline).monospacedDigit()
                            }
                        }
                        if let record = store.history.first(where: { $0.id == report.id }) {
                            NavigationLink { SessionReportView(record: record, profile: profile, history: store.history) } label: {
                                Label("Open session report", systemImage: "doc.text.magnifyingglass").font(.subheadline.weight(.semibold))
                            }.foregroundStyle(Palette.blue).padding(.top, 2)
                        }
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                }
            } else {
                Text(day.date > .now ? "Nothing logged yet for this day." : "Scheduled rest or no workout logged. Rest days are part of training.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("calendar-inspector")
    }
    private var badge: String { day.trained ? (day.hasCameraSets && day.hasManualSets ? "CAMERA AND LOGGED" : day.hasCameraSets ? "CAMERA TRACKED" : "LOGGED BY YOU") : "REST DAY" }
    private var badgeColor: Color { day.trained ? (day.hasCameraSets ? Palette.green : Palette.amber) : Palette.muted }
}

private struct WeekComparisonCard: View {
    let comparison: WeekComparison
    var body: some View {
        let days = comparison.trainingDays, rep = comparison.averageRepSeconds, hr = comparison.averageHeartRate
        InsightCard {
            Text("This week against last").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CompareTile(title: "Rep volume", value: "\(comparison.thisWeek.reps)",
                            delta: WeekComparison.delta(Double(comparison.thisWeek.reps), Double(comparison.lastWeek.reps)))
                CompareTile(title: "Sets", value: "\(comparison.thisWeek.setCount)",
                            delta: WeekComparison.delta(Double(comparison.thisWeek.setCount), Double(comparison.lastWeek.setCount)))
                CompareTile(title: "Training days", value: "\(days.this)", delta: WeekComparison.delta(Double(days.this), Double(days.last)))
                CompareTile(title: "Seconds per rep", value: rep.this.map { String(format: "%.1f", $0) } ?? "—",
                            delta: rep.this == nil ? "No timed reps yet" : rep.last == nil ? "None last week" : WeekComparison.delta((rep.this! * 10).rounded() / 10, (rep.last! * 10).rounded() / 10, unit: " s"))
            }
            Text(hr.this.map { "Average Apple Watch heart rate \(Int($0.rounded())) bpm\(hr.last.map { " (last week \(Int($0.rounded())))" } ?? "")." }
                 ?? "No Apple Watch heart-rate readings this week; missing readings are never shown as zero.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ConsistencyCard: View {
    let strip: ConsistencyStrip
    let select: (Date) -> Void
    private let colors = [Palette.surface, Palette.green.opacity(0.25), Palette.green.opacity(0.5), Palette.green.opacity(0.75), Palette.green]
    var body: some View {
        InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Text("30-day consistency").font(.headline)
                Spacer()
                Text("\(strip.trainedDays) training days").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), spacing: 5) {
                ForEach(strip.days) { day in
                    RoundedRectangle(cornerRadius: 5).fill(colors[day.level]).aspectRatio(1, contentMode: .fit)
                        .onTapGesture { select(day.date) }
                        .accessibilityLabel("\(day.date.formatted(.dateTime.day().month(.wide))), \(day.trained ? "\(day.volume) reps and seconds" : "no workout")")
                        .accessibilityAddTraits(.isButton)
                }
            }
            HStack {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { RoundedRectangle(cornerRadius: 3).fill(colors[$0]).frame(width: 12, height: 12) }
                Text("More, by your own volume").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }.accessibilityHidden(true)
            HStack(spacing: 10) {
                Tile(value: "\(strip.currentStreak)", title: strip.currentStreak == 1 ? "day current run" : "days current run")
                Tile(value: "\(strip.bestStreak)", title: strip.bestStreak == 1 ? "day best run" : "days best run")
            }
        }.accessibilityIdentifier("calendar-consistency")
    }
}

// MARK: - Reports

private struct ReportsSection: View {
    let store: TrainingStore
    let profile: LocalProfile?
    var body: some View {
        let records = TrainingMonth.unique(store.history).sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 10) {
            if records.isEmpty {
                InsightCard {
                    Text("Your first report starts here.").font(.headline)
                    Text("Finish a camera or logged workout and its report appears in this list.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(records.prefix(40)) { record in
                let report = WorkoutReport(record: record)
                NavigationLink { SessionReportView(record: record, profile: profile, history: store.history) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: report.sets.contains { $0.source == .camera } ? "camera.fill" : "square.and.pencil")
                            .foregroundStyle(report.sets.contains { $0.source == .camera } ? Palette.green : Palette.amber)
                            .frame(width: 40, height: 40).background(.white, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).font(.subheadline.weight(.semibold))
                            Text(Array(Set(report.sets.map(\.exerciseName))).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(report.setCount) sets · \(report.reps) reps\(report.holdSeconds > 0 ? " · \(Int(report.holdSeconds)) s held" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityIdentifier("insights-report-row")
            }
        }
    }
}

// MARK: - Weekly review

private struct WeeklyReviewSection: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var summary: CoachSummary?
    @State private var loading = false
    @State private var failure: String?

    var body: some View {
        let comparison = WeekComparison(history: store.history, now: .now)
        let interval = comparison.thisWeek.interval, days = comparison.trainingDays
        VStack(alignment: .leading, spacing: 18) {
            InsightCard {
                Text("Week of \(interval.start.formatted(.dateTime.day().month(.wide)))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(headline(comparison)).font(.title3.bold())
                if interval.end > .now { Label("Week in progress: recorded so far, not a completed week.", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CompareTile(title: "Sets", value: "\(comparison.thisWeek.setCount)", delta: WeekComparison.delta(Double(comparison.thisWeek.setCount), Double(comparison.lastWeek.setCount)))
                CompareTile(title: "Reps", value: "\(comparison.thisWeek.reps)", delta: WeekComparison.delta(Double(comparison.thisWeek.reps), Double(comparison.lastWeek.reps)))
                CompareTile(title: "Training days", value: "\(days.this)", delta: WeekComparison.delta(Double(days.this), Double(days.last)))
                CompareTile(title: "Active minutes", value: "\(Int((comparison.thisWeek.activeSeconds / 60).rounded()))",
                            delta: WeekComparison.delta((comparison.thisWeek.activeSeconds / 60).rounded(), (comparison.lastWeek.activeSeconds / 60).rounded(), unit: " min"))
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("What stood out", systemImage: "sparkles").font(.headline)
                ForEach(Array(comparison.highlights.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Palette.blue)
                            .frame(width: 24, height: 24).background(Palette.blue.opacity(0.1), in: Circle())
                        Text(line).font(.subheadline)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                }
            }
            if !comparison.thisWeek.categories.isEmpty {
                InsightCard {
                    Text("This week’s mix").font(.headline)
                    ForEach(comparison.thisWeek.categories) { category in
                        HStack { Text(category.category.rawValue.capitalized).font(.subheadline); Spacer(); Text("\(category.setCount) sets · \(category.reps) reps").font(.subheadline).monospacedDigit() }
                    }
                }
            }
            coachSummary
            Label("Plan next week with the Coach tab: it proposes days you approve.", systemImage: "calendar.badge.plus").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func headline(_ comparison: WeekComparison) -> String {
        let days = comparison.trainingDays.this
        if comparison.thisWeek.setCount == 0 { return "No sets recorded yet this week." }
        return "\(comparison.thisWeek.setCount) sets over \(days) \(days == 1 ? "day" : "days") this week."
    }

    @ViewBuilder private var coachSummary: some View {
        InsightCard {
            Label("Coach’s summary", systemImage: "text.bubble").font(.headline)
            if let summary {
                Text(summary.headline.text).font(.subheadline.weight(.semibold))
                ForEach(Array(summary.insights.enumerated()), id: \.offset) { _, insight in Text("• \(insight.text)").font(.subheadline) }
                Label(summary.focus.text, systemImage: "scope").font(.subheadline).foregroundStyle(Palette.blue)
                Text("Gemini, written from \(Set(([summary.headline, summary.focus] + summary.insights).flatMap(\.factIDs)).count) recorded facts. Every number comes from your history.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("One Gemini call turns this week’s recorded facts into a short summary. It can only cite what you recorded.").font(.subheadline).foregroundStyle(.secondary)
                if let failure { Text(failure).font(.caption).foregroundStyle(Palette.red) }
                Button { write() } label: {
                    Label(loading ? "Writing…" : "Write the summary", systemImage: "sparkles").frame(maxWidth: .infinity).padding(14)
                        .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain).disabled(loading || store.history.isEmpty).opacity(store.history.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("insights-write-summary")
            }
        }
    }

    private func write() {
        loading = true; failure = nil
        let request = CoachRequest(facts: CoachGrounding.facts(history: store.history, profile: profile), kind: .weekly)
        Task {
            do { summary = try await CoachSettings.client().summary(request, kind: .weekly) }
            catch { failure = (error as? LocalizedError)?.errorDescription ?? "The summary couldn’t be written. Try again." }
            loading = false
        }
    }
}

// MARK: - Research

private struct ResearchSection: View {
    @State private var query = ""
    private let registry = try? CoachGuidanceRegistry.bundled()
    var body: some View {
        let sources = (registry?.sources ?? []).filter {
            query.isEmpty || [$0.title, $0.summary, $0.audience].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        VStack(alignment: .leading, spacing: 14) {
            InsightCard {
                Text("The evidence behind your coach").font(.headline)
                Text("These reviewed public-health sources are the only ones the Coach may cite when it plans or explains. Each one is general guidance, not a judgement about you.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("Search sources", text: $query).textFieldStyle(.plain).padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).accessibilityIdentifier("research-search")
            if sources.isEmpty {
                Text(registry == nil ? "The source library couldn’t be read." : "No source matches “\(query)”.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 8) {
                    Text(source.title).font(.subheadline.weight(.semibold))
                    Text(source.summary).font(.subheadline)
                    Label(source.audience, systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: source.url) {
                        Link(destination: url) { Label("Open source", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold)) }
                            .foregroundStyle(Palette.blue)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                    .accessibilityIdentifier("research-source")
            }
            Label("A study finding never proves an individual outcome and never changes a pass criterion.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Building blocks

private struct InsightCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct Tile: View {
    let value: String
    let title: String
    var tint: Color = Palette.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }
}

private struct CompareTile: View {
    let title: String
    let value: String
    let delta: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(delta).font(.caption2.weight(.semibold))
                .foregroundStyle(delta.hasPrefix("+") || delta == "New this week" ? Palette.green : delta.hasPrefix("−") ? Palette.amber : .secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .combine)
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View { Label { Text(text).font(.caption2) } icon: { Circle().fill(color).frame(width: 7, height: 7) } }
}

private func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
}
