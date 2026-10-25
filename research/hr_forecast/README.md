# Public-data HR forecast baseline

A completed **offline PAMAP2** benchmark. [Recorded results](results/README.md), [locked protocol](protocol.json), [source provenance](provenance.json), and [project summary](../../docs/public-data-benchmark.md). This is a recorded-HR forecast experiment; no app integration or recovery/reserve prediction is implemented.

## Reproduce

From the Spottr repository root, use Python 3.14 and the versions in `requirements.txt`. No GPU, provider API, HPC, pickle or model download is needed. Set all three thread limits before Python imports NumPy/scikit-learn.

```sh
export OPENBLAS_NUM_THREADS=2 OMP_NUM_THREADS=2 VECLIB_MAXIMUM_THREADS=2
python3 -m unittest discover -s research/hr_forecast/tests -v
shasum -a256 -c research/hr_forecast/protocol.sha256
python3 -m research.hr_forecast.benchmark --output .local/research/PAMAP2/reproduction
```

The default archive path is `.local/research/PAMAP2/PAMAP2_Dataset.zip`. The benchmark refuses an existing output directory to preserve prior evidence. It enforces a 600-second compute alarm and checks peak RSS/derived-output budgets. On macOS, `ru_maxrss` is recorded in bytes. All data/model computation for the recorded run took 8.61 seconds, with 218.2 MiB peak RSS. The figures/report rendering is a separate step and performs no fitting:

```sh
python3 -m research.hr_forecast.summarize
```

That summary command reads the committed `results/` directory; it reconciles the trace counts/MAE and regenerates only its two figures, coverage summary, and explanatory README. `selection.json` was written and hashed before test scoring. Its `test_scored:false` field describes that frozen selection checkpoint, not the later completed run.

## Data acquisition

The recorded official outer archive is 688,226,940 bytes (656.3 MiB), fetched from:

`https://archive.ics.uci.edu/static/public/231/pamap2+physical+activity+monitoring.zip`

SHA-256: `76b3580bd5a804121f507717cb498c66a312ef5c774f4a78ac470e6558add352`.

It contains an inner `PAMAP2_Dataset.zip` and `readme.pdf`. Keep both ZIPs/raw documentation under ignored `.local/research/PAMAP2/`; no raw data are committed. Retrieve the public URL with HTTPS and an 800,000,000-byte/600-second bound, verify the exact source hash in `provenance.json`, then copy only the explicitly named inner ZIP through Python's `zipfile.ZipFile.open` into the default archive path. Do not perform unrestricted path extraction or use pickle. If the source hash changes, investigate and version the provenance rather than silently accepting it. The inner ZIP hash and Protocol member inventory/CRC32 values are recorded. The run reads plaintext Protocol members directly and checks their ZIP CRC while reading them to EOF. The current runner also verifies the inner archive SHA-256 before ingestion.

The raw cache retains the complete original notices. The official [readme](https://archive.ics.uci.edu/ml/machine-learning-databases/00231/readme.pdf), SHA-256 `99a0339f1d754089fc2f7f2c24f5a47888a51dc0646a8b210af60358c00da30d`, confirms column 3 HR and columns 5–7 wrist ±16g acceleration. Only time, HR, and three wrist-acceleration columns are used. The 100 Hz rows contain expected HR NaNs because HR was sampled around 9 Hz; bins require actual observations and are never filled.

## Evidence files

- `protocol.json` and `protocol.sha256`: fixed before fitting; participant groups, features, eligibility, target timing, candidates, selection and adaptation rules.
- `contract-red.txt`, `training-red.txt`: tests written before their implementation modules existed; both RED stages failed with missing modules. `integrity-red.txt` records the additional checksum-guard RED; `contract-green.txt`: all 13 behavioral contract checks pass.
- `results/inventory.json`: each expected participant, raw rows, eligibility and missingness counts, including the short participant 109 recording.
- `results/selection.json`: validation-only selection checkpoint. `models.json`: every fitted ridge coefficient/scaler exported as transparent JSON, with no executable serialized object.
- `results/report.json`: source/protocol/code hashes, UTC times, versions, resource measurements, every prespecified candidate and frozen/adaptive/last-value comparisons. `run-source/` retains the exact code that produced this run. `post-run-audit.json` documents the later checksum guard and confirms no refit.
- `results/test-predictions.csv`: chronological public-data forecasts, observed targets, target timing, and counts of matured outcomes used for bias updates.
- `results/coverage-summary.json`: separate planned, input-eligible, target-observed and scored counts per held-out participant/horizon.

Frozen test participants 108/109 have now been examined. Do not retune this protocol on those outcomes. The 30-second test has just one contributing participant; participant 109 has zero eligible 30-second targets and only four 10-second targets. The fixed adaptation worsened total MAE and remains a negative result. No confidence interval from overlapping windows is reported.

Attribution: Reiss, A. (2012), *PAMAP2 Physical Activity Monitoring*, UCI Machine Learning Repository, [DOI 10.24432/C5NW2H](https://doi.org/10.24432/C5NW2H). UCI declares CC BY 4.0; features, models, figures and reports are derived modifications. See the [protocol summary](../../docs/public-data-benchmark.md) for the research-method skill attribution and the PPG-DaLiA source-term discrepancy.


Bounded acquisition commands (official archive, exact source hash):

```sh
mkdir -p .local/research/PAMAP2
curl --fail --location --connect-timeout 15 --max-time 600 --max-filesize 800000000 \
  --output .local/research/PAMAP2/uci-pamap2.zip \
  'https://archive.ics.uci.edu/static/public/231/pamap2+physical+activity+monitoring.zip'
python3 - <<'PYTHON'
from pathlib import Path
import json, shutil, zipfile
from research.hr_forecast.benchmark import verify_archive
folder = Path('.local/research/PAMAP2')
provenance = json.loads(Path('research/hr_forecast/provenance.json').read_text())
verify_archive(folder / 'uci-pamap2.zip', provenance['archive_sha256'])
with zipfile.ZipFile(folder / 'uci-pamap2.zip') as archive:
    with archive.open('PAMAP2_Dataset.zip') as source:
        with (folder / 'PAMAP2_Dataset.zip').open('wb') as destination:
            shutil.copyfileobj(source, destination, 1024 * 1024)
verify_archive(folder / 'PAMAP2_Dataset.zip', provenance['data_zip_sha256'])
PYTHON
```
