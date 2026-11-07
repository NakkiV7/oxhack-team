import SwiftUI
import AuthenticationServices

@MainActor @Observable final class AccountWorkspaceCoordinator {
    let account: NativeAccountStore
    let membership: MembershipCoordinator
    let root: URL
    private(set) var directory: AccountProfileDirectory?
    private(set) var workspace: AccountWorkspace?
    private(set) var message: String?
    private var pendingWorkoutURL: URL?
    init(account: NativeAccountStore? = nil, root: URL? = nil, membership: MembershipCoordinator? = nil, membershipClient: (any MembershipClient)? = nil) {
        self.account = account ?? NativeAccountStore()
        let base = URL.applicationSupportDirectory.appendingPathComponent("Spottr")
        let namespace = ProcessInfo.processInfo.environment["SPOTTR_DATA_NAMESPACE"].flatMap(UUID.init(uuidString:))
        self.root = root ?? namespace.map { base.appendingPathComponent($0.uuidString) } ?? base
        self.membership = membership ?? MembershipStore(root: self.root, client: membershipClient)
        do {
            try ProtectedLocalStorage.prepare(self.root)
            for name in ["profile.json", "history.json", "rewards.json", "training-path.json", "watch-inbox.json"] {
                let file = self.root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try ProtectedLocalStorage.protect(file) }
            }
        } catch { message = "Local data protection could not be updated. Existing files have not been replaced." }
    }
    var visibleWorkspace: AccountWorkspace? {
        guard account.trusted, workspace?.scope.accountID == account.accountID else { return nil }
        return workspace
    }
    var websiteAccess: ProfileWebsiteAccess {
        let generation = account.authenticationGeneration, checkpoint = account.checkpoint
        if let captured = visibleWorkspace {
            return ProfileWebsiteAccess(profile: captured.profile, guardian: account.authorization, isCurrent: { [weak self, weak captured] in
                guard let self, let captured else { return false }
                return self.visibleWorkspace === captured && self.account.authenticationGeneration == generation
            })
        }
        return ProfileWebsiteAccess(guardian: account.authorization, isCurrent: { [weak self] in
            guard let self else { return false }
            return self.visibleWorkspace == nil && self.account.authenticationGeneration == generation && self.account.checkpoint == checkpoint
        })
    }
    func accountChanged() {
        membership.setAccount(account.trusted ? account.appAccountToken : nil)
        if account.state == .pendingMFA { workspace?.launch?.authenticationWillBegin() }
        if account.trusted && account.step == .complete { workspace?.launch?.authenticationDidComplete() }
        if account.state == .revoked { cancelPendingLaunch() }
        do {
            guard let id = account.accountID, account.trusted else { workspace?.suspend(preservingLaunchIntent: account.state != .signedOut && account.state != .revoked); directory = nil; return }
            if directory?.accountID != id { directory = try AccountProfileDirectory(accountID: id, root: root) }
            if let selected = directory?.selectedID { try select(selected) }
            deliverWorkoutURL()
        } catch { message = "This profile could not be opened. Saved data has not been changed." }
    }
    func openWorkoutURL(_ url: URL) {
        cancelPendingLaunch()
        guard url.scheme == "spottr", url.host == "workout" else { return }
        pendingWorkoutURL = url
        deliverWorkoutURL()
    }
    func cancelPendingLaunch() { pendingWorkoutURL = nil; workspace?.launch?.cancel() }
    private func deliverWorkoutURL() {
        guard let workspace = visibleWorkspace, let url = pendingWorkoutURL else { return }
        pendingWorkoutURL = nil
        workspace.launch?.open(url)
    }
    @discardableResult func createProfile(name: String, age: TrainingAgeContext) async -> Bool {
        do {
            guard account.trusted, let directory else { throw AccountFailure.reauthenticate }
            if age.guardianManaged || !directory.profiles.isEmpty { try await account.authorization.guardian() }
            guard account.accountID == directory.accountID else { throw AccountFailure.reauthenticate }
            try requireNoOtherWorkout()
            let isFirstProfile = directory.profiles.isEmpty
            let profile = try directory.add(age: age, name: name)
            if isFirstProfile { account.consumeInitialProfileCheckpoint() }
            try select(profile.id)
            deliverWorkoutURL()
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func updateSelectedIdentity(name: String, age: TrainingAgeContext) async {
        do {
            guard let captured = visibleWorkspace, let directory else { throw AccountFailure.reauthenticate }
            let generation = account.authenticationGeneration
            try await account.authorization.guardian()
            guard visibleWorkspace === captured, account.authenticationGeneration == generation else { throw AccountFailure.reauthenticate }
            try requireNoOtherWorkout()
            captured.invalidatePolicy()
            workspace = nil
            try directory.updateIdentity(id: captured.scope.profileID, name: name, age: age)
            try select(captured.scope.profileID)
        } catch { message = "The profile policy could not be updated. Reopen the matching profile before training. " + error.localizedDescription }
    }
    func choose(_ id: UUID) async {
        cancelPendingLaunch()
        do {
            guard let directory, account.accountID == directory.accountID else { throw AccountFailure.reauthenticate }
            try await account.authorization.guardian()
            guard account.accountID == directory.accountID else { throw AccountFailure.reauthenticate }
            try select(id)
        } catch { message = error.localizedDescription }
    }
    private func select(_ id: UUID) throws {
        guard let directory, directory.profiles.contains(where: { $0.id == id }), account.trusted, directory.accountID == account.accountID else { throw AccountFailure.reauthenticate }
        let scope = directory.scope(id)
        if workspace?.scope == scope { workspace?.watchSharing.setActive(true); workspace?.training.setAccountActive(true); return }
        try requireNoOtherWorkout()
        workspace?.suspend()
        let next = try AccountWorkspace(scope: scope)
        configureLaunch(next)
        try directory.select(id)
        workspace = next
    }
    private func configureLaunch(_ workspace: AccountWorkspace) {
        let scope = workspace.scope
        let launch = WorkoutLaunchCoordinator(training: workspace.training, profile: workspace.profile, membership: membership,
            owner: { [weak self, weak workspace] in
                guard let self, let workspace, self.visibleWorkspace === workspace, self.account.trusted,
                      self.account.accountID == scope.accountID else { return nil }
                return .init(accountID: scope.accountID, profileID: scope.profileID)
            }, generation: { [weak account] in account?.authenticationGeneration ?? UUID() })
        workspace.programmeSync = ProgrammeSyncStore(programme: workspace.programme, profile: workspace.profile, client: account,
            isCurrent: { [weak self, weak workspace] in
                guard let self, let workspace else { return false }
                return self.visibleWorkspace === workspace && self.account.trusted && self.account.accountID == scope.accountID
            }, hasOngoingWorkout: { [weak workspace] in workspace?.hasOngoingWorkout ?? true })
        workspace.programme.sync = workspace.programmeSync
        launch.healthStore = workspace.health; launch.guardianAuthorization = account.authorization
        workspace.launch = launch; workspace.training.launchCoordinator = launch
        let bridge = WatchWorkoutBridge(workspace: workspace, account: account, membership: membership,
            isCurrent: { [weak self, weak workspace] in
                guard let self, let workspace else { return false }
                return self.visibleWorkspace === workspace && self.account.trusted
            })
        workspace.watchBridge = bridge; workspace.training.watchBridge = bridge
    }
    private func requireNoOtherWorkout() throws {
        guard workspace?.hasOngoingWorkout != true else { throw WorkspaceFailure.unfinished }
    }
    func archivePausedWorkout() async {
        do {
            guard let captured = workspace, captured.hasOngoingWorkout else { return }
            try await account.authorization.guardian()
            guard workspace === captured else { throw AccountFailure.reauthenticate }
            captured.training.setAccountActive(false)
            try captured.training.preservePendingWorkout()
            workspace = nil
            message = "The unfinished workout snapshot is preserved for local export. No completed workout or XP was added."
        } catch { message = "The paused workout could not be archived. Its current session is still retained." }
    }

    func importLegacy() async {
        do {
            guard let workspace = visibleWorkspace, let age = workspace.profile.profile?.programmePreferences?.ageContext else { throw AccountFailure.reauthenticate }
            try await account.authorization.guardian()
            guard visibleWorkspace === workspace else { throw AccountFailure.reauthenticate }
            try requireNoOtherWorkout()
            try workspace.scope.importLegacy(from: root, age: age)
            self.workspace = try AccountWorkspace(scope: workspace.scope)
            if let next = self.workspace { configureLaunch(next) }
            message = "Your selected records were copied. Original files and a verified local archive are preserved."
        } catch { message = error.localizedDescription }
    }
    enum WorkspaceFailure: LocalizedError {
        case unfinished
        var errorDescription: String? { "Finish the paused workout in its original account and profile before switching. Its recorded quantities are preserved." }
    }
}

struct AccountRootView: View {
    @State private var coordinator = AccountWorkspaceCoordinator()
    @State private var controls = false
    @Environment(\.scenePhase) private var scenePhase
    @MainActor static func initialSetup(workspace: AccountWorkspace, authorization: any NativeAccountAuthorization) -> OnboardingView {
        OnboardingView(profileStore: workspace.profile, healthStore: workspace.health, guardianAuthorization: authorization, history: workspace.training.history, programme: workspace.programme, analytics: workspace.training.analytics, voicePreviews: workspace.training.voicePreviews) {
            workspace.training.remoteVoice?.reloadPreferences()
            workspace.training.repVoice.choose(workspace.training.remoteVoice?.gentleOnly == true ? nil : RepVoicePlan.Coach(rawValue: workspace.profile.preferencesDefaults.string(forKey: RepVoicePlayer.defaultsKey) ?? "off"))
            workspace.training.setVoiceFeedback(workspace.profile.preferencesDefaults.bool(forKey: "trainer.audioEnabled"))
        }
    }
    var body: some View {
        Group {
            if let workspace = coordinator.visibleWorkspace, coordinator.account.backupCodes.isEmpty {
                Group {
                    if !workspace.hasOngoingWorkout && !AccountPolicy.setupComplete(profile: workspace.profile.profile) {
                        Self.initialSetup(workspace: workspace, authorization: coordinator.account.authorization)
                    } else if workspace.profile.profile?.programmePreferences?.ageContext?.ageYears ?? 0 < 5 {
                        FamilyMovementView(workspace: workspace, authorization: coordinator.account.authorization)
                    } else {
                        SpottrRoot(store: workspace.training, profileStore: workspace.profile, healthStore: workspace.health,
                                   guardianAuthorization: coordinator.account.authorization, membership: coordinator.membership)
                    }
                }
                .safeAreaInset(edge: .top) {
                    Button {
                        Task {
                            if workspace.profile.profile?.programmePreferences?.ageContext?.ageYears ?? 0 < 18 {
                                do { try await coordinator.account.authorization.guardian() } catch { return }
                                guard coordinator.visibleWorkspace === workspace else { return }
                            }
                            controls = true
                        }
                    } label: { Label("Account and training profiles", systemImage: "person.crop.circle.badge.checkmark").font(.footnote).padding(8) }
                }
                .environment(\.watchSharing, workspace.watchSharing)
                .id(ObjectIdentifier(workspace))
                .task(id: ObjectIdentifier(workspace)) {
                    workspace.training.setAccountActive(true)
                    while !Task.isCancelled {
                        workspace.training.coachingTick(); workspace.training.publish()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } else {
                AccountSetupView(account: coordinator.account, coordinator: coordinator)
            }
        }
        .onOpenURL { url in coordinator.openWorkoutURL(url) }
        .sheet(isPresented: $controls) { AccountControlsView(coordinator: coordinator) }
        .task { await coordinator.account.restore(); coordinator.accountChanged() }
        .onChange(of: coordinator.account.accountID) { _, _ in coordinator.accountChanged(); controls = false }
        .onChange(of: coordinator.account.state) { _, state in coordinator.accountChanged(); if state == .pendingMFA { controls = false } }
        .onChange(of: scenePhase) { _, phase in
            coordinator.visibleWorkspace?.training.setAppActive(phase == .active)
        }
    }
}

struct AccountSetupView: View {
    @Bindable var account: NativeAccountStore
    let coordinator: AccountWorkspaceCoordinator
    @State private var age = ""
    @State private var role = AccountPolicy.Role.adultSelf
    @State private var profileRole: AccountPolicy.Role?
    @State private var email = ""
    @State private var code = ""
    @State private var name = ""
    @State private var backup = false
    @State private var purpose = IdentityPurpose.enroll
    @State private var localMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(account.trusted ? "Create a training profile for yourself or someone you care for." : "Start with your age, then sign in securely. An adult guardian manages children’s profiles.")
                    DisclosureGroup("How your account is protected") {
                        Text("Sign-in uses a passkey and an Authenticator code. A saved backup code can replace your Authenticator code.")
                        Text("Children do not need an email address. Guardians confirm their role themselves. Spottr does not verify legal guardianship.")
                    }
                }
                if account.trusted {
                    profileSetup
                } else {
                    authentication
                }
                if coordinator.workspace?.hasOngoingWorkout == true {
                    Section("Protected paused workout") {
                        Text("Return to its original account to resume, or keep its recorded quantities as an unfinished local snapshot before using another profile.")
                        Button("Keep snapshot and close paused session") { Task { await coordinator.archivePausedWorkout() } }
                    }
                }
                if let message = localMessage ?? account.message ?? coordinator.message { Section { Text(message).foregroundStyle(.secondary) } }
                Section("Membership and help") {
                    NavigationLink("Membership & restore purchases") { MembershipView(store: coordinator.membership) }.accessibilityIdentifier("account-membership")
                    WebsiteLink(title: "Spottr support", url: URL(string: "https://spottr.omarchoudhry.co.uk/support")!)
                }
                Section("Saved local data") {
                    NavigationLink("View or export existing phone records") { ProtectedLegacyRecordsView(root: coordinator.root, authorization: account.authorization) }
                    NavigationLink("Unlock retained account records") { LocalAccountArchivesView(root: coordinator.root, authorization: account.authorization) }
                    Text("Existing records stay on this phone. Importing them into an adult training profile is an explicit choice after sign-in.")
                }
            }.navigationTitle("Account and privacy").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) { SetupProgressHeader(stage: .account).background(Color(uiColor: .systemGroupedBackground)) }
        }
        .environment(\.profileWebsiteAccess, coordinator.websiteAccess)
    }
    @ViewBuilder private var authentication: some View {
        if account.step == .identity || account.step == .complete {
            Section("Who is the training profile for?") {
                TextField("Training person’s age in years", text: $age).keyboardType(.numberPad)
                Picker("Account owner", selection: $role) { Text("Adult training for myself").tag(AccountPolicy.Role.adultSelf); Text("Adult guardian managing a profile").tag(AccountPolicy.Role.guardian) }
                Button("Confirm age and role") {
                    do { guard let age = Int(age) else { throw AccountFailure.checkpointRequired }; try account.setCheckpoint(ageYears: age, role: role); localMessage = nil }
                    catch { localMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).tint(Palette.blue)
                if account.checkpoint != nil { Label("Age and role confirmed", systemImage: "checkmark.circle") }
            }
            Section("Create or recover") {
                Picker("Purpose", selection: $purpose) { Text("Create account").tag(IdentityPurpose.enroll); Text("Recover account").tag(IdentityPurpose.recover) }
                TextField("Adult account owner’s email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { await account.startEmail(email: email, purpose: purpose) } } label: {
                    Text("Send verification code").frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.borderedProminent).tint(Palette.blue)
                    .disabled(account.busy || (purpose == .enroll && account.checkpoint == nil))
                AppleAccountButton(enabled: !account.busy && (purpose != .enroll || account.checkpoint != nil)) {
                    Task { await account.startApple(purpose: purpose) }
                }.frame(height: 50)
            }
            Section("Already have a passkey?") {
                Button("Sign in with passkey") { Task { await account.login() } }.disabled(account.busy)
            }
        }
        if account.step == .emailCode {
            Section("Email verification") {
                SecureField("Email code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                Button("Verify email") { let entered = code; code = ""; Task { await account.verifyEmail(code: entered) } }.disabled(account.busy)
            }
        }
        if account.step == .passkey { Section { Button("Create your verified passkey") { Task { await account.enrollPasskey() } }.disabled(account.busy) } }
        if account.step == .recoveryBackup {
            Section("Recover with a linked identity and backup") {
                SecureField("Unused backup code", text: $code).textInputAutocapitalization(.never)
                Button("Create replacement passkey") { let entered = code; code = ""; Task { await account.enrollPasskey(recoveryBackup: entered) } }.disabled(account.busy)
                Text("Your existing credentials remain valid until the replacement passkey and Authenticator setup both finish.")
            }
        }
        if account.step == .authenticatorSetup || account.step == .secondFactor {
            Section("Authenticator verification") {
                if let seed = account.authenticatorSecret {
                    Text("Add this setup key to your Authenticator. It is shown only during setup.")
                    Text(seed).font(.system(.body, design: .monospaced)).textSelection(.enabled).privacySensitive()
                }
                if account.step == .secondFactor { Toggle("Use a backup code", isOn: $backup) }
                SecureField(backup ? "Backup code" : "Authenticator code", text: $code).textContentType(.oneTimeCode).privacySensitive()
                Button("Complete secure sign-in") { let entered = code; code = ""; Task { await account.complete(code: entered, useBackup: backup) } }.disabled(account.busy)
            }
        }
        if account.step != .identity { Section { Button("Cancel setup") { coordinator.cancelPendingLaunch(); account.cancelSetup(); code = "" }.disabled(account.busy) } }
    }
    private var initialProfileCheckpoint: TrainingAgeContext? {
        coordinator.directory?.profiles.isEmpty == true ? account.checkpoint : nil
    }
    private func trainingAgeForNewProfile() throws -> TrainingAgeContext {
        if let initialProfileCheckpoint { return initialProfileCheckpoint }
        guard let profileRole else { throw AccountFailure.checkpointRequired }
        return try AccountPolicy.checkpoint(ageYears: Int(age) ?? -1, role: profileRole)
    }
    @ViewBuilder private var profileSetup: some View {
        if !account.backupCodes.isEmpty {
            Section("Save your backup codes") {
                Text("Store these codes safely. Each works once after a verified passkey. Recovery also requires a linked email or Apple identity.")
                ForEach(account.backupCodes, id: \.self) { Text($0).font(.system(.body, design: .monospaced)).privacySensitive().textSelection(.enabled) }
                Button("I have saved my backup codes") { account.dismissBackupCodes() }
            }
        }
        Section("Training profile") {
            TextField("Profile name", text: $name)
            if initialProfileCheckpoint == nil {
                TextField("Training person’s age", text: $age).keyboardType(.numberPad)
                Picker("Role", selection: $profileRole) {
                    Text("Choose role").tag(nil as AccountPolicy.Role?)
                    Text("Adult self").tag(Optional(AccountPolicy.Role.adultSelf))
                    Text("Adult guardian").tag(Optional(AccountPolicy.Role.guardian))
                }.pickerStyle(.segmented)
            }
            Button("Create training profile") {
                Task {
                    do {
                        let context = try trainingAgeForNewProfile()
                        if await coordinator.createProfile(name: name, age: context) {
                            name = ""; age = ""; profileRole = nil
                        }
                    } catch { localMessage = error.localizedDescription }
                }
            }
            Text("Adults complete height and weight in profile setup. Junior measurements are optional and protected by the device owner’s authentication.")
        }
    }
}

struct AccountControlsView: View {
    let coordinator: AccountWorkspaceCoordinator
    @State private var creatingProfile = false
    @State private var confirmDelete = false
    @State private var linkEmail = ""
    @State private var revisedAge = ""
    @State private var revisedRole = AccountPolicy.Role.adultSelf
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Training profiles") {
                    ForEach(coordinator.directory?.profiles ?? []) { profile in
                        Button(profile.name.isEmpty ? "Training profile" : profile.name) { Task { await coordinator.choose(profile.id) } }
                    }
                    Button("Add a training profile") { creatingProfile = true }
                    Button("Import old phone records into this adult profile") { Task { await coordinator.importLegacy() } }
                }
                if let workspace = coordinator.visibleWorkspace {
                    Section("Age and guardian settings") {
                        Text("Changing age reviews this profile’s safety policy before another workout. Existing records stay saved.")
                        TextField("Training person’s age", text: $revisedAge).keyboardType(.numberPad)
                        Picker("Profile role", selection: $revisedRole) {
                            Text("Adult self").tag(AccountPolicy.Role.adultSelf)
                            Text("Adult guardian").tag(AccountPolicy.Role.guardian)
                        }
                        Button("Confirm age and guardian settings") {
                            Task {
                                do {
                                    let age = try AccountPolicy.checkpoint(ageYears: Int(revisedAge) ?? -1, role: revisedRole)
                                    await coordinator.updateSelectedIdentity(name: workspace.profile.profile?.name ?? "", age: age)
                                } catch { message = "Enter a valid age and guardian role." }
                            }
                        }.disabled(workspace.hasOngoingWorkout)
                    }
                }
                Section("Membership") { NavigationLink("Membership & restore purchases") { MembershipView(store: coordinator.membership) } }
                Section("Account security") {
                    TextField("Adult email to link", text: $linkEmail).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Link verified email") { Task { await coordinator.account.startEmail(email: linkEmail, purpose: .link); creatingProfile = true } }
                    Button("Link Apple identity") { Task { await coordinator.account.startApple(purpose: .link); creatingProfile = true } }
                    Button("Verify passkey and Authenticator again") { Task { await coordinator.account.login(); creatingProfile = true } }
                    Button("Sign out") {
                        coordinator.cancelPendingLaunch()
                        do { coordinator.workspace?.training.setAccountActive(false); try coordinator.workspace?.training.preservePendingWorkout(); coordinator.workspace?.suspend(); Task { await coordinator.account.signOut() } }
                        catch { message = "The paused workout could not be saved. Retry before signing out." }
                    }
                    Button("Delete online account", role: .destructive) { confirmDelete = true }
                    Text("Deletion requires recent complete MFA. Phone records and pending workouts are preserved. Export local records before removing data you want to keep.")
                }
                if let workspace = coordinator.visibleWorkspace {
                    Section("Local data export") {
                        NavigationLink("View and export this profile’s records") { LegacyAccountRecordsView(root: workspace.scope.folder) }
                    }
                }
                if let message = message ?? coordinator.message ?? coordinator.account.message { Text(message) }
            }.navigationTitle("Account and profiles")
        }
        .sheet(isPresented: $creatingProfile) { AccountSetupView(account: coordinator.account, coordinator: coordinator) }
        .confirmationDialog("Delete the online account and its cloud data?", isPresented: $confirmDelete) {
            Button("Delete online account", role: .destructive) {
                do { coordinator.workspace?.training.setAccountActive(false); try coordinator.workspace?.training.preservePendingWorkout(); Task { await coordinator.account.deleteAccount() } }
                catch { message = "The paused workout could not be saved. Retry before deleting the account." }
            }
        }
        .environment(\.profileWebsiteAccess, coordinator.websiteAccess)
    }
}

struct LegacyAccountRecordsView: View {
    let root: URL
    @State private var records: [SessionRecord] = []
    @State private var unfinishedFiles: [URL] = []
    @State private var export: URL?
    @State private var message: String?
    var body: some View {
        List {
            Text("These are existing records on this phone. Viewing or exporting them does not assign them to a new account or child.")
            ForEach(records) { record in Text(record.date.formatted(date: .abbreviated, time: .shortened)) }
            ForEach(unfinishedFiles, id: \.self) { file in
                NavigationLink(file.lastPathComponent == "pending-phone-workout.json" ? "Current unfinished workout" : "Archived unfinished workout") {
                    PendingWorkoutDataView(url: file)
                }
            }
            Button("Prepare history export") {
                do {
                    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("spottr-history.json")
                    try HistoryStore(url: root.appendingPathComponent("history.json")).export(to: url); export = url
                } catch { message = "The records could not be exported. The original file is unchanged." }
            }
            if let export { ShareLink("Share history export", item: export) }
            if let message { Text(message) }
        }.navigationTitle("Saved phone records")
            .task {
                do { unfinishedFiles = try PendingPhoneWorkout.files(in: root) } catch { message = "Unfinished snapshots could not be listed. Their files are unchanged." }
                do { records = try HistoryStore(url: root.appendingPathComponent("history.json")).load() } catch { message = "The saved file could not be read. It has not been replaced." }
            }
    }
}

struct FamilyMovementView: View {
    let workspace: AccountWorkspace
    let authorization: any NativeAccountAuthorization
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeading(title: "Family movement")
                    ProgrammeTodayCard(store: workspace.training, profileStore: workspace.profile, openSetup: {}, openLibrary: {})
                    if let quests = workspace.training.quests { QuestCardsView(store: workspace.training, quests: quests) }
                    TrainingRewardWidget(store: workspace.training, profile: workspace.profile.profile)
                    WebsiteLink(title: "NHS activity guidance for under fives", url: URL(string: "https://www.nhs.uk/live-well/exercise/physical-activity-guidelines-children-under-five-years/")!)
                }.padding()

            }.navigationTitle("Family").navigationBarTitleDisplayMode(.inline)
                .environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: workspace.profile, guardian: authorization))
        }
    }
}

private struct PendingWorkoutDataView: View {
    let url: URL
    @State private var saved: PendingPhoneWorkout?
    var body: some View {
        List {
            Text("This unfinished workout remains separate from completed history and earns no XP. Resume it in the original open session, or keep this export of its recorded quantities.")
            if let saved {
                Text(saved.record.date.formatted())
                Text(saved.exerciseID)
                if let count = saved.actualReps { LabeledContent("Current set recorded reps", value: String(count)) }
                if let seconds = saved.measuredSeconds { LabeledContent("Current set measured seconds", value: seconds.formatted()) }
                LabeledContent("Completed sets retained", value: String(saved.record.sets.count + saved.record.loggedSets.count))
            } else { Text("The saved draft is unavailable. The original file has not been changed.") }
            ShareLink("Export preserved unfinished file", item: url)
        }.navigationTitle("Unfinished workout")
            .task { saved = try? JSONDecoder().decode(PendingPhoneWorkout.self, from: Data(contentsOf: url)) }
    }
}

private struct LocalAccountArchivesView: View {
    let root: URL
    let authorization: any NativeAccountAuthorization
    @State private var scopes: [AccountDataScope] = []
    @State private var unlocked = false
    @State private var export: URL?
    @State private var message: String?
    var body: some View {
        List {
            Text("Records retained on this phone can be exported after device-owner authentication, including after online account deletion. This does not restore an online account.")
            if !unlocked {
                Button("Unlock local records") {
                    Task {
                        do { try await authorization.guardian(); scopes = try AccountLocalArchives.scopes(root: root); unlocked = true }
                        catch { message = "Local records were not unlocked. Their files are unchanged." }
                    }
                }
            } else {
                ForEach(scopes, id: \.self) { scope in
                    Section("Profile " + scope.profileID.uuidString.prefix(8)) {
                        NavigationLink("View saved records") { LegacyAccountRecordsView(root: scope.folder) }
                        Button("Prepare local profile export") {
                            do { export = try scope.exportLocalData() }
                            catch { message = "The local export could not be read. Original files are unchanged." }
                        }
                    }
                }
                if scopes.isEmpty { Text("No account profiles are stored on this phone.") }
            }
            if let export { ShareLink("Share local profile export", item: export) }
            if let message { Text(message) }
        }.navigationTitle("Retained phone records")
    }
}

private struct ProtectedLegacyRecordsView: View {
    let root: URL
    let authorization: any NativeAccountAuthorization
    @State private var unlocked = false
    @State private var message: String?
    var body: some View {
        Group {
            if unlocked { LegacyAccountRecordsView(root: root) }
            else {
                List {
                    Text("Unlock the existing records on this phone with device-owner authentication. No account import is performed.")
                    Button("Unlock existing records") {
                        Task {
                            do { try await authorization.guardian(); unlocked = true }
                            catch { message = "The records were not unlocked. Their files are unchanged." }
                        }
                    }
                    if let message { Text(message) }
                }.navigationTitle("Existing phone records")
            }
        }
    }
}

private struct AppleAccountButton: UIViewRepresentable {
    let enabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.cornerRadius = 12
        button.accessibilityIdentifier = "account-apple-sign-in"
        button.addTarget(context.coordinator, action: #selector(Coordinator.performAction), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}
