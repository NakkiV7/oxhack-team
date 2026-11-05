import SwiftUI

struct OfflineCoachView: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var choice = "Start moving"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let choices = ["Start moving", "Make it easier", "Build a routine", "Review my work"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeading(title: "Your coach")
                    if let playback = store.remoteVoice {
                        NavigationLink {
                            VoiceCoachSettingsView(playback: playback, cancelCoaching: store.cancelCoaching, repVoice: store.repVoice)
                        } label: {
                            HStack(spacing: 16) {
                                TrainerPortrait(voice: playback.preference).frame(width: 64, height: 64)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(playback.preference.title).font(.headline)
                                    Text("Choose your voice and style").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(SpottrPressStyle())
                    }
                    Text("What would help today?").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach(choices, id: \.self) { item in
                        Button { choice = item } label: {
                            HStack {
                                Text(item).font(.subheadline.weight(.semibold))
                                Spacer(); Image(systemName: choice == item ? "checkmark.circle.fill" : "circle")
                            }.frame(minHeight: 44).padding(.horizontal, 18).padding(.vertical, 8)
                                .background(choice == item ? Palette.blue.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(choice == item ? Palette.blue.opacity(0.4) : .clear, lineWidth: 1))
                        }.buttonStyle(SpottrPressStyle()).accessibilityIdentifier("coach-option-\(item)")
                            .accessibilityAddTraits(choice == item ? .isSelected : [])
                    }
                    guidance
                    if choice != "Review my work" {
                        Text("Choose a comfortable exercise").font(.headline)
                        ForEach(suggestions) { entry in
                            NavigationLink { CatalogueWorkoutSetupView(store: store, entry: entry) } label: {
                                HStack(spacing: 16) {
                                    ExerciseArtwork(entry: entry).frame(width: 52, height: 60)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.name).font(.headline)
                                        Text(entry.tracking == nil ? "Manual or timer" : "Camera or manual").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right")
                                }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(SpottrPressStyle())
                        }
                    }
                    CoachSummaryCard(history: store.history, kind: .weekly, profile: profile)
                }.padding(24)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: choice)
            }.background(.white).navigationTitle("Coach").navigationBarTitleDisplayMode(.inline)
                .sensoryFeedback(.selection, trigger: choice)
        }
    }
    private var suggestions: [ExerciseEntry] {
        let ids = choice == "Make it easier" ? ["wallPushup", "supportedSquat", "halfSquat"] : ["halfSquat", "wallPushup", "squat"]
        return ids.compactMap(ExerciseCatalog.find)
    }
    private var guidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(choice).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
    private var message: String {
        switch choice {
        case "Make it easier": return "Try a wall push-up or a supported squat. Reduce your rep target in workout setup and rest as needed. Stop if a movement causes pain."
        case "Build a routine": return "Your weekly aim is \(profile?.weeklyTarget ?? 3) training days. Choose a time you can repeat and leave space for rest. A short completed session is a useful start."
        case "Review my work": return "Your review below uses completed sets and their recorded source. Use Insights for your calendar, weekly comparisons and individual session reports."
        default: return profile?.weightManagementGoal == true ? "Build a repeatable movement habit. Spottr tracks training days, active time and Watch energy when available. Exercise counts alone cannot tell us how your weight is changing." : "Choose an exercise that feels comfortable. Start with a small target and use the camera, manual entry or spoken counting. You can switch without losing your count."
        }
    }
}
