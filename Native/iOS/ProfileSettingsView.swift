import SwiftUI

@MainActor @Observable
final class ProfileDraftPersistence {
    private let store: NativeProfileStore
    private var pending: LocalProfile?
    private var saveTask: Task<Void, Never>?
    private(set) var message: String?
    private(set) var validationError: String?
    var blocksDismissal: Bool { pending != nil }

    init(store: NativeProfileStore) { self.store = store }

    func edit(name: String, weeklyTarget: Int, goals: Set<TrainingGoal>) {
        reset()
        do {
            let profile = try LocalProfile(name: name, weeklyTarget: weeklyTarget, goals: legacyGoals(goals),
                                           baselineAbility: store.profile?.baselineAbility,
                                           bodyMeasurements: store.profile?.bodyMeasurements,
                                           comfortableExercises: store.profile?.comfortableExercises ?? [],
                                           weightManagementGoal: goals.contains(.weightManagement),
                                           onboardingRevision: store.profile?.onboardingRevision ?? 2,
                                           programmePreferences: try preferences(goals: goals, target: weeklyTarget))
            guard store.loadError == nil else {
                validationError = "Automatic saving is paused. Use Save profile to explicitly replace the unreadable profile."
                return
            }
            if profile == store.profile { message = "Profile saved."; return }
            pending = profile; message = "Saving…"
            saveTask = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                saveTask = nil
                _ = persistPending()
            }
        } catch { validationError = error.localizedDescription }
    }

    func save(name: String, weeklyTarget: Int, goals: Set<TrainingGoal>) -> Bool {
        reset()
        do {
            pending = try LocalProfile(name: name, weeklyTarget: weeklyTarget, goals: legacyGoals(goals),
                                       baselineAbility: store.profile?.baselineAbility,
                                       bodyMeasurements: store.profile?.bodyMeasurements,
                                           comfortableExercises: store.profile?.comfortableExercises ?? [],
                                           weightManagementGoal: goals.contains(.weightManagement),
                                           onboardingRevision: store.profile?.onboardingRevision ?? 2,
                                           programmePreferences: try preferences(goals: goals, target: weeklyTarget))
            return persistPending()
        } catch { validationError = error.localizedDescription; return false }
    }

    private func legacyGoals(_ goals: Set<TrainingGoal>) -> Set<TrainingAttribute> {
        let attributes = Set(goals.compactMap { TrainingAttribute(rawValue: $0.rawValue) })
        return attributes.isEmpty ? store.profile?.goals ?? [.stamina] : attributes
    }
    private func preferences(goals: Set<TrainingGoal>, target: Int) throws -> ProgrammePreferences? {
        guard !goals.isEmpty else { throw LocalProfile.Invalid.goals }
        guard let old = store.profile?.programmePreferences else { return nil }
        return try ProgrammePreferences(goals: goals, weekdays: old.weekdays.count == target ? old.weekdays : Set([1, 3, 5, 2, 4, 6, 7].prefix(target)),
            minutesPerSession: old.minutesPerSession, preferredLocalHour: old.preferredLocalHour,
            availableSupport: old.availableSupport, allowsFloorWork: old.allowsFloorWork,
            excludedExerciseIDs: old.excludedExerciseIDs, startingPoint: old.startingPoint,
            ageContext: old.ageContext, comfortAnswers: old.comfortAnswers)
    }
    func prepareToLeave() -> Bool {
        saveTask?.cancel(); saveTask = nil
        return persistPending()
    }

    func reset() {
        saveTask?.cancel(); saveTask = nil; pending = nil
        message = nil; validationError = nil
    }

    private func persistPending() -> Bool {
        guard let profile = pending else { return true }
        do {
            if profile != store.profile || store.loadError != nil { try store.save(profile) }
            pending = nil; validationError = nil; message = "Profile saved."
            return true
        } catch {
            message = nil; validationError = "Changes haven’t been saved. \(error.localizedDescription)"
            return false
        }
    }
}

struct ProfileSettingsView: View {
    let profileStore: NativeProfileStore
    let history: [SessionRecord]
    let exportData: () throws -> URL
    let resetHistory: () throws -> Void
    let rewards: NativeRewardsStore?
    let historyAvailable: Bool
    let workspace: PreviewWorkspace?
    let guardianAuthorization: (any NativeAccountAuthorization)?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var weeklyTarget: Int
    @State private var goals: Set<TrainingGoal>
    @State private var introduction: Introduction?
    @State private var rewardsPresented = false
    @State private var measurementsPresented = false
    @State private var deletion: Deletion?
    @State private var exportURL: URL?
    @State private var message: String?
    @State private var error: String?
    @State private var persistence: ProfileDraftPersistence
    private let membership: MembershipStore
    @State private var healthStore: HealthDataStore
    @FocusState private var editingName: Bool

    init(profileStore: NativeProfileStore, history: [SessionRecord],
         exportData: @escaping () throws -> URL, resetHistory: @escaping () throws -> Void,
         rewards: NativeRewardsStore? = nil, historyAvailable: Bool = true, workspace: PreviewWorkspace? = nil,
         healthStore: HealthDataStore? = nil, membership: MembershipStore? = nil, guardianAuthorization: (any NativeAccountAuthorization)? = nil) {
        self.guardianAuthorization = guardianAuthorization
        self.membership = membership ?? MembershipStore()
        self.profileStore = profileStore
        self.history = history
        self.exportData = exportData
        self.resetHistory = resetHistory
        self.rewards = rewards
        self.historyAvailable = historyAvailable
        self.workspace = workspace
        _healthStore = State(initialValue: healthStore ?? HealthDataStore())
        _persistence = State(initialValue: ProfileDraftPersistence(store: profileStore))
        _name = State(initialValue: profileStore.profile?.name ?? "")
        _weeklyTarget = State(initialValue: profileStore.profile?.weeklyTarget ?? 3)
        _goals = State(initialValue: profileStore.profile?.trainingGoals ?? [.strength])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Membership") {
                    Text("Account and membership required to train")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("profile-membership-required")
                    NavigationLink {
                        MembershipView(store: membership)
                    } label: {
                        HStack(spacing: 12) {
                            Image("membership-gem").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                            Text("Membership & Apple purchases")
                        }
                    }.accessibilityIdentifier("profile-membership")
                    Text("Plans, prices and trial eligibility are confirmed by the App Store. Restore remains available if membership has ended.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Label("Local profile", systemImage: "person.crop.circle").font(.headline)
                    Text("Your details stay on this iPhone").font(.caption).foregroundStyle(.secondary)
                        .contentShape(Rectangle()).onTapGesture { editingName = false }
                        .accessibilityIdentifier("profile-local-note")
                    if let issue = profileStore.loadError { Text(issue).font(.caption).foregroundStyle(Palette.red) }
                    TextField("Your name (optional)", text: Binding(get: { name }, set: { name = $0; queueSave() }))
                        .textContentType(.givenName).textInputAutocapitalization(.words).focused($editingName)
                        .submitLabel(.done).onSubmit { editingName = false; flushPendingSave() }
                    ProfileWeeklyTarget(target: Binding(get: { weeklyTarget }, set: { weeklyTarget = $0; editingName = false; queueSave() }))
                    if let validationError = persistence.validationError {
                        Text(validationError).font(.caption).foregroundStyle(Palette.red).accessibilityIdentifier("profile-validation-error")
                    } else if let message = message ?? persistence.message {
                        Text(message).font(.caption).foregroundStyle(message == "Saving…" ? Palette.muted : Palette.green)
                            .accessibilityIdentifier("profile-save-status")
                    }
                }
                Section("Your goals") {
                    TrainingGoalPicker(goals: Binding(get: { goals }, set: { goals = $0; editingName = false; queueSave() }), adult: AccountPolicy.allowsHealth(profile: profileStore.profile))
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    Button("Save profile") { editingName = false; save() }.disabled(goals.isEmpty).accessibilityIdentifier("save-profile")
                }
                Section("Your trainer") {
                    NavigationLink("Voice and coaching style") {
                        VoiceCoachSettingsView(playback: RemoteVoicePlayback(offlineOnly: true, defaults: profileStore.preferencesDefaults,
                            gentleOnly: (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) < 18), cancelCoaching: {})
                    }
                }
                Section("Phone and Watch") {
                    NavigationLink("Permissions and connection") {
                        ScrollView { PhonePermissionsView(profileStore: profileStore, healthStore: healthStore).padding(24) }
                            .navigationTitle("Phone and Watch")
                    }.accessibilityIdentifier("profile-permissions")
                }
                Section("Exercise lessons") {
                    NavigationLink { DemonstrationGuideView() } label: {
                        Label("Movement guides", systemImage: "figure.flexibility")
                    }
                }
                Section("Body measurements") {
                    Button {
                        editingName = false
                        guard flushPendingSave() else { return }
                        if (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) < 18 {
                            Task {
                                guard let guardianAuthorization else { error = "A guardian must unlock measurements."; return }
                                do {
                                    try await guardianAuthorization.guardian()
                                    guard profileStore.permitsPolicyCallbacks else { return }
                                    measurementsPresented = true
                                } catch { self.error = "Measurements were not unlocked." }
                            }
                        } else { measurementsPresented = true }
                    } label: {
                        Label("Height, weight & BMI", systemImage: "scalemass")
                    }.accessibilityIdentifier("profile-measurements").disabled(profileStore.loadError != nil)
                    if profileStore.loadError != nil {
                        Text("Save or reset the unreadable profile before changing measurements.").font(.caption).foregroundStyle(Palette.red)
                    }
                    Text(AccountPolicy.allowsHealth(profile: profileStore.profile) ? "Height and weight are required for adult training. Values stay on this iPhone." : "Junior measurements are optional and managed by the guardian.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Your training") {
                    if historyAvailable {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            let summary = StreakSummary(history: history, now: timeline.date)
                            LabeledContent("Current streak", value: dayCount(summary.currentStreak))
                            LabeledContent("Longest streak", value: dayCount(summary.longestStreak))
                            LabeledContent("Training days this week", value: "\(summary.daysThisWeek)")
                        }
                        Text("Streaks use distinct days with a recorded non-zero set. Video replays and planned sessions don’t count.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Training history unavailable").font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("profile-history-unavailable")
                        Text("Your saved sessions couldn’t be read. Streaks and training-day totals are unavailable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let rewards {
                        if let issue = rewards.loadError {
                            Text("Training rewards unavailable").font(.subheadline.weight(.semibold))
                            Text(issue).font(.caption).foregroundStyle(Palette.red)
                        } else {
                            Button {
                                editingName = false
                                if flushPendingSave() { rewardsPresented = true }
                            } label: {
                                HStack(spacing: 10) {
                                    Image("xp-double").resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                                    Text("Training rewards")
                                }
                            }.accessibilityIdentifier("training-rewards-settings")
                        }
                    }
                }
                Section("Get started again") {
                    Button("Restart introduction", systemImage: "arrow.counterclockwise") {
                        editingName = false
                        if flushPendingSave() { introduction = .show }
                    }
                    Text("Review the introduction and update your goals. Your history stays saved.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    Button("Prepare history export", systemImage: "square.and.arrow.up") {
                        do { exportURL = try exportData(); error = nil }
                        catch { self.error = "The export couldn’t be prepared. \(error.localizedDescription)" }
                    }.accessibilityIdentifier("prepare-history-export")
                    if let exportURL { ShareLink("Share history export", item: exportURL) }
                    Text("Prepare a file, then choose where to save or share it. Nothing is sent automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Delete local training history", systemImage: "trash", role: .destructive) { deletion = .history }
                        .accessibilityIdentifier("delete-local-history")
                    Button("Reset local profile", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { deletion = .profile }
                }
                Section("Website & support") {
                    WebsiteLink(title: "Privacy policy", url: URL(string: "https://spottr.omarchoudhry.co.uk/privacy")!)
                        .accessibilityIdentifier("profile-privacy")
                    WebsiteLink(title: "Spottr support", url: URL(string: "https://spottr.omarchoudhry.co.uk/support")!)
                        .accessibilityIdentifier("profile-support")
                    WebsiteLink(title: "Account website", url: URL(string: "https://spottr.omarchoudhry.co.uk/account")!)
                        .accessibilityIdentifier("profile-website-account")
                    Text("Your secure account keeps training profiles separate. Membership requires a verified Apple purchase. Creating an account does not upload your workouts.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile-account-separation")
                }
            }
            .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            .background { Color.white.contentShape(Rectangle()).onTapGesture { editingName = false } }.tint(Palette.blue)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editingName {
                    KeyboardDismissBar(identifier: "profile-keyboard-done") {
                        editingName = false
                        _ = flushPendingSave()
                    }
                }
            }
            .onDisappear { _ = flushPendingSave() }
            .navigationTitle("Profile & settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") {
                editingName = false
                if flushPendingSave() { dismiss() }
            } } }
            .sheet(item: $introduction, onDismiss: reloadDraft) { _ in
                OnboardingView(profileStore: profileStore, healthStore: healthStore, guardianAuthorization: guardianAuthorization, history: history, onComplete: reloadDraft)
            }
            .sheet(isPresented: $rewardsPresented) {
                if let rewards { TrainingRewardsSettingsView(store: rewards) }
            }
            .sheet(isPresented: $measurementsPresented, onDismiss: reloadDraft) {
                MeasurementsSettingsView(measurements: profileStore.profile?.bodyMeasurements, profileStore: profileStore,
                                         persist: profileStore.saveMeasurements)
            }
            .alert(deletion == .profile ? "Reset local profile?" : "Delete local training history?",
                   isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                if let deletion {
                    Button(deletion == .profile ? "Reset profile" : "Delete local history", role: .destructive) { perform(deletion) }
                }
                Button("Cancel", role: .cancel) { deletion = nil }
            } message: {
                Text(deletion == .profile
                     ? "Remove your name, goals and weekly target from this iPhone? Training history stays saved."
                     : "Remove \(history.count) saved sessions from this iPhone? Your profile stays. This doesn’t delete copies already synced to other services.")
            }
            .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }.preferredColorScheme(.light).interactiveDismissDisabled(persistence.blocksDismissal)
    }

    private func queueSave() {
        message = nil
        persistence.edit(name: name, weeklyTarget: weeklyTarget, goals: goals)
    }
    @discardableResult private func flushPendingSave() -> Bool {
        let saved = persistence.prepareToLeave()
        if !saved { error = persistence.validationError }
        if saved && persistence.validationError == nil && !editingName { name = profileStore.profile?.name ?? name }
        return saved
    }
    private func save() {
        message = nil
        if persistence.save(name: name, weeklyTarget: weeklyTarget, goals: goals), !editingName {
            name = profileStore.profile?.name ?? name
        }
    }

    private func reloadDraft() {
        persistence.reset()
        name = profileStore.profile?.name ?? ""
        weeklyTarget = profileStore.profile?.weeklyTarget ?? 3
        goals = profileStore.profile?.trainingGoals ?? [.strength]
    }

    private func perform(_ action: Deletion) {
        do {
            if action == .profile {
                try profileStore.resetProfile(); reloadDraft(); message = "Local profile reset."
            }
            else { try resetHistory(); message = "Local training history deleted." }
            exportURL = nil
        } catch { self.error = error.localizedDescription }
        deletion = nil
    }

    private func dayCount(_ count: Int) -> String { "\(count) \(count == 1 ? "day" : "days")" }
    private enum Introduction: String, Identifiable { case show; var id: String { rawValue } }
    private enum Deletion { case profile, history }
}
