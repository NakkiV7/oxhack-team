import SwiftUI

@MainActor @Observable
final class MeasurementsDraftPersistence {
    private enum Pending { case save(LocalBodyMeasurements), clear }
    private let persist: (LocalBodyMeasurements?) throws -> Void
    private let savedMessage: String
    private var pending: Pending?
    private var saveTask: Task<Void, Never>?
    private(set) var validationError: String?
    private(set) var message: String?
    var blocksDismissal: Bool { pending != nil }

    init(savedMessage: String = "Measurements saved.", persist: @escaping (LocalBodyMeasurements?) throws -> Void) {
        self.savedMessage = savedMessage; self.persist = persist
    }

    func edit(heightCM: String, weightKG: String, bmiEligible: Bool, thresholds: LocalBodyMeasurements.Thresholds?, units: MeasurementUnits = .metric) {
        saveTask?.cancel(); saveTask = nil; pending = nil; message = nil
        do {
            pending = .save(try units.measurements(height: heightCM, weight: weightKG, bmiEligible: bmiEligible, thresholds: thresholds))
            validationError = nil; message = "Saving…"
            saveTask = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                saveTask = nil
                _ = persistPending()
            }
        } catch { validationError = error.localizedDescription }
    }

    func prepareToLeave() -> Bool {
        saveTask?.cancel(); saveTask = nil
        return persistPending()
    }

    func clear() -> Bool {
        saveTask?.cancel(); saveTask = nil; pending = .clear
        return persistPending()
    }

    private func persistPending() -> Bool {
        guard let pending else { return true }
        do {
            switch pending {
            case .save(let measurements): try persist(measurements)
            case .clear: try persist(nil)
            }
            self.pending = nil; validationError = nil; message = savedMessage
            return true
        } catch {
            message = nil; validationError = "Changes haven’t been saved. \(error.localizedDescription)"
            return false
        }
    }
}

struct MeasurementsSettingsView: View {
    private let isIntroduction: Bool
    private let profileStore: NativeProfileStore?
    @Environment(\.dismiss) private var dismiss
    @State private var units = MeasurementUnits.metric
    @State private var heightCM: String
    @State private var weightKG: String
    @State private var eligible: Bool
    @State private var thresholds: LocalBodyMeasurements.Thresholds?
    @State private var persistence: MeasurementsDraftPersistence
    @FocusState private var field: Field?
    private enum Field { case height, weight }

    init(measurements: LocalBodyMeasurements?, isIntroduction: Bool = false, profileStore: NativeProfileStore? = nil,
         persist: @escaping (LocalBodyMeasurements?) throws -> Void) {
        self.isIntroduction = isIntroduction
        self.profileStore = profileStore
        _heightCM = State(initialValue: measurements?.heightCM.formatted(.number.precision(.fractionLength(0...2))) ?? "")
        _weightKG = State(initialValue: measurements?.weightKG.formatted(.number.precision(.fractionLength(0...2))) ?? "")
        _eligible = State(initialValue: measurements?.bmiEligible ?? false)
        _thresholds = State(initialValue: measurements?.thresholds)
        _persistence = State(initialValue: MeasurementsDraftPersistence(
            savedMessage: isIntroduction ? "Measurements ready for this introduction." : "Measurements saved.", persist: persist))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(isAdult ? "Your height and weight" : "Optional growth measurements").font(.headline)
                    Text(isIntroduction
                         ? "Review these values before saving your training setup. Measurements stay in this profile and do not award XP."
                         : "Saved only on this iPhone. They aren’t shared with Coach or cloud history, and don’t change challenges or XP.")
                        .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle()).onTapGesture { field = nil }
                    Picker("Units", selection: $units) {
                        Text("Centimetres and kilograms").tag(MeasurementUnits.metric)
                        Text("Inches and pounds").tag(MeasurementUnits.imperial)
                    }.onChange(of: units) { old, new in convert(from: old, to: new) }
                    HStack {
                        Label("Height", systemImage: "ruler")
                        TextField(units == .metric ? "cm" : "in", text: binding($heightCM)).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused($field, equals: .height).accessibilityLabel(units == .metric ? "Height in centimetres" : "Height in inches").accessibilityIdentifier("measurements-height")
                        Text(units == .metric ? "cm" : "in").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Weight", systemImage: "scalemass")
                        TextField(units == .metric ? "kg" : "lb", text: binding($weightKG)).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused($field, equals: .weight).accessibilityLabel(units == .metric ? "Weight in kilograms" : "Weight in pounds").accessibilityIdentifier("measurements-weight")
                        Text(units == .metric ? "kg" : "lb").foregroundStyle(.secondary)
                    }
                    if let error = persistence.validationError {
                        Text(error).font(.caption).foregroundStyle(Palette.red).accessibilityIdentifier("measurements-validation")
                    } else if let message = persistence.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("measurements-save-status")
                    }
                }
                if isAdult {
                Section("Adult BMI (optional)") {
                    Toggle("I confirm adult BMI is suitable for me", isOn: binding($eligible))
                        .accessibilityIdentifier("measurements-eligible")
                    Text("Confirm only if you are 18 or older, aren’t pregnant, don’t have or suspect an eating disorder, and have no condition affecting your height. Otherwise leave this off.")
                        .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle()).onTapGesture { field = nil }
                    Picker("Category thresholds", selection: binding($thresholds)) {
                        Text("Not sure yet").tag(nil as LocalBodyMeasurements.Thresholds?)
                        Text("Standard").tag(Optional(LocalBodyMeasurements.Thresholds.standard))
                        Text("Adjusted").tag(Optional(LocalBodyMeasurements.Thresholds.lower))
                    }.accessibilityIdentifier("measurements-thresholds")
                    Text("Some ethnic backgrounds use adjusted thresholds. Read About BMI to choose, or leave this unanswered.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let assessment = try? profileStore?.assessment(for: candidate), let bmi = assessment.value {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(bmi, format: .number.precision(.fractionLength(1))).font(.largeTitle.bold()).monospacedDigit()
                                .accessibilityLabel("BMI").accessibilityIdentifier("measurements-bmi")
                                .accessibilityValue(bmi.formatted(.number.precision(.fractionLength(1))))
                            if let reference = assessment.adultReference { BMIBandRail(reference: reference) }
                        }.padding(.vertical, 6)
                    } else {
                        Text("BMI is not applicable until you confirm it is suitable. Your measurements can still be saved.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("About BMI") {
                        Text("BMI is a rough measure, not a diagnosis or fitness score. It does not distinguish muscle from fat. Interpretation needs extra care with high muscle mass or from age 65.").font(.caption).foregroundStyle(.secondary)
                        Text("NHS guidance uses lower thresholds for South Asian, Chinese, other Asian, Middle Eastern, Black African and African-Caribbean backgrounds. Only your threshold choice is stored.").font(.caption).foregroundStyle(.secondary)
                    }
                    WebsiteLink(title: "NHS adult BMI guidance", url: URL(string: "https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-adults")!)
                }
                } else {
                    Section("Growth information") {
                        if let assessment = try? profileStore?.assessment(for: candidate), let value = assessment.value {
                            Text("BMI \(value.formatted(.number.precision(.fractionLength(1))))")
                        }
                        Text("Children need age-appropriate growth interpretation. Measurements are optional and stay in this local profile.")
                        if (profileStore?.profile?.programmePreferences?.ageContext?.ageYears ?? 0) >= 2 {
                            WebsiteLink(title: "NHS child growth calculator for parents", url: URL(string: "https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-children-teenagers/")!)
                        } else { Text("BMI is not calculated for children under two.") }
                    }
                }
                Section {
                    if !isIntroduction { Button("Clear measurements", role: .destructive) {
                        field = nil
                        if persistence.clear() { heightCM = ""; weightKG = ""; eligible = false; thresholds = nil }
                    }.buttonStyle(.bordered).accessibilityIdentifier("measurements-clear") }
                    Text(isIntroduction
                         ? "Your measurements are saved when you complete training setup."
                         : "Valid measurements save automatically. Your previous measurements stay saved until both new values are complete. Clearing removes only measurements.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).scrollDismissesKeyboard(.immediately).background(.white).tint(Palette.blue)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if field != nil { KeyboardDismissBar(identifier: "measurements-keyboard-done") { field = nil } }
                }
                .navigationTitle("Measurements").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") {
                    field = nil
                    if persistence.prepareToLeave() { dismiss() }
                } } }
                .onDisappear { _ = persistence.prepareToLeave() }
        }.preferredColorScheme(.light).interactiveDismissDisabled(persistence.blocksDismissal)
    }

    private func binding<Value>(_ value: Binding<Value>) -> Binding<Value> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; queueSave() })
    }
    private func queueSave() {
        persistence.edit(heightCM: heightCM, weightKG: weightKG, bmiEligible: eligible, thresholds: thresholds, units: units)
    }
    private var isAdult: Bool { (profileStore?.profile?.programmePreferences?.ageContext?.ageYears ?? -1) >= 18 }
    private var candidate: LocalBodyMeasurements? {
        try? units.measurements(height: heightCM, weight: weightKG, bmiEligible: eligible, thresholds: thresholds)
    }
    private func convert(from old: MeasurementUnits, to new: MeasurementUnits) {
        guard let value = try? old.measurements(height: heightCM, weight: weightKG, bmiEligible: eligible, thresholds: thresholds) else {
            heightCM = ""; weightKG = ""; return
        }
        heightCM = (value.heightCM / (new == .metric ? 1 : 2.54)).formatted(.number.precision(.fractionLength(0...4)))
        weightKG = (value.weightKG / (new == .metric ? 1 : 0.45359237)).formatted(.number.precision(.fractionLength(0...4)))
    }
    private func categoryTitle(_ category: LocalBodyMeasurements.Category) -> String {
        switch category {
        case .underweight: return "Underweight range"
        case .healthyWeight: return "Healthy weight range"
        case .overweight: return "Overweight range"
        case .obesity: return "Obesity range"
        }
    }
}

struct BMIBandRail: View {
    let reference: BMIReference
    private let colours: [Color] = [Palette.blue, Palette.green, Palette.amber, .orange, Palette.red, .purple]
    private let names = ["Underweight", "Healthy reference", "Overweight", "Obesity class 1", "Obesity class 2", "Obesity class 3"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let edges = [15.0] + reference.boundaries + [45.0]
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(0..<6) { index in
                            Rectangle().fill(colours[index]).frame(width: max(0, width * (edges[index + 1] - edges[index]) / 30 - 1), height: 12)
                        }
                    }.clipShape(Capsule())
                    Circle().fill(.white).frame(width: 22, height: 22).overlay(Circle().stroke(Palette.ink, lineWidth: 3))
                        .offset(x: max(0, min(max(0, width - 22), width * reference.visualMarkerPosition - 11)))
                }.frame(height: 24)
            }.frame(height: 24).accessibilityHidden(true)
            if let edge = reference.edge { Label(edge == .below ? "Below the displayed scale" : "Above the displayed scale", systemImage: edge == .below ? "arrow.left" : "arrow.right").font(.caption) }
            ForEach(0..<6) { index in
                HStack(alignment: .top) {
                    Circle().fill(colours[index]).frame(width: 10, height: 10).padding(.top, 4).accessibilityHidden(true)
                    Text(names[index]).font(.caption)
                    Spacer()
                    Text(range(index)).font(.caption).monospacedDigit()
                }
            }
            Text("Healthy reference weights at this height are \(reference.referenceWeightKG.lowerBound.formatted(.number.precision(.fractionLength(1)))) to \(reference.referenceWeightKG.upperBound.formatted(.number.precision(.fractionLength(1)))) kg. This is context, not a prescribed target.").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("adult-bmi-band-rail")
    }
    private func range(_ index: Int) -> String {
        if index == 0 { return "Below \(reference.boundaries[0].formatted())" }
        if index == 5 { return "\(reference.boundaries[4].formatted()) and above" }
        return "\(reference.boundaries[index - 1].formatted()) to below \(reference.boundaries[index].formatted())"
    }
}
