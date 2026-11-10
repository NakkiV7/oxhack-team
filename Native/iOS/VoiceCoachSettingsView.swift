import SwiftUI

struct TrainerPortrait: View {
    let voice: VoiceCoachPreference
    private var color: Color {
        switch voice {
        case .maya: return .purple
        case .leo: return .teal
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
    var gentleOnly = false
    var onToneSelect: ((TrainerTone) -> Void)? = nil
    private let defaults: UserDefaults
    init(onSelect: ((VoiceCoachPreference) -> Void)? = nil, gentleOnly: Bool = false,
         onToneSelect: ((TrainerTone) -> Void)? = nil, defaults: UserDefaults = .standard) {
        self.onSelect = onSelect; self.gentleOnly = gentleOnly; self.onToneSelect = onToneSelect
        self.defaults = defaults
        _selection = AppStorage(wrappedValue: "maya", "trainer.voice", store: defaults)
        _tone = AppStorage(wrappedValue: TrainerTone.encouraging.rawValue, "trainer.tone", store: defaults)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your coaching style").font(.headline).padding(.top, 10)
            if gentleOnly { Label("Gentle encouragement", systemImage: "waveform").font(.subheadline) }
            else {
            Slider(value: Binding(get: { Double(TrainerTone.allCases.firstIndex(of: TrainerTone(rawValue: tone) ?? .encouraging) ?? 1) },
                                  set: { let next = TrainerTone.allCases[min(2, max(0, Int($0.rounded())))]; guard tone != next.rawValue else { return }; SpottrHaptics.selection(); if let onToneSelect { onToneSelect(next) } else { tone = next.rawValue } }), in: 0...2, step: 1)
                .accessibilityLabel("Coaching style").accessibilityValue(tone)
            HStack { Text("Gentle"); Spacer(); Text("Encouraging"); Spacer(); Text("Direct") }.font(.caption).foregroundStyle(.secondary)
            }
            Text("Style changes encouragement. Form and stop instructions stay clear and calm.").font(.caption).foregroundStyle(.secondary)
            ForEach([VoiceCoachPreference.maya, .leo, .local]) { voice in
                Button {
                    SpottrHaptics.selection()
                    if let onSelect { onSelect(voice) } else { selection = voice.rawValue }
                } label: {
                    HStack(spacing: 15) {
                        TrainerPortrait(voice: voice).frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(voice.title).font(.headline)
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
                    .sheet(isPresented: $choosing) { if let previews = store.voicePreviews { VoiceCoachSettingsView(previews: previews, repVoice: store.repVoice) } }
            }
            Toggle("Voice feedback", isOn: Binding(get: { store.voiceFeedbackEnabled }, set: { store.setVoiceFeedback($0) }))
                .font(.caption).accessibilityIdentifier(identifier)
        }.padding(.horizontal, 24).padding(.vertical, 6)
    }
}

struct VoiceCoachSettingsView: View {
    @State var previews: VoicePreviewCoordinator
    var repVoice: RepVoicePlayer? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VoicePreviewControls(previews: previews)
                    TrainerSelection(onSelect: { voice in
                        previews.select(voice, tone: previews.preferences.tone)
                    }, gentleOnly: previews.preferences.gentleOnly,
                       onToneSelect: { previews.select(previews.preference, tone: $0) }, defaults: previews.preferences.preferencesDefaults)
                    if let repVoice, !previews.preferences.gentleOnly {
                        Toggle("Speak rep counts with device voice", isOn: Binding(get: { repVoice.coach != nil }, set: { enabled in
                            repVoice.choose(enabled ? .device : nil)
                        }))
                        Text("Optional rep counts use your iPhone’s speaking voice, separately from Maya and Leo coaching. Off until you choose it.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("About offline voices") {
                        Text("Recordings play on your device. Local voice uses your iPhone’s speaking voice. No workout text, video or health data is sent to a voice service.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }.background(.white).navigationTitle("Your trainer").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { previews.stop(); dismiss() } } }
        }.preferredColorScheme(.light).onDisappear { previews.stop() }
    }
}

struct VoicePreviewControls: View {
    @Bindable var previews: VoicePreviewCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Preview selections", isOn: Binding(get: { previews.enabled }, set: previews.setEnabled))
                .accessibilityIdentifier("voice-preview-enabled")
            Button("Stop preview", systemImage: "stop.circle", action: previews.stop)
                .buttonStyle(.bordered).disabled(!previews.isPlaying).accessibilityIdentifier("voice-preview-stop")
            if let message = previews.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("voice-preview-status") }
        }
    }
}
