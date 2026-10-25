# Local profile and onboarding wiring

## New APIs

- `NativeProfileStore(url: URL? = nil)` owns an optional `profile` and optional `loadError`. `save(_ profile: LocalProfile) throws` writes atomically before updating observable state. `resetProfile() throws` removes only its profile file.
- Default storage is `Application Support/Spottr/profile.json`, using the same valid UUID `SPOTTR_DATA_NAMESPACE` subfolder convention as training history. Missing profile means first-run setup; corrupt data is reported and preserved until an explicit save/reset.
- `LocalProfile(name: String = "", weeklyTarget: Int = 3, goals: Set<TrainingAttribute> = [.strength]) throws` accepts a guest name, trims whitespace, bounds name to 40 characters and target to 1–7 training days/week, and requires a goal. Decoding applies the same validation.
- `OnboardingView(profileStore: NativeProfileStore, onComplete: () -> Void = {})` presents three steps and saves only on completion. Existing-profile introduction has a Cancel action. Restarting it does not reset history or write partial drafts.
- `ProfileSettingsView(profileStore: NativeProfileStore, history: [SessionRecord], exportData: () throws -> URL, resetHistory: () throws -> Void)` owns a navigation stack for sheet presentation. Provide actual current history. Export prepares a local file, then the person chooses Share; the closure must not send data. History reset is called only after destructive confirmation and must remove local history only. It does not imply deletion from synced services.
- `StreakSummary(history: [SessionRecord], now: Date = Date(), calendar: Calendar = .current)` exposes `currentStreak`, `longestStreak`, `daysThisWeek`, `totalTrainingDays`, and `trainedToday`.

`SpottrApp` now owns one profile store and passes it to `SpottrRoot`. Normal first launch shows onboarding before the tabs. A valid UUID `SPOTTR_DATA_NAMESPACE` bypasses that first launch for other UI flows; `SPOTTR_FORCE_ONBOARDING=1` explicitly shows it. The visible Today button is identified as `profile-settings`. Settings dismissal precedes first-run onboarding after a profile reset, so sheets do not compete. The accepted `onboarding-skills` raster asset is registered.

`TrainingStore.exportHistory() throws -> URL` prepares a unique local JSON file from saved history, with no network operation. Its app-owned export folder is a sibling of the exact history file (`history.json.exports`), so default, namespaced and injected test stores remain separate; the export folder is excluded from backup. `clearHistory() throws` rejects active, paused and resting workouts before touching files. It removes the history file, updates observable history, then removes only that store's prepared-export folder. External copies saved or shared elsewhere and other stores' exports remain. A cleanup failure is reported rather than claiming full deletion; profile reset remains separate. The underlying `HistoryStore.export(to:)` validates/encodes records before writing atomically and rejects exporting onto the source path; `clear()` removes only that history file. Today and settings both derive streaks from the same current saved history; Today also shows selected goals and the weekly target.

## Streak evidence

Distinct local calendar days with at least one positive recorded rep/hold count. Video replay, zero quantities, empty sessions, future timestamps and invalid dates do not count. Session/set IDs are deduplicated before days. A streak ending yesterday remains current until today is over. Dates use calendar arithmetic across timezone and daylight-saving changes. Weekly targets and saved plans never create evidence. Discomfort is not an achievement qualification here; this summary simply records that training occurred.

## Verification performed

- Test-first missing-type/codec red checks; runtime profile-validation and false-streak failures observed before implementation.
- Full shared Swift package tests passed on 24 October 2026, including 77 Swift Testing tests and the XCTest suites then present. A concurrent agent's incomplete secondary-camera test initially prevented compilation; it was resolved in that agent's shared changes before the final full run.
- Ten isolated profile, streak and native persistence tests pass. Native persistence tests copy `NativeProfileStore.swift` into a temporary Swift package with the current core and `Tests/Native/ProfileStoreTests.swift`; only UUID temporary directories are changed. Existing app history is not touched.
- Standalone `swiftc -typecheck` for an arm64 iOS 17 simulator target passed with current core types, these three native files and the actual `Palette` / `PrimaryButton` definitions. This is not an app build or simulator interaction test.
- `Tests/UI/ProfileFlowTests.swift` was added before the views. Root captured its missing-onboarding-control RED before app wiring. It expects a fresh UUID namespace and uses `SPOTTR_FORCE_ONBOARDING=1` to request the real introduction even if other UI-test flows bypass it. The wired UI flow awaits root's simulator run.
- App-wiring follow-up: missing export/clear and introduction-routing API RED checks were observed. Fourteen isolated profile/streak/data-control tests now pass, covering export round-trip/source preservation, history-only reset, corrupt-history preservation and real/test first-run routing.
- Read-only `swiftc -typecheck` for all current core, shared Apple and native iOS sources passed for arm64 iOS 26 Simulator with the existing MediaPipe framework imports. This is not an app build or runtime test. `Tests/iOS/ProfileDataControlsTests.swift` adds the native bridge check for active/paused/rest deletion rejection and post-finish reset; root must register/run it.

## Integrated acceptance

The exact staged feature passed 37 XCTest and 84 Swift Testing cases, four isolated native-profile persistence cases, and eight native simulator cases. The simulator cases cover onboarding/goal selection/restart/cancel, filming-guide navigation, byte-preserving lesson import, corrupt-index and failed-removal preservation, unsafe lesson paths, and history export/deletion isolation. Failed active/paused history deletion preserves prepared exports; successful deletion removes only the current history domain's app-owned copies and preserves external copies and other domains.

This verifies local behavior on the existing Musalli-Test simulator. It does not establish physical file-picker/video playback or cloud account/sync acceptance. See [the app guide](app-guide.md) for the user flow. These views use no automatic animation.
