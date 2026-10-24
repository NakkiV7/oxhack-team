import AVFoundation
import SwiftUI

struct ContentView: View {
    @AppStorage("macHost") private var host = ""
    @AppStorage("voice") private var voiceOn = true
    @State private var client = PushupClient()
    @State private var showSettings = false
    private let speaker = Speaker()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    if let state = client.state {
                        dashboard(state)
                    } else {
                        placeholder
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CoachRoute.self) { _ in CoachLogView(client: client) }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) { settings }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true // keep the screen on while exercising
            if host.isEmpty { showSettings = true } else { client.connect(to: host) }
        }
        .onChange(of: client.state?.total) { _, _ in announceRep() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            if let label = client.state?.label {
                Text("· \(label)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { voiceOn.toggle() } label: { Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash") }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        .font(.body)
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: client.state?.running == true ? .green : .orange
        case .connecting: .yellow
        default: .red
        }
    }

    private var statusText: String {
        switch client.status {
        case .idle: "Not connected"
        case .connecting: "Connecting to \(host)…"
        case .connected: client.state?.running == true ? "Live" : "Connected: start the camera on your Mac"
        case .failed(let message): "\(message). Retrying…"
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 60))
            Text("Waiting for your Mac").font(.headline)
            Text("Run `npm run ui` in the pushup folder, open the page on the Mac and start the camera. Both devices must be on the same Wi-Fi.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: Dashboard

    private func dashboard(_ s: PushupState) -> some View {
        VStack(spacing: 10) {
            Text(s.feedback.isEmpty ? " " : s.feedback)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(8)
                .background(toneColor(s.tone).opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(toneColor(s.tone))

            PoseView(state: s, image: client.frame)

            coachBubble

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.count)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("reps").font(.footnote).foregroundStyle(.secondary)
                    Text("\(s.good) good form").font(.footnote.weight(.medium)).foregroundStyle(.green)
                }
                .frame(width: 110, alignment: .leading)

                VStack(spacing: 8) {
                    gauge("Elbow angle", value: s.elbow, caption: "down ≤ \(Int(s.down))°, up ≥ \(Int(s.up))°",
                          markers: [s.down, s.up], good: (s.elbow ?? 180) <= s.down)
                    gauge("Body line", value: s.line, caption: "keep ≥ \(Int(s.minLine))° (straight)",
                          markers: [s.minLine], good: s.lineOK)
                }
            }

            history(s.reps)
        }
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "bad": .red
        case "warn": .orange
        default: .green
        }
    }

    /// Latest coach message as a chat bubble; tap to open the full log.
    private var coachBubble: some View {
        NavigationLink(value: CoachRoute()) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.purple).padding(.top, 2)
                Text(client.coach.last?.text ?? "Your AI coach will chime in as you work out.")
                    .font(.subheadline)
                    .foregroundStyle(client.coach.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
            }
            .padding(10)
            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Bar from 60° to 180° with tick marks at the thresholds.
    private func gauge(_ title: String, value: Double?, caption: String, markers: [Double], good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\(Int($0))°" } ?? "–").font(.footnote.monospacedDigit())
            }
            GeometryReader { geo in
                let frac = { (a: Double) in min(max((a - 60) / 120, 0), 1) * geo.size.width }
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(good ? Color.green : Color.accentColor).frame(width: frac(value ?? 60))
                    ForEach(markers, id: \.self) { m in
                        Rectangle().fill(.primary.opacity(0.6)).frame(width: 2).offset(x: frac(m))
                    }
                }
            }
            .frame(height: 10)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Fixed-size frame: only the list inside scrolls, so the rest of the dashboard stays put.
    private func history(_ reps: [Rep]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History").font(.footnote).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if reps.isEmpty {
                        Text("No reps yet").font(.footnote).foregroundStyle(.tertiary)
                    }
                    ForEach(Array(reps.enumerated().reversed()), id: \.offset) { _, rep in
                        HStack(alignment: .top) {
                            Text(rep.counted ? (rep.good ? "✅" : "⚠️") : "✖️")
                            VStack(alignment: .leading) {
                                Text(rep.counted ? "Rep \(rep.n): elbow \(rep.minElbow)°, line \(rep.minLine)°" : "Not counted")
                                    .font(.subheadline)
                                if let issue = rep.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(height: 140) // fits the last 3 reps
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Settings

    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.23", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Mac address")
                } footer: {
                    Text("The IP printed by `npm run ui` in the pushup folder (same Wi-Fi). Add :port if you changed PORT.")
                }
                Section {
                    Toggle("Speak reps and advice", isOn: $voiceOn)
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        showSettings = false
                        client.connect(to: host)
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Voice

    private func announceRep() {
        guard voiceOn, let s = client.state, let rep = s.reps.last else { return }
        if rep.counted {
            speaker.say(rep.good ? "\(s.count)" : "\(s.count). \(rep.issue ?? "")")
        } else {
            speaker.say(rep.issue ?? "Not counted")
        }
    }
}

struct CoachRoute: Hashable {}

/// Second page: coach messages and your questions in time order, with a box to ask a new question.
struct CoachLogView: View {
    let client: PushupClient
    @State private var draft = ""
    @State private var refs: [Source]?
    @FocusState private var typing: Bool

    private enum Entry: Identifiable {
        case tip(CoachMessage), qa(QA)
        var id: String {
            switch self {
            case .tip(let m): "tip-\(m.id)-\(m.time)"
            case .qa(let q): "qa-\(q.id)"
            }
        }
        var date: Date {
            switch self {
            case .tip(let m): m.date
            case .qa(let q): q.time
            }
        }
    }

    private var entries: [Entry] {
        (client.coach.map(Entry.tip) + client.chat.map(Entry.qa)).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if entries.isEmpty {
                            Text("No messages yet. The coach speaks every few reps or when your form slips. You can also ask a short question below.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            switch entry {
                            case .tip(let m): tip(m)
                            case .qa(let q): qa(q)
                            }
                        }
                        Text("General information from official sources (WHO, CDC, NHS, NIH). Not medical advice.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: entries.map(\.id)) { _, _ in withAnimation { proxy.scrollTo("end") } }
                .onChange(of: client.chat.last?.answer) { _, _ in withAnimation { proxy.scrollTo("end") } }
                .onAppear { proxy.scrollTo("end") }
            }
            Divider()
            inputBar
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { refs.map(RefList.init) }, set: { refs = $0?.sources })) { list in
            ReferencesView(sources: list.sources)
        }
    }

    private func timestamp(_ date: Date, _ extra: String = "") -> some View {
        Text(date.formatted(date: .omitted, time: .standard) + extra)
            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 6)
    }

    private func tip(_ m: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(m.text) } icon: { Image(systemName: "sparkles").foregroundStyle(.purple) }
                .padding(12)
                .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            timestamp(m.date, " · after \(m.reps) reps")
        }
    }

    private func qa(_ q: QA) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(q.question)
                .padding(12)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                if let answer = q.answer {
                    Text(answer).foregroundStyle(q.failed ? Color.red : Color.primary)
                    if !q.sources.isEmpty {
                        // Tappable citations; "References" opens the full list in a dialog.
                        HStack(spacing: 6) {
                            ForEach(q.sources) { s in
                                if let url = URL(string: s.url) {
                                    Link("[\(s.id)] \(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "link")", destination: url)
                                        .font(.caption)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        Button { refs = q.sources } label: { Label("References", systemImage: "list.bullet.rectangle") }
                            .font(.caption).buttonStyle(.bordered)
                    }
                } else {
                    HStack { ProgressView(); Text("Checking official sources…").foregroundStyle(.secondary) }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            timestamp(q.time)
        }
    }

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a short question…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                    .onChange(of: draft) { _, new in
                        if new.count > maxQuestionLength { draft = String(new.prefix(maxQuestionLength)) }
                    }
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.chat.last?.pending == true)
            }
            Text("\(draft.count)/\(maxQuestionLength)").font(.caption2)
                .foregroundStyle(draft.count >= maxQuestionLength ? .red : .secondary)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let q = draft
        draft = ""
        Task { await client.ask(q) }
    }
}

private struct RefList: Identifiable {
    let sources: [Source]
    var id: String { sources.map { String($0.id) }.joined(separator: ",") }
}

/// Full reference list for an answer, in a dialog.
struct ReferencesView: View {
    let sources: [Source]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sources) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text("[\(s.id)] \(s.title)").font(.subheadline.weight(.medium))
                    if let url = URL(string: s.url) {
                        Link(s.url, destination: url).font(.caption).lineLimit(3)
                    }
                }
            }
            .navigationTitle("References")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Says short phrases aloud so the user can hear the count without looking at the phone.
final class Speaker {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
}

#Preview {
    ContentView()
}
