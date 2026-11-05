import SwiftUI

struct SpottrRoot: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    let workspace: PreviewWorkspace?
    @State private var introductionPresented: Bool
    @State private var settingsPresented = false
    @State private var selectedTab = "today"
    @State private var healthStore = HealthDataStore()

    init(store: TrainingStore, profileStore: NativeProfileStore, workspace: PreviewWorkspace? = nil) {
        self.store = store
        self.profileStore = profileStore
        self.workspace = workspace
        _introductionPresented = State(initialValue: profileStore.shouldShowIntroduction())
    }

    var body: some View {
        Group {
            if introductionPresented {
                OnboardingView(profileStore: profileStore, healthStore: healthStore) {
                    store.remoteVoice?.reloadPreferences()
                    store.repVoice.choose(RepVoicePlan.Coach(rawValue: UserDefaults.standard.string(forKey: RepVoicePlayer.defaultsKey) ?? "off"))
                    store.setVoiceFeedback(UserDefaults.standard.bool(forKey: "trainer.audioEnabled"))
                    introductionPresented = false
                }
            } else {
                TabView(selection: $selectedTab) {
                    TodayView(store: store, profileStore: profileStore, showSettings: { settingsPresented = true },
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
            store.repVoice.choose(RepVoicePlan.Coach(rawValue: UserDefaults.standard.string(forKey: RepVoicePlayer.defaultsKey) ?? "off"))
            if profileStore.profile == nil { introductionPresented = profileStore.shouldShowIntroduction() }
        }) {
            ProfileSettingsView(profileStore: profileStore, history: store.history,
                                exportData: store.exportHistory, resetHistory: store.clearHistory, rewards: store.rewards,
                                historyAvailable: store.historyAvailable, workspace: workspace, healthStore: healthStore)
        }
        .foregroundStyle(Palette.ink)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(greeting).font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("Choose your movement. Start at your own pace.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    nextSession
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
                    watchSetup
                    Button { rewardsPresented = true } label: {
                        Label("Training rewards & streaks", systemImage: "flame")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue)
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
                        Button(action: showSettings) { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Profile and settings").accessibilityIdentifier("profile-settings")
                    }
                }
        }
        .sheet(isPresented: $libraryPresented) { ExerciseLibraryView(store: store) }
        .sheet(isPresented: $rewardsPresented) { TrainingRewardsSettingsView(store: store.rewards) }
    }

    private var nextSession: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready when you are").font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.selectedExercise.title).font(.system(size: 28, weight: .bold)).tracking(-0.7)
                        .accessibilityIdentifier("today-selected-exercise")
                    Text("Start with this movement. Target \(store.selectedExercise.target) reps per set; stop when you need to.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                StickFigureArtwork(exercise: store.selectedExercise).frame(width: 90, height: 120).accessibilityHidden(true)
            }
            PrimaryButton(title: "Start session", action: store.start).accessibilityIdentifier("today-start-session")
            HStack(spacing: 18) {
                ForEach([Exercise.squat, .pushup], id: \.self) { exercise in
                    Button { store.selectedExercise = exercise } label: {
                        Label(exercise.title, systemImage: store.selectedExercise == exercise ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold)).padding(.vertical, 8)
                    }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                        .accessibilityLabel("Start with \(exercise.title)")
                }
            }
            Button { libraryPresented = true } label: {
                Label("Choose from the exercise library", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold)).padding(.vertical, 5)
            }.buttonStyle(.plain).foregroundStyle(Palette.blue).accessibilityIdentifier("today-library")
        }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
    }

    private var weeklyRhythm: some View {
        let dashboard = TrainingDashboard(history: store.history, now: .now, calendar: store.rewards.ledger.calendar)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your week, recorded").font(.headline)
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
                Text("\(dashboard.sessionCount) sessions · \(dashboard.totalSets) sets · \(dashboard.totalReps) reps")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Saved activity only. Video reviews don’t count as training days.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Saved history could not be read. Your weekly totals are unavailable.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("today-weekly-rhythm")
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

    private var watchSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "applewatch").font(.title2).foregroundStyle(Palette.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Watch, optional").font(.headline)
                    Text(store.watchReachable ? "Companion reachable now" : "Companion not reachable now")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Phone training works on its own. Open setup to install the companion and check your connection.")
                .font(.caption).foregroundStyle(.secondary)
            NavigationLink("Watch setup") { WatchSetupView() }
                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("today-watch-setup")
            if let healthStore {
                NavigationLink("Optional Health history & heart-rate zones") { HealthSetupView(store: healthStore) }
                    .font(.subheadline).accessibilityIdentifier("today-health-setup")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var greeting: String {
        let name = profileStore.profile?.name ?? ""
        return name.isEmpty ? "A little movement today." : "Ready when you are, \(name)."
    }
}
