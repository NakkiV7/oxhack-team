import SwiftUI

struct AnalyticsConsentChoices: View {
    let store: ConsentedAnalyticsStore
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.ledger.age?.allowsTimePressureRewards == true {
                Toggle("Share feature usage", isOn: choice(.usage)).accessibilityIdentifier("analytics-usage")
                Text("Optional coarse counts help us understand which features are used.").font(.subheadline).foregroundStyle(.secondary)
                Toggle("Share weekly workout statistics", isOn: choice(.workout)).accessibilityIdentifier("analytics-workout")
                Text("Optional weekly totals include sets, rounded reps and minutes, movement families, recording sources and broad effort groups.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Feature usage and workout statistics are not collected for this profile.")
            }
            if let message = error ?? store.message { Text(message).foregroundStyle(.secondary) }
        }
    }
    private func choice(_ kind: AnalyticsKind) -> Binding<Bool> {
        Binding(get: { kind == .usage ? store.ledger.usage : store.ledger.workout }, set: { value in
            do { try store.setConsent(kind, enabled: value); self.error = nil }
            catch { self.error = store.message ?? "The setting could not be saved. Your previous choice is unchanged." }
        })
    }
}

struct AnalyticsSettingsView: View {
    let store: ConsentedAnalyticsStore
    var body: some View {
        Form {
            Section("Your choices") { AnalyticsConsentChoices(store: store) }
            Section("How this works") {
                Text("Both choices start off and work independently. Turning one off clears its unsent data. A later opt-in does not upload earlier workouts.")
                Text("No account identifier, age, body measurements, raw Health data, precise workout time, video or audio is sent. A temporary weekly installation tag helps count contributions and is not a guarantee of anonymity.")
                Text("Every published bucket needs at least ten contributing installations. Already combined summaries cannot be traced back to your account for removal.")
                WebsiteLink(title: "Privacy policy", url: URL(string: AccountClient.origin + "/privacy/")!)
            }
        }.navigationTitle("Privacy and statistics")
    }
}
