import SwiftUI

struct OnboardingView: View {
    let profileStore: NativeProfileStore
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name: String
    @State private var weeklyTarget: Int
    @State private var goals: Set<TrainingAttribute>
    @State private var baselineAbility: LocalProfile.BaselineAbility?
    @State private var comfortableExercises: Set<String>
    @State private var weightManagementGoal: Bool
    @AppStorage("trainer.audioEnabled") private var audioEnabled = false
    @State private var bodyMeasurements: LocalBodyMeasurements?
    @State private var measurementsPresented = false
    @State private var error: String?
    @State private var healthStore: HealthDataStore
    @State private var optionalSetup: OptionalSetup?

    init(profileStore: NativeProfileStore, healthStore: HealthDataStore? = nil, onComplete: @escaping () -> Void = {}) {
        self.profileStore = profileStore
        self.onComplete = onComplete
        _healthStore = State(initialValue: healthStore ?? HealthDataStore())
        _name = State(initialValue: profileStore.profile?.name ?? "")
        _weeklyTarget = State(initialValue: profileStore.profile?.weeklyTarget ?? 3)
        _goals = State(initialValue: profileStore.profile?.goals ?? [.strength])
        _baselineAbility = State(initialValue: profileStore.profile?.baselineAbility)
        _comfortableExercises = State(initialValue: profileStore.profile?.comfortableExercises ?? [])
        _weightManagementGoal = State(initialValue: profileStore.profile?.weightManagementGoal ?? false)
        _bodyMeasurements = State(initialValue: profileStore.profile?.bodyMeasurements)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 { Button { step -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous step") }
                Spacer()
                Text("\(step + 1) of 6").font(.caption).foregroundStyle(.secondary)
                if profileStore.profile != nil { Button("Cancel introduction") { dismiss() }.font(.caption) }
            }.padding(.horizontal, 25).padding(.vertical, 17)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if step == 0 { introduction }
                    if step == 1 { optionalHealthSetup }
                    if step == 2 { goalSelection }
                    if step == 3 { personalDetails }
                    if step == 4 { comfortableMovements }
                    if step == 5 { trainer }
                    if let issue = profileStore.loadError { Text(issue).font(.caption).foregroundStyle(Palette.red) }
                    if let error { Text(error).font(.callout).foregroundStyle(Palette.red).accessibilityAddTraits(.updatesFrequently) }
                }.padding(.horizontal, 25).padding(.bottom, 20)
            }.scrollDismissesKeyboard(.interactively)
            VStack(spacing: 12) {
                PrimaryButton(title: step == 5 ? "Let’s get moving" : (step == 1 ? "Continue without setup" : "Continue")) { advance() }
                    .disabled(step == 2 && goals.isEmpty && !weightManagementGoal)
                    .opacity(step == 2 && goals.isEmpty && !weightManagementGoal ? 0.4 : 1)
                    .accessibilityIdentifier("onboarding-continue")
                Text("A local profile on this iPhone. No account needed.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.horizontal, 25).padding(.vertical, 18)
        }.background(.white).foregroundStyle(Palette.ink).preferredColorScheme(.light)
            .sheet(isPresented: $measurementsPresented) {
                MeasurementsSettingsView(measurements: bodyMeasurements, isIntroduction: true) { bodyMeasurements = $0 }
            }
            .sheet(item: $optionalSetup) { setup in
                NavigationStack {
                    Group {
                        if setup == .health { HealthSetupView(store: healthStore) }
                        else { WatchSetupView() }
                    }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { optionalSetup = nil } } }
                }
            }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("spottr").font(.title3.weight(.bold)).tracking(-0.6)
            StickFigureArtwork(exercise: .halfSquat).frame(maxWidth: .infinity).frame(height: 240).accessibilityHidden(true)
            Text("Move a little.\nBuild from there.").font(.largeTitle.bold()).tracking(-1)
            Text("Find a comfortable starting point, practise with clear feedback and see your progress over time.")
                .font(.body).foregroundStyle(.secondary)
            Label("Your pace. One achievable step at a time.", systemImage: "figure.walk").font(.subheadline.weight(.medium))
        }
    }

    private var goalSelection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What are you\nworking towards?").font(.largeTitle.bold()).tracking(-1)
            Text("Choose one or more goals. You can change them whenever you like.").foregroundStyle(.secondary)
            ProfileGoalPicker(goals: $goals)
            Toggle(isOn: $weightManagementGoal) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Weight management", systemImage: "scalemass").font(.headline)
                    Text("Build a movement habit and track your activity.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17)).accessibilityIdentifier("goal-weightManagement")
        }.padding(.top, 20)
    }

    private var optionalHealthSetup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "applewatch").font(.system(size: 56)).foregroundStyle(Palette.blue).accessibilityHidden(true)
            Text("Your Watch.\nYour choice.").font(.largeTitle.bold()).tracking(-1)
            Text("Apple Health and Watch setup are optional. Every phone feature remains available when you skip this step.")
                .foregroundStyle(.secondary).accessibilityIdentifier("onboarding-health-optional")
            Button { optionalSetup = .health } label: { Label("Choose Apple Health data", systemImage: "heart.text.square") }
                .accessibilityIdentifier("onboarding-health-setup")
            Button { optionalSetup = .watch } label: { Label("Watch installation guide", systemImage: "applewatch") }
                .accessibilityIdentifier("onboarding-watch-guide")
            Text("No Health data is requested until you choose it. Missing readings stay missing; your training history stays separate.")
                .font(.caption).foregroundStyle(.secondary)
            Text(healthStore.statusMessage).font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 20)
    }

    private var personalDetails: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("Make it yours.").font(.largeTitle.bold()).tracking(-1)
            Text("Start with a rhythm you can make time for.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9) {
                Text("What should we call you?").font(.subheadline.weight(.medium))
                TextField("Your name (optional)", text: $name).textContentType(.givenName)
                    .textInputAutocapitalization(.words).textFieldStyle(.roundedBorder)
                Text("Leave this blank to train as a guest.").font(.caption).foregroundStyle(.secondary)
            }
            ProfileWeeklyTarget(target: $weeklyTarget)
            VStack(alignment: .leading, spacing: 9) {
                Text("Your starting point (optional)").font(.subheadline.weight(.medium))
                Picker("Starting point", selection: $baselineAbility) {
                    Text("Skip for now").tag(nil as LocalProfile.BaselineAbility?)
                    ForEach(LocalProfile.BaselineAbility.allCases, id: \.self) { ability in
                        Text(ability.title).tag(Optional(ability))
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("onboarding-baseline")
                Text("Your self-report helps suggest practice ideas. It doesn’t verify ability, log sets or award achievements.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("Start simply", systemImage: "checkmark.circle").font(.headline)
                Text("Your first session can be a few controlled reps. Take breaks and tell your coach how the work feels.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            Button { measurementsPresented = true } label: {
                Label("Height, weight & BMI (optional)", systemImage: "scalemass")
            }.accessibilityIdentifier("onboarding-measurements")
            Text("Skip this or add measurements later in Profile & settings. They stay on this iPhone.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 20)
    }

    private var comfortableMovements: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Where do you feel comfortable?").font(.largeTitle.bold()).tracking(-1)
            Text("Choose the hardest movement you can comfortably repeat. Unsure is a good place to start too.").foregroundStyle(.secondary)
            ForEach([ExerciseFamily.push, .legs], id: \.self) { family in
                VStack(alignment: .leading, spacing: 12) {
                    Text(family.title).font(.headline)
                    let ids = LocalSkillPath.chain(family: family)
                    ForEach(ids.prefix(family == .push ? 4 : 3), id: \.self) { id in
                        if let entry = ExerciseCatalog.find(id) {
                            Button {
                                comfortableExercises.subtract(ids)
                                comfortableExercises.insert(id)
                            } label: {
                                HStack(spacing: 13) {
                                    ExerciseArtwork(entry: entry).frame(width: 42, height: 48)
                                    Text(entry.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: comfortableExercises.contains(id) ? "checkmark.circle.fill" : "circle")
                                }.padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityIdentifier("comfortable-\(id)")
                        }
                    }
                    Button("Not sure yet") { comfortableExercises.subtract(ids) }.font(.subheadline)
                }
            }
            Text("Your starting skills will be marked on your path. They don’t add workouts, camera results or XP.").font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 16)
    }

    private var trainer: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Find your voice").font(.largeTitle.bold()).tracking(-1)
            Text("Pick the coach and style you enjoy. You can change both later.").foregroundStyle(.secondary)
            TrainerSelection()
            Toggle("Voice feedback during workouts", isOn: $audioEnabled)
            Text("No faces or avatars. Just a voice and clear movement guidance.").font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 16)
    }

    private func advance() {
        guard step == 5 else { step += 1; return }
        do {
            try profileStore.save(LocalProfile(name: name, weeklyTarget: weeklyTarget, goals: goals.isEmpty ? [.stamina] : goals,
                                               baselineAbility: baselineAbility, bodyMeasurements: bodyMeasurements,
                                               comfortableExercises: comfortableExercises, weightManagementGoal: weightManagementGoal))
            onComplete()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private enum OptionalSetup: String, Identifiable { case health, watch; var id: String { rawValue } }
}

struct ProfileGoalPicker: View {
    @Binding var goals: Set<TrainingAttribute>
    var body: some View {
        VStack(spacing: 11) {
            ForEach(TrainingAttribute.allCases, id: \.self) { goal in
                Button {
                    if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                } label: {
                    HStack(spacing: 15) {
                        Image(goal.rawValue).resizable().scaledToFit().frame(width: 27, height: 27).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title).font(.subheadline.weight(.semibold))
                            Text(detail(goal)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: goals.contains(goal) ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(goals.contains(goal) ? Palette.blue : Palette.muted)
                    }.padding(17).foregroundStyle(Palette.ink)
                        .background(goals.contains(goal) ? Palette.blue.opacity(0.07) : Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityLabel(goal.title)
                    .accessibilityValue(goals.contains(goal) ? "Selected" : "Not selected")
                    .accessibilityIdentifier("goal-\(goal.rawValue)")
            }
        }
    }
    private func detail(_ goal: TrainingAttribute) -> String {
        switch goal {
        case .strength: return "Build controlled, consistent reps."
        case .stamina: return "Keep a steady training rhythm."
        case .mobility: return "Make time to move comfortably."
        case .balance: return "Practise stability and control."
        }
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
