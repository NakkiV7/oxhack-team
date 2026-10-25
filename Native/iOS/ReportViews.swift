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
                        Text("This week").font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("\(week.interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(week.interval.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated))) · week so far")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
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
                            Text("Your first session starts here.").font(.headline)
                            Text("Finish a set to see your reps, time and effort in one place.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        Text("Session reports").font(.headline)
                        ForEach(store.history) { record in
                            NavigationLink {
                                SessionReportView(record: record, profile: profile, history: store.history)
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
                                        Text("\(category.setCount) \(category.setCount == 1 ? "set" : "sets") · \(category.reps) \(category.reps == 1 ? "rep" : "reps")")
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
            Text("\(report.setCount) \(report.setCount == 1 ? "set" : "sets") · \(report.reps) \(report.reps == 1 ? "rep" : "reps")").font(.title3.weight(.semibold))
            HStack {
                Text(report.date.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                if report.holdSeconds > 0 { Text("\(Int(report.holdSeconds)) sec holds") }
            }.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
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
    init(record: SessionRecord, profile: LocalProfile? = nil, history: [SessionRecord]? = nil) {
        self.record = record; self.profile = profile; self.history = history
    }
    var body: some View {
        let report = WorkoutReport(record: record)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(report.sets.isEmpty && !record.skippedSets.isEmpty ? "Session check-in" : report.category.rawValue).font(.system(size: 30, weight: .bold)).tracking(-0.8)
                    Text(record.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 16) {
                    ReportTotal(value: "\(report.reps)", title: "Reps")
                    if report.holdSeconds > 0 {
                        ReportTotal(value: "\(Int(report.holdSeconds))", title: "Hold seconds")
                    }
                    ReportTotal(value: "\(report.setCount)", title: "Sets")
                }
                Label("\(clockText(report.activeSeconds)) recorded time", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
                ReportHighlightCard(highlight: report.highlight(history: history))
                if !report.sets.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your sets").font(.headline)
                        ForEach(Array(report.sets.enumerated()), id: \.element.id) { index, set in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .top, spacing: 12) {
                                    if let entry = ExerciseCatalog.find(set.exerciseID) {
                                        Image(entry.art).resizable().scaledToFit().frame(width: 52, height: 60).accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(set.exerciseName).font(.headline)
                                        Text("Set \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                        ReportSourceBadge(source: set.source, origin: set.quantityOrigin)
                                    }
                                    Spacer(minLength: 0)
                                    Text(set.quantityText).font(.title2.weight(.semibold)).monospacedDigit()
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(set.reason.title).font(.caption)
                                    .foregroundStyle(set.reason == .discomfort ? Palette.red : ([StopReason.form, .failure].contains(set.reason) ? Palette.amber : Palette.muted))
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
                        Text("Planned steps you chose to skip. These are not completed sets and do not add reps, active time or XP.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(record.skippedSets) { skipped in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ExerciseCatalog.find(skipped.exerciseID)?.name ?? skipped.exerciseID).font(.subheadline.weight(.semibold))
                                Text("Planned set \(skipped.number) · target \(skipped.target) \(skipped.unit == .reps ? (skipped.target == 1 ? "rep" : "reps") : "sec")")
                                    .font(.caption).foregroundStyle(.secondary)
                                ReportSourceBadge(source: skipped.source)
                                Text("Skipped by choice. Missing entries or observations do not prove no physical exercise occurred.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Skip details stay in local history and exports.").font(.caption).foregroundStyle(.secondary)
                    }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("session-skipped-sets")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Watch heart rate").font(.headline)
                    Text(report.heartRate.sourceLabel).font(.caption).foregroundStyle(.secondary)
                    if let average = report.heartRate.average {
                        HStack {
                            Metric(value: "\(Int(average.rounded())) bpm", title: "Average heart rate", symbol: "heart", symbolColor: Palette.red)
                            if let maximum = report.heartRate.maximum {
                                Metric(value: "\(Int(maximum.rounded())) bpm", title: "Highest reading", symbol: "arrow.up", symbolColor: Palette.red)
                            }
                        }
                        ReportSignalChart(signal: report.heartRate, unit: "bpm", color: Palette.red)
                    } else {
                        Text("No Watch heart-rate readings recorded.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Watch active energy", systemImage: "flame.fill")
                        .font(.headline).foregroundStyle(Palette.amber)
                    Text("Apple Watch · HealthKit").font(.caption).foregroundStyle(.secondary)
                    if report.activeEnergy.isEmpty {
                        Text("No Watch active-energy readings recorded.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(report.activeEnergy.enumerated()), id: \.element.recordingID) { index, energy in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(energy.kilocalories, format: .number.precision(.fractionLength(0...1)))
                                        .font(.system(size: 36, weight: .semibold)).monospacedDigit()
                                    Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text(report.activeEnergy.count == 1 ? "Estimated active energy" : "Recording \(index + 1) · estimated active energy")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("As of \(energy.asOf.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                                ReportEnergyChart(samples: report.energyTimeline.filter { $0.recordingID == energy.recordingID })
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("watch-active-energy-reading")
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tempo & movement").font(.headline)
                    if let average = report.averageRepSeconds {
                        Metric(value: String(format: "%.1f sec", average), title: "Average rep tempo", symbol: "metronome")
                        Text("\(report.timedRepCount) recorded reps · sets without timings excluded.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Rep tempo was not recorded.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ReportMotionSignal(title: "Wrist acceleration magnitude", signal: report.acceleration,
                                       unit: "g", missing: "No Watch acceleration readings recorded.")
                    ReportMotionSignal(title: "Wrist rotation magnitude", signal: report.rotation,
                                       unit: "rad/s", missing: "No Watch rotation readings recorded.")
                }
                CoachSummaryCard(record: record, profile: profile)
                DisclosureGroup("How this is recorded") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Camera counts are observations; manual reps are self-reported. Video results describe replayed footage.")
                        Text("Recorded time includes tracked sets, live manual set timers and logged hold durations. Bulk manual rep entries have no recorded duration.")
                        Text("Acceleration is the magnitude of Core Motion user acceleration with gravity removed, in g. Rotation is angular-speed magnitude in radians per second. The Watch sends sampled magnitudes, not continuous raw motion.")
                        Text("Watch averages weight each distinct reading once. Wrist movement does not establish exercise form. Missing periods stay unknown; timestamps do not establish exact set boundaries.")
                        Text("Active energy is the latest cumulative Watch estimate for each recording. Repeated readings are not added together. These estimates stay in local history and exports; they are not included in Coach requests or cloud sync.")
                        Text("Count highlights compare earlier saved sets of the same exercise and source; they do not establish strength or fitness changes.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.subheadline)
                if record.setCount == 0, !record.skippedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Saved locally", systemImage: "iphone").font(.subheadline.weight(.semibold))
                        Text("Skipped steps stay on this iPhone and in your history export. There are no completed sets to upload.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("skip-only-local-note")
                } else {
                    DisclosureGroup("Cloud sync") {
                        CloudSyncCard(record: record).padding(.top, 8)
                        if !record.skippedSets.isEmpty {
                            Text("Cloud sync includes completed sets only. Skip details remain in local history and exports.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.font(.subheadline)
                }
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
            Text(value).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportHighlightCard: View {
    let highlight: SessionHighlight
    private var title: String {
        switch highlight {
        case .firstActivity: return "A starting point."
        case .repBest: return "Your highest recorded set."
        case .discomfort: return "Discomfort was recorded."
        case .difficult: return "Review how it felt."
        case .noActivity: return "No reps or holds recorded."
        case .replay: return "Video review."
        case .recorded: return "Your session, recorded."
        }
    }
    private var detail: String {
        switch highlight {
        case .firstActivity: return "Your first non-video activity in the history saved on this iPhone."
        case .repBest(let exerciseID, let source, let reps, let previous):
            let name = ExerciseCatalog.find(exerciseID)?.name ?? "Exercise"
            let label = source == .manual ? "Manual self-report" : "Camera"
            return "\(name) · \(reps) reps · \(label). Earlier saved best for this exercise and source: \(previous) \(previous == 1 ? "rep" : "reps")."
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
        Text(title).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(source == .camera ? Palette.blue : Palette.muted)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(source == .camera ? Palette.blue.opacity(0.07) : .white, in: Capsule())
            .overlay(Capsule().stroke((source == .camera ? Palette.blue : Palette.muted).opacity(0.2)))
    }
}

private struct ReportMotionSignal: View {
    let title: String
    let signal: ReportSignal
    let unit: String
    let missing: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            Text(signal.sourceLabel).font(.caption).foregroundStyle(.secondary)
            if let average = signal.average, let maximum = signal.maximum {
                Text("Average \(average.formatted(.number.precision(.fractionLength(2)))) \(unit) · highest \(maximum.formatted(.number.precision(.fractionLength(2)))) \(unit)")
                    .font(.subheadline).monospacedDigit()
                ReportSignalChart(signal: signal, unit: unit)
            } else {
                Text(missing).font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier(unit == "g" ? "watch-acceleration-report" : "watch-rotation-report")
    }
}

private struct ReportEnergyChart: View {
    let samples: [ActiveEnergy]
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    // Points preserve sparse observations without suggesting continuous coverage.
                    PointMark(x: .value("As of", sample.asOf), y: .value("kcal", sample.kilocalories))
                        .foregroundStyle(Palette.amber).symbolSize(24)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
            .chartLegend(.hidden)
            .chartYAxisLabel("kcal").frame(height: 130)
            Text("Cumulative observations for this recording. Points are not added together; no new point means no new energy observation.")
                .font(.caption2).foregroundStyle(.secondary)
        }.accessibilityIdentifier("watch-energy-timeline")
    }
}

private struct ReportSignalChart: View {
    let signal: ReportSignal
    let unit: String
    var color: Color = Palette.blue
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart(signal.samples) { sample in
                LineMark(x: .value("Time", sample.date), y: .value(unit, sample.value), series: .value("Segment", sample.segment))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("Time", sample.date), y: .value(unit, sample.value))
                    .foregroundStyle(color).symbolSize(16)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
            .chartYAxisLabel(unit)
            .chartLegend(.hidden)
            .frame(height: 155)
            if let span = signal.sampleSpan {
                Text("\(signal.samples.count) \(signal.samples.count == 1 ? "reading" : "readings") · \(clockText(span)) first-to-last span · \(signal.gapCount) \(signal.gapCount == 1 ? "gap" : "gaps") over 12 sec")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Gaps stay blank. Time between the first and last reading is not continuous coverage.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
