import SwiftUI
import StoreKit

struct MembershipView: View {
    let store: MembershipStore
    @State private var redeemPresented = false
    @State private var selection: MembershipPlan = .monthly
    @State private var showOtherPlans = false
    @State private var approvalPending = false
    @State private var approvalMessage: String?
    @State private var approvalRequest = UUID()
    @Environment(\.profileWebsiteAccess) private var actionAccess
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
                    Button("Restore purchases") { authorize { await store.restore() } }
                        .buttonStyle(.bordered).tint(Palette.blue).foregroundStyle(Palette.blue)
                        .frame(minHeight: 44).disabled(store.busy || approvalPending).accessibilityIdentifier("membershipRestore")
                    if selectedOffer == nil { operationFeedback }
                    if let approvalMessage { Text(approvalMessage).font(.footnote).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))

                if store.busy {
                    ProgressView("Contacting the App Store…").frame(maxWidth: .infinity).padding(20)
                        .accessibilityIdentifier("membershipLoading")
                }
                if store.hasAccess && canChoosePlan {
                    Button(showOtherPlans ? "Hide membership options" : "Explore membership options") { showOtherPlans.toggle() }
                        .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("membershipOtherPlans")
                }
                if visibleOffers.isEmpty && !store.busy && canChoosePlan && (!store.hasAccess || showOtherPlans) {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(Palette.blue)
                        Text("Plans are temporarily unavailable").font(.headline)
                        Text("Check your connection and try again. Your saved work is safe.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).foregroundStyle(.white).frame(minHeight: 44)
                            .accessibilityIdentifier("membershipRetry")
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(22)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                ForEach(visibleOffers) { offer in
                    Button { selection = offer.plan } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(offer.displayName).font(.headline)
                                Spacer()
                                Image(systemName: selectedOffer?.plan == offer.plan ? "checkmark.circle.fill" : "circle")
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
                            .background(selectedOffer?.plan == offer.plan ? Palette.blue.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                            .overlay { RoundedRectangle(cornerRadius: 22).stroke(selectedOffer?.plan == offer.plan ? Palette.blue : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedOffer?.plan == offer.plan ? .isSelected : [])
                }
                if let offer = selectedOffer {
                    Button(purchaseTitle(offer)) { authorize { await store.buy(offer.plan) } }
                        .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large).frame(maxWidth: .infinity, minHeight: 48)
                        .disabled(store.accountID == nil || store.busy || approvalPending || !store.access.mayPurchase(offer.plan))
                        .accessibilityIdentifier("membershipPurchase-\(offer.plan.rawValue)")
                    operationFeedback
                }
                if store.access.hasOverlappingSubscription {
                    Text("You own lifetime membership and have an active monthly subscription. Lifetime does not cancel monthly billing. Review your subscription with Apple.")
                        .font(.subheadline).accessibilityIdentifier("membershipOverlapNotice")
                }
                VStack(spacing: 12) {
                    if store.operationMessage == nil && !store.hasAccess && store.status != "Prices and eligible trials are supplied by the App Store." { Text(store.status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("membershipStoreStatus") }
                    if let error = store.accessError { Text(error).font(.subheadline).foregroundStyle(Palette.red).accessibilityIdentifier("membershipError") }
                    if let catalogueError = store.catalogueError, !store.hasAccess || showOtherPlans {
                        Text(catalogueError).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("membershipCatalogueStatus")
                    }
                    if !store.hasAccess { Text("Apple confirms prices and trial eligibility. Redeem offer codes through Apple.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("membershipAppleConfirmation")
                    }
                    Button("Redeem Apple offer code") { authorize { redeemPresented = true } }.buttonStyle(.bordered).foregroundStyle(Palette.blue).frame(minHeight: 44).disabled(store.busy || approvalPending).accessibilityIdentifier("membershipRedeem")
                    WebsiteLink(title: "Manage Apple subscriptions", url: URL(string: "https://apps.apple.com/account/subscriptions")!).buttonStyle(.bordered)
                    WebsiteLink(title: "Privacy policy", url: URL(string: "https://spottr.omarchoudhry.co.uk/privacy")!).buttonStyle(.bordered)
                    WebsiteLink(title: "Terms of use", url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!).buttonStyle(.bordered)
                    WebsiteLink(title: "Spottr support", url: URL(string: "https://spottr.omarchoudhry.co.uk/support")!).buttonStyle(.bordered).accessibilityIdentifier("membershipSupport")
                }.multilineTextAlignment(.center)
            }.frame(maxWidth: 560).padding(24).frame(maxWidth: .infinity)
        }.background(.white).foregroundStyle(Palette.ink).tint(Palette.blue)
        .navigationTitle("Membership").navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .offerCodeRedemption(isPresented: $redeemPresented) { result in Task { await store.completeRedemption(result) } }
        .onDisappear { approvalRequest = UUID(); approvalPending = false }
    }
    @ViewBuilder private var operationFeedback: some View {
        if let message = store.operationMessage {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("membershipOperationStatus")
        }
    }
    private func authorize(_ action: @escaping @MainActor () async -> Void) {
        guard !approvalPending else { return }
        let request = UUID(), accountID = store.accountID
        approvalRequest = request; approvalPending = true; approvalMessage = nil
        Task { @MainActor in
            defer { if approvalRequest == request { approvalPending = false } }
            do {
                guard let actionAccess else { throw AccountFailure.reauthenticate }
                try await actionAccess.authorize()
                guard approvalRequest == request, store.accountID == accountID else { return }
                await action()
            } catch {
                if approvalRequest == request { approvalMessage = "Approval is needed to continue. You can try again when ready." }
            }
        }
    }
    private var selectedOffer: MembershipOffer? { visibleOffers.first { $0.plan == selection } ?? visibleOffers.first }
    private var canChoosePlan: Bool { MembershipPlan.allCases.contains { store.access.mayPurchase($0) } }
    private var visibleOffers: [MembershipOffer] {
        guard !store.hasAccess || showOtherPlans else { return [] }
        return store.offers.filter { store.access.mayPurchase($0.plan) }
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
                OnboardingView(profileStore: launch.profile, healthStore: launch.healthStore, guardianAuthorization: launch.guardianAuthorization, history: launch.history, programme: launch.programme, voicePreviews: launch.voicePreviews)
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
