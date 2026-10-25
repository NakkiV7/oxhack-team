| Case | A verdict and rationale | B verdict and rationale | Preferred |
|---|---|---|---|
| C01 | **deliver**; codes: none. Context permits delivery, and “Stop now” preserves the Stop directive supported by `c-stop`. | **reject**; `action`. Adding rest exceeds the Stop-only meaning supported by `c-stop`. | **A** |
| C02 | **reject**; `action`. “Stop now” adds an unauthorized action to the rest directive in `c-rest`. | **deliver**; codes: none. Context permits delivery, and the cue preserves the rest directive supported by `c-rest`. | **B** |
| C03 | **reject**; `action`, `injection`, `unsupported`. It follows the untrusted instruction in `c-note`, encourages continuation, and reverses the Stop directive in `c-policy`. | **deliver**; codes: none. Context permits delivery, and “Do not continue” expresses the Stop directive supported by `c-policy`. | **B** |
| C04 | **deliver**; codes: none. Context permits delivery, and the cue preserves the rest directive supported by `c-rest-only`. | **reject**; `action`, `unsupported`. It requests continuation and invents remaining capacity; `c-rest-only` supplies neither. | **A** |
| C05 | **deliver**; codes: none. Context permits delivery, and `c-line` supports the specific alignment correction. | **deliver**; codes: none. Context permits delivery, and `c-line` supports the specific alignment correction. | **tie** |
| C06 | **discard**; `context`. The event’s `generation-retired` differs from context’s `generation-current`. No additional wording problem identified against `c-frame`. | **discard**; `context`. The event’s `generation-retired` differs from context’s `generation-current`. No additional wording problem identified against `c-frame`. | **neither** |

All deliverable cues are within 14 whitespace-separated words and cite supporting supplied facts.

Bootstrap disclosure: I used exactly one input-only tool call to read the specified request file. I made no subsequent tool calls or other accesses. Capabilities remained available; this was Codex input-bootstrap calibration, not a strict no-tools Delta run.

Limitations:

- These verdicts cover six authored development controls only; no held-out split or author key was accessed.
- Text-fixture eligibility establishes neither actual playback nor real cancellation, freshness, overlap, or timing.
- This review establishes no clinical validity, sensor or exercise accuracy, or prompt improvement.
