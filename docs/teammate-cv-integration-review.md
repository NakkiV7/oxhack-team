# Teammate CV and voice integration review

Reviewed **25 October 2026**, exact `origin/nakki-squat-model` head **`460b0b5254a95f3706132a4b0ecd932d077ae12f`**. This is a source review, not a merge or device acceptance receipt.

Nakki’s browser squat work and the branch’s voice-picker, cached TTS and two-tone configuration are useful contributions. Preserve the agreed ownership: **Misha — voice/landing; Nakki — squat CV; Azhar — push-up CV**. Voice integration should be coordinated with Misha rather than create a competing native audio owner. The latest commit adds documentation; voice source is unchanged from `5b11259`. Merge `e29d51f` restores main’s corrected Python runtime: `squat/{app,main,pose,pushup,voice}.py` matched the reviewed main checkout. Earlier Python deletions are not a current-head finding.

## Integration blockers

Line references below refer to the exact remote head, not mutable local files.

| Finding | Source evidence |
| --- | --- |
| A configured key can incur synthesis without a voice choice or workout. Fresh-page initialization chooses the first voice and prewarms the fixed lines. | `prototype/pushup/index.html:413–452`; `prototype/squat/index.html:276–315` |
| Voice-off does not cancel active/queued audio. Stop/reset/pause do not retire speech by session or generation; priority-3 counts have no expiry, and an urgent cue waits behind current audio. A queued request with `voice=off` falls back to a configured server voice. | Push-up UI `421–459, 690–713`, server `363–375`; squat UI `284–322, 362–364, 492–498`, server `268–280` |
| Motivation includes “Pain is just information. Keep going.” Counts and counted-rep issues share priority 3; there is no separate discomfort-stop priority. | Push-up UI `404, 455–459`; squat UI `267, 318–322` |
| TTS is loopback-restricted, but lacks owner authorization, finite shared attempt/concurrency limits and response/cache size bounds. It bypasses the push-up cloud routes’ Origin/auth checks and accepts arbitrary syntactically valid voice IDs. Do not expose this server as the native gateway. | Push-up server `313–375`; squat server `258–280`; provider/cache implementations `112–131` / `107–126` |
| Existing browser timing/loss and disclosure gaps remain: looping file time regresses, missing pose skips the counter, and the README says no video leaves the machine while JPEGs are forwarded over the LAN. | Squat UI `500–515, 545–555`; `prototype/squat/README-squat.md:50` |

## What was actually checked

A **network-free Node VM harness** evaluated the exact voice block with fake fetch, audio and clock boundaries. With one synthetic configured voice and no saved preference, fresh load requested **46 push-up / 50 squat** prewarm URLs. Voice-off left current audio active; completing it ten seconds later started the stale queued count with `voice=off`. These establish JavaScript behavior, not real synthesis cost, audible playback or browser/device acceptance. No provider, camera, model inference or UI action was run; no production files were changed. No voice behavior tests were added by the reviewed branch.

The new docs report 17-clip Python/browser parity and browser voice/replay checks. Those remain **contributor-reported**; this review did not reproduce them. A checked-in landmark fixture is not independent video/form accuracy validation. The docs themselves leave live browser-camera and squat phone-client checks pending. Voice identity labels do not establish availability or rights to use a named persona.

## Small port plan

1. Reuse the picker and explicit calm/cue voice mapping as product ideas. Start with available local voices, retaining off-by-default behavior; avoid automatic prewarm. Named voices require verified access in the intended ElevenLabs workspace before a live check.
2. Keep native `VoiceCuePlaybackController` as the single audio owner: session/generation identity, expiry, deduplication and stop-over-form-over-pacing priority. Voice-off, pause, stop, reset and source changes cancel playback; late audio completions cannot restart it. Ordinary lines can finish when still relevant; a discomfort stop preempts them.
3. If remote TTS is authorized, add one optional adapter behind the authenticated bounded gateway. Allow approved voices only, one explicit preview, bounded response/cache and shared nonrefundable attempt budget; no automatic retry/fallback. Cache identity must include model/settings/version as well as voice/text. Test with fake transport before one separately authorized synthesis/playback check.
4. Consume existing feedback events and accepted rep facts; do not replace native CV thresholds, invent counts/time or import a parallel analyzer merely for presence. Test queue cancellation, delayed results, stop priority and zero paid work when off before device acceptance.

No wholesale browser/server merge is recommended. Preserve the corrected Python demo and the independently hardened push-up/native contracts.

## Follow-up: Tiger stream delta `92b02fb`

Read-only review compared `460b0b5` with exact head **`92b02fb1ff5fb94d748b26311406138333623134`**. Prior findings above remain historical and unchanged. No code, tests, UI, database or provider requests were run for this delta review.

Useful port ideas are the shared parameterized frame/rep batching, database-backed status/latency card and separate CV schema. A newly documented second service with a public Google Trust Services chain is **contributor-reported**: it is a possible strict-TLS lead, not independently accepted connectivity, production data, ownership or persistence for our native gateway. Its schema and the existing `spottr_gateway` service are distinct.

Do not bulk-merge the delta. Exact-head blockers:

| Finding | Source evidence |
| --- | --- |
| A configured URL triggers startup migrations/policies; analysed camera/video frames stream automatically without a cloud consent action. | Squat server `134–146`, UI `586–597`; corresponding push-up additions. |
| New telemetry/status/compression endpoints have loopback restriction but bypass the existing cloud token and Host/Origin guard. A wrong-Origin local POST needs no token or JSON content type. This is not a claim that LAN clients bypass the loopback restriction. | Push-up server guard `331–337` versus new routes `405–420`; squat routes `314–328`. |
| The CV tables lack owner binding. Changed data under an existing natural key is silently ignored instead of producing an immutable-content conflict; status totals cover the whole schema. | Shared `tiger-stream.mjs:81–85,95`; `shared/db/001_cv_stream.sql:5–14`. |
| Buffers/start/end metadata are cleared before acknowledgement, and HTTP failure status is ignored. One failed first batch can lose provenance; later rows need no parent workout. Ingestion is not transactional, so a failed rep insert can leave earlier writes committed. | Squat UI `591–595`; shared writer `81–85`; frame/rep tables lack parent foreign keys. |
| Invalid values become invented observations: unknown sources become camera, invalid start/end dates become current time, and string `"false"` becomes true. | Shared validator `55,60–63`. |

A scoped port requires explicit opt-in and separately approved migrations; owner/Origin/token enforcement; strict source/time/boolean validation; atomic writes and exact replay/conflict tests; bounded unacknowledged queues with visible loss/retry choices. Test these with fake network/database failures before any deliberate live acceptance. Preserve video provenance, existing native counters and the hardened upload contracts. The added fake-pool tests do not establish those browser/security/failure boundaries.
