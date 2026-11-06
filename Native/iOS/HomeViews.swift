import SwiftUI

struct SpottrRoot: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    let workspace: PreviewWorkspace?
    @State private var introductionPresented: Bool
    @State private var settingsPresented = false
    @State private var selectedTab = "today"
    private let healthStore: HealthDataStore
    let membership: MembershipStore?
    let guardianAuthorization: (any NativeAccountAuthorization)?

    init(store: TrainingStore, profileStore: NativeProfileStore, workspace: PreviewWorkspace? = nil, healthStore: HealthDataStore? = nil, guardianAuthorization: (any NativeAccountAuthorization)? = nil, membership: MembershipStore? = nil) {
        self.membership = membership
        self.store = store
        self.profileStore = profileStore
        self.workspace = workspace
        self.guardianAuthorization = guardianAuthorization
        self.healthStore = healthStore ?? HealthDataStore()
        _introductionPresented = State(initialValue: profileStore.shouldShowIntroduction())
    }

    var body: some View {
        Group {
            if introductionPresented {
                OnboardingView(profileStore: profileStore, healthStore: healthStore, guardianAuthorization: guardianAuthorization, history: store.history, programme: store.programme) {
                    store.remoteVoice?.reloadPreferences()
                    store.repVoice.choose(store.remoteVoice?.gentleOnly == true ? nil : RepVoicePlan.Coach(rawValue: profileStore.preferencesDefaults.string(forKey: RepVoicePlayer.defaultsKey) ?? "off"))
                    store.setVoiceFeedback(profileStore.preferencesDefaults.bool(forKey: "trainer.audioEnabled"))
                    introductionPresented = false
                }
            } else {
                TabView(selection: $selectedTab) {
                    TodayView(store: store, profileStore: profileStore, showSettings: { Task {
                                  if profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0 < 18 {
                                      guard let guardianAuthorization else { return }
                                      do { try await guardianAuthorization.guardian() } catch { return }
                                  }
                                  settingsPresented = true
                              } },
                              openPath: { selectedTab = "skills" }, healthStore: healthStore)
                        .tabItem { Label("Today", systemImage: "house") }.tag("today")
                    PathSkillsView(store: store, profile: profileStore.profile)
                        .tabItem { Label("Skills", systemImage: "point.3.connected.trianglepath.dotted") }.tag("skills")
                    InsightsView(store: store, profile: profileStore.profile, healthStore: healthStore)
                        .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }.tag("insights")
                    OfflineCoachView(store: store, profile: profileStore.profile)
                        .tabItem { Label("Coach", systemImage: "bubble") }.tag("coach")
                }
            }
        }
        .fullScreenCover(isPresented: $store.presented) { SessionView(store: store).interactiveDismissDisabled() }
        .sheet(isPresented: $settingsPresented, onDismiss: {
            store.remoteVoice?.reloadPreferences()
            store.repVoice.choose(store.remoteVoice?.gentleOnly == true ? nil : RepVoicePlan.Coach(rawValue: profileStore.preferencesDefaults.string(forKey: RepVoicePlayer.defaultsKey) ?? "off"))
            store.setVoiceFeedback(profileStore.preferencesDefaults.bool(forKey: "trainer.audioEnabled"))
            if profileStore.profile == nil { introductionPresented = profileStore.shouldShowIntroduction() }
        }) {
            ProfileSettingsView(profileStore: profileStore, history: store.history,
                                exportData: store.exportHistory, resetHistory: store.clearHistory, rewards: store.rewards.allowsTimePressureRewards ? store.rewards : nil,
                                historyAvailable: store.historyAvailable, workspace: workspace, healthStore: healthStore, membership: membership, guardianAuthorization: guardianAuthorization)
        }
        .sheet(isPresented: Binding(get: { store.launchCoordinator?.needsAttention == true && [WorkoutLaunchOrigin.today, .url, .watch].contains { $0 == store.launchCoordinator?.pendingOrigin } }, set: { if !$0 { store.launchCoordinator?.cancel() } })) {
            if let launch = store.launchCoordinator { WorkoutLaunchAccessView(launch: launch) }
        }
        .environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profileStore, guardian: guardianAuthorization))
        .foregroundStyle(Palette.ink)
        .id(ObjectIdentifier(store))
    }
}

struct TodayView: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    let showSettings: () -> Void
    var openPath: () -> Void = {}
    var healthStore: HealthDataStore? = nil
    @State private var libraryPresented = false
    @State private var rewardsPresented = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.caption).foregroundStyle(.secondary)
                        ScreenHeading(title: greeting)
                    }
                    ProgrammeTodayCard(store: store, profileStore: profileStore, openSetup: showSettings, openLibrary: { libraryPresented = true })
                    Button(action: openPath) {
                        Label("Explore your next skill", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue).accessibilityIdentifier("first-session-path")
                    if let warning = store.archiveDataWarning {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Watch sync needs attention", systemImage: "applewatch").font(.subheadline.weight(.semibold))
                            Text(warning).font(.caption).foregroundStyle(.secondary)
                            Button("Retry Watch sync") { store.retryWatchArchive() }
                                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("today-retry-watch-sync")
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    weeklyRhythm
                    recentReport
                    if store.rewards.allowsTimePressureRewards {
                    Button { rewardsPresented = true } label: {
                        Label("Training rewards & streaks", systemImage: "flame")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                    }
                    if store.previewMode {
                        Label("Preview history is synthetic and stored separately.", systemImage: "play.rectangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                }.padding(24)
            }.background(.white)
                .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: showSettings) { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Profile and settings").accessibilityIdentifier("profile-settings")
                    }
                }
        }
        .sheet(isPresented: $libraryPresented) { ExerciseLibraryView(store: store) }
        .sheet(isPresented: $rewardsPresented) { TrainingRewardsSettingsView(store: store.rewards) }
    }

    private var weeklyRhythm: some View {
        let dashboard = TrainingDashboard(history: store.history, now: .now, calendar: store.rewards.ledger.calendar)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your week").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if store.historyAvailable {
                Text("\(dashboard.trainingDays) / \(profileStore.profile?.weeklyTarget ?? 3) training days this week")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(dashboard.days) { day in
                        VStack(spacing: 9) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                            Image(systemName: day.setCount > 0 ? "checkmark" : "minus")
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(day.setCount > 0 ? .white : Palette.muted)
                                .background(day.setCount > 0 ? Palette.blue : Palette.surface, in: Circle())
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(day.setCount) recorded sets")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { weeklyTotals(dashboard) }
                    VStack(alignment: .leading, spacing: 12) { weeklyTotals(dashboard) }
                }
            } else {
                Text("Saved history could not be read. Your weekly totals are unavailable.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("today-weekly-rhythm")
    }

    @ViewBuilder private func weeklyTotals(_ dashboard: TrainingDashboard) -> some View {
        Text("\(dashboard.sessionCount) sessions")
        Text("\(dashboard.totalSets) sets")
        Text("\(dashboard.totalReps) reps")
    }

    @ViewBuilder private var recentReport: some View {
        let dashboard = TrainingDashboard(history: store.history, now: .now, calendar: store.rewards.ledger.calendar)
        if let record = dashboard.latestRecord, store.historyAvailable {
            let report = WorkoutReport(record: record)
            VStack(alignment: .leading, spacing: 12) {
                Text("Your latest session").font(.headline)
                NavigationLink {
                    SessionReportView(record: record, profile: profileStore.profile, history: store.history,
                                      previewEnabled: store.previewMode, zones: healthStore?.zones)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(report.category.rawValue).font(.headline)
                            Text("\(report.setCount) sets · \(report.reps) reps").font(.subheadline)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("today-recent-report")
            }
        }
    }


    private var greeting: String {
        let name = profileStore.profile?.name ?? ""
        return name.isEmpty ? "A little movement today" : "Ready when you are, \(name)"
    }
}
