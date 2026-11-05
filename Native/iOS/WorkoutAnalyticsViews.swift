import SwiftUI
import Charts

struct WorkoutAnalyticsSections: View {
    let record: SessionRecord
    var zones: HeartRateZoneConfiguration? = nil

    var body: some View {
        let analysis = WorkoutAnalytics(record: record, zones: zones)
        VStack(alignment: .leading, spacing: 24) {
            WorkoutTimeCard(analysis: analysis)
            WorkoutHeartCard(heart: analysis.heart, configuration: zones)
            WorkoutPaceCard(pace: analysis.pace)
            WorkoutMotionCard(motion: analysis.motion)
        }.accessibilityIdentifier("workout-measured-analytics")
    }
}

private struct AnalyticsCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct AnalyticsValue: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct AnalyticsValueGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var minimumWidth: CGFloat = 140
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                  ? [GridItem(.flexible(), alignment: .leading)]
                  : [GridItem(.adaptive(minimum: minimumWidth), spacing: 16, alignment: .leading)],
                  alignment: .leading, spacing: 20) {
            content
        }
    }
}

private struct WorkoutTimeCard: View {
    let analysis: WorkoutAnalytics
    var body: some View {
        AnalyticsCard(title: "Recorded work & rest", symbol: "clock") {
            AnalyticsValueGrid {
                AnalyticsValue(title: "Active time", value: analysis.activeSeconds > 0 ? clockText(analysis.activeSeconds) : "Not timed")
                AnalyticsValue(title: "Rest", value: analysis.restSeconds.map(clockText) ?? "Not recorded")
            }
            if let ratio = analysis.workRestRatio {
                Text("Work / rest: \(ratio, format: .number.precision(.fractionLength(2))) : 1")
                    .font(.subheadline).monospacedDigit()
            }
            if let elapsed = analysis.elapsedSeconds {
                Text("\(clockText(elapsed)) elapsed · \(clockText(analysis.pausedSeconds)) paused")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Session start and finish times weren’t recorded.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Label("Watch active energy", systemImage: "flame").font(.subheadline.weight(.semibold))
            if let energy = analysis.activeKilocalories {
                AnalyticsValue(title: "Apple Watch estimate", value: energy.formatted(.number.precision(.fractionLength(0...1))) + " kcal")
            } else {
                Text("No Watch active-energy readings recorded.").font(.subheadline).foregroundStyle(.secondary)
            }
            if analysis.energyResetCount > 0 {
                Text("\(analysis.energyResetCount) decreasing energy observations were flagged. They do not count as new recordings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("About work & rest") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Only saved timers and rest are shown. Manual rep entries may be untimed.")
                    Text("Watch energy estimates are counted once per recording. A lower reading is flagged rather than treated as a new recording.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).frame(minHeight: 44)
                .accessibilityIdentifier("workout-time-details")
        }.accessibilityIdentifier("workout-time-analysis")
    }
}

private struct WorkoutHeartCard: View {
    let heart: HeartRateAnalysis
    let configuration: HeartRateZoneConfiguration?
    var body: some View {
        AnalyticsCard(title: "Watch heart rate", symbol: "heart") {
            Text("Apple Watch · HealthKit · this session").font(.caption).foregroundStyle(.secondary)
            if heart.samples.isEmpty {
                Text("No Watch heart-rate readings recorded.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                AnalyticsValueGrid {
                    if let average = heart.average { AnalyticsValue(title: "Time-weighted average", value: "\(Int(average.rounded())) bpm") }
                    if let minimum = heart.minimum, let maximum = heart.maximum {
                        AnalyticsValue(title: "Recorded range", value: "\(Int(minimum.rounded()))–\(Int(maximum.rounded())) bpm")
                    }
                }
                AnalyticsSignalChart(samples: heart.samples, unit: "bpm", color: Palette.red)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Observation coverage").font(.subheadline.weight(.semibold))
                    Text("\(clockText(heart.observedSeconds)) observed of \(clockText(heart.eligibleSeconds)) · \(heart.coverageBasis)")
                    if let fraction = heart.coverageFraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    } else {
                        Text("Coverage cannot be estimated from a single reading.")
                    }
                    Text("\(heart.samples.count) readings · \(heart.gapCount) gaps")
                }.font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("About heart-rate coverage") {
                    Text("Nearby readings estimate observed time. Averages weight intervals of at most 12 seconds, excluding known pauses. Longer gaps remain unknown.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.subheadline).frame(minHeight: 44)
            }
            if let configuration {
                Divider()
                Text("Heart-rate zones").font(.subheadline.weight(.semibold))
                Text("Based on \(Int(configuration.maximumHeartRate.rounded())) bpm \(configuration.isEstimated ? "estimated maximum" : "maximum you entered"). These estimates may differ from Apple Watch zones.")
                    .font(.caption).foregroundStyle(.secondary)
                if heart.observedSeconds > 0 {
                    Chart(heart.zones) { zone in
                        BarMark(x: .value("Observed seconds", zone.seconds), y: .value("Zone", "Zone \(zone.id)"))
                            .foregroundStyle(Palette.blue).cornerRadius(4)
                    }.chartXAxisLabel("Observed seconds").frame(height: 160)
                    ForEach(heart.zones) { zone in
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("Band \(zone.id): \(Int(zone.lowerBPM.rounded()))–\(Int(zone.upperBPM.rounded())) bpm")
                                Spacer()
                                Text(clockText(zone.seconds)).monospacedDigit()
                            }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Band \(zone.id): \(Int(zone.lowerBPM.rounded()))–\(Int(zone.upperBPM.rounded())) bpm")
                                Text(clockText(zone.seconds)).monospacedDigit()
                            }
                        }.font(.caption)
                    }
                    Text("Below 50%: \(clockText(heart.belowZoneSeconds)) · Above configured maximum: \(clockText(heart.aboveMaximumSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not enough nearby readings to estimate time in bands.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Set an optional maximum heart rate in Health setup to see heart-rate zones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("workout-heart-analysis")
    }
}

private struct WorkoutPaceCard: View {
    let pace: RepPaceAnalysis
    var body: some View {
        AnalyticsCard(title: "Camera rep pace", symbol: "metronome") {
            if let average = pace.averageSeconds {
                AnalyticsValueGrid {
                    AnalyticsValue(title: "Average rep", value: "\(average.formatted(.number.precision(.fractionLength(1)))) sec")
                    if let rate = pace.repRatePerMinute {
                        AnalyticsValue(title: "Rep rate", value: "\(rate.formatted(.number.precision(.fractionLength(1)))) / min")
                    }
                }
                Chart(Array(pace.durations.enumerated()), id: \.offset) { index, duration in
                    BarMark(x: .value("Recorded rep", index + 1), y: .value("Seconds", duration))
                        .foregroundStyle(Palette.blue).cornerRadius(3)
                }.chartYAxisLabel("sec / rep").frame(height: 130)
                if let fastest = pace.fastestSeconds, let slowest = pace.slowestSeconds {
                    Text("Recorded range \(fastest.formatted(.number.precision(.fractionLength(1))))–\(slowest.formatted(.number.precision(.fractionLength(1)))) sec")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let variation = pace.variabilityPercent {
                    Text("Rep-duration variation: \(variation.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(pace.timedReps) complete camera-timed reps")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Rep tempo was not recorded.").font(.subheadline).foregroundStyle(.secondary)
            }
            DisclosureGroup("About rep pace") {
                Text("Pace needs complete camera rep timings. Manual entries, video replays and incomplete timings are excluded. Pace does not measure form or strength.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).frame(minHeight: 44)
        }.accessibilityIdentifier("workout-pace-analysis")
    }
}

private struct WorkoutMotionCard: View {
    let motion: MotionAnalysis
    var body: some View {
        AnalyticsCard(title: "Wrist movement", symbol: "waveform.path") {
            Text("Apple Watch · Core Motion").font(.caption).foregroundStyle(.secondary)
            if let rms = motion.rmsAccelerationG, let peak = motion.peakAccelerationG {
                AnalyticsValueGrid {
                    AnalyticsValue(title: "RMS acceleration", value: rms.formatted(.number.precision(.fractionLength(2))) + " g")
                    AnalyticsValue(title: "Peak acceleration", value: peak.formatted(.number.precision(.fractionLength(2))) + " g")
                }
                AnalyticsSignalChart(samples: motion.accelerationSamples, unit: "g")
            } else if !motion.accelerationSamples.isEmpty {
                Text("Sampled wrist acceleration").font(.subheadline.weight(.medium))
                AnalyticsSignalChart(samples: motion.accelerationSamples, unit: "g")
                if let peak = motion.peakAccelerationG {
                    Text("Highest sampled reading: \(peak.formatted(.number.precision(.fractionLength(2)))) g")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Individual Watch readings are available; a motion-window summary wasn’t recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No Watch acceleration readings recorded.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let rotation = motion.meanRotationRadiansPerSecond, let peak = motion.peakRotationRadiansPerSecond {
                AnalyticsValueGrid {
                    AnalyticsValue(title: "Mean angular speed", value: rotation.formatted(.number.precision(.fractionLength(2))) + " rad/s")
                    AnalyticsValue(title: "Peak angular speed", value: peak.formatted(.number.precision(.fractionLength(2))) + " rad/s")
                }
                AnalyticsSignalChart(samples: motion.rotationSamples, unit: "rad/s")
            } else {
                Text("No Watch rotation readings recorded.").font(.subheadline).foregroundStyle(.secondary)
            }
            if motion.windowCount > 0 {
                Text("\(motion.windowCount) motion windows · \(motion.sampleCount) samples · \(clockText(motion.observedSeconds)) observed")
                    .font(.caption).foregroundStyle(.secondary)
                if let variation = motion.variationPercent {
                    Text("Window RMS variation: \(variation.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Missing periods stay unknown.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("About wrist movement") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Acceleration excludes gravity. RMS acceleration combines motion windows using their sample counts. Rotation is angular speed in radians per second.")
                    Text("Wrist motion does not measure your body’s speed or exercise technique. These are sampled Watch readings, not continuous raw motion.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).frame(minHeight: 44)
        }.accessibilityIdentifier("workout-motion-analysis")
    }
}

struct AnalyticsSignalChart: View {
    let samples: [ReportSample]
    let unit: String
    var color: Color = Palette.blue
    var body: some View {
        Chart(samples) { sample in
            LineMark(x: .value("Time", sample.date), y: .value(unit, sample.value), series: .value("Observed segment", sample.segment))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
            PointMark(x: .value("Time", sample.date), y: .value(unit, sample.value)).foregroundStyle(color).symbolSize(16)
        }.chartLegend(.hidden).chartYAxisLabel(unit).frame(height: 145)
            .accessibilityLabel("Recorded \(unit) readings. Gaps separate observed segments.")
    }
}

struct TrainingOverviewSection: View {
    @Bindable var store: TrainingStore
    let profile: LocalProfile?
    var healthStore: HealthDataStore? = nil

    var body: some View {
        let dashboard = TrainingDashboard(history: store.history)
        VStack(alignment: .leading, spacing: 24) {
            AnalyticsCard(title: "Training trends", symbol: "chart.bar") {
                if store.historyAvailable {
                    AnalyticsValueGrid {
                        AnalyticsValue(title: "Training days this week", value: "\(dashboard.trainingDays)")
                        AnalyticsValue(title: "Sets this week", value: "\(dashboard.totalSets)")
                        AnalyticsValue(title: "Reps this week", value: "\(dashboard.totalReps)")
                    }
                    Chart(dashboard.days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Sets", day.setCount))
                            .foregroundStyle(Palette.blue).cornerRadius(4)
                    }.chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                    }.chartYAxisLabel("sets").frame(height: 135)
                    Text("This calendar week · saved sessions, excluding video replays. Unlogged activity isn’t included.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Saved history is unavailable. Try again to see your totals.").font(.subheadline).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("insights-training-trends")
            if !dashboard.recentRecords.isEmpty, store.historyAvailable {
                recordedTrends(records: Array(dashboard.recentRecords.prefix(20).reversed()))
            }
            if let healthStore { HealthHistoryCard(store: healthStore) }
        }
    }

    private func recordedTrends(records: [SessionRecord]) -> some View {
        let observations = records.map { SessionTrendObservation(record: $0, analysis: WorkoutAnalytics(record: $0)) }
        return AnalyticsCard(title: "Recent session measurements", symbol: "chart.xyaxis.line") {
            if observations.contains(where: { $0.analysis.heart.average != nil }) {
                Text("Time-weighted Watch heart rate").font(.subheadline.weight(.semibold))
                Chart {
                    ForEach(observations) { observation in
                        if let average = observation.analysis.heart.average {
                            PointMark(x: .value("Session date", observation.record.date), y: .value("bpm", average))
                                .foregroundStyle(Palette.red).symbolSize(35)
                        }
                    }
                }.chartYAxisLabel("bpm").frame(height: 140)
            }
            if observations.contains(where: { $0.analysis.pace.repRatePerMinute != nil }) {
                Text("Camera-timed rep rate").font(.subheadline.weight(.semibold))
                Chart {
                    ForEach(observations) { observation in
                        if let pace = observation.analysis.pace.repRatePerMinute {
                            PointMark(x: .value("Session date", observation.record.date), y: .value("Reps/min", pace))
                                .foregroundStyle(Palette.blue).symbolSize(35)
                        }
                    }
                }.chartYAxisLabel("reps/min").frame(height: 140)
            }
            if !observations.contains(where: { $0.analysis.heart.average != nil || $0.analysis.pace.repRatePerMinute != nil }) {
                Text("No heart-rate trend or camera rep timings yet. Complete a session with those readings to see them here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Up to 20 recent sessions. Open a report for its source and coverage.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("About session comparisons") {
                Text("Each point is a separate saved session. Different exercises, input sources and observation coverage can affect comparisons.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).frame(minHeight: 44)
        }
    }
}

private struct HealthHistoryCard: View {
    let store: HealthDataStore
    var body: some View {
        AnalyticsCard(title: "Apple Health history", symbol: "heart.text.square") {
            Text("Historical readings, separate from your workout measurements")
                .font(.caption).foregroundStyle(.secondary)
            if let snapshot = store.snapshot {
                Text("Updated \(snapshot.asOf.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if !snapshot.latestObservations.isEmpty {
                    Text("Latest readings").font(.subheadline.weight(.semibold))
                    ForEach(snapshot.latestObservations) { observation in HealthHistoryRow(observation: observation) }
                }
                if !snapshot.dailyObservations.isEmpty {
                    Text("Daily totals for \(snapshot.dayStart.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.semibold)).padding(.top, 5)
                    ForEach(snapshot.dailyObservations) { observation in HealthHistoryRow(observation: observation) }
                }
                if snapshot.observations.isEmpty {
                    Text("No readings yet. Check Spottr’s Health permissions and refresh.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("Connect Apple Health to see saved readings here. It’s optional.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(store.statusMessage).font(.caption).foregroundStyle(.secondary)
            NavigationLink("Health history & zone setup") { HealthSetupView(store: store) }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("insights-health-setup")
            if store.hasRequestedAccess {
                Button { Task { await store.refresh() } } label: {
                    Label("Refresh Health snapshot", systemImage: "arrow.clockwise")
                }.font(.subheadline).frame(minHeight: 44).disabled(store.isBusy)
            }
        }.accessibilityIdentifier("insights-health-history")
    }
}

private struct HealthHistoryRow: View {
    let observation: HealthObservation
    private var title: String {
        if observation.metric == .steps { return "Steps" }
        if observation.metric == .walkingRunningDistance { return "Walking/running distance" }
        return observation.title
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer(minLength: 10)
                    readingValue
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium))
                    readingValue
                }
            }
            Text("\(observation.date.formatted(date: .abbreviated, time: .shortened)) · \(observation.source)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private var readingValue: some View {
        Text(observation.value.formatted(.number.precision(.fractionLength(0...1))) + " " + observation.unit)
            .font(.subheadline.weight(.semibold)).monospacedDigit()
    }
}

private struct SessionTrendObservation: Identifiable {
    let record: SessionRecord
    let analysis: WorkoutAnalytics
    var id: UUID { record.id }
}
