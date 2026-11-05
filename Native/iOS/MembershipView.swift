import SwiftUI
import StoreKit

struct MembershipView: View {
    let store: MembershipStore
    @State private var redeemPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("membership-gem").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                    Text("A little support for every session").font(.title2.weight(.semibold))
                }
                Text("All features available during beta")
                    .font(.headline)
                    .accessibilityIdentifier("membershipBetaAccess")
                Text("You can use every Spottr feature during this beta. Membership purchases are optional. Your history, exports, manual tracking and help remain available without a membership.")
                    .foregroundStyle(.secondary)
                Text("Only plans available from the App Store can be purchased. Apple confirms pricing, trial eligibility and membership.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("membershipAppleConfirmation")
            }

            Section("Your membership") {
                Label(accessTitle, systemImage: store.hasAccess ? "checkmark.seal" : "person.crop.circle")
                    .accessibilityIdentifier("membershipAccessStatus")
                if !store.access.lifetime, let deadline = store.access.expiresAt {
                    Text("Current access through \(deadline.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.access.hasOverlappingSubscription {
                    Text("You own lifetime membership and have an active monthly subscription. Lifetime does not cancel monthly billing. Review your subscription with Apple.")
                        .accessibilityIdentifier("membershipOverlapNotice")
                }
            }

            ForEach(store.offers) { offer in
                Section(offer.displayName) {
                    Text(offer.plan == .monthly ? "\(offer.displayPrice) per month" : "\(offer.displayPrice) one-time payment")
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("membershipPrice-\(offer.plan.rawValue)")
                    if let days = offer.eligibleTrialDays {
                        Text("\(days)-day free trial, then \(offer.displayPrice) per month. Eligibility and final terms are confirmed by Apple.")
                            .font(.subheadline)
                            .accessibilityIdentifier("membershipIntroductoryOffer")
                    }
                    if offer.plan == .monthly {
                        Text("Renews automatically each month until cancelled in your Apple subscription settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Lifetime membership has no renewal. It does not cancel an existing monthly subscription.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(purchaseTitle(offer)) { Task { await store.buy(offer.plan) } }
                        .disabled(store.busy || !store.access.mayPurchase(offer.plan))
                        .accessibilityIdentifier("membershipPurchase-\(offer.plan.rawValue)")
                }
            }

            Section {
                if store.busy { ProgressView("Contacting the App Store…") }
                Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("membershipStoreStatus")
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("membershipError")
                }
                Button("Refresh App Store plans") { Task { await store.load() } }
                    .disabled(store.busy)
                Button("Restore purchases") { Task { await store.restore() } }
                    .disabled(store.busy)
                    .accessibilityIdentifier("membershipRestore")
                Button("Redeem Apple offer code") { redeemPresented = true }
                    .disabled(store.busy)
                    .accessibilityIdentifier("membershipRedeem")
                Link("Manage Apple subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            } footer: {
                Text("Offer codes are validated by Apple. A code or completed redemption sheet unlocks membership only after Apple confirms a verified purchase.")
            }

            Section {
                Link("Privacy policy", destination: URL(string: "https://spottr.omarchoudhry.co.uk/privacy")!)
                Link("Terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Spottr support", destination: URL(string: "https://spottr.omarchoudhry.co.uk/support")!)
            }
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .offerCodeRedemption(isPresented: $redeemPresented) { result in
            Task { await store.completeRedemption(result) }
        }
    }

    private var accessTitle: String {
        if store.access.lifetime { return "Lifetime membership active" }
        return store.hasAccess ? "Monthly membership active" : "No active Apple membership"
    }

    private func purchaseTitle(_ offer: MembershipOffer) -> String {
        if let days = offer.eligibleTrialDays { return "Start \(days)-day free trial" }
        return offer.plan == .monthly ? "Subscribe monthly" : "Buy lifetime membership"
    }
}
