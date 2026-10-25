# Native proposal and report acceptance

On 24 October 2026, CUA exercised the existing Musalli-Test iOS 26.5 simulator against the real local gateway HTTP/schema path with an injected deterministic fake provider. The gateway used loopback port 8841, a separately verified URL, and the existing owner token read privately. It received no real provider keys and made **zero external provider calls**. This check is separate from the [earlier real Gemini chat](native-gemini-chat-2026-10-24.md).

The [receipt](native-synthetic-coach-2026-10-24.json) records the three synthetic generations, native binary hashes, observations and cleanup. The initial Debug app was version 0.1 (1); it is not the frozen App Store archive. No public screenshot artifact is claimed; CUA displayed the inspected screens inline.

## Observed behavior

- **Proposal:** Squats (1 × 2 reps) and Forearm plank (1 × 5 sec) appeared with the marked synthetic rationale. Both started unselected; selecting Squats left plank unselected. Approval was deliberately not submitted, so the stored plan stayed untouched. Existing native tests cover approval validation separately.
- **Empty history:** weekly generation was disabled and made no request.
- **Reports:** a Debug-only plan fixture enabled logging one synthetic manual squat set in a fresh UUID namespace. Weekly totals were 1 session, 1 set and 2 reps. The session retained its Manual source and 00:00 recorded time; no Watch readings or rep duration were invented. Explicit generation displayed the marked synthetic headline/insight in both reports and the focus in the session report. The weekly focus was below the visible area and was not visually accepted in this pass.
- **Failure:** after the exact temporary server stopped, one explicit Regenerate attempt showed “The coach couldn’t respond. Check your connection and try again.” Saved local stats remained available. Regeneration clears the previous optional generated summary; it does not erase the deterministic workout report.

The normal interface includes a Gemini attribution label. That label is not evidence that a provider ran: these responses were clearly marked synthetic and returned by the local stub. This pass verifies transport, validation and exercised display behavior, not generation quality, physiological truth or physical networking.

## Copy fix and cleanup

The manual save screen initially displayed “1 sets.” A one-line singular/plural fix was rebuilt with simulator ad-hoc signing and no warnings (build log `build_sim_2026-10-24T22-06-31-681Z_pid4129_cbc3828b.log`). CUA then verified “1 set · 1 rep per set.” The first draft failed compilation because it compared String state to an integer; the corrected code parses the already-validated quantities. No persistence or logging behavior changed. This copy change is not in uploaded TestFlight build 1.

Both generated manual records stayed under namespace `BE228517-A5E2-43C3-92BC-C9B8F08D5CD8`. They were backed up privately under ignored `.local/native-fixture-check-20261024/`, then removed from that exact namespace. No other workout records were changed. The original gateway URL `http://127.0.0.1:8788` was restored and verified, its token was preserved, no approved plan was persisted, the temporary server was stopped, and the app was relaunched without fixture variables. Keyboard capture was restored off.

Reproduce the underlying behavior with `CoachFlowTests` in `Tests/iOS`, the gateway HTTP tests in `server/test`, and a disposable UUID namespace for manual UI checks. Reuse the existing simulator; do not erase it or save fixtures into the user's namespace. Real Gemini proposals/reports, physical HTTPS, actual camera/sensors and audible voice remain separate acceptance work.
