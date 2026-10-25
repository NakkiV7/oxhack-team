import SwiftUI

struct CatalogueWorkoutSetupView: View {
    let store: TrainingStore
    let entry: ExerciseEntry
    @State private var sets = "3"
    @State private var target: String
    @State private var restSeconds = "60"
    @State private var supportConfirmed = false
    @State private var error: String?
    @FocusState private var enteringQuantity: Bool

    init(store: TrainingStore, entry: ExerciseEntry) {
        self.store = store; self.entry = entry
        _target = State(initialValue: String(entry.goal))
    }

    var body: some View {
        Form {
            Section(entry.name) {
                Text(entry.instruction).font(.subheadline)
                Text("Set your targets, then enter only the work you actually complete.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your workout") {
                quantity("Sets", value: $sets, identifier: "catalogue-sets")
                quantity(entry.unit == .reps ? "Target reps per set" : "Target seconds per set",
                         value: $target, identifier: "catalogue-target")
                quantity("Rest between sets (sec)", value: $restSeconds, identifier: "catalogue-rest")
                Text("1–10 sets · 1–\(entry.unit == .reps ? 200 : 600) \(entry.unit == .reps ? "reps" : "seconds") per set · 0–600 seconds of suggested rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let support = entry.support {
                Section("Household support") {
                    Toggle("I have: \(support)", isOn: $supportConfirmed)
                        .accessibilityIdentifier("catalogue-support-confirmation")
                }
            }
            Section {
                Text("Start and end each set when you’re ready. Log the reps you complete; hold time runs only while your set is active.")
                    .font(.caption).foregroundStyle(.secondary)
                if entry.tracking != nil {
                    Text("You can choose iPhone camera or Pi side camera before starting a set.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
        }
        .scrollContentBackground(.hidden).background(.white).tint(Palette.blue)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Set up workout").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Start workout", symbol: "play") {
                enteringQuantity = false
                start()
            }
            .disabled(entry.support != nil && !supportConfirmed)
            .accessibilityIdentifier("catalogue-workout-start")
            .padding(.horizontal, 24).padding(.vertical, 12).background(.white)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { enteringQuantity = false }
                    .accessibilityIdentifier("catalogue-quantity-done")
            }
        }
    }

    private func quantity(_ title: String, value: Binding<String>, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: value).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .focused($enteringQuantity).frame(width: 70).accessibilityIdentifier(identifier)
        }
    }

    private func start() {
        guard let sets = Int(sets), let target = Int(target), let rest = Int(restSeconds) else {
            error = "Enter whole numbers for sets, target and rest."; return
        }
        let support = Set(supportConfirmed ? entry.support.map { [$0] } ?? [] : [])
        do {
            let plan = try CoachSavedPlan.catalogue(exerciseID: entry.id, sets: sets, target: target,
                                                    restSeconds: rest, availableSupport: support)
            store.startPlan(plan, availableSupport: support)
            error = store.error
        } catch {
            self.error = "Check the quantities and confirm the support shown above. Your workout hasn’t started."
        }
    }
}
