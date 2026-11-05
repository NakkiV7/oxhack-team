# UI and Watch setup verification — build 21

5 November 2026. This continues the native Spottr overhaul on `codex/spottr-demo-consolidation`. Build21 is now approved and available for internal and external TestFlight testing.

## Consumer changes

Onboarding, Today, exercise previews and Skills now share the existing workout illustration treatment: dark rounded figures, subtle edging and bright joint markers. The onboarding demonstration changes between existing movement frames, with cancellable low-rate playback gated by visibility, scene activity and Reduce Motion. Supported squats retain a visible grounded support. Manual vector guides use the same visual treatment, without faces.

Shared headings, press feedback, larger action targets and restrained transitions replace inconsistent styles. Today shows the actual rep target with shorter copy. Its exercise controls stack at accessibility text sizes. Insights has a clear progress heading and changes to a menu at accessibility sizes. Coach choices expose selection visually and to accessibility. The exercise library loads rows lazily. Skills and report explanations are available on demand. Settings and movement-guide copy no longer reads as a filming checklist or implementation note. Profile editing has an explicit Done bar with a drag handle, with interactive keyboard dismissal. Measurement dates, sources, coverage, gaps, errors and missing values remain available.

## Guided Watch setup

Setup asks which Watch family the user has, including SE, Series 6 or later, Ultra, Not sure and No Watch. This preference is local and optional, with a phone-only exit. It tailors guidance; it does not attest hardware, grant permissions or discard historical Health readings from another device. SE guidance follows [Apple’s Blood Oxygen availability documentation](https://support.apple.com/en-au/120358). Motion availability is read from the Watch recorder’s existing CoreMotion manager using [the actual availability API](https://developer.apple.com/documentation/coremotion/cmmotionmanager/isdevicemotionavailable), without starting a second stream or requesting sensor access during setup.

Pairing, app installation, reachability and a fresh companion response are separate observed milestones. The single existing CompanionLink remains the WCSession delegate. Nonce-bearing versioned setup probes accept only matching replies within 15 seconds using the phone’s clock. Active setup refreshes at a bounded normal rate of one probe per 12 seconds, checks newly reachable companions promptly and allows manual retry. Polling stops when inactive or No Watch is chosen. Reduce Motion disables milestone transitions.

Queue status is a snapshot at the last confirmed check. The last actual data-arrival time is separate from connection-check time, is not persisted across launches and is cleared on paired-Watch changes. Cached activation context still reaches the normal telemetry decoder but cannot claim a new arrival. Connection and motion availability never claim Health read authorization; HealthKit intentionally does not disclose read denial. See [Apple’s authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

## Verification checkpoints

- Shared core **131 XCTest + 262 Swift Testing checks passed (393 total)**, no core exclusions.
- The selected native app suite **224 checks passed** on the existing shared iPhone simulator. Four pre-existing StoreKit framework cases remain explicitly excluded because simulator setup returns `notEntitled`; no paid-purchase acceptance is claimed.
- Focused Watch checks passed **12 recorder + 9 store cases**, plus actual CompanionLink/decoder/history/export/report replay with durable ACK, older payloads, nonce/freshness validation and cached-context receipt regression.
- The initial app red run reproduced five expected failures: artwork mismatch, missing onboarding caption, large-text selector, progress heading and expanded timing explanation. A further native red case reproduced missing support. The cached-receipt replay also failed before the receipt fix. Green results and actual screen captures follow below.
- Source review found two concrete issues (lost squat support and cached receipt timestamp). Both were fixed and re-reviewed in source. This scoped review does not establish physical sensor or clinical acceptance.
- Protected build17 **209 files** and Vendor **157 files** retain their baseline content and metadata exactly. No simulator was created or erased, no Chrome testing or HPC work was performed, and no runtime AI or paid service was added.

## Practical limits

Hardware Watch pairing, sensor/permission availability, background delivery, battery, haptics and movement accuracy remain physical-device checks. Model selection is guidance only; unsupported or missing live sensor readings are never invented. Existing dated Health history remains separate from live workout readings. Default and large-text screen checks are distinct from a full VoiceOver or accessibility audit.

Durable telemetry retains the build20 limits: bounded 7,200-packet queues, possible loss of unflushed samples, visible storage/overflow failure and no automatic reconstruction of an unfinished phone workout after process termination. These layout changes do not establish battery or performance benchmarks.

## Integrated UI results and review

All **23 unique selected UI journeys** passed across the integrated and targeted correction runs. The full native suite passed **224 cases**, with the four StoreKit cases excluded explicitly. Raw results remain on the SSD under `WatchInsights20/Results`: `Polish-Final-21.xcresult`, `Polish-Profile-Correction-21.xcresult`, `Polish-Keyboard-Onboarding-21.xcresult` and `Polish-Focus-21.xcresult`.

The initial integrated result preserves three old profile-copy lookups failing. Those tests now use the stable profile-note identifier. A further keyboard journey exposed unreliable generic downward dismissal; the new explicit Done/drag bar and interactive dismissal were checked through repeated focus/background/drag/Done cycles. Measurements, profile autosave, invalid-goal preservation and restarted introduction passed. The final focus case passed after keyboard readiness was awaited and immediate scroll dismissal was changed to interactive dismissal. All observed integration failure case IDs have a later passing result; no failed case was removed.

[Actual native screen review](../media/ui-watch-polish-2026-11-05/review.md) includes the refreshed concise optional-setup step, shared figures, coach selection, Skills and accessibility-size Today/Insights controls. Images are unedited, with isolated test storage and no seeded physiology. The source review fixes were re-reviewed; the visible squat support was also inspected in the actual rendered attachment.

## Signed candidate and storage

Version **0.1 (21)**, phone and Watch. IPA **41,740,485 bytes**, SHA-256 `d3b060435823ee8da4d00b43879a6f166e48ad016949faef3dff2694d804970e`. Both strict signatures, HealthKit entitlements/profiles and binary/dSYM UUIDs pass. The Full-pose model is unchanged; all 99 MP3 files match source bytes. Local StoreKit configuration and private keys are absent from the delivered app.

All 104 frozen release inputs (99 Swift files plus packaging inputs) remained unchanged through the final archive. Source hashes and signed-bundle receipts are retained privately. Apple validation completed with no errors. The final archive was rebuilt after the last keyboard/wording corrections; earlier candidate logs remain preserved. Archive, IPA, audit and verification evidence are on the Extreme SSD-backed development volume under `Releases/Spottr-21-*`.

## Apple distribution

Build/delivery ID `d7afbbf5-c15d-4301-8a4b-055d11b2a500` is **VALID**, with encryption declaration `false`. Internal and external states are both **IN_BETA_TESTING**, and beta review is **APPROVED**. Both existing beta groups contain build21 after assignment. The existing [TestFlight invitation](https://testflight.apple.com/join/f3MhePbf) is unchanged. Update both phone and Watch apps for the new setup protocol; older workout telemetry remains compatible. No public App Store release or paid transaction was submitted.

Implementation commit `c582616abecdcd74e56983a4a7a81cde952f68f7` is pushed to `codex/spottr-demo-consolidation`. Private receipts are copied and hash-verified to `Releases/Spottr-21-Evidence` on the SSD-backed development volume. Original test failures, candidate logs and source evidence remain preserved, as do the two original untracked evidence directories.
