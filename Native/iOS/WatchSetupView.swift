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
            Text("Choose existing resting/walking heart rate, SDNN heart rate variability, cardio fitness, one-minute recovery, oxygen, respiration, steps and walking/running distance when available.")
                .font(.subheadline)
            Text("Readings stay in memory on this iPhone. They are not uploaded, saved in your training history or treated as live workout measurements.")
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
                Text("Review Spottr’s sharing permissions in the Health app. Completing a permission request does not tell Spottr which read permissions you granted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            Text("Five descriptive bands use 50–60–70–80–90–100% of your maximum. The optional 220-minus-age estimate is imprecise and is not a measured maximum or a workout target. These are Spottr’s bands, separate from Apple’s zone settings. Your chosen basis stays on this iPhone.")
                .font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        Form {
            Section("Optional companion") {
                Label("Your phone works without a Watch", systemImage: "applewatch")
                Text("A compatible Apple Watch can supply real workout readings. Missing sensors or permissions never become invented values.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Install the current TestFlight beta") {
                Text("1. Install the available Spottr beta on the iPhone paired with your Watch.")
                Text("2. In TestFlight, open Spottr’s page, then App Details in the Information section. If a compatible Watch app is offered, use its Install or Update button.")
                Text("3. You can also open the iPhone Watch app → My Watch → Available Apps, then tap Install next to Spottr if it appears.")
                Text("4. Open Spottr on both devices. Review the Health permissions shown on the Watch when you choose to record a workout.")
                Link("Open Spottr in TestFlight", destination: URL(string: "https://testflight.apple.com/join/f3MhePbf")!)
                Text("Apple controls compatible builds and available testing places. If no Watch app is offered, continue on your iPhone and check the current beta in TestFlight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Connection status") {
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(connectionText).accessibilityIdentifier("watch-setup-status")
                }
                Text("This is pairing, installation and reachability information, not confirmation of Health permissions, a started recording or sensor accuracy. Keep the apps open and the devices nearby for live controls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("After public release") {
                Text("Once Spottr is publicly available, its compatible Watch app can also be installed through Apple’s Watch App Store or the iPhone Watch app. This beta does not confirm public App Store availability.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link("Apple’s Watch installation guide", destination: URL(string: "https://support.apple.com/guide/watch/get-apps-apd99e3c6a68/watchos")!)
            }
        }
        .navigationTitle("Watch setup").navigationBarTitleDisplayMode(.inline).tint(Palette.blue)
    }

    private var connectionText: String {
        guard WCSession.isSupported() else { return "Watch connectivity is not available on this device." }
        let session = WCSession.default
        let status = WatchSetupStatus.evaluate(supported: true, activated: session.activationState == .activated,
                                              paired: session.isPaired, installed: session.isWatchAppInstalled,
                                              reachable: session.isReachable)
        switch status {
        case .unsupported: return "Watch connectivity is not available on this device."
        case .notReady: return "Connection status is not ready. Open Spottr on your iPhone and Watch, then return."
        case .notPaired: return "No paired Apple Watch is reported by this iPhone."
        case .notInstalled: return "A Watch is paired, but Spottr is not reported as installed on it."
        case .installedOffline: return "Spottr is installed on your paired Watch. It is not reachable for live controls right now."
        case .reachable: return "Spottr on your paired Watch is reachable right now."
        }
    }
}
