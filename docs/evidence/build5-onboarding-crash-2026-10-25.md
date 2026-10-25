# Build 5 onboarding crash investigation

The reported physical crash immediately after onboarding in **TestFlight 0.1 (5)** remains unresolved. No physical crash report or reproduction is available. This investigation changes documentation only; it does not establish a fix.

## Release and symbols

The investigated source is **`f3eae89ced8547e283bd93abe6c560c9e1ce8e2c`**, preserved in the primary checkout's ignored `.local/release/mvp-build-5/source/`. Later energy, keyboard, rewards and current integration changes are outside this release.

Fresh read-only checks on 25 October 2026 found:

- The archived iPhone Info.plist identifies `com.omarchoudhry.spottr`, version **0.1**, build **5**, minimum OS **26.0**, SDK **iphoneos27.0**. These are artifact properties; the affected phone's model and installed OS remain unknown.
- `xcrun dwarfdump --uuid` reports **`05A18349-C958-31DD-9DCF-965C757683D8` (arm64)** for both the archived iPhone executable and `Spottr.app.dSYM/Contents/Resources/DWARF/Spottr`.
- The [release audit](testflight-build-5-2026-10-25.md) previously hash-checked all 135 tracked Native/Shared files against this commit. The existing optimized probe handoff also records zero source mismatches. Those source/resource checks do not establish physical runtime acceptance.

The matching archive and dSYM remain under `.local/release/mvp-build-5/Spottr.xcarchive/`. Compare any incoming report's Spottr image UUID before using these symbols. A different build/image UUID needs its own symbols, even if the visible version is similar. See [Apple's symbolication guidance](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report).

## Report availability

At **07:20:23.211 UTC on 25 October 2026**, a bounded ASC request for this app's beta crash-feedback submissions returned **0 records and no next page** (`limit=20`, newest first, build relationship included). The prior 06:23 UTC query was also empty. An initial collection reached a local response-save error; one manual retry after correcting that collector preserved the successful response. No polling or automatic retry was added.

This endpoint covers [crash feedback submitted by beta testers](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions). An empty response does not show that the reported crash did not happen or that all Apple/device diagnostics are empty. Xcode Organizer's earlier missing-account-login gate remains; Organizer was not reopened in this lane.

A read-only filename search found no Spottr/Jetsam reports in the existing local `Library/Logs/DiagnosticReports` or `Library/Developer/Xcode/Products` directories. `Library/Logs/CrashReporter/MobileDevice` was absent. This bounded Mac search is not a search of the affected phone or Apple's Organizer service.

The raw ASC response, collector and artifact-check receipt remain private in this chat's managed worktree under ignored `.local/build5-crash-investigation/`. Do not commit raw reports, tester details, authentication material or signed download URLs.

## Existing runtime evidence

The primary checkout's private `.local/build5-onboarding-probe-20261025/diagnostic-report.md` records these completed checks against the frozen source; they were read, not rerun:

- Original onboarding case: **1/1 passed**, Mobility, focused name keyboard, completion, Profile and restart/Cancel.
- Expanded final run `06:47:32_41567da4`: **2/2 passed**, 138.7 seconds total. One case used all goals, Regular practice, seven days and a blank name, including cold-relaunch persistence. The other used Mobility, Starting out, one day and an Arabic/emoji name with the keyboard open. Both completed onboarding and visited all tabs, practice suggestions and empty charts without Send/Start.
- Earlier expanded attempts stopped at Stepper/text accessibility assertions before completion. The harness was corrected; those failures were not reproduced app crashes.

The probe used Release optimization, unsigned simulator execution and `ENABLE_TESTABILITY=YES`. It was not the delivered arm64 executable on the affected phone. No simulator/device UI, installation, reset, native build or upload was performed in this investigation.

## Bounded source trace

The frozen source shows this completion path:

1. `OnboardingView.advance()` constructs a validated `LocalProfile`, then calls `NativeProfileStore.save`.
2. Saving creates the parent directory and writes JSON atomically before publishing the observable profile. Thrown validation/write errors stay in onboarding through its error handler.
3. The completion closure in `SpottrRoot` sets `introductionPresented = false`, replacing the introduction with the Today/Progress/Skills/Coach tabs. `advance()` then calls its environment dismiss action.

The dismissal after root replacement remains **an unconfirmed hypothesis**. The existing optimized cases exercise that sequence successfully. There is no report, exception or failing regression that justifies changing it.

The tab construction and associated state introduce local profile/history projections, the Today timeline, progress charts and Coach saved-plan decoding. `CoachModel` initialization and profile updates do not issue a provider request; the reviewed requests are behind user actions. First completion does not call session start, pose-detector preparation or Pi capture start.

Some runtime work already exists before completion: `TrainingStore` constructs `VisionWorker` (capture session/Core Image context), local speech playback and a secondary-camera worker; `CompanionLink` activates a supported WatchConnectivity session. The app task ticks coaching and publishes snapshots during onboarding too. Their actual physical callbacks, device memory pressure and OS-specific behavior remain unverified. These observations locate boundaries for an incoming stack/log; they do not identify a culprit or exclude framework/runtime failures.

No production change or new regression test was made because no failing app behavior was reproduced. Existing profile/history files and onboarding restart/Cancel behavior were left intact.

## Next decisive evidence and coordinated checks

Obtain the affected phone model, exact iOS version, approximate incident time/timezone, and the matching complete `.ips`/`.crash` report or `JetsamEvent` report. Also retain the exact final onboarding choices, whether the keyboard was open, and what happens when the app is reopened. Preserve installed data; deleting the app or resetting the profile would erase potentially relevant state.

When Organizer is unavailable, Apple documents collecting the app log or `JetsamEvent` near the incident from **Settings → Analytics & Improvements → Analytics Data** and sharing that file privately. See [Apple's collection instructions](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs). No report has been collected from the phone yet.

Before proposing a fix, confirm the report's bundle/version/build and image UUID, symbolicate with the matching dSYM, and distinguish a Swift trap, Objective-C exception, watchdog or memory termination. Retain the exception/termination reason, triggered thread, relevant backtrace, binary images and timestamp privately. Use that evidence to create the smallest failing regression, then verify the fix with the primary chat's coordinated native queue and affected-device acceptance.

Existing selectors available to the primary chat, if new evidence warrants another run:

- Repository: `SpottrUITests/ProfileFlowTests/testLocalOnboardingRequiresAGoalAndCanBeRestartedWithoutErasingProfile`.
- Frozen private probe: `SpottrUITests/Build5OnboardingVariantTests/testAllGoalsRegularPracticeAndSevenDaysMountEveryTabAndPersistBlankName`.
- Frozen private probe: `SpottrUITests/Build5OnboardingVariantTests/testMobilityStartingOutAndUnicodeNameCompleteWithKeyboardOpenAndMountEveryTab`.

The expanded probe source remains private and is not registered in the current project by this PR. These selectors are handoff information, not a request to repeat passing probes or a claim of physical verification. Primary retains ownership of native integration, simulator use, signing and the next TestFlight upload.
