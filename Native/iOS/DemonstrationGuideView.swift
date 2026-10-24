import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct DemonstrationGuideView: View {
    @State private var library = DemonstrationVideoLibrary()
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Your filming checklist").font(.title2.bold())
                Text("\(library.recordedIDs.count) of \(ExerciseDemonstrationGuide.all.count) filmed · \(library.importedCount) local videos added")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Film each exercise when you’re ready. Add your own recording to see it beside the guide graphic.")
                    .font(.subheadline)
                if let error = error ?? library.loadError { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
            Section("All exercises") {
                ForEach(ExerciseDemonstrationGuide.all) { guide in
                    HStack(spacing: 14) {
                        Button {
                            do { try library.markRecorded(guide.id, recorded: !library.recordedIDs.contains(guide.id)) }
                            catch { self.error = error.localizedDescription }
                        } label: {
                            Image(systemName: library.recordedIDs.contains(guide.id) ? "checkmark.square.fill" : "square")
                                .font(.title3).foregroundStyle(Palette.ink)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Mark \(guide.name) as \(library.recordedIDs.contains(guide.id) ? "not filmed" : "filmed")")
                            .accessibilityIdentifier("filmed-\(guide.id)")
                        NavigationLink {
                            DemonstrationGuideDetail(guide: guide, library: library)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(guide.name).font(.subheadline.weight(.medium))
                                Text(library.url(for: guide.id) == nil ? "Recording guide" : "Local lesson video added")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("guide-\(guide.id)")
                    }.padding(.vertical, 5)
                }
            }
            Section {
                Text("Videos are stored privately on this iPhone. Filmed is your own checklist; these lesson clips don’t create workout records.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Film your exercises").navigationBarTitleDisplayMode(.inline)
            .onAppear { library.reload() }
    }
}

private struct DemonstrationGuideDetail: View {
    let guide: ExerciseDemonstrationGuide
    @Bindable var library: DemonstrationVideoLibrary
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemonstrationComparisonContent(guide: guide, library: library)
                Label("Camera view", systemImage: "camera").font(.headline)
                Text(guide.cameraAngle.instructions).font(.subheadline)
                Text(guide.framing).font(.subheadline).foregroundStyle(.secondary)
                if let support = guide.support { Label("Include the support: \(support)", systemImage: "square.dashed").font(.subheadline) }
                Text("Record the full cycle").font(.headline)
                ForEach(Array(guide.phases.enumerated()), id: \.offset) { index, phase in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.caption.bold()).frame(width: 25, height: 25)
                            .background(Palette.surface, in: Circle())
                        Text(phase).font(.subheadline)
                    }
                }
                Text(guide.takeInstructions).font(.subheadline)
                Text(guide.sideInstructions).font(.subheadline.weight(.medium))
                ForEach(guide.recordingInstructions, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Toggle("I filmed this exercise", isOn: Binding(
                    get: { library.recordedIDs.contains(guide.id) },
                    set: { value in
                        do { try library.markRecorded(guide.id, recorded: value) }
                        catch { self.error = error.localizedDescription }
                    }
                )).tint(Palette.ink)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }.padding(24)
        }.background(.white).navigationTitle(guide.name).navigationBarTitleDisplayMode(.inline)
    }
}

struct DemonstrationComparisonView: View {
    let exerciseID: String
    @State private var library = DemonstrationVideoLibrary()
    var body: some View {
        Group {
            if let guide = ExerciseDemonstrationGuide.find(exerciseID) {
                DemonstrationComparisonContent(guide: guide, library: library)
            }
        }.onAppear { library.reload() }
    }
}

private struct DemonstrationComparisonContent: View {
    let guide: ExerciseDemonstrationGuide
    @Bindable var library: DemonstrationVideoLibrary
    @State private var importing = false
    @State private var replacing: URL?
    @State private var removing = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 9) {
                    Text("Guide graphic").font(.caption.weight(.medium))
                    Group {
                        if UIImage(named: guide.art) != nil { Image(guide.art).resizable().scaledToFit() }
                        else { Image(systemName: "figure.strengthtraining.traditional").resizable().scaledToFit().padding(35) }
                    }.frame(maxWidth: .infinity).frame(height: 200)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityLabel(guide.name)
                }.frame(maxWidth: .infinity)
                if let url = library.url(for: guide.id) {
                    VStack(spacing: 9) {
                        Text("Your lesson video").font(.caption.weight(.medium))
                        DemonstrationMoviePlayer(url: url).id(url)
                    }.frame(maxWidth: .infinity)
                }
            }
            if library.isImporting {
                HStack { ProgressView(); Text("Adding your video…").font(.caption) }
            } else {
                HStack {
                    Button(library.url(for: guide.id) == nil ? "Add your recording" : "Replace recording", systemImage: "film") { importing = true }
                        .font(.subheadline.weight(.medium)).accessibilityIdentifier("add-lesson-\(guide.id)")
                    Spacer()
                    if library.url(for: guide.id) != nil {
                        Button("Remove", role: .destructive) { removing = true }.font(.caption)
                    }
                }
            }
            Text("MOV, MP4 or M4V · up to 2 minutes and 100 MB · private on this iPhone")
                .font(.caption2).foregroundStyle(.secondary)
            if let error = error ?? library.loadError { Text(error).font(.caption).foregroundStyle(Palette.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            guard case .success(let url) = result else { return }
            if library.url(for: guide.id) != nil { replacing = url }
            else { add(url) }
        }
        .confirmationDialog("Replace this lesson video?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            Button("Replace private lesson copy") { if let url = replacing { add(url) }; replacing = nil }
        } message: { Text("The current private copy for \(guide.name) will be replaced by the video you selected.") }
        .alert("Remove this lesson video?", isPresented: $removing) {
            Button("Remove private copy", role: .destructive) {
                do { try library.removeMovie(for: guide.id) }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your original source video and filming checklist will be kept.") }
        .onDisappear { task?.cancel() }
    }
    private func add(_ url: URL) {
        error = nil
        task = Task {
            do { try await library.importMovie(from: url, exerciseID: guide.id) }
            catch is CancellationError {}
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct DemonstrationMoviePlayer: View {
    @State private var player: AVPlayer
    @State private var playing = false
    @Environment(\.scenePhase) private var scenePhase
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VStack(spacing: 8) {
            DemonstrationPlayerSurface(player: player).frame(height: 200)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).clipShape(RoundedRectangle(cornerRadius: 15))
            Button(playing ? "Pause lesson" : "Play lesson", systemImage: playing ? "pause.fill" : "play.fill") {
                if playing { player.pause() } else { player.play() }
                playing.toggle()
            }.font(.caption.weight(.medium))
        }.onDisappear { player.pause() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player.pause(); playing = false } }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
                playing = false; player.seek(to: .zero)
            }
    }
}

private struct DemonstrationPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> Surface {
        let view = Surface(); view.backgroundColor = .clear; view.isOpaque = false
        view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.isOpaque = false
        return view
    }
    func updateUIView(_ view: Surface, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.playerLayer.player = nil }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
