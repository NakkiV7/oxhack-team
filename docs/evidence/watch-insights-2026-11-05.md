# Watch, Health and reporting verification — build 20

5 November 2026. This checkpoint covers the native Today/report/Insights overhaul and optional Health/Watch setup, built from `codex/spottr-demo-consolidation`. It supersedes build 19 for these features. Apple has processed and approved this build for internal and external TestFlight testing.

## Implemented behavior

Today has one visible session action, a chosen exercise and actual target, library access, weekly recorded work, the latest saved report, Watch installation guidance and optional Health setup. Insights adds an Overview alongside Calendar, Reports, Weekly and Research. Reports show observed heart-rate plots and coverage, optional five-zone time, minimum/maximum and time-weighted average, cumulative active energy, recorded work/rest, complete camera-rep timing and wrist-motion summaries. No AI summaries or paid runtime services are used.

Apple Health access is explicit and optional. Read-only snapshots contain dated/source-labelled resting/walking heart rate, SDNN HRV, VO₂ max, one-minute recovery, oxygen saturation, respiratory rate and current-day steps/distance when available and shared. Snapshot history stays in memory and is separate from saved workout readings. No Health data is sent to the website or an account. The user supplies a maximum heart rate or explicitly chooses an adult age estimate; there is no invented age or maximum and these are not Apple’s private zone settings or prescribed targets.

The Watch summarises acceleration and rotation over sampled windows, flushes partial windows at pause/end, and keeps an established recording active during a stale phone connection. Commands still require a current session. Durable batches remain queued until the phone acknowledges persistence. Saved-session late batches are bounded and validated against known lifetime; they cannot add reps or sets. The phone persists active batches before acknowledgement, deduplicates replays and saves late packets to known reports. Pauses and recording restarts split chart lines.

## Verified software and screens

- Shared core passed **125 XCTest + 260 Swift Testing checks**, with no core exclusions. Behavioral fixtures cover zones, gaps, pause coverage, rep timing, energy reset, late-packet bounds, replay, Health conversion and dashboard history.
- The existing shared iPhone simulator passed **220 selected native checks** across the integrated run and final packaging correction, plus **13 selected UI journeys** after stale navigation assertions were corrected. Fresh SSD DerivedData was used when an older test runner retained stale compiled helper text. Result bundles are `WatchInsights20/Results/Final-20.xcresult` and `Final-20-Correction.xcresult` on the development volume. The earlier result preserves one identifier-lookup failure; its corrected journey and all three dashboard journeys passed in the final correction run.
- **Four existing StoreKit framework cases were excluded** because `SKTestSession` setup on this simulator returns `notEntitled`. Local framework setup and paid-purchase acceptance remain unresolved; beta access is unrestricted.
- Watch SDK doubles passed **12 recorder and 8 store cases**. Codec and actual CompanionLink durable-delivery replay checks passed, including ACK, retry, malformed and rejected queues. These do not establish hardware behavior.
- [Actual Today, Insights and Watch guide captures](../media/watch-insights-2026-11-05/review.md) were visually reviewed at the existing device’s default text size. No seeded physiology or demo history appears. No Chrome, new simulator, erase or device reset was used.
- Read-only re-review found no remaining concrete blocker in the scoped persistence/privacy/chart changes. This is not a comprehensive security or clinical certification.

## Signed candidate

- Version **0.1 (20)**, phone and embedded Watch.
- IPA **41,481,510 bytes**, SHA-256 `e011339fc446dea8f5c428fcd9f454d674f2f7c613ffb0ce91f5937439d01917`.
- Both strict signatures, embedded HealthKit entitlements/profiles and binary/dSYM UUIDs verified. The original 99 MP3 files match source bytes; the Full-pose model hash is unchanged. Local StoreKit configuration and private signing keys are absent from the app.
- All **95 Swift source files** in the audit match the signed candidate. Signed archive, IPA, extracted audit and private receipts are on the Extreme SSD-backed development volume under `Releases/Spottr-20-*`.
- Apple validation initially rejected a missing host Health-update purpose string. Both purpose strings are now present and the corrected IPA passed Apple validation with no errors. The iPhone HealthKit capability required a replacement App Store profile; Apple invalidated the previous distribution profile automatically. Existing build 19 remained valid and active. No certificate or old local build was removed.
- Protected build 17’s **209 files** and Vendor’s **157 files** still match their prior content and metadata manifests exactly.
- The expanded [live privacy notice](https://spottr.omarchoudhry.co.uk/privacy/) was deployed to Cloudflare Worker version `0ea3bbab-a8b9-4ab6-ab4e-32221860d33d`; all 14 site checks passed and the public body was read back.

## Practical limits

Physical Watch installation, Health permission/data availability, sensor accuracy, background delivery, long-workout battery, larger text and VoiceOver still need device acceptance. Motion is wrist acceleration/rotation, not linear body speed or camera form scoring. Missing readings remain absent and gaps are not extrapolated. Maximum-HR estimates are optional approximations. Available Health types depend on device, region, permissions and prior data.

Queues are bounded to 7,200 samples; overflow/write failures are visible but cannot guarantee retention. Unflushed memory samples may be lost on termination. A phone crash does not reconstruct an unfinished workout from orphaned inbox samples. One-second JSON outbox persistence has not been battery-profiled. No new model training or HPC workload was started.

## Apple distribution read-back

Build/delivery ID `f27a5859-7ace-4458-be22-1c87ccd5a47c` is **VALID**, with encryption declaration `false`. Both `internalBuildState` and `externalBuildState` are **IN_BETA_TESTING**; beta review is **APPROVED**. The existing internal group and OxHack external group both contain build 20, verified through each group’s build relationship after assignment. [Existing TestFlight invitation](https://testflight.apple.com/join/f3MhePbf). No public App Store release or real paid transaction was submitted.

Implementation commit `705893c3369e0ace00420c47f6b481c87c2dfda1` is pushed on `codex/spottr-demo-consolidation`. Private validation/upload/API receipts are copied and hash-verified in `Releases/Spottr-20-Evidence` on the SSD-backed development volume; originals remain preserved. The two original untracked evidence directories remain untouched.
