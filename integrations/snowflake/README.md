# Public PAMAP forecast evaluation

The runnable workflow is documented in [Snowflake analytics](../../docs/snowflake-analytics.md). The CLI defaults to a local dry run and does not create Snowflake resources or execute this directory's SQL.

`001_public_pamap_forecast.sql` is a review-only table definition for a separately approved existing database/schema. It has no replacement, deletion, warehouse, role or database statements. A later approved operator may create the table with their normal administrative tooling. The CLI itself uses only fixed lookup, insert-only MERGE, and evaluation statements.

`pamap2-forecast-v1.manifest.json` pins the reviewed public experiment's protocol, source provenance/license, selected/fitted models, coverage, prediction CSV, and original run code. Each listed artifact must match its exact SHA-256. The CSV's existing `.gitattributes` rule preserves its original CRLF bytes. An alternative `--artifacts` directory must contain identical pinned bytes. A new experiment requires a new reviewed manifest and tests; the CLI has no general dataset or SQL import option.

Data attribution: Reiss, A. (2012), *PAMAP2 Physical Activity Monitoring*, UCI Machine Learning Repository, [DOI 10.24432/C5NW2H](https://doi.org/10.24432/C5NW2H). The [official UCI source](https://archive.ics.uci.edu/dataset/231/pamap2+physical+activity+monitoring) declares CC BY 4.0. Features, prediction traces, models and evaluation are derived changes. This integration uploads no raw archive, app session or private biometric record.
