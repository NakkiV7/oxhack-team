# Public wearable HR benchmark

Protocol locked 24 October 2026 before fitting. Completed offline run: 20:43:51–20:43:59 UTC. Recorded results are linked below; no app integration is claimed.

The approved first experiment is **PAMAP2 HR forecasting**, separate from app integration and reserve/failure prediction. This extends the existing [dataset survey](../research/datasets-and-models.md) and [personal-learning plan](personal-learning.md); it does not replace them. Raw data/archive stay in ignored `.local/research/PAMAP2/`.

## Dataset and scope

The official [UCI PAMAP2 record](https://archive.ics.uci.edu/dataset/231/pamap2+physical+activity+monitoring) lists nine participants, HR around 9 Hz, 100 Hz IMUs including a wrist device, missing NaNs, 54 columns, and a 656.3 MB archive. It declares **CC BY 4.0**. Attribution: Attila Reiss (2012), *PAMAP2 Physical Activity Monitoring*, UCI Machine Learning Repository, [DOI 10.24432/C5NW2H](https://doi.org/10.24432/C5NW2H). Retain source notices and mark derived features/results as changes. Chest/ankle IMUs, invalid orientation channels, demographics, and activity labels are excluded from features. Protocol sessions only; optional sessions were excluded before inspecting outcomes.

[PPG-DaLiA](https://archive.ics.uci.edu/dataset/495/ppg+dalia) was considered first: 15 participants, wrist BVP 64 Hz/ACC 32 Hz, 2.7 GB archive, UCI CC BY 4.0. Its [author page](https://ubi29.informatik.uni-siegen.de/usi/data_ppgdalia.html) still specifies scientific non-commercial use; retain this discrepancy rather than inferring product permissions. Its [official readme](https://archive.ics.uci.edu/ml/machine-learning-databases/00495/readme.pdf) and [original paper](https://kristofvl.github.io/usi/pdf/ubi_sensors2019.pdf) define ECG-derived 8-second HR means shifted 2 seconds. Forecasting those labels from past labels would be an idealized reference-HR-input experiment, not wrist-PPG or Watch validation. S6 contains only its valid first ~1.5 hours after a hardware issue. Only the 817,798-byte readme was retrieved, not the dataset.

## Locked comparison

The complete machine-readable [protocol](../research/hr_forecast/protocol.json) and [pre-fit SHA-256](../research/hr_forecast/protocol.sha256) specify thresholds, features, models and selection. Train participants 101–105; validation 106–107; locked test 108–109. Keep missing/short people in reporting; never replace them after seeing outcomes. Two test participants support an exploratory comparison only.

Every 5 seconds, forecast the mean of five **observed** one-second HR-bin means ending 10 or 30 seconds later. Features use only the preceding 60 seconds, ending at the origin. Targets begin strictly after the input. No interpolation, future fill, bidirectional filtering, future activity or test-normalization statistics are allowed.

Compare latest-value persistence with standardized ridge regression predicting HR change from past HR summaries; a prespecified wrist-acceleration variant is included only after metadata verification. Train-only scaling and equal total fit weight per training participant. Select alpha 0.1/1/10 and model on validation participant-macro MAE; freeze the selection before test scoring. A tie favors simpler models. A baseline win remains a valid result.

Coverage separates planned origins, input eligibility/abstention, target availability and scored predictions. Reject stale/missing history before looking at its target. Report per-person counts, MAE, RMSE, bias and paired MAE difference from persistence. Do not turn correlated windows into independent sample counts or confidence intervals.

Secondary adaptation adds a small fixed-rate, bounded per-person bias only after previous forecast outcomes mature; predict first, score later, update once. It is evaluated chronologically alongside the frozen model and never substitutes for the frozen held-out result. It predicts HR only; no failure/reserve labels exist here.

## Resource and evidence boundaries

Approved: official archive ≤800 MB; CPU ≤2 threads; peak RAM ≤4 GiB; computation ≤10 minutes; derived artifacts ≤100 MB. No GPU/HPC authentication or job, paid provider, app changes, or private biometric input. Save source URL/hash/license notices, split hash, environment, code hashes, raw-input inventory, contract test evidence, candidate validation selection, frozen test metrics and chronological prediction traces.

Contract tests must fail first for time-window alignment, no future-feature influence, participant separation, train-only normalization, missingness/abstention, and predict-before-update order. Tests verify the data contract rather than asserting particular fitted numerical predictions.

The design used the experimental-design skill for participant-level replication and matched comparisons. Procedural reference: Kassis T, Agarwal V, He Y, Patel D, Brueckner AM (2026), [Scientific Agent Skills](https://doi.org/10.48550/arXiv.2609.00065), current record checked 24 October 2026.


## Completed run

[Full results and figures](../research/hr_forecast/results/README.md) retain the original frozen selection and per-origin prediction trace. Validation chose HR-only ridge (alpha 0.1) at both horizons. The 10-second participant-macro MAE was 2.808 bpm versus 3.081 for latest-value persistence; participant 108 supplied 803 scored forecasts and participant 109 only four. At 30 seconds, only participant 108 was eligible: MAE 7.066 versus 7.650 bpm over 799 forecasts. Participant109's 84.76-second recording cannot supply 60 seconds of history plus 30 seconds of future data; it remains a visible zero-coverage test participant at that horizon.

The fixed prequential bias adapter worsened full-run MAE: 2.843 bpm at 10 seconds and 7.473 bpm at 30 seconds. This does not validate adaptive improvement. Wrist features did not win validation, so no candidate was substituted after examining test performance. Further algorithm selection needs a new evaluation protocol and unexamined data.

The run processed 2,872,533 public Protocol rows in 8.61 seconds wall/8.53 seconds CPU, peaking at 218.2 MiB RSS. Derived results/figures are under 1 MB. Thirteen behavioral checks now pass, following recorded RED stages. A post-run source-integrity guard was added without refitting: original run sources are retained with their matching hashes, and the new guard was tested against the actual archive. The [reproduction guide](../research/hr_forecast/README.md) and [post-run audit](../research/hr_forecast/results/post-run-audit.json) distinguish these steps.

Independent review reran all 13 light behavior tests and reconciled every saved forecast, adaptive update and aggregate metric without refitting. No important causal/evaluation issue was found. The frozen CSV retains its original CRLF bytes and hash; its scoped Git attributes prevent line-ending conversion.
