import SwiftUI

struct ProgrammeSyncView: View {
    @Bindable var sync: ProgrammeSyncStore
    @State private var slot = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Optional cloud programme") {
                Text("Save your training preferences and planned week to your signed-in account. Your age, profile details, comfort answers, measurements, workouts and effort stay on this device.")
                Text(sync.consented ? "Sync consent is on for this adult profile." : "Local syncing is off.").font(.subheadline.weight(.semibold))
                if sync.withdrawalPending {
                    Text("Removal is pending. This action checks the saved copy once, then removes it. It does not turn syncing back on.").font(.caption)
                    Button("Remove saved programme") { Task { await sync.removeSavedProgramme() } }.disabled(sync.busy)
                } else if sync.consented {
                    Button("Save this phone’s plan") { Task { await sync.upload() } }.disabled(sync.busy)
                    Button("Read saved plan") { Task { await sync.read() } }.disabled(sync.busy)
                    Button("Turn off and remove cloud programme", role: .destructive) { Task { await sync.withdraw() } }
                } else {
                    Button("Allow plan sync") { do { try sync.consent(); error = nil } catch { self.error = "This profile cannot enable sync right now." } }.disabled(sync.busy)
                }
                if sync.busy { ProgressView("Checking your saved configuration…") }
                if let message = sync.message { Text(message).font(.caption).accessibilityIdentifier("programme-sync-status") }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }
            if let remote = sync.pendingRemote {
                Section("Review saved configuration") {
                    Text("Saved \(remote.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("\(remote.preferences.weekdays.count) days each week · \(remote.preferences.minutesPerSession) minutes per session")
                    if let week = remote.programme {
                        ForEach(week.days, id: \.id) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.date.formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline.weight(.semibold))
                                Text(day.plan?.items.map { "\(ExerciseCatalog.find($0.exerciseID)?.name ?? $0.exerciseID): \($0.sets) × \($0.target) \($0.unit.rawValue)" }.joined(separator: ", ") ?? "Rest").font(.caption)
                            }
                        }
                    }
                    Button("Use saved future programme") {
                        do { try sync.restoreReviewed(); error = nil }
                        catch { self.error = "Finish your active workout first. Recorded and past days cannot be replaced." }
                    }.disabled(sync.busy)
                    Button("Keep this phone’s plan") { Task { await sync.keepLocalReviewed() } }.disabled(sync.busy)
                }
            }
            if sync.consented && !sync.withdrawalPending {
                Section("Use this profile on another device") {
                    Text("Only link the saved programme belonging to this same adult training profile. This reference is not your account or local profile ID.").font(.caption)
                    Text(sync.profileSlot.uuidString.lowercased()).font(.caption.monospaced()).textSelection(.enabled)
                    TextField("Saved programme reference", text: $slot).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Link this profile’s saved programme") {
                        guard let id = UUID(uuidString: slot) else { error = "Enter a valid saved programme reference."; return }
                        do { try sync.linkSlot(id); error = nil }
                        catch { self.error = "Finish the current workout or request before linking a saved programme." }
                    }.disabled(sync.busy)
                }
            }
        }.navigationTitle("Programme sync")
    }
}
