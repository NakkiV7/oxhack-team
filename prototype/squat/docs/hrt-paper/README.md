# Technical paper: short-horizon tempo forecasting

`main.pdf` is the compiled paper. Every number in it is a macro generated from the evaluation artifact, so the paper cannot drift from the app's evidence dialog.

## Rebuild

From this folder, with the repository's virtualenv (`.venv`, Python 3.15 with matplotlib) and Tectonic (`brew install tectonic`):

```bash
../../../../.venv/bin/python make_tables.py     # results.tex: macros and table bodies from ../../hrt/results.json
../../../../.venv/bin/python make_figures.py    # fig_*.pdf from results.json and demo-review.json
tectonic -X compile main.tex                    # main.pdf
```

Regenerate the artifact first if the data or model changed: in `prototype/squat`, `node hrt/build_dataset.mjs <landmark-dir>` then `node hrt/train.mjs`. The demo timeline figure reads `demo-review.json`, an export of one stored replay's forecasts and reps from Tiger Data (see `docs/HRT.md` for the export snippet); delete it to drop that figure.

## Files

- `main.tex`, `references.bib`: the paper. References are real publications and documentation pages checked on 25 October 2026.
- `results.tex`: generated macros; do not edit.
- `fig_brier.pdf`, `fig_reliability.pdf`, `fig_frontier.pdf`, `fig_timeline.pdf`: generated figures.
- `demo-review.json`: the stored replay used for the timeline figure (shadow mode, held-out Creative Commons clip).
- `main.pdf`: the compiled output.

When the held-out test split is evaluated, `make_tables.py` defines the `\Test...` macros and the paper's held-out paragraph switches from "not evaluated" to the measured numbers automatically.
