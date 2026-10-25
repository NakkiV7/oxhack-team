import SwiftUI

struct WorkoutVoiceControls: View {
    let store: TrainingStore
    let identifier: String
    @State private var choosing = false
    var body: some View {
        HStack(spacing: 14) {
            if let voice = store.remoteVoice {
                Button { choosing = true } label: {
                    Label(voice.preference.title, systemImage: "gearshape")
                        .font(.caption).lineLimit(1)
                }.accessibilityLabel("Choose coach voice")
                    .accessibilityIdentifier("choose-coach-voice")
                    .sheet(isPresented: $choosing) {
                        VoiceCoachSettingsView(playback: voice, cancelCoaching: store.cancelCoaching)
                    }
            }
            Toggle("Voice feedback", isOn: Binding(get: { store.voiceFeedbackEnabled }, set: { store.setVoiceFeedback($0) }))
                .font(.caption).accessibilityIdentifier(identifier)
        }.padding(.horizontal, 24).padding(.vertical, 6)
    }
}

struct VoiceCoachSettingsView: View {
    let playback: RemoteVoicePlayback
    let cancelCoaching: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var refresh: UUID?
    @State private var loading = false
    @State private var error: String?
    @State private var connection = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(VoiceCoachPreference.allCases) { voice in
                        Button {
                            do {
                                cancelCoaching()
                                try playback.select(voice)
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            HStack(spacing: 14) {
                                portrait(voice)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.title).font(.headline).foregroundStyle(Palette.ink)
                                    Text(voice == .local ? "On this iPhone" : (playback.isPreview ? "Preview · bundled cues · offline" : "ElevenLabs · current coaching cues"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if playback.preference == voice {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.blue)
                                }
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(voice != .local && !playback.configuredVoices.contains(voice))
                            .accessibilityLabel("\(voice.title)\(playback.preference == voice ? ", selected" : "")")
                            .accessibilityIdentifier("coach-voice-\(voice.rawValue)")
                    }
                } header: { Text("Your coach") } footer: {
                    Text("Voice feedback stays off until you enable it in a workout. Choosing a voice doesn’t play audio.")
                }
                Section {
                    Button { refresh = UUID() } label: {
                        HStack {
                            Label("Check configured voices", systemImage: "arrow.clockwise")
                            Spacer()
                            if loading { ProgressView() }
                        }
                    }.disabled(loading).accessibilityIdentifier("coach-voices-refresh")
                    Button { connection = true } label: { Label("Gateway connection", systemImage: "network") }
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.red).accessibilityIdentifier("coach-voice-error") }
                    if let error = playback.errorMessage { Text(error).font(.caption).foregroundStyle(Palette.red) }
                } footer: {
                    Text(playback.isPreview ? "Arnold preview uses bundled audio without network requests. Stop feedback uses immediate local speech." : "Remote voices send short coaching text to your gateway and ElevenLabs. Checking lists server configuration; it doesn’t verify synthesis or use voice credits. Stop feedback always uses immediate local speech.")
                }
            }.scrollContentBackground(.hidden).background(.white).tint(Palette.blue)
                .navigationTitle("Coach voice").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $connection) { CoachSettingsView() }
                .task(id: refresh) {
                    guard refresh != nil else { return }
                    loading = true
                    defer { loading = false }
                    do { try await playback.refreshVoices(); error = nil }
                    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.preferredColorScheme(.light)
    }

    @ViewBuilder private func portrait(_ voice: VoiceCoachPreference) -> some View {
        if voice == .local {
            Image(systemName: "speaker.wave.2.fill").font(.title2).foregroundStyle(Palette.blue)
                .frame(width: 52, height: 56).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        } else {
            Image(voice == .david ? "coach-david" : "coach-arnold").resizable().scaledToFill()
                .frame(width: 52, height: 56).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
        }
    }
}
