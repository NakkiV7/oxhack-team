import SwiftUI
import WatchConnectivity

struct HealthSetupView: View {
    let store: HealthDataStore
    @State private var maximum = ""
    @State private var age = ""
    @State private var zoneError: String?
    @FocusState private var editingNumber: Bool

    var body: some View {
        Form {
            healthAccess
            Section {
                NavigationLink { WatchSetupView() } label: {
                    Label("Install and connect your Watch", systemImage: "applewatch")
                }.accessibilityIdentifier("health-watch-guide")
            }
            zoneSettings
            if let snapshot = store.snapshot, !snapshot.observations.isEmpty {
                Section("Available readings") {
                    Text("Historical Health readings, separate from recorded workouts. Each reading keeps its date and source.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(snapshot.latestObservations) { observation in healthRow(observation) }
                }
                if !snapshot.dailyObservations.isEmpty {
                    Section("Activity today") {
                        Text("\(snapshot.dayStart.formatted(date: .abbreviated, time: .shortened)) – \(snapshot.asOf.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(snapshot.dailyObservations) { observation in healthRow(observation) }
                    }
                }
            }
        }
        .navigationTitle("Apple Health & zones").navigationBarTitleDisplayMode(.inline)
        .tint(Palette.blue).scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingNumber = false }
            }
        }
        .task { await store.refresh() }
        .onAppear {
            if let configuration = store.zones { maximum = configuration.maximumHeartRate.formatted(.number.precision(.fractionLength(0...1))) }
        }
    }

    private var healthAccess: some View {
        Section("Apple Health is optional") {
            Text("Show optional heart, recovery and activity readings from Apple Health")
                .font(.subheadline)
            Text("Historical readings stay separate from your recorded workouts")
                .font(.caption).foregroundStyle(.secondary)
            if !store.hasRequestedAccess {
                Text("Not requested. No Apple Health readings are loaded.")
                    .font(.caption).accessibilityIdentifier("health-not-requested")
            }
            Text(store.statusMessage).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("health-status")
            Button("Choose Health data") { Task { await store.connect() } }
                .disabled(store.isBusy).accessibilityIdentifier("health-connect")
            if store.hasRequestedAccess {
                Button("Refresh readings") { Task { await store.refresh() } }
                    .disabled(store.isBusy).accessibilityIdentifier("health-refresh")
                Button("Stop showing Apple Health") { store.disconnect() }
                    .accessibilityIdentifier("health-disconnect")
            }
            DisclosureGroup("Readings & privacy") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose resting/walking heart rate, SDNN heart rate variability, cardio fitness, one-minute recovery, oxygen, respiration, steps and walking/running distance when available.")
                    Text("Readings stay in memory on this iPhone. They are not uploaded or added to training history.")
                    Text("Review sharing permissions in the Health app. Spottr cannot tell which read permissions you granted; missing data can have several causes.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.accessibilityIdentifier("health-data-details")
            if store.isBusy { ProgressView("Reading Apple Health…") }
        }
    }

    private var zoneSettings: some View {
        Section("Heart rate zones (optional)") {
            if let configuration = store.zones {
                LabeledContent(configuration.isEstimated ? "Estimated maximum" : "Your entered maximum",
                               value: "\(configuration.maximumHeartRate.formatted(.number.precision(.fractionLength(0...1)))) bpm")
                    .accessibilityIdentifier("health-zone-basis")
            } else {
                Text("No maximum configured. Heart rate zones are not shown.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Maximum heart rate (bpm)", text: $maximum).keyboardType(.decimalPad).focused($editingNumber)
                .accessibilityIdentifier("health-maximum-heart-rate")
            Button("Save entered maximum") { saveMaximum() }.accessibilityIdentifier("health-save-maximum")
            TextField("Your age (optional, 18–100)", text: $age).keyboardType(.numberPad).focused($editingNumber)
                .accessibilityIdentifier("health-age-estimate")
            Button("Use an age-based estimate") { estimateMaximum() }.accessibilityIdentifier("health-estimate-maximum")
            if store.zones != nil { Button("Remove zone configuration") { store.clearZones(); maximum = ""; age = ""; zoneError = nil } }
            if let zoneError { Text(zoneError).font(.caption).foregroundStyle(Palette.red).accessibilityIdentifier("health-zone-error") }
            Text("An age estimate is imprecise. It is not a measured maximum or a workout target.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("How zones are calculated") {
                Text("Five descriptive bands use 50–60–70–80–90–100% of your maximum. The optional estimate uses 220 minus age. These are Spottr’s bands, separate from Apple’s zones. Your chosen basis stays on this iPhone.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.accessibilityIdentifier("health-zone-details")
        }
    }

    private func healthRow(_ observation: HealthObservation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent(observation.title, value: "\(observation.value.formatted(.number.precision(.fractionLength(0...1)))) \(observation.unit)")
            Text("\(observation.date.formatted(date: .abbreviated, time: .shortened)) · \(observation.source)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func saveMaximum() {
        guard let value = Double(maximum.replacingOccurrences(of: ",", with: ".")) else {
            zoneError = "Enter a maximum between 60 and 260 bpm, or leave zones unconfigured."
            return
        }
        do { try store.setMaximumHeartRate(value); zoneError = nil; editingNumber = false }
        catch { zoneError = "Enter a finite maximum between 60 and 260 bpm, or leave zones unconfigured." }
    }

    private func estimateMaximum() {
        guard let value = Int(age) else { zoneError = "Enter your age from 18 to 100 to choose an optional estimate."; return }
        do {
            try store.estimateZones(age: value)
            maximum = store.zones?.maximumHeartRate.formatted(.number.precision(.fractionLength(0...1))) ?? ""
            zoneError = nil
            editingNumber = false
        } catch { zoneError = "Enter your age from 18 to 100, or leave zones unconfigured." }
    }
}

struct WatchSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = WatchSetupStore()
    @State private var showInstallation = false
    private var checksActive: Bool { scenePhase == .active && store.selectedModel != .noWatch }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeading(title: "Connect your Watch", subtitle: "Optional. Your iPhone works on its own.")
                modelChoice
                if store.selectedModel == .noWatch {
                    SpottrCard {
                        Text(store.selectedModel.sensorExplanation).accessibilityIdentifier("watch-phone-only")
                        PrimaryButton(title: "Continue on iPhone", symbol: "iphone") { dismiss() }
                    }
                } else {
                    connection
                    if store.presentation.needsInstallation { installation }
                    workoutAccess
                    if !store.presentation.needsInstallation { installation }
                }
            }.padding(24)
        }
        .navigationTitle("Watch setup").navigationBarTitleDisplayMode(.inline).tint(Palette.blue)
        .task(id: checksActive) {
            guard checksActive else { return }
            store.checkConnection()
            while !Task.isCancelled {
                store.refreshConnection()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    private var modelChoice: some View {
        SpottrCard {
            Text("Which Watch do you have?").font(.title3.bold())
            Text("Choose a model, or leave it as Not sure").font(.subheadline).foregroundStyle(.secondary)
            ForEach(WatchModelPreference.allCases, id: \.self) { model in
                Button {
                    store.select(model)
                } label: {
                    HStack(spacing: 12) {
                        Text(model.title).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: store.selectedModel == model ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.selectedModel == model ? Palette.blue : Palette.muted)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(SpottrPressStyle())
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(store.selectedModel == model ? [.isSelected] : [])
                .accessibilityIdentifier("watch-model-\(model.rawValue)")
            }
            if store.selectedModel != .noWatch {
                Text(store.selectedModel.sensorExplanation).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("watch-model-guidance")
            }
        }
    }

    private var connection: some View {
        SpottrCard {
            Text("Connection").font(.title3.bold())
            Text(store.presentation.summary).font(.subheadline).accessibilityIdentifier("watch-setup-status")
            ForEach(store.presentation.milestones) { milestone in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: milestone.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(milestone.isComplete ? Palette.green : Palette.muted)
                        .font(.title3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(milestone.title).font(.subheadline.weight(.semibold))
                        Text(milestone.detail).font(.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(milestone.title), \(milestone.isComplete ? "complete" : "waiting"). \(milestone.detail)")
                .accessibilityIdentifier("watch-step-\(milestone.id)")
            }
            PrimaryButton(title: "Check connection", symbol: "arrow.clockwise") { store.checkConnection() }
                .accessibilityIdentifier("watch-check-connection")
            if let date = store.presentation.lastCheckedAt {
                Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(store.presentation.queueText ?? "Check the companion to see pending Watch data")
                .font(.subheadline).accessibilityIdentifier("watch-queue-status")
            if let date = store.presentation.lastDataReceivedAt {
                Text("Last Watch data received \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("watch-last-data")
            } else {
                Text("Last Watch data received: not available").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("watch-last-data")
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.presentation.milestones)
    }

    private var workoutAccess: some View {
        SpottrCard {
            Text("Record a workout").font(.title3.bold())
            Text("Start a workout on iPhone, then choose Record on Watch. Review workout access on your Watch when asked.")
                .font(.subheadline)
            Text("Heart rate, active energy and movement appear when available. A connection check does not grant Health access.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(store.presentation.motionText).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("watch-motion-availability")
        }
    }

    private var installation: some View {
        SpottrCard {
            DisclosureGroup("Install Spottr on your Watch", isExpanded: $showInstallation) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. Install the current Spottr beta on the iPhone paired with your Watch.")
                    Text("2. Open the iPhone Watch app → My Watch → Available Apps. Tap Install next to Spottr if it appears.")
                    Text("3. In TestFlight, you can also open Spottr → App Details. Use Install or Update if a compatible Watch app is offered.")
                    Text("4. Open Spottr on both devices and keep them nearby. Return here and check the connection.")
                    Link("Open Spottr in TestFlight", destination: URL(string: "https://testflight.apple.com/join/f3MhePbf")!)
                        .frame(minHeight: 44, alignment: .leading)
                    Text("If no Watch app is offered, continue on iPhone and check for a compatible beta later.")
                        .foregroundStyle(.secondary)
                    Link("Apple’s Watch installation guide", destination: URL(string: "https://support.apple.com/guide/watch/get-apps-apd99e3c6a68/watchos")!)
                        .frame(minHeight: 44, alignment: .leading)
                }.font(.subheadline).padding(.top, 12)
            }.accessibilityIdentifier("watch-installation-guide")
        }
    }
}
