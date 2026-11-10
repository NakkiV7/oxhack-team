import SwiftUI

struct OnboardingView: View {
    let profileStore: NativeProfileStore
    let healthStore: HealthDataStore
    let history: [SessionRecord]
    let programme: ProgrammeStore?
    let analytics: ConsentedAnalyticsStore?
    var guardianAuthorization: (any NativeAccountAuthorization)? = nil
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentation: TrainingSetupPresentation
    @State private var name: String
    @State private var expanded: Set<ExerciseFamily> = []
    @State private var measurements: LocalBodyMeasurements?
    @State private var measurementsPresented = false
    @State private var error: String?
    @State private var previewAnchor = Date.now
    @AccessibilityFocusState private var focusedHeading: Bool
    @AccessibilityFocusState private var focusedError: Bool
    @AppStorage("trainer.audioEnabled") private var audioEnabled = false
    @State var previews: VoicePreviewCoordinator
    private var playback: RemoteVoicePlayback { previews.preferences }

    init(profileStore: NativeProfileStore, healthStore: HealthDataStore? = nil,
         guardianAuthorization: (any NativeAccountAuthorization)? = nil, history: [SessionRecord] = [], programme: ProgrammeStore? = nil, analytics: ConsentedAnalyticsStore? = nil, voicePreviews: VoicePreviewCoordinator? = nil, onComplete: @escaping () -> Void = {}) {
        self.profileStore = profileStore; self.healthStore = healthStore ?? HealthDataStore()
        self.guardianAuthorization = guardianAuthorization; self.history = history; self.onComplete = onComplete; self.programme = programme
        self.analytics = analytics
        _audioEnabled = AppStorage(wrappedValue: false, "trainer.audioEnabled", store: profileStore.preferencesDefaults)
        _previews = State(initialValue: voicePreviews ?? VoicePreviewCoordinator(preferences: RemoteVoicePlayback(offlineOnly: true, defaults: profileStore.preferencesDefaults,
            gentleOnly: (profileStore.profile?.programmePreferences?.ageContext?.ageYears ?? 0) < 18), permitsSelection: { profileStore.permitsPolicyCallbacks }, canPreview: { false }))
        let profile = profileStore.profile
        _presentation = State(initialValue: TrainingSetupPresentation(preferences: profile?.effectiveProgrammePreferences, hasAnalytics: analytics != nil))
        _name = State(initialValue: profile?.name ?? "")
        _measurements = State(initialValue: profile?.bodyMeasurements)
    }
    private var age: TrainingAgeContext? { profileStore.profile?.programmePreferences?.ageContext }
    private var adult: Bool { (age?.ageYears ?? -1) >= 18 }
    private var underFive: Bool { (age?.ageYears ?? 0) < 5 }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SetupProgressHeader(stage: presentation.stage, skip: presentation.stage.canSkip ? advance : nil)
                    .background(.white).zIndex(1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ScreenHeading(title: presentation.title).accessibilityFocused($focusedHeading)
                            switch presentation.stage {
                            case .account: accountPrivacy
                            case .body: bodyProfile
                            case .goals:
                                TrainingRhythmContent(step: presentation.rhythmStep, goals: $presentation.goals,
                                    weekdays: $presentation.weekdays, minutes: $presentation.minutes, hour: $presentation.hour,
                                    support: $presentation.support, floor: $presentation.floor, adult: adult)
                            case .comfort: comfort
                            case .permissions: PhonePermissionsView(profileStore: profileStore, healthStore: healthStore)
                            case .coach: coach
                            }
                        }.padding(24).id(presentation.pageID)
                    }.scrollDismissesKeyboard(.interactively).clipped()
                        .onChange(of: presentation.pageID) { _, next in
                            proxy.scrollTo(next, anchor: .top)
                            focusedHeading = true
                        }
                }
                VStack(spacing: 10) {
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(Palette.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("setup-error").accessibilityFocused($focusedError)
                    }
                    PrimaryButton(title: presentation.stage == .coach ? "Save my training setup" : "Continue", action: advance)
                        .accessibilityIdentifier("onboarding-continue")
                    if presentation.canGoBack {
                        Button("Back", systemImage: "arrow.left") { presentation.goBack(); error = nil; SpottrHaptics.selection() }
                            .frame(minHeight: 44).buttonStyle(.bordered).tint(Palette.blue)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.background(.white).foregroundStyle(Palette.ink).tint(Palette.blue)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: presentation.pageID)
                .sheet(isPresented: $measurementsPresented) {
                    MeasurementsSettingsView(measurements: measurements, isIntroduction: true, profileStore: profileStore) { measurements = $0; error = nil }
                }
        }.interactiveDismissDisabled(!AccountPolicy.setupComplete(profile: profileStore.profile))
            .onDisappear { previews.stop() }
            .onChange(of: presentation.stage) { _, _ in previews.stop() }
            .onChange(of: error) { _, value in focusedError = value != nil }
            .environment(\.profileWebsiteAccess, ProfileWebsiteAccess(profile: profileStore, guardian: guardianAuthorization))
    }
    private var accountPrivacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(adult ? "Choose what you share" : "Your practice stays private", systemImage: "lock.shield")
                .font(.headline)
            Text(adult ? "Both choices are optional. Continue with them off if you prefer." : "A guardian manages this profile. Your progress stays with your profile and paired devices.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let analytics { AnalyticsConsentChoices(store: analytics, compact: true) }
            WebsiteLink(title: "Privacy policy", url: URL(string: AccountClient.origin + "/privacy/")!)
            DisclosureGroup("Sharing details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your personal reports use your saved records. Change sharing later in Privacy and statistics.")
                    Text("Turning a choice off clears its unsent data. A later opt-in does not upload earlier workouts.")
                    Text("No account identifier, age, body measurements, raw Health data, precise workout time, video or audio is sent. A temporary weekly installation tag helps count contributions and is not a guarantee of anonymity.")
                    Text("Every published bucket needs at least ten contributing installations. Already combined summaries cannot be traced back to your account for removal.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.frame(minHeight: 44)
        }
    }
    private var bodyProfile: some View {
        VStack(alignment: .leading, spacing: 18) {
            MovementDemonstration(exercise: .halfSquat, isActive: !reduceMotion && !measurementsPresented)
                .frame(maxWidth: .infinity).frame(height: 150).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                TextField("Profile name", text: $name).textFieldStyle(.roundedBorder).textContentType(.givenName)
                    .frame(minHeight: 44)
                Text(adult ? "Confirm your height and weight to prepare your training profile." : "Measurements are optional. Your guardian can add them for growth context.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                    Label(measurements == nil ? "Add height and weight" : "Review height and weight", systemImage: "ruler")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.bordered).accessibilityIdentifier("onboarding-measurements")
                if let measurements {
                    Text("\(measurements.heightCM.formatted()) cm and \(measurements.weightKG.formatted()) kg").font(.headline)
                }
            }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            if age == nil { Text("Return to Account and profiles to confirm this person’s age.").foregroundStyle(Palette.red) }
            DisclosureGroup("Profile details") {
                VStack(alignment: .leading, spacing: 10) {
                    if let age {
                        Label("Age \(age.ageYears)", systemImage: "calendar")
                        Text(age.guardianManaged ? "This profile is managed by an adult guardian." : "Your local age answer is saved with this profile.")
                    }
                    Text("Change age and guardian settings in Account and profiles. Changing age reviews the safety policy before another workout.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.frame(minHeight: 44)
        }
    }
    @ViewBuilder private var comfort: some View {
        if underFive {
            Text("Start with supervised movement and play. Formal rep targets and camera assessments are not used for children under five.")
        } else {
            switch presentation.comfortStep {
            case .startingPoint:
                TrainingStartingPointChoices(selection: $presentation.startingPoint)
            case .family(let family):
                TrainingComfortFamily(family: family, choices: comfortChoices(family), answer: presentation.answers[family],
                    expanded: expanded.contains(family), onExpand: { toggle(family, in: &expanded) },
                    onAnswer: { value in presentation.answer(value, family: family); error = nil })
                if !presentation.answers.isEmpty {
                    DisclosureGroup("Review earlier choices") {
                        TrainingComfortReview(answers: presentation.answers, onChange: changeFamily)
                    }.frame(minHeight: 44)
                }
            case .review:
                Text("Your starting point is ready. Change any choice before you continue.").font(.subheadline).foregroundStyle(.secondary)
                TrainingComfortReview(answers: presentation.answers, onChange: changeFamily)
                Button("Change starting point", systemImage: "slider.horizontal.3") { presentation.changeStartingPoint(); SpottrHaptics.selection() }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
            Text("These choices do not add recorded sets or XP.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func changeFamily(_ family: ExerciseFamily) {
        presentation.review(family); error = nil; SpottrHaptics.selection()
    }
    private var coach: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let profile = try? candidate(), let week = try? preparedWeek(profile) {
                TrainingWeekPreview(week: week)
            } else { Text("Review your days and available support to prepare a week.").foregroundStyle(.secondary) }
            Toggle("Voice feedback during workouts", isOn: $audioEnabled)
            DisclosureGroup("Preview and choose my coach") {
                VStack(alignment: .leading, spacing: 16) {
                    VoicePreviewControls(previews: previews)
                    TrainerSelection(onSelect: { voice in preview(voice, tone: adult ? playback.tone : .gentle) },
                        gentleOnly: !adult, onToneSelect: { tone in preview(playback.preference, tone: tone) }, defaults: profileStore.preferencesDefaults)
                }.padding(.top, 8)
            }.frame(minHeight: 44)
            HStack(spacing: 14) {
                TrainerPortrait(voice: playback.preference).frame(width: 48, height: 48)
                Text(playback.preference.title).font(.headline)
            }.accessibilityElement(children: .combine).accessibilityLabel("Selected coach \(playback.preference.title)")
        }
    }
    private func preparedWeek(_ profile: LocalProfile) throws -> TrainingProgramme {
        if let programme { return try programme.preview(profile: profile, history: history, at: previewAnchor) }
        return try ProgrammePlanner.makeWeek(profile: profile, history: history, start: previewAnchor)
    }
    private func preview(_ voice: VoiceCoachPreference, tone: TrainerTone) { previews.select(voice, tone: tone) }
    private func preferences() throws -> ProgrammePreferences {
        try presentation.preferences(age: age, excludedExerciseIDs: profileStore.profile?.programmePreferences?.excludedExerciseIDs ?? [])
    }
    private func candidate() throws -> LocalProfile {
        let prefs = try preferences()
        let legacyGoals = Set(presentation.goals.compactMap { TrainingAttribute(rawValue: $0.rawValue) })
        return try LocalProfile(name: name, weeklyTarget: presentation.weekdays.count, goals: legacyGoals.isEmpty ? profileStore.profile?.goals ?? [.stamina] : legacyGoals,
            baselineAbility: presentation.startingPoint.flatMap { LocalProfile.BaselineAbility(rawValue: $0.rawValue) }, bodyMeasurements: measurements,
            comfortableExercises: Set(presentation.answers.values.compactMap { if case .movement(let id) = $0 { return id }; return nil }),
            weightManagementGoal: presentation.goals.contains(.weightManagement), onboardingRevision: TrainingSetup.revision, programmePreferences: prefs)
    }
    private func advance() {
        error = nil
        switch presentation.advance(age: age, hasMeasurements: measurements != nil,
            excludedExerciseIDs: profileStore.profile?.programmePreferences?.excludedExerciseIDs ?? []) {
        case .blocked(let message): error = message
        case .moved: SpottrHaptics.selection()
        case .save:
            do {
                let profile = try candidate()
                guard AccountPolicy.setupComplete(profile: profile) else { error = "Complete the required profile and movement choices first."; return }
                let week = try preparedWeek(profile)
                try programme?.acceptPreview(week, profile: profile)
                try profileStore.save(profile); SpottrHaptics.success(); onComplete(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func comfortChoices(_ family: ExerciseFamily) -> [ExerciseEntry] {
        guard let prefs = try? preferences() else { return [] }
        return ExerciseCatalog.all.filter { $0.family == family && prefs.canUse($0) }.sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
    }
    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) { if set.contains(value) { set.remove(value) } else { set.insert(value) } }
}

struct TrainingRhythmContent: View {
    let step: TrainingSetupPresentation.RhythmStep
    @Binding var goals: Set<TrainingGoal>
    @Binding var weekdays: Set<Int>
    @Binding var minutes: Int
    @Binding var hour: Int
    @Binding var support: Set<String>
    @Binding var floor: Bool
    let adult: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch step {
            case .goals:
                Text("Choose what matters to you. You can pick more than one.").font(.subheadline).foregroundStyle(.secondary)
                TrainingGoalPicker(goals: $goals, adult: adult, visualGrid: true)
            case .schedule:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 130 : 80))]) {
                    ForEach(1...7, id: \.self) { day in
                        Button { toggle(day, in: &weekdays); SpottrHaptics.selection() } label: {
                            Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day - 1]).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).tint(weekdays.contains(day) ? Palette.blue : Palette.muted)
                            .accessibilityValue(weekdays.contains(day) ? "Selected" : "Not selected")
                    }
                }
                Text("Easier days and rest are part of your week.").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minutes per session").font(.headline)
                    Picker("Minutes per session", selection: $minutes) {
                        ForEach([10, 20, 30, 45], id: \.self) { Text("\($0) minutes").tag($0) }
                    }.labelsHidden().pickerStyle(.menu).frame(minHeight: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferred time").font(.headline)
                    Picker("Preferred time", selection: $hour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).frame(minHeight: 44)
                }
            case .support:
                Text("Choose the stable support you can use. None is also fine.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(PathSurvey.equipmentChoices, id: \.self) { item in
                    ChoiceCard(title: item, selected: support.contains(item), action: { toggle(item, in: &support) }) {
                        Image(systemName: item == "Wall" ? "rectangle" : "square.dashed")
                    }
                }
                Toggle("Floor movements are comfortable", isOn: $floor).frame(minHeight: 44)
            }
        }
    }
    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

struct TrainingStartingPointChoices: View {
    @Binding var selection: TrainingStartingPoint?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let entry = ExerciseCatalog.find(["sitToStand", "halfSquat", "squat", "tempoSquat"][(selection?.suggestedLevel ?? 1) - 1]) {
                ExerciseArtwork(entry: entry).frame(height: 150).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            Text("Choose the experience that feels closest.").font(.subheadline).foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                ForEach(TrainingStartingPoint.allCases, id: \.self) { point in
                    ChoiceCard(title: point.title, selected: selection == point, action: { selection = point }) {
                        Text("\(point.suggestedLevel)").font(.title2.bold())
                    }.accessibilityIdentifier("starting-point-\(point.rawValue)")
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 4), spacing: 6) {
                    ForEach(TrainingStartingPoint.allCases, id: \.self) { point in
                        Button { selection = point; SpottrHaptics.selection() } label: {
                            VStack(spacing: 8) {
                                Image(systemName: selection == point ? "checkmark.circle.fill" : "circle")
                                Text(point.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(.horizontal, 5).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 90)
                                .foregroundStyle(selection == point ? Palette.blue : Palette.ink)
                                .background(selection == point ? Palette.blue.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(SpottrPressStyle()).accessibilityValue(selection == point ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selection == point ? [.isSelected] : [])
                            .accessibilityIdentifier("starting-point-\(point.rawValue)")
                    }
                }
            }
            Text(selection?.title ?? "Not answered").font(.headline).accessibilityIdentifier("starting-point-value")
        }
    }
}

struct TrainingComfortFamily: View {
    let family: ExerciseFamily
    let choices: [ExerciseEntry]
    let answer: TrainingSetup.Comfort?
    let expanded: Bool
    let onExpand: () -> Void
    let onAnswer: (TrainingSetup.Comfort) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Family \((ExerciseFamily.allCases.firstIndex(of: family) ?? 0) + 1) of \(ExerciseFamily.allCases.count)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text("Choose a comfortable movement. Not sure yet is a useful answer.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(choices.prefix(expanded ? choices.count : 3)), id: \.id) { entry in
                ChoiceCard(title: entry.name, selected: answer == .movement(entry.id), action: { onAnswer(.movement(entry.id)) }) {
                    ExerciseArtwork(entry: entry)
                }.accessibilityIdentifier("comfortable-\(entry.id)")
            }
            ChoiceCard(title: "Not sure yet", detail: "Start gently and explore with support.", selected: answer == .unsure,
                action: { onAnswer(.unsure) }) { Image(systemName: "questionmark.circle") }
                .accessibilityIdentifier("comfortable-unsure-\(family.rawValue)")
            if choices.count > 3 {
                Button(expanded ? "Fewer variations" : "More variations", systemImage: "slider.horizontal.3", action: onExpand)
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }
}

struct TrainingComfortReview: View {
    let answers: [ExerciseFamily: TrainingSetup.Comfort]
    let onChange: (ExerciseFamily) -> Void
    var body: some View {
        VStack(spacing: 12) {
            ForEach(ExerciseFamily.allCases.filter { answers[$0] != nil }, id: \.self) { family in
                Button { onChange(family) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(family.title).font(.headline)
                            Text(answerTitle(family)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Label("Change", systemImage: "pencil").font(.subheadline)
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(SpottrPressStyle()).accessibilityLabel("Change \(family.title), \(answerTitle(family))")
                    .accessibilityIdentifier("comfortable-review-\(family.rawValue)")
            }
        }
    }
    private func answerTitle(_ family: ExerciseFamily) -> String {
        switch answers[family] {
        case .unsure: "Not sure yet"
        case .movement(let id): ExerciseCatalog.find(id)?.name ?? "Review this choice"
        case nil: "Not answered"
        }
    }
}

struct TrainingWeekPreview: View {
    let week: TrainingProgramme
    @Environment(\.dynamicTypeSize) private var typeSize
    private func title(_ day: TrainingProgramme.Day) -> String {
        day.kind == .rest ? "Rest" : day.kind == .recovery ? "Easier movement" : day.kind == .familyMovement ? "Family movement and play" : "Practice"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let next = week.days.first(where: { $0.plan != nil }), let plan = next.plan {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next practice on \(next.date.formatted(.dateTime.weekday(.wide)))").font(.headline)
                    Text("\(plan.items.count) \(plan.items.count == 1 ? "movement" : "movements") at your pace")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            Text("Your prepared week").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 2 : 7), spacing: 12) {
                ForEach(week.days) { day in
                    VStack(spacing: 8) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold))
                        Image(systemName: day.kind == .rest ? "moon" : "figure.strengthtraining.traditional")
                            .foregroundStyle(day.kind == .rest ? Palette.muted : Palette.blue)
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(title(day))")
                }
            }
            DisclosureGroup("View my week") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(week.days) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(day.date.formatted(.dateTime.weekday(.wide))) · \(title(day))").font(.headline)
                            if let plan = day.plan {
                                ForEach(plan.items, id: \.exerciseID) { item in
                                    Text(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID).font(.subheadline)
                                }
                            }
                        }
                    }
                }.padding(.top, 12)
            }.frame(minHeight: 44)
            Text("Adjust your week whenever you need. Rest days are part of your plan.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
extension TrainingStartingPoint {
    var title: String {
        switch self { case .startingOut: "Starting out"; case .somePractice: "Some practice"; case .regularPractice: "Regular practice"; case .experienced: "Experienced" }
    }
}
struct TrainingGoalPicker: View {
    @Binding var goals: Set<TrainingGoal>
    var adult = true
    var visualGrid = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var choices: [TrainingGoal] { TrainingGoal.allCases.filter { adult || $0 != .weightManagement } }
    var body: some View {
        if visualGrid && !typeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(choices, id: \.self) { goal in
                    Button { toggle(goal); SpottrHaptics.selection() } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { GoalGlyph(goal: goal); Spacer(); Image(systemName: goals.contains(goal) ? "checkmark.circle.fill" : "circle") }
                            Text(goal.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                            .foregroundStyle(Palette.ink)
                            .background(goals.contains(goal) ? Palette.blue.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("goal-\(goal.rawValue)")
                        .accessibilityValue(goals.contains(goal) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(goals.contains(goal) ? [.isSelected] : [])
                }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(choices, id: \.self) { goal in
                    ChoiceCard(title: goal.title, selected: goals.contains(goal), action: { toggle(goal) }) {
                        GoalGlyph(goal: goal)
                    }.accessibilityIdentifier("goal-\(goal.rawValue)")
                }
            }
        }
    }
    private func toggle(_ goal: TrainingGoal) {
        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
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


/// Local presentation state only. Persisted categories and profile validation stay unchanged.
struct TrainingSetupPresentation {
    enum RhythmStep: String { case goals, schedule, support }
    enum ComfortStep: Equatable { case startingPoint, family(ExerciseFamily), review }
    enum Advance: Equatable { case moved, blocked(String), save }
    private(set) var stage: TrainingSetup.Stage
    private(set) var rhythmStep = RhythmStep.goals
    private(set) var comfortStep = ComfortStep.startingPoint
    let firstStage: TrainingSetup.Stage
    var goals: Set<TrainingGoal>
    var weekdays: Set<Int>
    var minutes: Int
    var hour: Int
    var support: Set<String>
    var floor: Bool
    var startingPoint: TrainingStartingPoint?
    var answers: [ExerciseFamily: TrainingSetup.Comfort]
    private let excludedExerciseIDs: Set<String>

    init(preferences: ProgrammePreferences?, hasAnalytics: Bool) {
        firstStage = hasAnalytics ? .account : .body
        stage = firstStage
        goals = preferences?.goals ?? []
        weekdays = preferences?.weekdays ?? []
        minutes = preferences?.minutesPerSession ?? 20
        hour = preferences?.preferredLocalHour ?? 18
        support = preferences?.availableSupport ?? []
        floor = preferences?.allowsFloorWork ?? true
        startingPoint = preferences?.startingPoint
        answers = preferences?.comfortAnswers ?? [:]
        excludedExerciseIDs = preferences?.excludedExerciseIDs ?? []
    }
    var title: String {
        if stage == .goals {
            switch rhythmStep {
            case .goals: return "What would you like to work on?"
            case .schedule: return "When would you like to practise?"
            case .support: return "What support is available?"
            }
        }
        if stage == .comfort {
            switch comfortStep {
            case .startingPoint: return stage.title
            case .family(let family): return family.title
            case .review: return "Review your starting point"
            }
        }
        return stage.title
    }
    var pageID: String {
        if stage == .goals { return "goals-\(rhythmStep.rawValue)" }
        if stage == .comfort {
            switch comfortStep {
            case .startingPoint: return "comfort-starting-point"
            case .family(let family): return "comfort-\(family.rawValue)"
            case .review: return "comfort-review"
            }
        }
        return "stage-\(stage.rawValue)"
    }
    var canGoBack: Bool { stage.rawValue > firstStage.rawValue }
    func preferences(age: TrainingAgeContext?, excludedExerciseIDs: Set<String>? = nil) throws -> ProgrammePreferences {
        try ProgrammePreferences(goals: goals, weekdays: weekdays, minutesPerSession: minutes, preferredLocalHour: hour,
            availableSupport: support, allowsFloorWork: floor, excludedExerciseIDs: excludedExerciseIDs ?? self.excludedExerciseIDs,
            startingPoint: startingPoint, ageContext: age, comfortAnswers: answers)
    }
    mutating func advance(age: TrainingAgeContext?, hasMeasurements: Bool, excludedExerciseIDs: Set<String>? = nil) -> Advance {
        guard let age else { return .blocked("Confirm this person’s age in Account and profiles.") }
        if stage == .body && age.ageYears >= 18 && !hasMeasurements { return .blocked("Enter your height and weight to continue.") }
        if stage == .goals {
            switch rhythmStep {
            case .goals:
                guard !goals.isEmpty else { return .blocked("Choose at least one goal to continue.") }
                rhythmStep = .schedule
                return .moved
            case .schedule:
                guard !weekdays.isEmpty else { return .blocked("Choose at least one activity day to continue.") }
                rhythmStep = .support
                return .moved
            case .support: break
            }
        }
        if stage == .comfort && age.ageYears >= 5 {
            switch comfortStep {
            case .startingPoint:
                guard startingPoint != nil else { return .blocked("Choose a starting point to continue.") }
                comfortStep = TrainingSetup.nextUnanswered(answers).map(ComfortStep.family) ?? .review
                return .moved
            case .family(let family):
                guard answers[family] != nil else { return .blocked("Choose a movement or Not sure yet to continue.") }
                comfortStep = TrainingSetup.nextUnanswered(answers).map(ComfortStep.family) ?? .review
                return .moved
            case .review:
                guard let preferences = try? preferences(age: age, excludedExerciseIDs: excludedExerciseIDs), TrainingSetup.comfortComplete(preferences) else {
                    if let family = firstInvalidFamily(age: age, excludedExerciseIDs: excludedExerciseIDs) { comfortStep = .family(family) }
                    return .blocked("Review each movement choice. Not sure yet is valid.")
                }
            }
        }
        if stage == .coach { return .save }
        stage = TrainingSetup.Stage(rawValue: stage.rawValue + 1) ?? .coach
        return .moved
    }
    mutating func goBack() {
        if stage == .goals {
            if rhythmStep == .support { rhythmStep = .schedule; return }
            if rhythmStep == .schedule { rhythmStep = .goals; return }
        }
        if stage == .comfort {
            switch comfortStep {
            case .review:
                comfortStep = ExerciseFamily.allCases.last.map(ComfortStep.family) ?? .startingPoint
                return
            case .family(let family):
                let index = ExerciseFamily.allCases.firstIndex(of: family) ?? 0
                comfortStep = index > 0 ? .family(ExerciseFamily.allCases[index - 1]) : .startingPoint
                return
            case .startingPoint: break
            }
        }
        guard stage.rawValue > firstStage.rawValue else { return }
        stage = TrainingSetup.Stage(rawValue: stage.rawValue - 1) ?? firstStage
    }
    mutating func answer(_ value: TrainingSetup.Comfort, family: ExerciseFamily) {
        answers[family] = value
        comfortStep = TrainingSetup.nextUnanswered(answers).map(ComfortStep.family) ?? .review
    }
    mutating func review(_ family: ExerciseFamily) { comfortStep = .family(family) }
    mutating func changeStartingPoint() { comfortStep = .startingPoint }
    private func firstInvalidFamily(age: TrainingAgeContext, excludedExerciseIDs: Set<String>?) -> ExerciseFamily? {
        guard let preferences = try? preferences(age: age, excludedExerciseIDs: excludedExerciseIDs) else { return ExerciseFamily.allCases.first }
        return ExerciseFamily.allCases.first { family in
            switch answers[family] {
            case .unsure: return false
            case .movement(let id):
                guard let entry = ExerciseCatalog.find(id) else { return true }
                return entry.family != family || !preferences.canUse(entry)
            case nil: return true
            }
        }
    }
}
