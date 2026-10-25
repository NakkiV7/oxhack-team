import SwiftUI

struct ProfileSettingsView: View {
    let profileStore: NativeProfileStore
    let history: [SessionRecord]
    let exportData: () throws -> URL
    let resetHistory: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var weeklyTarget: Int
    @State private var goals: Set<TrainingAttribute>
    @State private var introduction: Introduction?
    @State private var deletion: Deletion?
    @State private var exportURL: URL?
    @State private var message: String?
    @State private var error: String?

    init(profileStore: NativeProfileStore, history: [SessionRecord],
         exportData: @escaping () throws -> URL, resetHistory: @escaping () throws -> Void) {
        self.profileStore = profileStore
        self.history = history
        self.exportData = exportData
        self.resetHistory = resetHistory
        _name = State(initialValue: profileStore.profile?.name ?? "")
        _weeklyTarget = State(initialValue: profileStore.profile?.weeklyTarget ?? 3)
        _goals = State(initialValue: profileStore.profile?.goals ?? [.strength])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Local profile", systemImage: "person.crop.circle").font(.headline)
                    Text("Saved on this iPhone. No account or sign-in is needed.").font(.caption).foregroundStyle(.secondary)
                    if let issue = profileStore.loadError { Text(issue).font(.caption).foregroundStyle(Palette.red) }
                    TextField("Your name (optional)", text: $name).textContentType(.givenName).textInputAutocapitalization(.words)
                    ProfileWeeklyTarget(target: $weeklyTarget)
                }
                Section("Your goals") { ProfileGoalPicker(goals: $goals).listRowInsets(EdgeInsets()) }
                Section {
                    Button("Save profile") { save() }.disabled(goals.isEmpty).accessibilityIdentifier("save-profile")
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Exercise lessons") {
                    NavigationLink { DemonstrationGuideView() } label: {
                        Label("Film your exercises", systemImage: "video")
                    }
                }
                Section("Your training") {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let summary = StreakSummary(history: history, now: timeline.date)
                        LabeledContent("Current streak", value: dayCount(summary.currentStreak))
                        LabeledContent("Longest streak", value: dayCount(summary.longestStreak))
                        LabeledContent("Training days this week", value: "\(summary.daysThisWeek)")
                    }
                    Text("Streaks use distinct days with a recorded non-zero set. Video replays and planned sessions don’t count.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Get started again") {
                    Button("Restart introduction") { introduction = .show }
                    Text("Review the introduction and update your goals. Your history stays saved.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    Button("Prepare history export") {
                        do { exportURL = try exportData(); error = nil }
                        catch { self.error = "The export couldn’t be prepared. \(error.localizedDescription)" }
                    }.accessibilityIdentifier("prepare-history-export")
                    if let exportURL { ShareLink("Share history export", item: exportURL) }
                    Text("Prepare a file, then choose where to save or share it. Nothing is sent automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Delete local training history", role: .destructive) { deletion = .history }
                        .accessibilityIdentifier("delete-local-history")
                    Button("Reset local profile", role: .destructive) { deletion = .profile }
                }
            }
            .scrollContentBackground(.hidden).background(.white).tint(Palette.ink)
            .navigationTitle("Profile & settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $introduction, onDismiss: reloadDraft) { _ in
                OnboardingView(profileStore: profileStore, onComplete: reloadDraft)
            }
            .alert(deletion == .profile ? "Reset local profile?" : "Delete local training history?",
                   isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                if let deletion {
                    Button(deletion == .profile ? "Reset profile" : "Delete local history", role: .destructive) { perform(deletion) }
                }
                Button("Cancel", role: .cancel) { deletion = nil }
            } message: {
                Text(deletion == .profile
                     ? "Remove your name, goals and weekly target from this iPhone? Training history stays saved."
                     : "Remove \(history.count) saved sessions from this iPhone? Your profile stays. This doesn’t delete copies already synced to other services.")
            }
            .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }.preferredColorScheme(.light)
    }

    private func save() {
        do {
            try profileStore.save(LocalProfile(name: name, weeklyTarget: weeklyTarget, goals: goals))
            name = profileStore.profile?.name ?? ""
            message = "Profile saved."
        } catch { self.error = error.localizedDescription }
    }

    private func reloadDraft() {
        name = profileStore.profile?.name ?? ""
        weeklyTarget = profileStore.profile?.weeklyTarget ?? 3
        goals = profileStore.profile?.goals ?? [.strength]
    }

    private func perform(_ action: Deletion) {
        do {
            if action == .profile { try profileStore.resetProfile(); reloadDraft(); message = "Local profile reset." }
            else { try resetHistory(); message = "Local training history deleted." }
            exportURL = nil
        } catch { self.error = error.localizedDescription }
        deletion = nil
    }

    private func dayCount(_ count: Int) -> String { "\(count) \(count == 1 ? "day" : "days")" }
    private enum Introduction: String, Identifiable { case show; var id: String { rawValue } }
    private enum Deletion { case profile, history }
}
