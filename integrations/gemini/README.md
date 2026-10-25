# Gemini coaching boundary

The native Coach UI and runnable gateway implement chat, session/weekly summaries and catalogue-only workout proposals. `Shared/Core/CoachGrounding.swift` exports saved sets and game progress; `CoachContracts.swift` independently validates structured replies and explicit selections. All four request types have real Gemini responses using synthetic inputs, including signed-simulator native chat, proposal and both report screens. [Chat evidence](../../docs/evidence/native-gemini-chat-2026-10-24.md) and [structured-output correction/acceptance](../../docs/evidence/gemini-structured-compatibility-2026-10-25.md). The latest proposal's independent selection and both summaries' agreement with one synthetic manual set were inspected; approval was not submitted. Physical networking, real-user guidance quality and broader request coverage remain pending.

See [gateway setup](../gateway/README.md) for runtime commands and private configuration. The schema files in this directory document the versioned wire contract; the gateway derives its runtime contract and permitted exercises from the current Swift catalogue. No provider key belongs in the app bundle.

The app sends only when asked. Cancel/stale responses cannot overwrite the current view or plan; failed/invalid output preserves local training and reports. Approved selections preserve exercise order, sets, targets, units and rest targets in a custom workout. Each set begins in Manual; supported base push-up/squat entries can explicitly choose camera input, and seconds exercises use an active hold timer. The fixed six-set routine remains available separately.

A valid fact reference establishes membership, not that the generated prose follows from it. Judge factual entailment using saved evaluation cases. Ordinary tests use fixtures and make no paid request.

Official references: [structured outputs](https://ai.google.dev/gemini-api/docs/structured-output), [generateContent](https://ai.google.dev/api/generate-content).
