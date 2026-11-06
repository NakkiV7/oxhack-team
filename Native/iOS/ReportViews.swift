import SwiftUI
import Charts

struct WeeklyProgressView: View {
    let store: TrainingStore
    let profile: LocalProfile?
    init(store: TrainingStore, profile: LocalProfile? = nil) { self.store = store; self.profile = profile }
    var body: some View {
        let week = WeekReport(history: store.history)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This week").font(.largeTitle.weight(.bold)).tracking(-1)
                        Text("\(week.interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(week.interval.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated))), week so far")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    AnalyticsValueGrid(minimumWidth: 96) {
                        Metric(value: "\(week.sessions.count)", title: "Sessions", symbol: "calendar")
                        Metric(value: "\(week.setCount)", title: "Sets", symbol: "square.3.layers.3d")
                        Metric(value: "\(week.reps)", title: "Reps", symbol: "repeat")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sets by day").font(.caption.weight(.semibold))
                        Chart(week.days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Sets", day.setCount), width: .ratio(0.5))
                                .foregroundStyle(Palette.blue).cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow))
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 100)
                        if week.holdSeconds > 0 {
                            Text("\(Int(week.holdSeconds)) seconds of recorded holds").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if store.history.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.xyaxis.line").font(.system(size: 34, weight: .light))
                            Text("Your first session starts here").font(.headline)
                            Text("Finish a set to see your reps, time and effort in one place")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        Text("Session reports").font(.headline)
                        ForEach(store.history) { record in
                            NavigationLink {
                                SessionReportView(record: record, profile: profile, history: store.history, previewEnabled: store.previewMode)
                            } label: {
                                ReportSessionCard(report: WorkoutReport(record: record))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("session-report")
                        }
                    }
                    CoachSummaryCard(history: store.history.filter { $0.date >= week.interval.start && $0.date < week.interval.end }, kind: .weekly, profile: profile)
                    if !week.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("This week’s mix").font(.headline)
                            ForEach(week.categories) { category in
                                HStack(alignment: .top) {
                                    Text(category.category.rawValue).font(.subheadline.weight(.medium))
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(category.setCount) \(category.setCount == 1 ? "set" : "sets"), \(category.reps) \(category.reps == 1 ? "rep" : "reps")")
                                        if category.holdSeconds > 0 { Text("\(Int(category.holdSeconds)) sec holds") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    } else if !store.history.isEmpty {
                        Text("No completed sets recorded this week.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            .background(.white)
            .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ReportSessionCard: View {
    let report: WorkoutReport
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(report.category.rawValue).font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }
            Text("\(report.setCount) \(report.setCount == 1 ? "set" : "sets"), \(report.reps) \(report.reps == 1 ? "rep" : "reps")").font(.title3.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(report.date.formatted(date: .abbreviated, time: .shortened))
                    Spacer(minLength: 12)
                    if report.holdSeconds > 0 { Text("\(Int(report.holdSeconds)) sec holds") }
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.date.formatted(date: .abbreviated, time: .shortened))
                    if report.holdSeconds > 0 { Text("\(Int(report.holdSeconds)) sec holds") }
                }
            }.font(.caption).foregroundStyle(.secondary)
            AnalyticsValueGrid(minimumWidth: 90) {
                ForEach([InputSource.camera, .manual, .video], id: \.rawValue) { source in
                    if report.sets.contains(where: { $0.source == source }) { ReportSourceBadge(source: source) }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SessionReportView: View {
    let record: SessionRecord
    let profile: LocalProfile?
    let history: [SessionRecord]?
    let previewEnabled: Bool
    let zones: HeartRateZoneConfiguration?
    @State private var sourcesExpanded: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    init(record: SessionRecord, profile: LocalProfile? = nil, history: [SessionRecord]? = nil, previewEnabled: Bool = false, zones: HeartRateZoneConfiguration? = nil) {
        self.record = record; self.profile = profile; self.history = history
        self.previewEnabled = previewEnabled; self.zones = zones; _sourcesExpanded = State(initialValue: previewEnabled)
    }
    var body: some View {
        let report = WorkoutReport(record: record)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(report.sets.isEmpty && !record.skippedSets.isEmpty ? "Session check-in" : report.category.rawValue).font(.largeTitle.weight(.bold)).tracking(-0.8)
                    Text(record.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                AnalyticsValueGrid(minimumWidth: 96) {
                    ReportTotal(value: "\(report.reps)", title: "Reps")
                    if report.holdSeconds > 0 {
                        ReportTotal(value: "\(Int(report.holdSeconds))", title: "Hold seconds")
                    }
                    ReportTotal(value: "\(report.setCount)", title: "Sets")
                }
                if report.activeSeconds > 0 {
                    Label("\(clockText(report.activeSeconds)) recorded active time", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
                }
                ReportHighlightCard(highlight: report.highlight(history: history))
                if !report.sets.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your sets").font(.headline)
                        ForEach(Array(report.sets.enumerated()), id: \.element.id) { index, set in
                            VStack(alignment: .leading, spacing: 9) {
                                let layout = dynamicTypeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                                layout {
                                    HStack(alignment: .top, spacing: 12) {
                                        if let entry = ExerciseCatalog.find(set.exerciseID) {
                                            ExerciseArtwork(entry: entry).frame(width: 52, height: 60).accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(set.exerciseName).font(.headline)
                                            Text("Set \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                            ReportSourceBadge(source: set.source, origin: set.quantityOrigin)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(set.quantityText).font(.title2.weight(.semibold)).monospacedDigit()
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(set.reason.title).font(.caption)
                                    .foregroundStyle(set.reason == .discomfort ? Palette.red : ([StopReason.form, .failure].contains(set.reason) ? Palette.amber : Palette.muted))
                                Text("Effort: \(record.loggedSets.first(where: { $0.id == set.id })?.effort.map { "\($0.rawValue) · \($0.title)" } ?? "Unrated")").font(.caption).foregroundStyle(.secondary)
                                if let reserve = set.reserve {
                                    Text("\(reserve == 3 ? "3+" : "\(reserve)") reps in reserve").font(.caption).foregroundStyle(.secondary)
                                }
                                if set.averageRepSeconds != nil || set.restSecondsBefore != nil {
                                    DisclosureGroup("Tempo & rest") {
                                        if let average = set.averageRepSeconds {
                                            Text("\(average, format: .number.precision(.fractionLength(1))) sec per recorded rep")
                                        }
                                        if let rest = set.restSecondsBefore {
                                            Text("\(rest, format: .number.precision(.fractionLength(0...1))) sec rest before this set")
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if index < report.setCount - 1 { Divider() }
                        }
                    }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                if !record.skippedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Skipped sets").font(.headline)
                        Text("Skipped by choice · excluded from completed sets, reps, active time and XP")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(record.skippedSets) { skipped in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ExerciseCatalog.find(skipped.exerciseID)?.name ?? skipped.exerciseID).font(.subheadline.weight(.semibold))
                                Text("Planned set \(skipped.number), target \(skipped.target) \(skipped.unit == .reps ? (skipped.target == 1 ? "rep" : "reps") : "sec")")
                                    .font(.caption).foregroundStyle(.secondary)
                                ReportSourceBadge(source: skipped.source)
                            }
                        }
                        Text("Saved in local history and exports. Unlogged activity isn’t included.").font(.caption).foregroundStyle(.secondary)
                    }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("session-skipped-sets")
                }

                let allowsHealth = record.trainingContext?.age?.allowsHealthIntegration == true && profile?.programmePreferences?.ageContext?.allowsHealthIntegration == true
                WorkoutAnalyticsSections(record: record, zones: allowsHealth ? zones : nil, allowsHealth: allowsHealth)
                CoachSummaryCard(record: record, profile: profile)
                DisclosureGroup(previewEnabled ? "Data sources" : "How this is recorded", isExpanded: $sourcesExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        if previewEnabled {
                            Text("Sample history is stored separately from your workouts. These values are examples, including any missing readings.")
                        }
                        Text("Camera counts are observations; manual reps are self-reported. Video results describe replayed footage.")
                        Text("Recorded time includes tracked sets, live manual set timers and logged hold durations. Bulk manual rep entries have no recorded duration.")
                        Text("Acceleration is the magnitude of Core Motion user acceleration with gravity removed, in g. Rotation is angular-speed magnitude in radians per second. The Watch sends sampled magnitudes, not continuous raw motion.")
                        Text("Heart-rate averages weight observed intervals of at most 12 seconds, excluding known pauses. Longer gaps remain unknown. Wrist motion windows do not establish exercise form.")
                        Text("Active energy uses cumulative Watch recording deltas. Repeated readings are not added together; decreases within a recording are flagged. These estimates stay in local history and exports; they are not included in Coach requests or cloud sync.")
                        Text("Count highlights compare earlier saved sets of the same exercise and source; they do not establish strength or fitness changes.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.subheadline)
                Label("Saved locally on this iPhone", systemImage: "iphone").font(.caption.weight(.semibold))
                Text("View or export your history in Profile and settings. Your account does not sync workouts, video or Health data.")
                    .font(.caption).foregroundStyle(.secondary)

            }.padding(24)
        }.background(.white)
            .navigationTitle("Session report").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReportTotal: View {
    let value: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private struct ReportHighlightCard: View {
    let highlight: SessionHighlight
    private var title: String {
        switch highlight {
        case .firstActivity: return "A starting point"
        case .repBest: return "Your highest recorded set"
        case .discomfort: return "Discomfort recorded"
        case .difficult: return "Review how it felt"
        case .noActivity: return "No reps or holds recorded"
        case .replay: return "Video review"
        case .recorded: return "Session saved"
        }
    }
    private var detail: String {
        switch highlight {
        case .firstActivity: return "A starting point in your training history on this iPhone."
        case .repBest(let exerciseID, let source, let reps, let previous):
            let name = ExerciseCatalog.find(exerciseID)?.name ?? "Exercise"
            let label = source == .manual ? "manually logged" : "camera counted"
            return "\(name): \(reps) reps, \(label). Previous saved best with the same source: \(previous) \(previous == 1 ? "rep" : "reps")."
        case .discomfort: return "Give yourself time to recover. Your recorded work is below."
        case .difficult: return "You recorded difficulty with form or completing a set. Your sets and feedback are below."
        case .noActivity: return "Recorded time and any available sensor readings are shown below."
        case .replay: return "These results describe recorded footage."
        case .recorded: return "Review your work and how each set felt."
        }
    }
    private var color: Color {
        switch highlight {
        case .firstActivity, .repBest: return Palette.green
        case .discomfort: return Palette.red
        case .difficult: return Palette.amber
        default: return Palette.ink
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline).foregroundStyle(color)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("session-highlight")
    }
}

private struct ReportSourceBadge: View {
    let source: InputSource
    let origin: LoggedSet.QuantityOrigin?
    init(source: InputSource, origin: LoggedSet.QuantityOrigin? = nil) {
        self.source = source; self.origin = origin
    }
    private var title: String {
        if origin == .activeTimer { return "Manual hold timer" }
        switch source {
        case .camera: return "Camera"
        case .manual: return "Manual"
        case .video: return "Video"
        }
    }
    var body: some View {
        Text(title).font(.caption2.weight(.semibold))
            .foregroundStyle(source == .camera ? Palette.blue : Palette.muted)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(source == .camera ? Palette.blue.opacity(0.07) : .white, in: Capsule())
            .overlay(Capsule().stroke((source == .camera ? Palette.blue : Palette.muted).opacity(0.2)))
    }
}
