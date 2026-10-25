import SwiftUI

struct CoachView: View {
    let store: TrainingStore
    let profile: LocalProfile?
    @State private var model = CoachModel()
    @State private var message = ""
    @FocusState private var composerFocused: Bool
    @State private var settingsPresented = false
    @State private var support = Set<String>()
    @State private var selected = Set<String>()
    @State private var task: Task<Void, Never>?
    @State private var logItem: CoachSavedPlan.Item?
    @State private var removingPlan = false
    private let supports = Array(Set(ExerciseCatalog.all.compactMap(\.support))).sorted()

    init(store: TrainingStore, profile: LocalProfile? = nil) { self.store = store; self.profile = profile }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introduction
                        WeeklyCoachPanel(model: model, store: store, profile: profile, support: support) { week in
                            let draft = message
                            run { await model.proposeWeek(message: draft, week: week, history: store.history, support: support) }
                        }
                        if let plan = model.approvedPlan { approvedPlan(plan) }
                        DisclosureGroup("What support do you have?") {
                            ForEach(supports, id: \.self) { name in
                                Toggle(name, isOn: Binding(get: { support.contains(name) }, set: { if $0 { support.insert(name) } else { support.remove(name) } }))
                                    .font(.subheadline).tint(Palette.blue)
                            }.padding(.top, 8)
                        }.font(.subheadline.weight(.medium)).disabled(model.isLoading)
                        Button {
                            let draft = message
                            run { await model.propose(message: draft, history: store.history, support: support) }
                        } label: {
                            Label("Propose a workout", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(17).background(Palette.blue, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(model.isLoading)
                        if let proposal = model.proposal { proposalReview(proposal) }
                        ForEach(Array(model.turns.enumerated()), id: \.offset) { _, turn in
                            HStack {
                                if turn.role == .user { Spacer(minLength: 32) }
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(turn.role == .user ? "YOU" : "SPOTTR · GEMINI").font(.system(size: 9, weight: .bold)).tracking(1)
                                    Text(turn.text).font(.subheadline).textSelection(.enabled)
                                }.padding(17).foregroundStyle(turn.role == .user ? .white : Palette.ink)
                                    .background(turn.role == .user ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: 19))
                                if turn.role == .model { Spacer(minLength: 14) }
                            }
                        }
                        if model.isLoading {
                            HStack { ProgressView().tint(Palette.blue); Text(model.loadingText).font(.subheadline); Spacer(); Button("Cancel", action: cancel) }
                        }
                        if let error = model.error {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(error).font(.caption).foregroundStyle(Palette.red)
                                Button(model.retryTitle) { run { await model.retry(history: store.history, support: support) } }
                                    .font(.caption.weight(.semibold)).disabled(!model.canRetry)
                            }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(24)
                }.background(.white)
                    .scrollDismissesKeyboard(.immediately)
                    .accessibilityIdentifier("coach-conversation")
                    .onChange(of: model.turns.count) { _, _ in withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
                    .safeAreaInset(edge: .bottom) { composer }
            }.navigationTitle("Coach").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if model.isLoading { Button("Cancel", action: cancel).accessibilityLabel("Cancel coach request") }
                    }
                    ToolbarItem(placement: .principal) {
                        if model.isLoading {
                            HStack(spacing: 7) {
                                ProgressView().tint(Palette.blue)
                                Text(model.loadingText).font(.caption.weight(.medium))
                            }.accessibilityElement(children: .combine).accessibilityIdentifier("coach-loading-status")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button { composerFocused = false; settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Coach settings") } }
                .sheet(isPresented: $settingsPresented) { CoachSettingsView() }
                .alert("Remove saved workout?", isPresented: $removingPlan) {
                    Button("Remove workout", role: .destructive) { model.removeApprovedPlan() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Completed sessions stay in your history.") }
                .sheet(item: $logItem) { item in
                    if let entry = ExerciseCatalog.find(item.exerciseID) {
                        ManualWorkoutView(store: store, entry: entry, initialCount: item.target, initialSets: item.sets)
                    }
                }
                .onChange(of: model.proposal?.generationID) { _, _ in selected = [] }
                .onAppear { model.updateProfile(profile) }
                .onChange(of: profile?.goals) { _, _ in profileChanged() }
                .onChange(of: profile?.weeklyTarget) { _, _ in profileChanged() }
                .onChange(of: support) { _, _ in selected = []; task?.cancel(); model.invalidateContext() }
                .onChange(of: store.history) { _, _ in task?.cancel(); model.invalidateContext() }
                .onDisappear(perform: cancel)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your next move.").font(.system(size: 32, weight: .bold)).tracking(-1)
            CoachGoalContext(profile: profile, identifier: "coach-goal-context")
            Text("Plan your week, build a single workout, or talk through your recorded training.").font(.subheadline).foregroundStyle(.secondary)
            Text(profile == nil
                 ? "Send, Propose a workout and Propose my week share your current text, recent conversation, training sets and recorded Watch summaries with Gemini."
                 : "Send, Propose a workout and Propose my week share your current text, recent conversation, selected goals, weekly target, training sets and recorded Watch summaries with Gemini. Your profile name isn’t added automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }.contentShape(Rectangle()).onTapGesture { composerFocused = false }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask your coach", text: $message, axis: .vertical).lineLimit(1...4).font(.subheadline)
                .focused($composerFocused)
                .padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15)).accessibilityIdentifier("coach-message")
            Button {
                let text = message; message = ""
                run { await model.send(message: text, history: store.history, support: support) }
            } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).background(Palette.blue, in: Circle()).foregroundStyle(.white) }
                .accessibilityLabel("Send message").disabled(model.isLoading || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.count > 4000)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.white)
    }

    private func proposalReview(_ proposal: WorkoutProposal) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Make it yours.").font(.title3.bold())
            Text(proposal.rationale.text).font(.subheadline).foregroundStyle(.secondary)
            ForEach(proposal.items, id: \.exerciseID) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.exerciseID) }, set: { if $0 { selected.insert(item.exerciseID) } else { selected.remove(item.exerciseID) } })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID).font(.subheadline.weight(.semibold))
                        Text("\(item.sets) × \(item.target) \(item.unit == .reps ? "reps" : "sec") · \(item.restSeconds)s rest").font(.caption).foregroundStyle(.secondary)
                    }
                }.tint(Palette.blue)
            }
            Button("Approve & save selected exercises") { model.approve(selected: selected, currentSupport: support) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(selected.isEmpty ? Palette.muted : Palette.blue).disabled(selected.isEmpty)
            Text("Choose exercises to save your plan. Log only the work you complete.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(19).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func approvedPlan(_ plan: CoachSavedPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your saved plan", systemImage: "checkmark.circle").font(.headline).foregroundStyle(Palette.green)
            ForEach(plan.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID).font(.subheadline.weight(.medium))
                        Text("\(item.sets) × \(item.target) \(item.unit == .reps ? "reps" : "sec") · \(item.restSeconds)s rest").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Log") { composerFocused = false; logItem = item }.font(.subheadline.weight(.semibold)).accessibilityLabel("Log \(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID)")
                }
            }
            PrimaryButton(title: "Start saved workout", symbol: "play") { composerFocused = false; store.startPlan(plan, availableSupport: support) }
                .accessibilityIdentifier("start-saved-workout")
            Text("Follow the saved order with manual reps and active hold timers. Log is also available after training.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Remove saved workout", role: .destructive) { removingPlan = true }
                .font(.subheadline).foregroundStyle(Palette.red).accessibilityIdentifier("remove-saved-workout")
            if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
        }.padding(19).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func run(_ action: @escaping @MainActor () async -> Void) { composerFocused = false; task?.cancel(); task = Task { await action() } }
    private func cancel() { composerFocused = false; task?.cancel(); model.cancel() }
    private func profileChanged() { task?.cancel(); model.updateProfile(profile); selected = [] }
}

private struct CoachGoalContext: View {
    let profile: LocalProfile?
    let identifier: String
    var body: some View {
        if let profile {
            Text("\(profile.goals.map(\.title).sorted().joined(separator: " · ")) · \(profile.weeklyTarget) \(profile.weeklyTarget == 1 ? "day" : "days")/week")
                .font(.caption.weight(.medium)).accessibilityIdentifier(identifier)
        }
    }
}

struct CoachSettingsView: View {
    private enum Field: Hashable { case url, token }
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var url = CoachSettings.gatewayURL
    @State private var token = CoachSettings.token() ?? ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Gateway URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($focusedField, equals: .url)
                    SecureField("Gateway access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .token)
                    Text("Use the access token for your Spottr gateway. Your Gemini provider key stays on the server. The access token is stored in this iPhone’s Keychain.").font(.caption)
                        .contentShape(Rectangle()).onTapGesture { focusedField = nil }
                }
                Section {
                    Button("Save connection") {
                        focusedField = nil
                        do { try CoachSettings.save(url: url, token: token); dismiss() }
                        catch { self.error = "Use an HTTPS gateway URL and its access token. Localhost HTTP is supported for development." }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
                }
            }.scrollDismissesKeyboard(.immediately).accessibilityIdentifier("coach-settings-form")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if focusedField != nil { KeyboardDismissBar(identifier: "coach-settings-keyboard-done") { focusedField = nil } }
                }
                .navigationTitle("Coach settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { focusedField = nil; dismiss() } }
                }
        }
    }
}

struct CoachSummaryCard: View {
    let history: [SessionRecord]
    let kind: CoachSummaryKind
    let profile: LocalProfile?
    @State private var model = CoachModel()
    @State private var task: Task<Void, Never>?
    init(history: [SessionRecord], kind: CoachSummaryKind, profile: LocalProfile? = nil) {
        self.history = history; self.kind = kind; self.profile = profile
    }
    init(record: SessionRecord, profile: LocalProfile? = nil) { history = [record]; kind = .session; self.profile = profile }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Coach insight", systemImage: "sparkles").font(.headline)
            CoachGoalContext(profile: profile, identifier: "coach-summary-goal-context")
            if let summary = model.summary {
                Text(summary.headline.text).font(.subheadline.weight(.semibold))
                ForEach(Array(summary.insights.enumerated()), id: \.offset) { _, insight in Text(insight.text).font(.subheadline) }
                Text(summary.focus.text).font(.subheadline).foregroundStyle(.secondary)
                Text("Generated with Gemini from the recorded facts shared for this report.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Share this \(kind == .weekly ? "week’s" : "session’s") training sets and recorded Watch summaries\(profile == nil ? "" : ", plus your selected goals and weekly target") with Gemini when you tap.").font(.caption).foregroundStyle(.secondary)
                if profile != nil { Text("Your optional profile name stays on this iPhone.").font(.caption).foregroundStyle(.secondary) }
            }
            if model.isLoading {
                HStack { ProgressView(); Text(model.loadingText).font(.caption); Spacer(); Button("Cancel") { task?.cancel(); model.cancel() } }
            } else {
                Button(model.summary == nil ? "Generate coach summary" : "Regenerate summary") { task = Task { await model.summarize(history: history, kind: kind) } }
                    .font(.subheadline.weight(.semibold)).disabled(history.isEmpty)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .onAppear { model.updateProfile(profile) }
            .onChange(of: profile?.goals) { _, _ in task?.cancel(); model.updateProfile(profile) }
            .onChange(of: profile?.weeklyTarget) { _, _ in task?.cancel(); model.updateProfile(profile) }
            .onChange(of: history) { _, _ in task?.cancel(); model.invalidateContext() }
            .onDisappear { task?.cancel(); model.cancel() }
    }
}
