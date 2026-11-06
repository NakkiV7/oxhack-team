import Foundation
import Observation

@MainActor @Observable final class WorkoutLaunchCoordinator {
    private struct Intent {
        let id = UUID()
        let plan: CoachSavedPlan
        let origin: WorkoutLaunchOrigin
        let owner: WorkoutOwner
        var generation: UUID
        let plannedWorkoutID: String?
    }
    private let training: TrainingStore
    let profile: NativeProfileStore
    let membership: MembershipCoordinator
    private let owner: () -> WorkoutOwner?
    private let generation: () -> UUID
    private var pending: Intent?
    private var expectedAuthenticationIntent: UUID?
    private(set) var decision: WorkoutAccessPolicy.Decision?
    var pendingOrigin: WorkoutLaunchOrigin? { pending?.origin }
    var pendingID: UUID? { pending?.id }
    var needsAttention: Bool { pending != nil && decision != .start && decision != .resumeExisting }

    init(training: TrainingStore, profile: NativeProfileStore, membership: MembershipCoordinator,
         owner: @escaping () -> WorkoutOwner?, generation: @escaping () -> UUID) {
        self.training = training; self.profile = profile; self.membership = membership
        self.owner = owner; self.generation = generation
    }
    func request(plan: CoachSavedPlan, origin: WorkoutLaunchOrigin, plannedWorkoutID: String? = nil) {
        cancel()
        guard let scope = training.accountScope else { decision = .requiresAccount; return }
        let intent = Intent(plan: plan, origin: origin, owner: .init(accountID: scope.accountID, profileID: scope.profileID), generation: generation(), plannedWorkoutID: plannedWorkoutID)
        pending = intent
        evaluate(intent)
    }
    func continuePending(id: UUID) {
        guard let intent = pending, intent.id == id, intent.generation == generation(), owner() == intent.owner else { cancel(); return }
        evaluate(intent)
    }
    func authenticationWillBegin() { expectedAuthenticationIntent = pending?.id }
    func authenticationDidComplete() {
        guard let pending, expectedAuthenticationIntent == pending.id, owner() == pending.owner else { return }
        self.pending?.generation = generation()
        expectedAuthenticationIntent = nil
    }
    func cancel() { pending = nil; decision = nil; expectedAuthenticationIntent = nil }
    func open(_ url: URL) {
        cancel()
        guard url.scheme == "spottr", url.host == "workout",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "exercise" })?.value,
              let entry = ExerciseCatalog.find(id), let profile = profile.profile else { return }
        let age = profile.programmePreferences?.ageContext?.ageYears ?? 0
        let target = age < 18 ? min(entry.goal, entry.unit == .reps ? (age < 13 ? 6 : 10) : (age < 13 ? 10 : 20)) : entry.goal
        guard let plan = try? CoachSavedPlan.catalogue(exerciseID: id, sets: 1, target: target, restSeconds: 60,
                                                       availableSupport: profile.effectiveProgrammePreferences.availableSupport) else { return }
        request(plan: plan, origin: .url)
    }
    private func evaluate(_ intent: Intent) {
        guard intent.generation == generation() else { cancel(); return }
        let trusted = owner()
        guard trusted == nil || trusted == intent.owner else { cancel(); return }
        let ongoing = training.sessionPhase != .idle && training.sessionPhase != .finished
        decision = WorkoutAccessPolicy.decide(trustedOwner: trusted, activeOwner: ongoing ? intent.owner : nil,
                                               profile: profile.profile, membership: membership.accountID == trusted?.accountID && membership.hasAccess,
                                               plan: intent.plan, origin: intent.origin)
        switch decision {
        case .start:
            pending = nil
            training.beginAuthorizedPlan(intent.plan, availableSupport: profile.profile?.effectiveProgrammePreferences.availableSupport ?? [], plannedWorkoutID: intent.plannedWorkoutID)
        case .resumeExisting:
            pending = nil
            training.presented = true
        default: break
        }
    }
}
