import SwiftUI

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
                        ContentUnavailableView("No sample workouts yet", systemImage: "chart.xyaxis.line",
                            description: Text("Completed preview workouts will appear here."))
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
            Label("TESTFLIGHT PREVIEW", systemImage: "sparkle")
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Palette.blue)
            Text("Sample progress").font(.largeTitle.bold()).tracking(-1)
            Text("Sample workouts. Your real history stays separate.")
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
            Text("These totals come from the sample workout records below.")
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
                Text(insight?.title ?? report.category.rawValue).font(.headline)
                Text(report.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(report.setCount) sets · \(report.reps) reps\(report.holdSeconds > 0 ? " · \(Int(report.holdSeconds)) sec holds" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(insight == nil ? "Recorded workout" : "Preview effort & achievement")
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
            .accessibilityLabel("Preview grade \(grade), \(score) out of 100")
    }
}

struct DemoWorkoutInsightsView: View {
    let history: [SessionRecord]
    let profile: LocalProfile?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Every workout has a story").font(.largeTitle.bold()).tracking(-0.8)
                Text("Sample insights, most recent first. Grades illustrate effort and achievement in this preview.")
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
                    Text("SAMPLE WORKOUT").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Palette.blue)
                    Text(insight?.title ?? report.category.rawValue).font(.largeTitle.bold()).tracking(-0.8)
                    Text(record.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                if let insight {
                    VStack(alignment: .leading, spacing: 20) {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
                        layout {
                            DemoGradeRing(score: insight.score, grade: insight.grade)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preview grade").font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
                                Text("Effort & achievement").font(.title3.bold())
                            }
                        }
                        Text(insight.summary).font(.headline)
                        Text(insight.rationale).font(.subheadline).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 24) { scoreBreakdown(insight) }
                            VStack(alignment: .leading, spacing: 14) { scoreBreakdown(insight) }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("What you completed").font(.title2.bold())
                    ForEach(report.sets) { set in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(set.exerciseName).font(.subheadline.weight(.semibold))
                                Text("Sample · \(set.sourceLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(set.quantityText).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                }
                NavigationLink {
                    SessionReportView(record: record, profile: profile, history: history)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("How preview grades work").font(.subheadline.weight(.semibold))
            Text("A+ · A · A− · B+ · B · B− · C+ · C · C− · D+ · D · D−")
                .font(.caption).foregroundStyle(.secondary)
            Text("Authored sample effort and completed targets illustrate achievement. These grades are not a health or readiness assessment. Stopping for discomfort is always appropriate.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 4).accessibilityIdentifier("demo-grade-explanation")
    }
}
