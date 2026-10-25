# Profile and zero/one-rep simulator acceptance

25 October 2026. CUA checked the existing Musalli-Test iPhone simulator after the root-reported 03:35:14 native checks (4 ProfileDataControls and 11 Configured cases) and 03:38:01 relaunch. This lane ran no build or test command. The isolated namespace contained three synthetic records before these checks.

## Profile regression

Changed weekly target five to four, observed **Profile saved**, closed with Done and reopened: four persisted. Restored five and observed autosave. Deselecting the only Strength goal displayed validation feedback; Done and reopening retained the last valid Strength goal and target five. The decoded profile equals the before-profile after restoration. No write failure was forced in UI, and no keyboard-dismissal regression was repeated here.

## Skip-only session

Opened Squats from the catalogue and configured three sets, target two, rest zero. Manual was the default input. Explicitly chose **Skip set / stop here** before starting. The check-in made **Finish session** primary and offered a separate, optional next-step action; nothing advanced automatically.

Finished and saved. Review and reopened Progress report showed zero completed sets, zero reps and zero recorded active time. A separate **Skipped sets** section identified Squats, planned set 1, target two, Manual and skipped by choice. It explicitly excluded skips from reps, active time and XP. The bottom displayed **Saved locally** and explained there were no completed sets to upload, with no sync button.

Record: `2E0FD353-FD94-4EA3-A718-F8264DB0D7E3` — no legacy or logged completed sets, one separate skipped step.

## One-rep session

Started the same three-set/target-two manual setup, entered a synthetic actual quantity of one and explicitly ended the set. The rest screen offered **Use 1 rep for remaining Squats sets**. After selecting it and explicitly choosing the next set, preparation showed target one, **Set 2 of 3 · 2 of 3 planned**, and a Start button. That set was not started.

Finished through the ended-set confirmation. Review and reopened report showed one set and one rep, with a Manual source badge. Persisted work retained original target two, actual reps one and `quantityOrigin: selfReport`; no remaining set was counted. The catalogue setup still showed three sets, target two and rest zero.

Record: `AC6A2878-3B6B-4126-B42A-07570C6FBF91` — one logged manual set, no skipped steps. Its approximately 52 seconds of recorded active time includes this synthetic UI interaction; it is not evidence of physical exercise.

## Preservation and limits

The three earlier records remain semantically unchanged; their previously absent `skippedSets` field was re-encoded as an empty array. Only the two authorized synthetic records were added. Profile values, Grid mode, preview off, Capture Keyboard off, localhost zoom 25% and the temporary viewport were restored; the task mirror tab was closed and the app left on Today. Skills still showed zero of 19 earned and zero XP in all attributes.

No provider, camera, Health measurement, voice or cloud upload was used. The third future target was not individually opened. The weekly empty-category copy issue could not reproduce with prior positive records in this namespace; its subsequent source fix is outside this installed-binary acceptance.

## Unchanged synthetic simulator captures

- [Reopened skip-only report](zero-work-reopened-report-2026-10-25.jpg)
- [Reopened one-rep report](one-rep-reopened-report-2026-10-25.jpg)

SHA-256:

- `zero-work-reopened-report-2026-10-25.jpg`: `5726a1e52010e7c6bbabfb524f39e0a2b2d60bf7d3453947185c329661cd26a2`
- `one-rep-reopened-report-2026-10-25.jpg`: `d3abb66a3517e04b8fd6bc9333553f8d73d52391c180672766527d159ed97bf1`
