import SwiftUI
import StoreKit

struct MembershipView: View {
    let store: MembershipStore
    @State private var redeemPresented = false
    @State private var selection: MembershipPlan = .monthly
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image("membership-gem").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                    Text("Your membership").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Start workouts with a membership. Keep access to your history and exports.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .accessibilityIdentifier("membershipRequirements")
                }
                VStack(spacing: 12) {
                    Label(accessTitle, systemImage: store.hasAccess ? "checkmark.seal.fill" : "diamond")
                        .font(.headline).accessibilityIdentifier("membershipAccessStatus")
                    if let deadline = store.access.expiresAt, !store.access.lifetime {
                        Text("Current access through \(deadline.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if store.accountID == nil { Text("Sign in to purchase. Restore is always available.").font(.footnote).multilineTextAlignment(.center) }
                    Button("Restore purchases") { Task { await store.restore() } }
                        .buttonStyle(.bordered).tint(Palette.blue).foregroundStyle(Palette.blue)
                        .frame(minHeight: 44).disabled(store.busy).accessibilityIdentifier("membershipRestore")
                }.frame(maxWidth: .infinity).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))

                if store.busy {
                    ProgressView("Contacting the App Store…").frame(maxWidth: .infinity).padding(20)
                        .accessibilityIdentifier("membershipLoading")
                }
                if store.offers.isEmpty && !store.busy && !store.hasAccess {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(Palette.blue)
                        Text("Plans are temporarily unavailable").font(.headline)
                        Text("Check your connection and try again. Your saved work is safe.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).foregroundStyle(.white).frame(minHeight: 44)
                            .accessibilityIdentifier("membershipRetry")
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(22)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                ForEach(store.hasAccess ? [] : store.offers) { offer in
                    Button { selection = offer.plan } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(offer.displayName).font(.headline)
                                Spacer()
                                Image(systemName: selection == offer.plan ? "checkmark.circle.fill" : "circle")
                            }
                            Text(offer.plan == .monthly ? "\(offer.displayPrice) per month" : "\(offer.displayPrice) one-time payment")
                                .font(.title2.bold()).accessibilityIdentifier("membershipPrice-\(offer.plan.rawValue)")
                            if let days = offer.eligibleTrialDays {
                                Text("\(days)-day free trial, then \(offer.displayPrice) per month.")
                                    .font(.subheadline).accessibilityIdentifier("membershipIntroductoryOffer")
                            }
                            Text(offer.plan == .monthly ? "Renews automatically each month until cancelled in Apple subscription settings." : "No renewal. Lifetime does not cancel an existing monthly subscription.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(selection == offer.plan ? Palette.blue.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                            .overlay { RoundedRectangle(cornerRadius: 22).stroke(selection == offer.plan ? Palette.blue : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == offer.plan ? .isSelected : [])
                }
                if !store.hasAccess, let offer = store.offers.first(where: { $0.plan == selection }) ?? store.offers.first {
                    Button(purchaseTitle(offer)) { Task { await store.buy(offer.plan) } }
                        .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large).frame(maxWidth: .infinity, minHeight: 48)
                        .disabled(store.accountID == nil || store.busy || !store.access.mayPurchase(offer.plan))
                        .accessibilityIdentifier("membershipPurchase-\(offer.plan.rawValue)")
                }
                if store.access.hasOverlappingSubscription {
                    Text("You own lifetime membership and have an active monthly subscription. Lifetime does not cancel monthly billing. Review your subscription with Apple.")
                        .font(.subheadline).accessibilityIdentifier("membershipOverlapNotice")
                }
                VStack(spacing: 12) {
                    if !store.hasAccess { Text(store.status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("membershipStoreStatus") }
                    if let error = store.error { Text(error).font(.subheadline).foregroundStyle(Palette.red).accessibilityIdentifier("membershipError") }
                    if !store.hasAccess { Text("Apple confirms prices and trial eligibility. Redeem offer codes through Apple.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("membershipAppleConfirmation")
                    }
                    Button("Redeem Apple offer code") { redeemPresented = true }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44).disabled(store.busy).accessibilityIdentifier("membershipRedeem")
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        Label { Text("Manage Apple subscriptions").underline() } icon: { Image(systemName: "arrow.up.right.square") }
                    }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44)
                    Link(destination: URL(string: "https://spottr.omarchoudhry.co.uk/privacy")!) {
                        Label { Text("Privacy policy").underline() } icon: { Image(systemName: "arrow.up.right.square") }
                    }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44)
                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                        Label { Text("Terms of use").underline() } icon: { Image(systemName: "arrow.up.right.square") }
                    }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44)
                    Link(destination: URL(string: "https://spottr.omarchoudhry.co.uk/support")!) {
                        Label { Text("Spottr support").underline() } icon: { Image(systemName: "arrow.up.right.square") }
                    }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44).accessibilityIdentifier("membershipSupport")
                }.multilineTextAlignment(.center)
            }.frame(maxWidth: 560).padding(24).frame(maxWidth: .infinity)
        }.background(.white).foregroundStyle(Palette.ink).tint(Palette.blue)
        .navigationTitle("Membership").navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .offerCodeRedemption(isPresented: $redeemPresented) { result in Task { await store.completeRedemption(result) } }
    }
    private var accessTitle: String {
        if store.access.lifetime { return "Lifetime membership active" }
        switch store.condition {
        case .gracePeriod: return "Membership in billing grace period"
        case .expired: return "Membership expired"
        case .revoked: return "Purchase refunded or revoked"
        case .active: return "Monthly membership active"
        default: return "No active Apple membership"
        }
    }
    private func purchaseTitle(_ offer: MembershipOffer) -> String {
        if let days = offer.eligibleTrialDays { return "Start \(days)-day free trial" }
        return offer.plan == .monthly ? "Subscribe monthly" : "Buy lifetime membership"
    }
}

struct WorkoutLaunchAccessView: View {
    let launch: WorkoutLaunchCoordinator
    @State private var measurementsPresented = false
    var body: some View {
        NavigationStack {
            Group {
                if launch.decision == .requiresMembership {
                    MembershipView(store: launch.membership)
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView(title, systemImage: "figure.mind.and.body", description: Text(detail))
                        if launch.decision == .requiresSetup {
                            Button("Complete training setup") { measurementsPresented = true }
                                .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large).padding(.bottom)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = launch.pendingID {
                    Button("Continue to workout") { launch.continuePending(id: id) }
                        .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large).padding()
                        .frame(maxWidth: .infinity).background(.white)
                        .disabled(launch.decision == .requiresMembership && !launch.membership.hasAccess)
                }
            }
            .sheet(isPresented: $measurementsPresented) {
                OnboardingView(profileStore: launch.profile, healthStore: launch.healthStore, guardianAuthorization: launch.guardianAuthorization, history: launch.history)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { launch.cancel() } } }
        }
    }
    private var title: String {
        switch launch.decision {
        case .requiresAccount: "Sign in to train"
        case .requiresSetup: "Complete your profile"
        default: "Choose a suitable workout"
        }
    }
    private var detail: String {
        switch launch.decision {
        case .requiresAccount: "Use Account and training profiles to finish secure sign-in, then select your workout again."
        case .requiresSetup: "Add your age and required profile details in settings before starting. Your saved work stays available."
        default: "This workout does not match this profile’s age, support or movement preferences. Adjust the workout before starting."
        }
    }
}
