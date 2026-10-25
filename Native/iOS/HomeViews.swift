import SwiftUI

struct SpottrRoot: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    @State private var introductionPresented: Bool
    @State private var settingsPresented = false

    init(store: TrainingStore, profileStore: NativeProfileStore) {
        self.store = store
        self.profileStore = profileStore
        _introductionPresented = State(initialValue: profileStore.shouldShowIntroduction())
    }

    var body: some View {
        Group {
            if introductionPresented {
                OnboardingView(profileStore: profileStore) { introductionPresented = false }
            } else {
                TabView {
                    TodayView(store: store, profileStore: profileStore) { settingsPresented = true }
                        .tabItem { Label("Today", systemImage: "house") }
                    WeeklyProgressView(store: store, profile: profileStore.profile).tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                    PathSkillsView(store: store, profile: profileStore.profile).tabItem { Label("Skills", systemImage: "point.3.connected.trianglepath.dotted") }
                    CoachView(store: store, profile: profileStore.profile).tabItem { Label("Coach", systemImage: "bubble") }
                }
            }
        }
        .fullScreenCover(isPresented: $store.presented) { SessionView(store: store).interactiveDismissDisabled() }
        .sheet(isPresented: $settingsPresented, onDismiss: {
            if profileStore.profile == nil { introductionPresented = profileStore.shouldShowIntroduction() }
        }) {
            ProfileSettingsView(profileStore: profileStore, history: store.history,
                                exportData: store.exportHistory, resetHistory: store.clearHistory, rewards: store.rewards,
                                historyAvailable: store.historyAvailable)
        }
        .foregroundStyle(Palette.ink)
    }
}

struct TodayView: View {
    @Bindable var store: TrainingStore
    let profileStore: NativeProfileStore
    let showSettings: () -> Void
    @State private var libraryPresented = false
    @State private var rewardsPresented = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text("Spottr").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1.2)
                    Spacer()
                    Button(action: showSettings) {
                        Image(systemName: "person.crop.circle").font(.title3).padding(12).background(Palette.surface, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Profile and settings").accessibilityIdentifier("profile-settings")
                }.padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 9) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.caption).foregroundStyle(.secondary)
                    Text(greeting).font(.system(size: 32, weight: .bold)).tracking(-1)
                }
                trainingRhythm
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image("strength").resizable().scaledToFit().frame(width: 27, height: 27)
                        Text("Strength").font(.caption.weight(.semibold))
                    }
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Build your\nfoundation.").font(.system(size: 27, weight: .bold)).tracking(-0.8)
                            HStack(spacing: 14) {
                                Label("12 min", systemImage: "clock")
                                Label("6 sets", systemImage: "square.3.layers.3d")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image("\(store.selectedExercise.rawValue)-mid").resizable().scaledToFit().frame(width: 116, height: 155)
                    }
                    PrimaryButton(title: "Start session", action: store.start)
                }.padding(21).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
                HStack { Text("Your session").font(.headline); Spacer(); Text("Bodyweight").font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    ForEach(Exercise.allCases, id: \.self) { exercise in
                        Button { store.selectedExercise = exercise } label: {
                            HStack(spacing: 14) {
                                Image("\(exercise.rawValue)-mid").resizable().scaledToFit().frame(width: 42, height: 47)
                                    .padding(6).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.title).font(.subheadline.weight(.semibold))
                                    Text("3 sets × \(exercise.target) reps").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: store.selectedExercise == exercise ? "checkmark.circle.fill" : "circle").font(.body)
                            }.padding(.vertical, 15).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Start with \(exercise.title)")
                        Divider()
                    }
                }
                Button { libraryPresented = true } label: {
                    Label("Exercise library", systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                Label("Keep your rhythm.", systemImage: "applewatch").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }.padding(24)
        }.background(.white).sheet(isPresented: $libraryPresented) { ExerciseLibraryView(store: store) }
            .sheet(isPresented: $rewardsPresented) { TrainingRewardsSettingsView(store: store.rewards) }
    }

    private var greeting: String {
        let name = profileStore.profile?.name ?? ""
        return name.isEmpty ? "Let’s get to work." : "Let’s get to work, \(name)."
    }

    private var trainingRhythm: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let summary = StreakSummary(history: store.history, now: timeline.date, calendar: store.rewards.ledger.calendar)
            VStack(alignment: .leading, spacing: 0) {
                if let issue = store.rewards.loadError ?? (store.historyAvailable ? nil : "Your saved sessions couldn’t be read. Training rewards haven’t been changed.") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Training rewards unavailable").font(.headline)
                        Text(issue).font(.caption).foregroundStyle(.secondary)
                        if store.historyAvailable {
                            Text("\(summary.daysThisWeek) / \(profileStore.profile?.weeklyTarget ?? 3) training days this week")
                                .font(.caption)
                        }
                    }.padding(18)
                } else {
                    let rewards = store.rewards.summary(history: store.history, at: timeline.date)
                    let progress = SkillProgress.evaluate(history: store.history, calendar: store.rewards.ledger.calendar)
                    let baseXP = TrainingAttribute.allCases.reduce(0) { $0 + progress.points(for: $1) }
                    let totalXP = store.rewards.totalXP(history: store.history)
                    StreakCard(protectedStreak: rewards.protectedStreak, actualTrainingDays: rewards.actualTrainingDays,
                               trainedToday: rewards.trainedToday, remainingFreezes: rewards.remainingFreezes,
                               trainingDaysThisWeek: summary.daysThisWeek, weeklyTarget: profileStore.profile?.weeklyTarget ?? 3,
                               baseXP: baseXP, bonusXP: max(0, totalXP - baseXP), totalXP: totalXP,
                               onManage: { rewardsPresented = true })
                }
                if let profile = profileStore.profile {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 9) {
                        ForEach(TrainingAttribute.allCases.filter { profile.goals.contains($0) }, id: \.self) { goal in
                            HStack(spacing: 7) {
                                Image(goal.rawValue).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                                Text(goal.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 18)
                }
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .task(id: store.rewards.ledger.calendar.startOfDay(for: timeline.date)) { store.refreshRewards(at: timeline.date) }
        }
    }
}
