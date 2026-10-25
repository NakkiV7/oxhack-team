# Integration checkpoint — 25 October 2026

## Tested foundation

- Default iPhone simulator build: 41 native checks passed, including pose fixture, camera preview lifecycle, voice transport doubles, and Presage unavailable-by-default behavior.
- Camera background handling: seven further checks passed. Watch Resume cannot restart camera capture while the iPhone app is inactive; returning to foreground alone does not restart capture.
- Optional measurements: height 170 cm and weight 70 kg display BMI 24.2 after explicit suitability confirmation; profile preservation, introduction restart, relaunch and clearing measurements passed the UI flow.
- Preview workspace: ten native tests passed after observed missing-API and edge-case failures. Real profile/history/rewards remain separate, repeated switches preserve both workspaces, unreadable files are not overwritten, and the former workout store is released.

## Integration being verified

Account preview is off by default. Enabling selects a separate local workspace and routes Coach/Progress to authored examples. Switching workspace recreates navigation and cancels the old workout loop. The full mode-switch UI flow, scripted Coach approval/start, grid/linear skill access and corruption/symlink regressions passed. Offline voice routing and once-only completion passed in the combined 39-case native run. Default provider connection remains a separate gate.

## Release boundaries

- Presage's SmartSpectra and MediaPipe currently contain duplicate Objective-C runtime classes. Default builds exclude SmartSpectra; experimental linking is not release approval. The locally saved Presage key has not been used and must await Omar's explicit go-ahead.
- Public landing page and a bounded hosted Gemini request have been exercised. New demo-only routing, Tiger trust/configuration and Snowflake account acceptance have separate outstanding checks; see integration readiness for provider status.
- No physical Watch, phone/Pi camera, eduroam or cellular acceptance is inferred from simulator tests. Devices are currently disconnected.
- TestFlight 0.1 (5)'s reported onboarding crash remains unreproduced. These current-source tests do not diagnose the old binary. Upload the next build only after the combined release checks.
- Preview scores and conversation are authored examples, not measured physiology or live AI output. Real accounts are not seeded.

No provider keys belong in Git, app resources or documentation. A separately scoped, expiring demo gateway bearer can be injected privately; it must never authorize owner/storage routes.

## Installed local build

Local 0.1 (6) was built with explicit development profiles for the registered phone and Watch, installed over USB and launched successfully. The process was subsequently confirmed alive. Its bundle has 12 Arnold clips, the dedicated private Pi pairing and the Watch companion, with SmartSpectra absent. Human audible output, actual phone-to-Pi reachability and physical Watch sync are not inferred from this installation. See [the remaining list](LOCAL-DEMO-REMAINING.md).
