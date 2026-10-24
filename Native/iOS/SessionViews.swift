import SwiftUI
import UniformTypeIdentifiers

struct SessionView: View {
    @Bindable var store: TrainingStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.finish() } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                    .accessibilityLabel("Finish session now")
                Spacer()
                VStack(spacing: 4) {
                    Text(title).font(.headline)
                    if store.session.phase == .active || store.session.phase == .paused {
                        Text("Set \(store.session.setNumber) of 3").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: store.session.phase == .rest ? "wind" : "figure.strengthtraining.traditional").frame(width: 40, height: 40)
            }.padding(.horizontal, 14).padding(.top, 8)
            switch store.session.phase {
            case .active, .paused: LiveSetView(store: store)
            case .rest: RecoveryView(store: store)
            case .finished: FinishedView(store: store)
            case .idle: Color.white
            }
        }.background(.white).foregroundStyle(Palette.ink)
    }
    private var title: String {
        switch store.session.phase {
        case .rest: return "Take a breather."
        case .finished: return "Your session"
        default: return store.session.exercise.title
        }
    }
}

struct LiveSetView: View {
    @Bindable var store: TrainingStore
    @State private var guide = "top"
    @State private var importing = false
    @State private var pendingImport: URL?
    @State private var replaceCamera = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%02d", store.session.counter.reps)).font(.system(size: 70, weight: .semibold, design: .rounded)).tracking(-3).monospacedDigit()
                            .accessibilityIdentifier("rep-count")
                        Text("/ \(store.session.exercise.target)").foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Label(store.heartRate(at: Date()), systemImage: "heart.fill").font(.caption.weight(.medium))
                            Label(clockText(store.session.elapsed(at: store.now)), systemImage: "stopwatch").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                ZStack(alignment: .topLeading) {
                    Palette.surface
                    if case .camera = store.visionState, store.session.phase == .active {
                        CameraPreview(session: store.vision.capture)
                    } else if let image = store.image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Image("\(store.session.exercise.rawValue)-\(guide)").resizable().scaledToFit().padding(27)
                    }
                    if let frame = store.frame { PoseOverlay(frame: frame, exercise: store.session.exercise) }
                    Text(store.session.phase == .paused ? "Paused" : (store.hasInput ? store.visionState.message : "Movement guide"))
                        .font(.caption.weight(.medium)).padding(8).background(.white.opacity(0.9), in: Capsule()).padding(12)
                }.frame(height: 295).clipShape(RoundedRectangle(cornerRadius: 23))
                if !store.hasInput {
                    Picker("Movement phase", selection: $guide) {
                        Text("Top").tag("top"); Text("Middle").tag("mid"); Text("Bottom").tag("bottom")
                    }.pickerStyle(.segmented)
                }
                HStack(spacing: 14) {
                    Button("Use camera", systemImage: "camera") {
                        if store.hasInput { replaceCamera = true; return }
                        store.camera()
                    }
                    Spacer()
                    Button("Import video", systemImage: "film") { importing = true }
                }.font(.subheadline.weight(.medium)).buttonStyle(.plain)
                if !store.hasInput { Text(store.visionState.message).font(.caption).foregroundStyle(.secondary) }
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: store.session.phase == .paused ? "pause" : "arrow.down")
                        .padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.session.cue.text).font(.system(size: 19, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(store.session.phase == .paused ? "Your set is on hold." : "\(store.session.exercise.guide)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Metric(value: store.heartRate(at: context.date), title: "Apple Watch", symbol: "heart")
                    }
                    Metric(value: store.session.counter.lastRepDuration.map { String(format: "%.1f s", $0) } ?? "—", title: "Last rep", symbol: "speedometer")
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    store.session.phase == .paused ? store.resume() : store.pause()
                } label: {
                    Label(store.session.phase == .paused ? "Resume" : "Pause", systemImage: store.session.phase == .paused ? "play" : "pause")
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(19)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.12)))
                }.buttonStyle(.plain)
                PrimaryButton(title: "End set", symbol: "checkmark", action: store.endSet)
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.white)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            guard case .success(let url) = result else { return }
            if store.hasInput || store.session.counter.reps > 0 { pendingImport = url; return }
            store.video(url)
        }
        .confirmationDialog("Start a fresh set with this video?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Start fresh set") { if let url = pendingImport { store.video(url) }; pendingImport = nil }
        } message: { Text("The current set’s count will reset.") }
        .confirmationDialog("Start a fresh camera set?", isPresented: $replaceCamera) {
            Button("Start fresh set") { store.camera() }
        } message: { Text("The current set’s count will reset.") }
    }
}

struct RecoveryView: View {
    @Bindable var store: TrainingStore
    @State private var reserve: Int?
    @State private var reason: StopReason = .voluntary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 9) {
                        Text("Suggested rest").font(.caption).foregroundStyle(.secondary)
                        Text(clockText(max(0, 45 - context.date.timeIntervalSince(store.restStarted))))
                            .font(.system(size: 69, weight: .medium, design: .rounded)).tracking(-3).monospacedDigit()
                        Text("Take longer if you need it.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("How many more could you do?").font(.headline)
                    Text("Think clean reps, with the same form.").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(0..<4) { number in
                            Button {
                                reserve = number; feedback()
                            } label: {
                                Text(number == 3 ? "3+" : "\(number)").frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .foregroundStyle(reserve == number ? .white : Palette.ink)
                                    .background(reserve == number ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("\(number) reps in reserve")
                        }
                        Button("Skip") { reserve = nil; feedback() }.font(.caption).padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why did you stop?").font(.headline)
                    Picker("Why did you stop?", selection: $reason) {
                        ForEach(StopReason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if reason == .discomfort {
                    Label("Call it here. Give yourself time to recover.", systemImage: "hand.raised").font(.subheadline)
                } else {
                    PrimaryButton(title: store.session.sets.count == 6 ? "Review session" : "Ready for the next set", symbol: "arrow.right") { feedback(); store.next() }
                }
                Button("Finish session") { feedback(); store.finish() }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 15)
            }.padding(24)
        }
        .onAppear { reason = store.session.sets.last?.reason ?? .voluntary }
        .onChange(of: reason) { _, _ in feedback() }
    }
    private func feedback() { store.session.feedback(reserve: reserve, reason: reason) }
}

struct FinishedView: View {
    let store: TrainingStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label(store.error == nil ? "Session saved" : "Save interrupted", systemImage: store.error == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(store.error == nil ? Palette.green : Palette.red).padding(.top, 35)
                Text("That’s your session.").font(.system(size: 33, weight: .bold)).tracking(-1)
                Label(clockText(store.session.record.activeSeconds), systemImage: "clock").foregroundStyle(.secondary)
                HStack {
                    Metric(value: "\(store.session.record.reps)", title: "Reps", symbol: "figure.strengthtraining.traditional")
                    Metric(value: "\(store.session.sets.count)", title: "Sets", symbol: "square.3.layers.3d")
                }
                Divider()
                ForEach(store.session.sets) { set in
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(set.exercise.title) · Set \(set.number)").font(.headline)
                            Text(set.reason.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Text("\(set.reps) reps").font(.subheadline)
                    }
                }
                if let error = store.error {
                    Text(error).font(.subheadline).foregroundStyle(Palette.red)
                    PrimaryButton(title: "Retry save", symbol: "arrow.clockwise", action: store.save)
                }
                PrimaryButton(title: "Done", symbol: "checkmark") { store.presented = false }
            }.padding(24)
        }
    }
}
