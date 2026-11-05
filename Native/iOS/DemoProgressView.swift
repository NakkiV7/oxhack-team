import SwiftUI
import Charts

struct DemoProgressView: View {
    let store: TrainingStore
    let profile: LocalProfile?

    init(store: TrainingStore, profile: LocalProfile? = nil) {
        self.store = store
        self.profile = profile
    }

    private var history: [SessionRecord] { store.history.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if history.isEmpty {
                        ContentUnavailableView("No workouts yet", systemImage: "chart.xyaxis.line",
                            description: Text("Complete a workout to see your progress here."))
                            .accessibilityIdentifier("demo-progress-empty")
                    } else {
                        weeklyOverview
                        NavigationLink {
                            DemoWorkoutInsightsView(history: history, profile: profile)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "sparkles").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Workout insights").font(.headline)
                                    Text("Explore effort, achievements and every set")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("demo-progress-insights")
                        workoutMix
                        DemoBiometricOverview(history: history)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Recent workouts").font(.title2.bold())
                            Text("Most recent first").font(.caption).foregroundStyle(.secondary)
                            ForEach(history) { record in
                                NavigationLink {
                                    DemoWorkoutInsightDetail(record: record, history: history, profile: profile)
                                } label: {
                                    DemoWorkoutRow(record: record)
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("demo-progress-workout-\(record.id.uuidString)")
                            }
                        }
                    }
                }.padding(24)
            }
            .background(.white).foregroundStyle(Palette.ink)
            .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("demo-progress-dashboard")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Training progress").font(.largeTitle.bold()).tracking(-1)
            Text("Your workouts and trends at a glance.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var weeklyOverview: some View {
        let week = WeekReport(history: history)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your week, in motion").font(.title2.bold())
                Text("\(week.interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(week.interval.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 22) {
                DemoProgressMetric(value: "\(week.sessions.count)", label: "Workouts", symbol: "calendar")
                DemoProgressMetric(value: "\(week.setCount)", label: "Sets completed", symbol: "checkmark.circle")
                DemoProgressMetric(value: "\(week.reps)", label: "Reps recorded", symbol: "repeat")
            }
            if week.holdSeconds > 0 {
                Label("\(Int(week.holdSeconds)) seconds of mobility & holds", systemImage: "figure.cooldown")
                    .font(.subheadline).foregroundStyle(Palette.green)
            }
            Divider()
            Text("Every completed set adds to the picture.")
                .font(.subheadline.weight(.medium))
            Text("Explore each workout for the sets and observations behind these totals.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("demo-progress-week")
    }

    private var workoutMix: some View {
        let week = WeekReport(history: history)
        return VStack(alignment: .leading, spacing: 18) {
            Text("This week’s mix").font(.title2.bold())
            if week.categories.isEmpty {
                Text("No completed sets this week.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(week.categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(category.category.rawValue).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(category.setCount) sets").font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Palette.surface)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Palette.blue)
                                    .frame(width: proxy.size.width * CGFloat(category.setCount) / CGFloat(max(1, week.setCount)))
                            }
                    }.frame(height: 7).accessibilityHidden(true)
                }.accessibilityElement(children: .combine)
            }
        }.accessibilityIdentifier("demo-progress-workout-mix")
    }
}

private struct DemoProgressMetric: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.body).foregroundStyle(Palette.blue).accessibilityHidden(true)
            Text(value).font(.largeTitle.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct DemoWorkoutRow: View {
    let record: SessionRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let report = WorkoutReport(record: record)
        let insight = DemoPreviewData.insight(for: record)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            if let insight {
                DemoGradeRing(score: insight.score, grade: insight.grade)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(insight?.displayTitle ?? report.category.rawValue).font(.headline)
                Text(report.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(report.setCount) sets, \(report.reps) reps\(report.holdSeconds > 0 ? ", \(Int(report.holdSeconds)) sec holds" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(insight == nil ? "Recorded workout" : "Effort & achievement")
                    .font(.caption2.weight(.medium)).foregroundStyle(Palette.blue)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(Palette.ink.opacity(0.09), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

private struct DemoGradeRing: View {
    let score: Int
    let grade: String
    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 76
    private var color: Color { score >= 80 ? Palette.green : (score >= 60 ? Palette.amber : Palette.red) }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(max(0, min(score, 100))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.title2.bold()).monospacedDigit()
                Text(grade).font(.caption.weight(.bold)).foregroundStyle(color)
            }
        }.frame(width: min(diameter, 116), height: min(diameter, 116))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Grade \(grade), \(score) out of 100")
    }
}

struct DemoWorkoutInsightsView: View {
    let history: [SessionRecord]
    let profile: LocalProfile?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Every workout has a story").font(.largeTitle.bold()).tracking(-0.8)
                Text("Explore effort, completed targets and the details behind each workout.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if history.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "chart.bar.doc.horizontal")
                }
                ForEach(history.sorted { $0.date > $1.date }) { record in
                    NavigationLink {
                        DemoWorkoutInsightDetail(record: record, history: history, profile: profile)
                    } label: {
                        DemoWorkoutRow(record: record)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("demo-insight-workout-\(record.id.uuidString)")
                }
                DemoGradeExplanation()
            }.padding(24)
        }.background(.white).foregroundStyle(Palette.ink)
            .navigationTitle("Workout insights").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("demo-workout-insights")
    }
}

private struct DemoWorkoutInsightDetail: View {
    let record: SessionRecord
    let history: [SessionRecord]
    let profile: LocalProfile?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let report = WorkoutReport(record: record)
        let insight = DemoPreviewData.insight(for: record)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight?.displayTitle ?? report.category.rawValue).font(.largeTitle.bold()).tracking(-0.8)
                    Text(record.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                if let insight {
                    VStack(alignment: .leading, spacing: 20) {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
                        layout {
                            DemoGradeRing(score: insight.score, grade: insight.grade)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Effort & achievement").font(.title3.bold())
                            }
                        }
                        Text("\(report.setCount) sets, \(report.reps) reps\(report.holdSeconds > 0 ? ", \(Int(report.holdSeconds)) sec holds" : "")").font(.headline)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 24) { scoreBreakdown(insight) }
                            VStack(alignment: .leading, spacing: 14) { scoreBreakdown(insight) }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                }
                if let insight {
                    DemoWorkoutBiometrics(record: record, insight: insight)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("What you completed").font(.title2.bold())
                    ForEach(report.sets) { set in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(set.exerciseName).font(.subheadline.weight(.semibold))
                                Text(set.sourceLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(set.quantityText).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }
                NavigationLink {
                    SessionReportView(record: record, profile: profile, history: history, previewEnabled: true)
                } label: {
                    Label("Open full workout report", systemImage: "arrow.up.right")
                        .font(.headline).frame(maxWidth: .infinity).padding(18)
                        .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("demo-workout-full-report")
                DemoGradeExplanation()
            }.padding(24)
        }.background(.white).foregroundStyle(Palette.ink)
            .navigationTitle("Workout insights").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("demo-workout-detail-\(record.id.uuidString)")
    }

    @ViewBuilder private func scoreBreakdown(_ insight: DemoPreviewInsight) -> some View {
        Text("Effort  \(insight.effortScore)/100").font(.subheadline.weight(.semibold))
        Text("Achievement  \(insight.achievementScore)/100").font(.subheadline.weight(.semibold))
    }
}

private struct DemoGradeExplanation: View {
    var body: some View {
        DisclosureGroup("About grades") {
            VStack(alignment: .leading, spacing: 8) {
            Text("A+, A, A−, B+, B, B−, C+, C, C−, D+, D, D−")
                .font(.caption).foregroundStyle(.secondary)
            Text("Effort and completed targets illustrate achievement. These example grades are not a health or readiness assessment. Stopping for discomfort is always appropriate.")
                .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.top, 4).accessibilityIdentifier("demo-grade-explanation")
    }
}

private struct DemoBiometricWorkout: Identifiable {
    let record: SessionRecord
    let insight: DemoPreviewInsight
    let report: WorkoutReport
    var id: UUID { record.id }
    init?(_ record: SessionRecord) {
        guard let insight = DemoPreviewData.insight(for: record) else { return nil }
        self.record = record; self.insight = insight; self.report = WorkoutReport(record: record)
    }
    var energy: Double? {
        report.activeEnergy.isEmpty ? nil : report.activeEnergy.map(\.kilocalories).reduce(0, +)
    }
}

private struct DemoBiometricOverview: View {
    let history: [SessionRecord]
    private var workouts: [DemoBiometricWorkout] {
        history.compactMap(DemoBiometricWorkout.init).sorted { $0.record.date < $1.record.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Heart rate & effort").font(.title2.bold())
            Text("Session averages across your workouts").font(.caption).foregroundStyle(.secondary)
            Chart(workouts) { workout in
                if let average = workout.report.heartRate.average {
                    LineMark(x: .value("Workout", workout.record.date), y: .value("bpm", average))
                        .foregroundStyle(Palette.red).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Workout", workout.record.date), y: .value("bpm", average))
                        .foregroundStyle(Palette.red).symbolSize(35)
                }
            }.chartYAxisLabel("bpm").chartLegend(.hidden).frame(height: 145)
                .accessibilityLabel("Heart rate session-average trend")
            if let latest = workouts.last {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    DemoBiometricValue(title: "Average heart rate", value: demoBiometricNumber(latest.report.heartRate.average), unit: "bpm", color: Palette.red)
                    DemoBiometricValue(title: "Active energy", value: demoBiometricNumber(latest.energy), unit: "kcal", color: Palette.amber)
                    DemoBiometricValue(title: "Acceleration", value: demoBiometricNumber(latest.report.acceleration.average, digits: 2), unit: "g", color: Palette.blue)
                    DemoBiometricValue(title: "Rotation", value: demoBiometricNumber(latest.report.rotation.average, digits: 2), unit: "rad/s", color: Palette.blue)
                }
                Text("Latest workout, \(latest.insight.displayTitle)").font(.caption).foregroundStyle(.secondary)
            }
            if let lower = workouts.min(by: { $0.insight.effortScore < $1.insight.effortScore }),
               let higher = workouts.max(by: { $0.insight.effortScore < $1.insight.effortScore }), lower.id != higher.id {
                Divider()
                Text("Compare effort").font(.headline)
                comparison(lower)
                comparison(higher)
            }
            DisclosureGroup("Data sources") {
                Text("Synthetic preview, not recorded health data. These fictional workouts, Watch-style heart rate, motion and cumulative energy, and Presage-style stationary pulse/breathing values are authored examples. Effort bands and grades are not inferred from biometrics and do not assess readiness or fitness. Your real history remains separate.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).accessibilityIdentifier("demo-progress-data-sources")
        }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("demo-progress-biometric-trends")
    }
    private func comparison(_ workout: DemoBiometricWorkout) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(workout.insight.biometrics.effortBand).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(workout.insight.effortScore)/100").font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
            }
            Text("\(demoBiometricNumber(workout.report.heartRate.average)) bpm average, \(demoBiometricNumber(workout.energy)) kcal, \(workout.report.reps) reps")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct DemoWorkoutBiometrics: View {
    let record: SessionRecord
    let insight: DemoPreviewInsight
    private var report: WorkoutReport { WorkoutReport(record: record) }
    private var energy: Double? { report.activeEnergy.isEmpty ? nil : report.activeEnergy.map(\.kilocalories).reduce(0, +) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Heart rate", systemImage: "heart.fill").font(.title2.bold()).foregroundStyle(Palette.red)
            if report.heartRate.samples.isEmpty {
                Text("No heart-rate observations in this workout.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                DemoBiometricSignalChart(signal: report.heartRate, unit: "bpm", color: Palette.red)
                HStack(spacing: 24) {
                    DemoBiometricValue(title: "Average", value: demoBiometricNumber(report.heartRate.average), unit: "bpm", color: Palette.red)
                    DemoBiometricValue(title: "Peak", value: demoBiometricNumber(report.heartRate.maximum), unit: "bpm", color: Palette.red)
                }
            }
            Divider()
            Text("Stationary snapshot").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { cameraValues }
                VStack(alignment: .leading, spacing: 16) { cameraValues }
            }
            Divider()
            Text("Movement & energy").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 18) {
                DemoBiometricValue(title: "Active energy", value: demoBiometricNumber(energy), unit: "kcal", color: Palette.amber)
                DemoBiometricValue(title: "Acceleration", value: demoBiometricNumber(report.acceleration.average, digits: 2), unit: "g", color: Palette.blue)
                DemoBiometricValue(title: "Rotation", value: demoBiometricNumber(report.rotation.average, digits: 2), unit: "rad/s", color: Palette.blue)
            }
            DisclosureGroup("Explore movement & energy") {
                VStack(alignment: .leading, spacing: 16) {
                    if !report.acceleration.samples.isEmpty {
                        Text("Acceleration magnitude").font(.caption.weight(.semibold))
                        DemoBiometricSignalChart(signal: report.acceleration, unit: "g", color: Palette.blue)
                    }
                    if !report.energyTimeline.isEmpty {
                        Text("Cumulative active energy").font(.caption.weight(.semibold))
                        Chart(Array(report.energyTimeline.enumerated()), id: \.offset) { item in
                            PointMark(x: .value("Time", item.element.asOf), y: .value("kcal", item.element.kilocalories))
                                .foregroundStyle(Palette.amber).symbolSize(25)
                        }.chartYAxisLabel("kcal").frame(height: 110)
                        Text("Each point is cumulative within its recording; points are not added together.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            }.font(.subheadline)
            DisclosureGroup("Data sources") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.biometrics.sourceLabel).font(.caption.weight(.semibold))
                    Text("Heart rate, acceleration, rotation and energy are authored Watch-style telemetry. Stationary pulse and breathing are authored Presage-style examples, separate from Watch heart rate. No physical sensor or API produced these values.")
                    Text(insight.biometrics.rationale)
                    Text(insight.rationale)
                    Text("Energy uses the latest cumulative value per recording. Missing values stay blank; motion values are magnitudes, not intensity or a safe exercise zone.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).accessibilityIdentifier("demo-workout-data-sources")
        }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("demo-workout-biometric-detail")
    }
    @ViewBuilder private var cameraValues: some View {
        DemoBiometricValue(title: "Pulse", value: demoBiometricNumber(insight.biometrics.presagePulse), unit: "bpm", color: Palette.red)
        DemoBiometricValue(title: "Breathing", value: demoBiometricNumber(insight.biometrics.presageBreathing), unit: "/min", color: Palette.blue)
    }
}

private struct DemoBiometricSignalChart: View {
    let signal: ReportSignal
    let unit: String
    let color: Color
    var body: some View {
        Chart(signal.samples) { sample in
            LineMark(x: .value("Time", sample.date), y: .value(unit, sample.value), series: .value("Segment", sample.segment))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Time", sample.date), y: .value(unit, sample.value)).foregroundStyle(color).symbolSize(14)
        }.chartYAxisLabel(unit).chartLegend(.hidden).frame(height: 130)
            .accessibilityLabel("\(unit) observations over time")
    }
}

private struct DemoBiometricValue: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private func demoBiometricNumber(_ value: Double?, digits: Int = 0) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(digits)))
}

private extension DemoPreviewInsight {
    var displayTitle: String { title == "A complete sample session" ? "Full-body foundations" : title }
}
