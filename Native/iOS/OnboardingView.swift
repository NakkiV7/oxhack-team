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
    @State private var bodyMeasurements: LocalBodyMeasurements?
    @State private var measurementsPresented = false
    @State private var error: String?

    init(profileStore: NativeProfileStore, onComplete: @escaping () -> Void = {}) {
        self.profileStore = profileStore
        self.onComplete = onComplete
        _name = State(initialValue: profileStore.profile?.name ?? "")
        _weeklyTarget = State(initialValue: profileStore.profile?.weeklyTarget ?? 3)
        _goals = State(initialValue: profileStore.profile?.goals ?? [.strength])
        _baselineAbility = State(initialValue: profileStore.profile?.baselineAbility)
        _bodyMeasurements = State(initialValue: profileStore.profile?.bodyMeasurements)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 { Button { step -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous step") }
                Spacer()
                Text("\(step + 1) of 3").font(.caption).foregroundStyle(.secondary)
                if profileStore.profile != nil { Button("Cancel introduction") { dismiss() }.font(.caption) }
            }.padding(.horizontal, 25).padding(.vertical, 17)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if step == 0 { introduction }
                    if step == 1 { goalSelection }
                    if step == 2 { personalDetails }
                    if let issue = profileStore.loadError { Text(issue).font(.caption).foregroundStyle(Palette.red) }
                    if let error { Text(error).font(.callout).foregroundStyle(Palette.red).accessibilityAddTraits(.updatesFrequently) }
                }.padding(.horizontal, 25).padding(.bottom, 20)
            }.scrollDismissesKeyboard(.interactively)
            VStack(spacing: 12) {
                PrimaryButton(title: step == 2 ? "Let’s train" : "Continue") { advance() }
                    .disabled(step == 1 && goals.isEmpty)
                    .opacity(step == 1 && goals.isEmpty ? 0.4 : 1)
                    .accessibilityIdentifier("onboarding-continue")
                Text("A local profile on this iPhone. No account needed.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.horizontal, 25).padding(.vertical, 18)
        }.background(.white).foregroundStyle(Palette.ink).preferredColorScheme(.light)
            .sheet(isPresented: $measurementsPresented) {
                MeasurementsSettingsView(measurements: bodyMeasurements, isIntroduction: true) { bodyMeasurements = $0 }
            }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("spottr").font(.title3.weight(.bold)).tracking(-0.6)
            Image("onboarding-skills").resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 260).accessibilityHidden(true)
            Text("Train. Level up.\nRepeat.").font(.largeTitle.bold()).tracking(-1)
            Text("Build a routine around real training. Earn XP, explore new skills and get clear cues while you move.")
                .font(.body).foregroundStyle(.secondary)
            Label("Your pace. Your next challenge.", systemImage: "figure.strengthtraining.traditional").font(.subheadline.weight(.medium))
        }
    }

    private var goalSelection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What are you\nworking towards?").font(.largeTitle.bold()).tracking(-1)
            Text("Choose one or more goals. You can change them whenever you like.").foregroundStyle(.secondary)
            ProfileGoalPicker(goals: $goals)
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

    private func advance() {
        guard step == 2 else { step += 1; return }
        do {
            try profileStore.save(LocalProfile(name: name, weeklyTarget: weeklyTarget, goals: goals,
                                               baselineAbility: baselineAbility, bodyMeasurements: bodyMeasurements))
            onComplete()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
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
