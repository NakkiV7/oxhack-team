import SwiftUI
import Charts

struct ProgrammeInsightsSection: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var exerciseID = ""
    @State private var weightEntry = false
    private var exerciseIDs: [String] { Set(store.history.flatMap(\.loggedSets).filter { $0.source != .video }.map(\.exerciseID)).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let week = store.programme?.current {
                let days = ProgrammeInsights.progress(week: week, history: store.history)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Planned and recorded").font(.headline)
                    ForEach(week.days) { day in
                        let actual = days.first { $0.id == day.id }
                        HStack(alignment: .top) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day())).font(.subheadline)
                            Spacer()
                            Text(day.plan == nil ? (day.kind == .familyMovement ? "Family play" : "Rest") : "\(actual?.recordedSets ?? 0) / \(actual?.plannedSets ?? 0) sets recorded")
                                .font(.subheadline).multilineTextAlignment(.trailing)
                        }
                    }
                    Text("Only work saved against that scheduled day is included. A recorded set does not mean its target was achieved.")
                        .font(.caption).foregroundStyle(.secondary)
                }.programmeCard()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("How your sets felt").font(.headline)
                if exerciseIDs.isEmpty {
                    Text("No effort history yet. Rate a set after saving it, or leave it unrated.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let selected = exerciseIDs.contains(exerciseID) ? exerciseID : exerciseIDs[0]
                    Picker("Movement", selection: Binding(get: { selected }, set: { exerciseID = $0 })) {
                        ForEach(exerciseIDs, id: \.self) { id in Text(ExerciseCatalog.find(id)?.name ?? id).tag(id) }
                    }
                    let points = Array(ProgrammeInsights.effort(history: store.history, exerciseID: selected).suffix(30))
                    if points.contains(where: { $0.effort != nil }) {
                        Chart(points) { point in
                            if let effort = point.effort {
                                PointMark(x: .value("Recorded date", point.date), y: .value("Perceived effort", effort.rawValue))
                                    .foregroundStyle(Palette.blue)
                            }
                        }.chartYScale(domain: 0...10).chartYAxis { AxisMarks(values: [2, 4, 6, 8, 10]) }.frame(height: 150)
                    }
                    Text("\(points.filter { $0.effort == nil }.count) unrated of \(points.count) recent sets. Unrated is not zero.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(points.suffix(5).reversed()) { point in
                        HStack { Text(point.date.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(point.effort.map { "\($0.rawValue), \($0.title)" } ?? "Unrated") }.font(.caption)
                    }
                    Text("Self-reported effort is personal, not a clinical assessment or camera measurement. Higher effort earns no extra credit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.programmeCard().accessibilityIdentifier("insights-effort")
            if profile?.programmePreferences?.ageContext?.ageYears ?? 0 >= 18, let programme = store.programme {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your recorded weight").font(.headline)
                    if programme.weights.isEmpty {
                        Text("No dated entries yet. Add a measurement and the day you took it.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Chart(programme.weights) { entry in
                            PointMark(x: .value("Measured date", entry.date), y: .value("Weight, kg", entry.kilograms)).foregroundStyle(Palette.blue)
                        }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 150)
                        ForEach(programme.weights.suffix(5).reversed()) { entry in
                            HStack { Text(entry.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text("\(entry.kilograms, format: .number.precision(.fractionLength(1))) kg") }.font(.subheadline)
                        }
                    }
                    Button("Add a dated weight") { weightEntry = true }.buttonStyle(.bordered).accessibilityIdentifier("insights-add-weight")
                    Text("Entered measurements only. Reps, calories and profile setup do not create a weight history.").font(.caption).foregroundStyle(.secondary)
                }.programmeCard()
                .sheet(isPresented: $weightEntry) { DatedWeightEntryView(programme: programme) }
            }
        }
    }
}

private struct DatedWeightEntryView: View {
    let programme: ProgrammeStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var pounds = false
    @State private var measured = Date.now
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Measured on", selection: $measured, in: ...Date.now, displayedComponents: .date)
                Picker("Unit", selection: $pounds) { Text("kg").tag(false); Text("lb").tag(true) }.pickerStyle(.segmented)
                TextField("Measured weight", text: $quantity).keyboardType(.decimalPad).accessibilityIdentifier("dated-weight-quantity")
                Text("Enter a measurement you actually took. Stored locally for this training profile.").font(.caption)
                if let error { Text(error).foregroundStyle(Palette.red) }
                Button("Save measurement") {
                    let formatter = NumberFormatter(); formatter.numberStyle = .decimal
                    guard let number = formatter.number(from: quantity)?.doubleValue else { error = "Enter a measured weight."; return }
                    do { try programme.recordWeight(kilograms: pounds ? number / 2.2046226218 : number, date: measured); SpottrHaptics.success(); dismiss() }
                    catch { self.error = "Use a valid weight and a date no later than today." }
                }.accessibilityIdentifier("dated-weight-save")
            }.navigationTitle("Dated weight").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private extension View {
    func programmeCard() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22)) }
}
