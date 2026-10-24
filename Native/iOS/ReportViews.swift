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
                                .foregroundStyle(Palette.ink).cornerRadius(4)
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
                                SessionReportView(record: record, profile: profile)
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
                                        Text("\(category.setCount) \(category.setCount == 1 ? "set" : "sets") · \(category.reps) reps")
                                        if category.holdSeconds > 0 { Text("\(Int(category.holdSeconds)) sec holds") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    } else if !store.history.isEmpty {
                        Text("No sessions recorded this week.").font(.subheadline).foregroundStyle(.secondary)
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
            Text("\(report.setCount) \(report.setCount == 1 ? "set" : "sets") · \(report.reps) reps").font(.title3.weight(.semibold))
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
    init(record: SessionRecord, profile: LocalProfile? = nil) { self.record = record; self.profile = profile }
    var body: some View {
        let report = WorkoutReport(record: record)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(report.category.rawValue).font(.system(size: 30, weight: .bold)).tracking(-0.8)
                    Text(record.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Metric(value: "\(report.setCount)", title: "Sets", symbol: "square.3.layers.3d")
                    Metric(value: "\(report.reps)", title: "Reps", symbol: "repeat")
                    Metric(value: clockText(report.activeSeconds), title: "Recorded time", symbol: "clock")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your sets").font(.headline)
                    ForEach(Array(report.sets.enumerated()), id: \.element.id) { index, set in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .top, spacing: 12) {
                                if let entry = ExerciseCatalog.find(set.exerciseID) {
                                    Image(entry.art).resizable().scaledToFit().frame(width: 45, height: 48).accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(index + 1). \(set.exerciseName)").font(.subheadline.weight(.semibold))
                                    Text(set.quantityText).font(.subheadline).monospacedDigit()
                                }
                                Spacer(minLength: 0)
                                ReportSourceBadge(source: set.source, origin: set.quantityOrigin)
                            }
                            if let average = set.averageRepSeconds {
                                Text("Tempo · \(average, format: .number.precision(.fractionLength(1))) sec per rep")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let rest = set.restSecondsBefore {
                                Text("Rest before · \(rest, format: .number.precision(.fractionLength(0...1))) sec")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(set.reason.title).font(.caption).foregroundStyle(.secondary)
                            if let reserve = set.reserve {
                                Text("\(reserve == 3 ? "3+" : "\(reserve)") reps in reserve").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if index < report.setCount - 1 { Divider() }
                    }
                    Text("Recorded time includes tracked sets, live manual set timers and logged hold durations. Bulk manual rep entries have no recorded duration.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                CoachSummaryCard(record: record, profile: profile)
                CloudSyncCard(record: record)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Watch heart rate").font(.headline)
                    if let average = report.heartRate.average {
                        HStack {
                            Metric(value: "\(Int(average.rounded())) bpm", title: "Average heart rate", symbol: "heart")
                            if let maximum = report.heartRate.maximum {
                                Metric(value: "\(Int(maximum.rounded())) bpm", title: "Highest reading", symbol: "arrow.up")
                            }
                        }
                        ReportSignalChart(signal: report.heartRate, unit: "bpm")
                        Text("\(report.heartRate.samples.count) distinct Watch readings. The average weights each recorded reading once.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No Watch heart-rate readings recorded.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tempo & movement").font(.headline)
                    if let average = report.averageRepSeconds {
                        Metric(value: String(format: "%.1f sec", average), title: "Average rep tempo", symbol: "metronome")
                        Text("\(report.timedRepCount) recorded reps · sets without timings excluded.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Rep tempo was not recorded.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !report.acceleration.samples.isEmpty {
                        Text("Wrist acceleration magnitude").font(.subheadline.weight(.medium))
                        ReportSignalChart(signal: report.acceleration, unit: "g")
                    }
                    if !report.rotation.samples.isEmpty {
                        Text("Wrist rotation magnitude").font(.subheadline.weight(.medium))
                        ReportSignalChart(signal: report.rotation, unit: "rad/s")
                    }
                    if report.acceleration.samples.isEmpty && report.rotation.samples.isEmpty {
                        Text("No Watch motion samples recorded.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Watch wrist magnitudes describe recorded movement; they do not establish exercise form.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(24)
        }.background(.white)
            .navigationTitle("Session report").navigationBarTitleDisplayMode(.inline)
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
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.white, in: Capsule()).overlay(Capsule().stroke(Palette.ink.opacity(0.12)))
    }
}

private struct ReportSignalChart: View {
    let signal: ReportSignal
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Chart(signal.samples) { sample in
                LineMark(x: .value("Time", sample.date), y: .value(unit, sample.value), series: .value("Segment", sample.segment))
                    .foregroundStyle(Palette.ink).lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("Time", sample.date), y: .value(unit, sample.value))
                    .foregroundStyle(Palette.ink).symbolSize(16)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
            .chartYAxisLabel(unit)
            .chartLegend(.hidden)
            .frame(height: 155)
            Text("Measured timestamps · gaps over 12 seconds stay blank.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
