import SwiftUI

struct TrainerPortrait: View {
    let voice: VoiceCoachPreference
    private var color: Color {
        switch voice {
        case .maya: return .purple
        case .leo: return .teal
        case .arnold: return .orange
        case .david: return Palette.ink
        case .local: return Palette.blue
        }
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19).fill(color.opacity(0.12))
            Circle().stroke(color.opacity(0.25), lineWidth: 2).padding(9)
            HStack(spacing: 3) {
                ForEach(0..<5) { i in Capsule().fill(color).frame(width: 4, height: CGFloat([13, 25, 35, 25, 13][i])) }
            }
        }.accessibilityHidden(true)
    }
}

struct TrainerSelection: View {
    @AppStorage("trainer.voice") private var selection = "maya"
    @AppStorage("trainer.tone") private var tone = TrainerTone.encouraging.rawValue
    var onSelect: ((VoiceCoachPreference) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your coaching style").font(.headline).padding(.top, 10)
            Slider(value: Binding(get: { Double(TrainerTone.allCases.firstIndex(of: TrainerTone(rawValue: tone) ?? .encouraging) ?? 1) },
                                  set: { tone = TrainerTone.allCases[min(2, max(0, Int($0.rounded())))].rawValue }), in: 0...2, step: 1)
                .accessibilityLabel("Coaching style").accessibilityValue(tone)
            HStack { Text("Gentle"); Spacer(); Text("Encouraging"); Spacer(); Text("Direct") }.font(.caption).foregroundStyle(.secondary)
            Text("Style changes encouragement. Form and stop instructions stay clear and calm.").font(.caption).foregroundStyle(.secondary)
            ForEach([VoiceCoachPreference.maya, .leo, .arnold, .david, .local]) { voice in
                Button {
                    selection = voice.rawValue
                    if voice == .arnold || voice == .david {
                        UserDefaults.standard.set(voice == .arnold ? "arnold" : "goggins", forKey: RepVoicePlayer.defaultsKey)
                    } else { UserDefaults.standard.set("off", forKey: RepVoicePlayer.defaultsKey) }
                    onSelect?(voice)
                } label: {
                    HStack(spacing: 15) {
                        TrainerPortrait(voice: voice).frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(voice == .david ? "Goggins" : voice.title).font(.headline)
                            Text(detail(voice)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selection == voice.rawValue ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.blue)
                    }.padding(12).background(selection == voice.rawValue ? Palette.blue.opacity(0.06) : Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("coach-voice-\(voice.rawValue)")
            }

        }
    }
    private func detail(_ voice: VoiceCoachPreference) -> String {
        switch voice {
        case .maya: return "Warm female voice with natural offline coaching"
        case .leo: return "Calm male voice with natural offline coaching"
        case .arnold, .david: return "Optional inspired voice pack with offline rep audio"
        case .local: return "Your iPhone’s default speaking voice"
        }
    }
}

struct WorkoutVoiceControls: View {
    let store: TrainingStore
    let identifier: String
    @State private var choosing = false
    var body: some View {
        HStack(spacing: 14) {
            if let voice = store.remoteVoice {
                Button { choosing = true } label: { Label(voice.preference.title, systemImage: "waveform").font(.caption).lineLimit(1) }
                    .accessibilityLabel("Choose coach voice").accessibilityIdentifier("choose-coach-voice")
                    .sheet(isPresented: $choosing) { VoiceCoachSettingsView(playback: voice, cancelCoaching: store.cancelCoaching, repVoice: store.repVoice) }
            }
            Toggle("Voice feedback", isOn: Binding(get: { store.voiceFeedbackEnabled }, set: { store.setVoiceFeedback($0) }))
                .font(.caption).accessibilityIdentifier(identifier)
        }.padding(.horizontal, 24).padding(.vertical, 6)
    }
}

struct VoiceCoachSettingsView: View {
    let playback: RemoteVoicePlayback
    let cancelCoaching: () -> Void
    var repVoice: RepVoicePlayer? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TrainerSelection { voice in
                        cancelCoaching(); try? playback.select(voice)
                        repVoice?.choose(voice == .arnold ? .arnold : voice == .david ? .goggins : nil)
                    }
                    if let repVoice {
                        Toggle("Speak rep counts", isOn: Binding(get: { repVoice.coach != nil }, set: { enabled in
                            repVoice.choose(enabled ? (playback.preference == .david ? .goggins : .arnold) : nil)
                        }))
                        Text("Optional rep packs use the bundled Arnold or Goggins recordings. Turn them off for coaching only.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Coach recordings play offline. Local voice uses your iPhone’s speaking voice. No workout text, video or health data is sent to a voice service.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(.white).navigationTitle("Your trainer").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.light)
    }
}
