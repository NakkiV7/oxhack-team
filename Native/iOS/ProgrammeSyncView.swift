import SwiftUI

struct ProgrammeSyncView: View {
    @Bindable var sync: ProgrammeSyncStore
    @State private var code = ""
    @State private var enteringCode = false
    @State private var error: String?
    private var shareCode: String { "Spottr programme code\n\(sync.profileSlot.uuidString.lowercased())" }
    var body: some View {
        Form {
            Section("Your saved programme") {
                Text("Keep a copy of your preferences and planned week in your account.")
                Label(sync.consented ? "Cloud saving is on" : "Saved on this phone", systemImage: sync.consented ? "icloud" : "iphone")
                    .font(.subheadline.weight(.semibold))
                if sync.withdrawalPending {
                    Text("Your cloud copy still needs to be removed. Retry when you have a connection.").font(.subheadline)
                    Button("Retry removal", systemImage: "arrow.clockwise") { Task { await sync.removeSavedProgramme() } }.buttonStyle(.bordered).disabled(sync.busy)
                } else if sync.consented {
                    Text("Save again whenever you want to update the cloud copy.").font(.caption).foregroundStyle(.secondary)
                    Button("Save this plan", systemImage: "icloud.and.arrow.up") { Task { await sync.upload() } }.buttonStyle(.borderedProminent).disabled(sync.busy)
                    Button("Review saved plan", systemImage: "icloud.and.arrow.down") { Task { await sync.read() } }.buttonStyle(.bordered).disabled(sync.busy)
                    Button("Turn off and remove cloud copy", role: .destructive) { Task { await sync.withdraw() } }.buttonStyle(.bordered)
                } else {
                    Button("Allow cloud saving", systemImage: "icloud") {
                        do { try sync.consent(); error = nil } catch { self.error = "Cloud saving is unavailable for this profile right now." }
                    }.buttonStyle(.bordered).disabled(sync.busy)
                }
                if sync.busy { ProgressView("Checking your saved programme…") }
                if let message = sync.message { Text(message).font(.caption).accessibilityIdentifier("programme-sync-status") }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
            if let remote = sync.pendingRemote {
                Section("Review before replacing your plan") {
                    Text("Saved \(remote.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("\(remote.preferences.weekdays.count) days each week, with \(remote.preferences.minutesPerSession) minutes per session.")
                    if let week = remote.programme {
                        DisclosureGroup("See the saved week") {
                            ForEach(week.days, id: \.id) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline.weight(.semibold))
                                    if let plan = day.plan {
                                        ForEach(plan.items, id: \.exerciseID) { item in
                                            Text("\(ExerciseCatalog.find(item.exerciseID)?.name ?? item.exerciseID), \(item.sets) × \(item.target) \(item.unit.rawValue).").font(.caption)
                                        }
                                    } else { Text("Rest day").font(.caption) }
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                    Text("Check that this plan belongs to the person using this profile. Recorded work stays on this phone.").font(.caption).foregroundStyle(.secondary)
                    Button("Use saved future plan", systemImage: "checkmark") {
                        do { try sync.restoreReviewed(); error = nil }
                        catch { self.error = "Finish your active workout first. Recorded and past days stay protected." }
                    }.buttonStyle(.borderedProminent).disabled(sync.busy)
                    Button("Keep this phone’s plan", systemImage: "iphone") { Task { await sync.keepLocalReviewed() } }.buttonStyle(.bordered).disabled(sync.busy)
                }
            }
            if sync.consented && !sync.withdrawalPending {
                Section("Continue on another device") {
                    Text("Save your plan, then share its code with your other device. Sign in to the same account and choose the matching adult training profile.").font(.subheadline)
                    ShareLink(item: shareCode) { Label("Share programme code", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    DisclosureGroup("Enter a saved programme code", isExpanded: $enteringCode) {
                        Text("Paste a code to review its plan. Pasting never replaces your current plan.").font(.caption).foregroundStyle(.secondary)
                        PasteButton(payloadType: String.self) { values in code = values.first ?? ""; error = nil }
                        TextField("Programme code", text: $code, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("programme-restore-code")
                        Button("Review this code", systemImage: "doc.text.magnifyingglass", action: reviewCode).buttonStyle(.bordered).disabled(sync.busy || code.isEmpty)
                    }
                }
            }
            Section {
                DisclosureGroup("What is saved online?") {
                    Text("Only training preferences and the planned week are saved. Your age, profile details, comfort answers, measurements, completed workouts and effort stay on this device. Cloud saving is optional and is available only for adult profiles.").font(.caption)
                    Text("Turning it off requests removal of the cloud copy. If removal is pending, retry to finish it.").font(.caption)
                }
            }
        }.navigationTitle("Saved programme").navigationBarTitleDisplayMode(.inline)
    }
    private func reviewCode() {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Spottr programme code\n"
        let reference = value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
        guard let id = UUID(uuidString: reference) else { error = "Paste a complete Spottr programme code and try again."; return }
        do { try sync.linkSlot(id); error = nil }
        catch { self.error = "Finish the current workout or request before reviewing another saved programme."; return }
        Task { await sync.read() }
    }
}
