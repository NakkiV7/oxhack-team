import SwiftUI
import AVKit

struct DemoStudioView: View {
    let store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var example: Example?

    private struct Example: Identifiable {
        let exercise: Exercise
        var id: String { exercise.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("See Spottr in motion.").font(.system(size: 32, weight: .bold)).tracking(-1)
                        Text("Two recorded examples. Then try a session at your own pace.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach([Exercise.squat, .pushup], id: \.self) { exercise in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 20) {
                                Image("\(exercise.rawValue)-mid").resizable().scaledToFit()
                                    .frame(width: 88, height: 100).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(exercise.title).font(.title3.weight(.semibold))
                                    Text(exercise == .squat ? "See depth and movement cues." : "See rep counting and body-line cues.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Label("Available offline", systemImage: "arrow.down.circle")
                                        .font(.caption).foregroundStyle(Palette.green)
                                }
                            }
                            PrimaryButton(title: "Watch example", symbol: "play.fill") { example = Example(exercise: exercise) }
                                .accessibilityIdentifier("demo-example-\(exercise.rawValue)")
                        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    Text("Examples have prepared overlays and narration. Watching them doesn’t log training or earn progress. For live feedback, start a session and choose Use camera.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(.white).navigationTitle("Demo studio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .sheet(item: $example) { item in RecordedExampleView(exercise: item.exercise) }
        }
    }
}

private struct RecordedExampleView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var muted = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Recorded example, not your workout", systemImage: "play.rectangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.blue)
                    if let player {
                        VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    Toggle("Example audio", isOn: Binding(get: { !muted }, set: { muted = !$0; player?.isMuted = muted }))
                        .font(.subheadline)
                    Text("Prepared footage from the web prototype, including its original visual feedback. Use it to understand the experience; it isn’t a live assessment.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cavemantraining, CC BY-SA 4.0").font(.caption.weight(.semibold))
                        Text("Source footage credit retained from the contributor’s demonstration. Overlay and narration: Spottr prototype.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Creative Commons licence", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                            .font(.caption)
                    }
                }.padding(24)
            }.background(.white).navigationTitle(exercise.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .task {
                    guard let url = Bundle.main.url(forResource: "\(exercise.rawValue)_side", withExtension: "mp4") else { return }
                    let example = AVPlayer(url: url)
                    example.isMuted = muted
                    player = example
                    example.play()
                }
                .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
        }
    }
}
