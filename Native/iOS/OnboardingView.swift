import SwiftUI

struct OnboardingView: View {
    let profileStore: NativeProfileStore
    let healthStore: HealthDataStore
    let history: [SessionRecord]
    let programme: ProgrammeStore?
    var guardianAuthorization: (any NativeAccountAuthorization)? = nil
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = TrainingSetup.Stage.body
    @State private var name: String
    @State private var goals: Set<TrainingGoal>
    @State private var weekdays: Set<Int>
    @State private var minutes: Int
    @State private var hour: Int
    @State private var support: Set<String>
    @State private var floor: Bool
    @State private var startingPoint: TrainingStartingPoint?
    @State private var answers: [ExerciseFamily: TrainingSetup.Comfort]
    @State private var expanded: Set<ExerciseFamily> = []
    @State private var measurements: LocalBodyMeasurements?
    @State private var measurementsPresented = false
    @State private var error: String?
    @State private var previewAnchor = Date.now
    @AccessibilityFocusState private var focusedFamily: ExerciseFamily?
    @AppStorage("trainer.audioEnabled") private var audioEnabled = false
    @State private var previews: VoicePreviewCoordinator
    private var playback: RemoteVoicePlayback { previews.preferences }

    init(profileStore: NativeProfileStore, healthStore: HealthDataStore? = nil,
         guardianAuthorization: (any NativeAccountAuthorization)? = nil, history: [SessionRecord] = [], programme: ProgrammeStore? = nil, onComplete: @escaping () -> Void = {}) {
        self.profileStore = profileStore; self.healthStore = healthStore ?? HealthDataStore()
        self.guardianAuthorization = guardianAuthorization; self.history = history; self.onComplete = onComplete; self.programme = programme
        _audioEnabled = AppStorage(wrappedValue: false, "trainer.audioEnabled", store: profileStore.preferencesDefaults)
        _previews = State(initialValue: VoicePreviewCoordinator(preferences: RemoteVoicePlayback(offlineOnly: true, defaults: profileStore.preferencesDefaults,
            gentleOnly: (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) < 18), permitsSelection: { profileStore.permitsPolicyCallbacks }))
        let profile = profileStore.profile
        let preferences = profile?.effectiveProgrammePreferences
        _name = State(initialValue: profile?.name ?? "")
        _goals = State(initialValue: preferences?.goals ?? [])
        _weekdays = State(initialValue: preferences?.weekdays ?? [])
        _minutes = State(initialValue: preferences?.minutesPerSession ?? 20)
        _hour = State(initialValue: preferences?.preferredLocalHour ?? 18)
        _support = State(initialValue: preferences?.availableSupport ?? [])
        _floor = State(initialValue: preferences?.allowsFloorWork ?? true)
        _startingPoint = State(initialValue: preferences?.startingPoint)
        _answers = State(initialValue: preferences?.comfortAnswers ?? [:])
        _measurements = State(initialValue: profile?.bodyMeasurements)
    }
    private var age: TrainingAgeContext? { profileStore.profile?.programmePreferences?.ageContext }
    private var adult: Bool { (age?.ageYears ?? -1) >= 18 }
    private var underFive: Bool { (age?.ageYears ?? 0) < 5 }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SetupProgressHeader(stage: stage, skip: stage.canSkip ? advance : nil)
                    .background(.white).zIndex(1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ScreenHeading(title: stage.title)
                            switch stage {
                            case .account: EmptyView()
                            case .body: bodyProfile
                            case .goals: rhythm
                            case .comfort: comfort(proxy)
                            case .permissions: PhonePermissionsView(profileStore: profileStore, healthStore: healthStore)
                            case .coach: coach
                            }
                            if let error { Text(error).foregroundStyle(Palette.red).accessibilityIdentifier("setup-error") }
                        }.padding(24).id(stage)
                    }.scrollDismissesKeyboard(.interactively).clipped()
                        .onChange(of: stage) { _, next in proxy.scrollTo(next, anchor: .top) }
                }
                VStack(spacing: 10) {
                    PrimaryButton(title: stage == .coach ? "Save my training setup" : "Continue", action: advance)
                        .accessibilityIdentifier("onboarding-continue")
                    if stage != .body {
                        Button("Back", systemImage: "arrow.left") { stage = TrainingSetup.Stage(rawValue: stage.rawValue - 1) ?? .body; error = nil }
                            .frame(minHeight: 44).buttonStyle(.bordered).tint(Palette.blue)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.background(.white).foregroundStyle(Palette.ink).tint(Palette.blue)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: stage)
                .sheet(isPresented: $measurementsPresented) {
                    MeasurementsSettingsView(measurements: measurements, isIntroduction: true, profileStore: profileStore) { measurements = $0; error = nil }
                }
        }.interactiveDismissDisabled(!AccountPolicy.setupComplete(profile: profileStore.profile))
            .onDisappear { previews.stop() }
            .onChange(of: stage) { _, _ in previews.stop() }
            .environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profileStore, guardian: guardianAuthorization))
    }
    private var bodyProfile: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Profile name", text: $name).textFieldStyle(.roundedBorder).textContentType(.givenName)
            if let age {
                Label("Age \(age.ageYears)", systemImage: "calendar").font(.headline)
                Text(age.guardianManaged ? "This profile is managed by an adult guardian." : "Your local age answer is saved with this profile.").foregroundStyle(.secondary)
            } else { Text("Return to Account and profiles to confirm this person’s age.").foregroundStyle(Palette.red) }
            MovementDemonstration(exercise: .halfSquat, isActive: !reduceMotion && !measurementsPresented)
                .frame(maxWidth: .infinity).frame(height: 170).accessibilityHidden(true)
            Text(adult ? "Confirm your height and weight to prepare your training profile." : "Measurements are optional. Your guardian can add them for growth context.")
            Button {
                Task {
                    if !adult {
                        guard let guardianAuthorization else { error = "An adult guardian must unlock measurements."; return }
                        do { try await guardianAuthorization.guardian() } catch { self.error = error.localizedDescription; return }
                    }
                    guard profileStore.permitsPolicyCallbacks else { return }
                    measurementsPresented = true
                }
            } label: {
                Label(measurements == nil ? "Add height and weight" : "Review height and weight", systemImage: "ruler").padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("onboarding-measurements")
            if let measurements {
                Text("\(measurements.heightCM.formatted()) cm and \(measurements.weightKG.formatted()) kg").font(.headline)
            }
            Text("You can change age and guardian settings in Account and profiles. Changing age reviews the safety policy before another workout.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 20) {
            TrainingGoalPicker(goals: $goals, adult: adult)
            Text("Choose your activity days").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                ForEach(1...7, id: \.self) { day in
                    Button { toggle(day, in: &weekdays); SpottrHaptics.selection() } label: {
                        Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day - 1]).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).tint(weekdays.contains(day) ? Palette.blue : Palette.muted)
                        .accessibilityValue(weekdays.contains(day) ? "Selected" : "Not selected")
                }
            }
            Text("Easier days and rest are part of your week.").font(.caption).foregroundStyle(.secondary)
            Picker("Minutes per session", selection: $minutes) { ForEach([10, 20, 30, 45], id: \.self) { Text("\($0) minutes").tag($0) } }
            Picker("Preferred time", selection: $hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            Text("Available support").font(.headline)
            ForEach(PathSurvey.equipmentChoices, id: \.self) { item in
                ChoiceCard(title: item, selected: support.contains(item), action: { toggle(item, in: &support) }) { Image(systemName: "square.dashed") }
            }
            Toggle("Floor movements are comfortable", isOn: $floor)
        }
    }
    private func comfort(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if underFive {
                Text("Start with supervised movement and play. Formal rep targets and camera assessments are not used for children under five.")
            } else {
                Text("Choose a starting point").font(.headline)
                if let startingPoint {
                    Text(startingPoint.title).font(.title3.bold()).accessibilityIdentifier("starting-point-value")
                    if let entry = ExerciseCatalog.find(["sitToStand", "halfSquat", "squat", "tempoSquat"][startingPoint.suggestedLevel - 1]) {
                        ExerciseArtwork(entry: entry).frame(height: 130).frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                } else { Text("Choose the experience that feels closest.").foregroundStyle(.secondary) }
                Slider(value: Binding(get: { Double((startingPoint?.suggestedLevel ?? 1) - 1) }, set: {
                    let next = TrainingStartingPoint.allCases[min(3, max(0, Int($0.rounded())))]
                    if startingPoint != next { startingPoint = next; SpottrHaptics.selection() }
                }), in: 0...3, step: 1).accessibilityLabel("Starting point").accessibilityValue(startingPoint?.title ?? "Not answered")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) {
                    ForEach(TrainingStartingPoint.allCases, id: \.self) { point in
                        Button(point.title) { startingPoint = point; SpottrHaptics.selection() }.buttonStyle(.bordered)
                            .tint(startingPoint == point ? Palette.blue : Palette.muted)
                    }
                }
                Text("Choose a comfortable movement in each family. Not sure yet is a useful answer.").foregroundStyle(.secondary)
                ForEach(ExerciseFamily.allCases, id: \.self) { family in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(family.title).font(.title3.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($focusedFamily, equals: family)
                        let choices = comfortChoices(family)
                        ForEach(Array(choices.prefix(expanded.contains(family) ? choices.count : 3)), id: \.id) { entry in
                            ChoiceCard(title: entry.name, selected: answers[family] == .movement(entry.id), action: { answer(.movement(entry.id), family: family, proxy: proxy) }) { ExerciseArtwork(entry: entry) }
                                .accessibilityIdentifier("comfortable-\(entry.id)")
                        }
                        ChoiceCard(title: "Not sure yet", detail: "Start gently and explore with support.", selected: answers[family] == .unsure,
                                   action: { answer(.unsure, family: family, proxy: proxy) }) { Image(systemName: "questionmark.circle") }
                            .accessibilityIdentifier("comfortable-unsure-\(family.rawValue)")
                        if choices.count > 3 {
                            Button(expanded.contains(family) ? "Fewer variations" : "More variations", systemImage: "slider.horizontal.3") { toggle(family, in: &expanded) }.buttonStyle(.bordered).frame(minHeight: 44)
                        }
                    }.id(family)
                }
                Text("These answers help place your starting point. They do not add recorded sets or XP.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var coach: some View {
        VStack(alignment: .leading, spacing: 20) {
            VoicePreviewControls(previews: previews)
            TrainerSelection(onSelect: { voice in preview(voice, tone: adult ? playback.tone : .gentle) },
                gentleOnly: !adult, onToneSelect: { tone in preview(playback.preference, tone: tone) }, defaults: profileStore.preferencesDefaults)
            Toggle("Voice feedback during workouts", isOn: $audioEnabled)
            Text("Your prepared week").font(.title3.bold())
            if let profile = try? candidate(), let week = try? preparedWeek(profile) {
                if let next = week.days.first(where: { $0.plan != nil }), let plan = next.plan {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next practice on \(next.date.formatted(.dateTime.weekday(.wide)))").font(.headline)
                        Text(plan.items.compactMap { ExerciseCatalog.find($0.exerciseID)?.name }.joined(separator: ", "))
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                ForEach(week.days) { day in
                    HStack(alignment: .top, spacing: 12) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated))).fontWeight(.semibold).frame(minWidth: 44, alignment: .leading)
                        Text(day.kind == .rest ? "Rest" : day.kind == .recovery ? "Easier movement" : day.kind == .familyMovement ? "Family movement and play" : "Practice")
                        Spacer(minLength: 0)
                    }.font(.subheadline)
                }
                Text("Adjust your week whenever you need. Rest days are part of your plan.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Review your days and available support to prepare a week.").foregroundStyle(.secondary) }
        }
    }
    private func preparedWeek(_ profile: LocalProfile) throws -> TrainingProgramme {
        if let programme { return try programme.preview(profile: profile, history: history, at: previewAnchor) }
        return try ProgrammePlanner.makeWeek(profile: profile, history: history, start: previewAnchor)
    }
    private func preview(_ voice: VoiceCoachPreference, tone: TrainerTone) {
        previews.select(voice, tone: tone)
    }
    private func preferences() throws -> ProgrammePreferences {
        try ProgrammePreferences(goals: goals, weekdays: weekdays, minutesPerSession: minutes, preferredLocalHour: hour,
            availableSupport: support, allowsFloorWork: floor,
            excludedExerciseIDs: profileStore.profile?.programmePreferences?.excludedExerciseIDs ?? [],
            startingPoint: startingPoint, ageContext: age, comfortAnswers: answers)
    }
    private func candidate() throws -> LocalProfile {
        let prefs = try preferences()
        let legacyGoals = Set(goals.compactMap { TrainingAttribute(rawValue: $0.rawValue) })
        return try LocalProfile(name: name, weeklyTarget: weekdays.count, goals: legacyGoals.isEmpty ? profileStore.profile?.goals ?? [.stamina] : legacyGoals,
            baselineAbility: startingPoint.flatMap { LocalProfile.BaselineAbility(rawValue: $0.rawValue) }, bodyMeasurements: measurements,
            comfortableExercises: Set(answers.values.compactMap { if case .movement(let id) = $0 { return id }; return nil }),
            weightManagementGoal: goals.contains(.weightManagement), onboardingRevision: TrainingSetup.revision, programmePreferences: prefs)
    }
    private func advance() {
        error = nil
        guard age != nil else { error = "Confirm this person’s age in Account and profiles."; return }
        if stage == .body && adult && measurements == nil { error = "Enter your height and weight to continue."; return }
        if stage == .goals && (goals.isEmpty || weekdays.isEmpty) { error = "Choose at least one goal and activity day."; return }
        if stage == .comfort && !underFive {
            guard startingPoint != nil, let prefs = try? preferences(), TrainingSetup.comfortComplete(prefs) else { error = "Choose your starting point and answer each movement family. Not sure yet is valid."; return }
        }
        if stage != .coach { stage = TrainingSetup.Stage(rawValue: stage.rawValue + 1) ?? .coach; SpottrHaptics.selection(); return }
        do {
            let profile = try candidate()
            guard AccountPolicy.setupComplete(profile: profile) else { error = "Complete the required profile and movement choices first."; return }
            let week = try preparedWeek(profile)
            try programme?.acceptPreview(week, profile: profile)
            try profileStore.save(profile); SpottrHaptics.success(); onComplete(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func comfortChoices(_ family: ExerciseFamily) -> [ExerciseEntry] {
        guard let prefs = try? preferences() else { return [] }
        return ExerciseCatalog.all.filter { $0.family == family && prefs.canUse($0) }.sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
    }
    private func answer(_ answer: TrainingSetup.Comfort, family: ExerciseFamily, proxy: ScrollViewProxy) {
        answers[family] = answer
        guard let next = TrainingSetup.nextUnanswered(answers) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(next, anchor: .top) }
        focusedFamily = next
    }
    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) { if set.contains(value) { set.remove(value) } else { set.insert(value) } }
}

extension TrainingStartingPoint {
    var title: String {
        switch self { case .startingOut: "Starting out"; case .somePractice: "Some practice"; case .regularPractice: "Regular practice"; case .experienced: "Experienced" }
    }
}
struct TrainingGoalPicker: View {
    @Binding var goals: Set<TrainingGoal>
    var adult = true
    var body: some View {
        VStack(spacing: 12) {
            ForEach(TrainingGoal.allCases.filter { adult || $0 != .weightManagement }, id: \.self) { goal in
                ChoiceCard(title: goal.title, selected: goals.contains(goal), action: {
                    if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                }) { GoalGlyph(goal: goal) }.accessibilityIdentifier("goal-\(goal.rawValue)")
            }
        }
    }
}
struct ProfileGoalPicker: View {
    @Binding var goals: Set<TrainingAttribute>
    var body: some View {
        TrainingGoalPicker(goals: Binding(get: { Set(goals.compactMap { TrainingGoal(rawValue: $0.rawValue) }) },
                                         set: { goals = Set($0.compactMap { TrainingAttribute(rawValue: $0.rawValue) }) }), adult: false)
    }
}

struct ProfileWeeklyTarget: View {
    @Binding var target: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Stepper(value: $target, in: 1...7) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly target").font(.subheadline.weight(.medium))
                    Text("\(target) training \(target == 1 ? "day" : "days")").font(.title3.weight(.semibold))
                }
            }.accessibilityIdentifier("weekly-training-target")
            Text("Leave room for rest. This is a plan, not a completed workout.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
