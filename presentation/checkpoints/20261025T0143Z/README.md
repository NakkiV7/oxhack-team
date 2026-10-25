# Judges checkpoint: 25 October 2026, 01:43 UTC

Ten editable slides preserve the existing design and shared assets. Visible changes are limited to slides 6, 9 and 10: accepted synthetic approved-plan execution, separate Python demo scope, and TestFlight build 4. The [00:36 deck](../../output/spottr-judges.pptx), previews, source and provenance remain unchanged. The [presenter guide](../../../docs/judges-guide.md) explains claim boundaries.

Source inventory supplied by the release owner: `485a33c`. Native build 4 is frozen at `7f4b5ba5f5478b0efa2c18605eb0252c6f9cb3ec`; Apple read-back at 01:32:51.286 UTC reports VALID, internal/external IN_BETA_TESTING and beta review APPROVED. Physical installation remains unverified.

## Verification

All ten final imported-PPTX slides were rendered and inspected individually, including full-size comparison of changed slides 6/9/10 and the whole montage. Seven other previews are byte-identical to the historical renders. All 29 historical source/output/preview/asset files match their recorded hashes.

Package integrity, reference-font policy, first-party import and editable chart/embedded literal workbook checks pass. The layout checker reports zero findings and one conservative slide 9 native-table overflow warning of 0.3423 inches; the actual Artifact Tool render shows no table/footer overlap. Native PowerPoint/Keynote behavior remains untested.

The native PDF exporter still fails with missing `#standard-fonts/Helvetica`. The delivered PDF is a separate static assembly of the final slide PNGs. No runtime dependency was installed or altered. No provider calls, new illustrations, app builds, Git operations or publication occurred.

## Outputs

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `preview-montage.png` | 700,116 | `509897b3c1dde22d9b195826db88852bbd0ad61b6a255ee1ec2ccce75bb1d94d` |
| `spottr-judges-rendered.pdf` | 975,107 | `2905efad7ae10f97f5eb880715a720a474e1c7da52b5674f3ef41fb3cd6de6da` |
| `spottr-judges.pptx` | 256,465 | `acbfe6ade175042be2f111d43c4d669be3816ba4c7d1dd558defdb93d387a628` |

`source/provenance.json` records source and preview hashes, actual limits and the private finalizer receipt. `source/historical-preservation.json` pins the unchanged historical files.

## Rebuild on this host

Use the bundled runtime locations and existing workflow described in the [historical presentation README](../../README.md). Copy `source/build.mjs` into this checkpoint's ignored `.build/build.mjs`, link `.build/node_modules` to the bundled packages, and run it with the bundled Node executable. Use a fresh internal revision before another finalization because outputs/receipts are immutable. The builder reads existing `presentation/assets/` without copying or regenerating assets.

Then run `source/export-rendered-pdf.py` with bundled Python and the skill's montage helper against `previews/`, writing `output/preview-montage.png`. Recheck evidence status, render/inspect all slides and refresh hashes before presenting a later checkpoint.
