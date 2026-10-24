# Gemini coaching boundary

The native Coach UI and runnable gateway now implement chat, session/weekly summaries and catalogue-only workout proposals. `Shared/Core/CoachGrounding.swift` exports actual saved sets and game progress; `CoachContracts.swift` independently validates structured replies and explicit selections. All four request types returned real Gemini responses to synthetic gateway inputs. Two signed-simulator chat checks reached Google; the revised product context correctly distinguishes camera from manual/timed exercises. [Native acceptance receipt](../../docs/evidence/native-gemini-chat-2026-10-24.md). Live native proposals/reports and physical networking remain pending.

See [gateway setup](../gateway/README.md) for runtime commands and private configuration. The schema files in this directory document the versioned wire contract; the gateway derives its runtime contract and permitted exercises from the current Swift catalogue. No provider key belongs in the app bundle.

The app sends only when asked. Cancel/stale responses cannot overwrite the current view or plan; failed/invalid output preserves local training and reports. Approved selections preserve exercise order, sets, targets, units and rest targets in a custom workout. Each set begins in Manual; supported base push-up/squat entries can explicitly choose camera input, and seconds exercises use an active hold timer. The fixed six-set routine remains available separately.

A valid fact reference establishes membership, not that the generated prose follows from it. Judge factual entailment using saved evaluation cases. Ordinary tests use fixtures and make no paid request.

Official references: [structured outputs](https://ai.google.dev/gemini-api/docs/structured-output), [generateContent](https://ai.google.dev/api/generate-content).
