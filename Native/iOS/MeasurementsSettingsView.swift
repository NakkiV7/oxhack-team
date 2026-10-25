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

    func edit(heightCM: String, weightKG: String, bmiEligible: Bool, thresholds: LocalBodyMeasurements.Thresholds?) {
        saveTask?.cancel(); saveTask = nil; pending = nil; message = nil
        do {
            let separator = Locale.current.decimalSeparator ?? "."
            guard let height = Double(heightCM.replacingOccurrences(of: separator, with: ".")),
                  let weight = Double(weightKG.replacingOccurrences(of: separator, with: ".")) else {
                validationError = "Enter both height and weight to save. Your last saved measurements stay unchanged."
                return
            }
            pending = .save(try LocalBodyMeasurements(heightCM: height, weightKG: weight, bmiEligible: bmiEligible, thresholds: thresholds))
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
    @Environment(\.dismiss) private var dismiss
    @State private var heightCM: String
    @State private var weightKG: String
    @State private var eligible: Bool
    @State private var thresholds: LocalBodyMeasurements.Thresholds?
    @State private var persistence: MeasurementsDraftPersistence
    @FocusState private var field: Field?
    private enum Field { case height, weight }

    init(measurements: LocalBodyMeasurements?, isIntroduction: Bool = false,
         persist: @escaping (LocalBodyMeasurements?) throws -> Void) {
        self.isIntroduction = isIntroduction
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
                    Text("Optional, private measurements").font(.headline)
                    Text(isIntroduction
                         ? "Kept in this introduction until you tap Let’s train. They aren’t shared with Coach or cloud history, and don’t change challenges or XP."
                         : "Saved only on this iPhone. They aren’t shared with Coach or cloud history, and don’t change challenges or XP.")
                        .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle()).onTapGesture { field = nil }
                    HStack {
                        Label("Height", systemImage: "ruler")
                        TextField("cm", text: binding($heightCM)).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused($field, equals: .height).accessibilityLabel("Height in centimetres").accessibilityIdentifier("measurements-height")
                        Text("cm").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Weight", systemImage: "scalemass")
                        TextField("kg", text: binding($weightKG)).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            .focused($field, equals: .weight).accessibilityLabel("Weight in kilograms").accessibilityIdentifier("measurements-weight")
                        Text("kg").foregroundStyle(.secondary)
                    }
                    if let error = persistence.validationError {
                        Text(error).font(.caption).foregroundStyle(Palette.red).accessibilityIdentifier("measurements-validation")
                    } else if let message = persistence.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("measurements-save-status")
                    }
                }
                Section("Adult BMI (optional)") {
                    Toggle("I confirm adult BMI is suitable for me", isOn: binding($eligible))
                        .accessibilityIdentifier("measurements-eligible")
                    Text("Confirm only if you are 18 or older, aren’t pregnant, don’t have or suspect an eating disorder, and have no condition affecting your height. Otherwise leave this off.")
                        .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle()).onTapGesture { field = nil }
                    Picker("Category thresholds", selection: binding($thresholds)) {
                        Text("No category").tag(nil as LocalBodyMeasurements.Thresholds?)
                        Text("Standard").tag(Optional(LocalBodyMeasurements.Thresholds.standard))
                        Text("Lower").tag(Optional(LocalBodyMeasurements.Thresholds.lower))
                    }.accessibilityIdentifier("measurements-thresholds")
                    Text("Lower thresholds apply to South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean backgrounds. You can skip this choice; only the threshold choice is stored.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let measurements = candidate, let bmi = measurements.bmi {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(bmi, format: .number.precision(.fractionLength(1))).font(.largeTitle.bold()).monospacedDigit()
                                .accessibilityLabel("BMI").accessibilityIdentifier("measurements-bmi")
                                .accessibilityValue(bmi.formatted(.number.precision(.fractionLength(1))))
                            ProgressView(value: min(bmi, 50), total: 50).tint(Palette.blue).accessibilityHidden(true)
                            if let category = measurements.category { Text(categoryTitle(category)).font(.subheadline) }
                        }.padding(.vertical, 6)
                    } else {
                        Text("BMI unavailable until valid measurements and suitability are confirmed.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("BMI is a rough measure, not a diagnosis or fitness score. It doesn’t distinguish muscle from fat; interpretation needs extra care with high muscle mass or from age 65. Ask a healthcare professional if you’re concerned about your weight.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("NHS adult BMI guidance", destination: URL(string: "https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-adults")!)
                }
                Section {
                    Button("Clear measurements", role: .destructive) {
                        field = nil
                        if persistence.clear() { heightCM = ""; weightKG = ""; eligible = false; thresholds = nil }
                    }.accessibilityIdentifier("measurements-clear")
                    Text(isIntroduction
                         ? "Complete valid edits update this introduction’s draft. You can skip measurements; nothing is saved before Let’s train."
                         : "Complete valid edits save automatically. An incomplete draft keeps your last saved measurements. Clearing removes only measurements.")
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
        persistence.edit(heightCM: heightCM, weightKG: weightKG, bmiEligible: eligible, thresholds: thresholds)
    }
    private var candidate: LocalBodyMeasurements? {
        let separator = Locale.current.decimalSeparator ?? "."
        guard let height = Double(heightCM.replacingOccurrences(of: separator, with: ".")),
              let weight = Double(weightKG.replacingOccurrences(of: separator, with: ".")) else { return nil }
        return try? LocalBodyMeasurements(heightCM: height, weightKG: weight, bmiEligible: eligible, thresholds: thresholds)
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
