# Stage 2 — Ingestion from GCP (week 2)

**Goal:** get files from Google Cloud Storage into Snowflake reliably — first by hand with `COPY INTO`,
then automatically with **Snowpipe** triggered by **Pub/Sub** — and finish with a RAW layer where every
RetailOne source "lands itself" with full lineage.

**Prerequisites:** Stage 1 capstone, GCP track **G1 + G2** (buckets, topic, subscription), `YOUR_PROJECT_ID` replaced.

| # | File | What you learn | Needs |
| --- | --- | --- | --- |
| 01 | [01_internal_stage_and_copy.sql](01_internal_stage_and_copy.sql) | Stages, file formats, COPY, ON_ERROR, VALIDATION_MODE, load metadata | `snow` CLI |
| 02 | [02_storage_integration.sql](02_storage_integration.sql) | Storage + notification integrations, granting Snowflake's SAs in GCP | G1, G2 |
| 03 | [03_external_stage_and_formats.sql](03_external_stage_and_formats.sql) | External stage on GCS, shared formats, querying files in place | 02 |
| 04 | [04_infer_schema_and_evolution.sql](04_infer_schema_and_evolution.sql) | INFER_SCHEMA, USING TEMPLATE, schema evolution, INCLUDE_METADATA | generator |
| 05 | [05_snowpipe_auto_ingest.sql](05_snowpipe_auto_ingest.sql) | Snowpipe auto-ingest, REFRESH, pausing, the "recreate" trap | 02, 03 |
| 06 | [06_monitoring_and_troubleshooting.sql](06_monitoring_and_troubleshooting.sql) | PIPE_STATUS, COPY_HISTORY, VALIDATE_PIPE_LOAD, cost | capstone |
| 07 | [07_external_tables.sql](07_external_tables.sql) | External tables with path partitions | capstone |
| C2 | [capstone_02_raw_layer.sql](capstone_02_raw_layer.sql), [capstone_02_backfill_copy.sql](capstone_02_backfill_copy.sql), [capstone_02_verify.sql](capstone_02_verify.sql) | The RAW layer for all 10 feeds | all above |

---

## 1. Concepts in plain language

### 1.1 Stages: where files wait

| Stage | Syntax | Storage | Use |
| --- | --- | --- | --- |
| User | `@~` | Snowflake-managed | Your private scratch area |
| Table | `@%SALES_LINES` | Snowflake-managed | Files for exactly one table |
| Named internal | `@RETAIL_LAB.INGEST.INTERNAL_STG` | Snowflake-managed | Uploads from laptops / apps via PUT |
| **Named external** | `@RETAIL_RAW.COMMON.LANDING` | **Your GCS bucket** | Production landing zone |

### 1.2 Storage integration: access without keys

```
Snowflake account ──(creates once)──► Google service account  xxx@gcpuscentral1-....iam.gserviceaccount.com
                                              │
You, in GCP IAM:  grant it a minimal custom role on gs://<project>-landing   (storage.objects.get/list, buckets.get)
```

No secrets are stored in SQL. You can revoke access in GCP at any time.

### 1.3 COPY INTO in one picture

```
@stage/path/*.csv ──► FILE FORMAT parses ──► optional SELECT transform ($1, $2, METADATA$FILENAME…) ──► table
                                              ON_ERROR decides what happens to bad rows/files
                                              load metadata (64 days) prevents loading the same file twice
```

Key options: `ON_ERROR` (`ABORT_STATEMENT` / `CONTINUE` / `SKIP_FILE`), `VALIDATION_MODE` (dry run),
`PATTERN` (regex on the path), `MATCH_BY_COLUMN_NAME` (Parquet/JSON by name), `FORCE` (reload — creates duplicates),
`PURGE` (delete after load). File sizing sweet spot: **100–250 MB compressed**.

### 1.4 Snowpipe on GCP

```
file lands ─► GCS OBJECT_FINALIZE ─► Pub/Sub topic ─► subscription ─► GCS_NOTIF integration ─► PIPE (COPY) ─► RAW table
                                                                                     serverless compute, ~1 min latency
```

| | COPY INTO | Snowpipe | Snowpipe Streaming |
| --- | --- | --- | --- |
| Trigger | You / Airflow | File-arrival event | SDK / Kafka connector pushes rows |
| Compute | Your warehouse | Serverless | Serverless |
| Latency | When you run it | ~1 minute | Seconds |
| Unit | Files (batch) | Files (micro-batch) | Rows |
| Load history | Table metadata, 64 days | Pipe metadata, 14 days | Offset tokens per channel |
| Best for | Backfills, controlled big loads | Continuous file drops | Event streams, IoT, POS events |

### 1.5 Lineage columns

Every RAW row carries `_file_name`, `_file_row_number`, `_loaded_at`. When a number in a dashboard looks wrong,
these let you trace it back to the exact file and line — and replay just that file.

### 1.6 Schema changes

- **JSON** lands in a `VARIANT`: new keys never break loading.
- **Parquet** loads by column name; `ENABLE_SCHEMA_EVOLUTION = TRUE` **adds** new columns automatically.
- **CSV** is positional: a new column at the end is silently ignored, a column in the middle shifts everything. Contracts with the source team matter most here.

---

## 2. Step-by-step

### Lessons

1. **Lesson 01** (internal stage). Run PART A, upload the two sample files with `snow stage copy …` (commands in the file header), continue.
2. **Lesson 02** (integrations). Run step 1, run the grant script in Git Bash, run step 2, run the second grant script, run steps 3–4. `LIST @RETAIL_RAW.COMMON.LANDING` must work before you continue.
3. **Lesson 03**. Upload the sample CSV to `lab/pos_sales/…` (command in the header), run the file.
4. **Lesson 04**. Generate sample data locally (`… generate.py backfill --days 65 --output-dir output_sample`), upload the two order files, replace `<DAY1>` in the SQL, run.
5. **Lesson 05**. Create the lab pipe, upload new files, watch them arrive.

### Capstone 2 — "Data lands itself"

```powershell
# 1. Create all RAW tables and pipes (pipes must exist BEFORE files arrive)
snow sql -c retail_engineer -f stage_02_ingestion/capstone_02_raw_layer.sql

# 2. Generate 90 days locally and look at the files (Rainbow CSV helps)
python capstone_retail_platform/data_generator/generate.py backfill --days 90

# 3. Generate again WITH upload (deterministic: same files) — ~2,700 files, a few minutes
python capstone_retail_platform/data_generator/generate.py backfill --days 90 --upload
```

4. Wait 3–5 minutes, then run [capstone_02_verify.sql](capstone_02_verify.sql) sections 1–4.
5. Chaos test:

   ```powershell
   python capstone_retail_platform/data_generator/generate.py new-day --upload --inject-bad-file --duplicate-file
   ```

   Run section 5 of the verify script: the corrupt file is `Load failed`, the resend loaded duplicates into RAW.
6. Point the G3 Cloud Run job at the same bucket: its ads files land in `ads/` and load through `PIPE_ADS` too.
7. Run lessons 06 and 07 now that real data exists.

> If you uploaded files *before* creating the pipes: run `ALTER PIPE <name> REFRESH;` for each pipe
> (covers the last 7 days) or [capstone_02_backfill_copy.sql](capstone_02_backfill_copy.sql) (older files).

## 3. Try this

- Pause `PIPE_POS_SALES`, upload a new day, check `pendingFileCount`, resume, watch it drain.
- Rename a column header in a copy of a POS file and upload it. What happens? (Nothing: CSV is positional and `SKIP_HEADER` ignores names. That's why CSV feeds need contracts.)
- Upload a 0-byte file to `pos_sales/`. What does `COPY_HISTORY` say?
- Compare `ON_ERROR = CONTINUE` vs `SKIP_FILE` on money data. Which would you defend to a finance team?

## 4. Common errors

| Error | Fix |
| --- | --- |
| `Integration GCS_INT does not exist or not authorized` | Lesson 02 step 3 (`GRANT USAGE ON INTEGRATION`) |
| `Failed to access remote file: access denied` | Grant script not run, wrong SA email, or wait 60 s for IAM |
| Pipe `RUNNING` but nothing loads | Files outside the pipe's path/PATTERN, or Pub/Sub grant missing (check `lastReceivedMessageTimestamp`) |
| `Number of columns in file does not match` | Only for plain COPY; with a `SELECT $1…` transform, count the `$n` |
| `Timestamp 'not-a-date' is not recognized` | Expected for the corrupt test file: `SKIP_FILE` did its job |

## 5. Interview check

<details><summary>COPY INTO vs Snowpipe vs Snowpipe Streaming — when each?</summary>

COPY on a warehouse for backfills and big controlled loads (you pick size and timing). Snowpipe for continuous
file drops where ~1 minute latency is fine (nightly POS files from 400 stores arriving all evening) — serverless,
event-driven, pay per use. Snowpipe Streaming when the source is a stream of rows (Kafka/Pub/Sub POS events) and you
need seconds; no files at all.
</details>

<details><summary>How does Snowflake avoid loading a file twice?</summary>

Load metadata: COPY keeps per-table history of loaded files (name + checksum) for 64 days; Snowpipe keeps per-pipe
history for 14 days. Re-running COPY skips loaded files unless `FORCE = TRUE`. Gaps: the two histories are separate
(COPY + pipe on the same files = duplicates), recreating a pipe resets its history, and the *same data under a new
file name* is a new file. That's why RAW is append-only and staging dedupes on business keys.
</details>

<details><summary>How would you handle a source that adds a new column?</summary>

Prefer self-describing formats. JSON → VARIANT, extract the new key in staging when needed. Parquet → load by name with
`ENABLE_SCHEMA_EVOLUTION`, the column appears automatically. CSV → agree a contract (append-only columns at the end,
advance notice), version the file layout, detect drift with a contract test at staging. Never let a schema change
silently shift columns into the wrong place.
</details>

<details><summary>A store says it sent its file but the dashboard is missing its sales. Walk me through it.</summary>

1) `LIST` the stage path — is the file there with the expected name/date? 2) `SYSTEM$PIPE_STATUS` — running, messages
received recently? 3) `COPY_HISTORY` for that file — loaded, failed (first error), or never seen? 4) If never seen:
uploaded before the pipe / outside its PATTERN → `ALTER PIPE REFRESH` or targeted COPY. 5) If loaded: follow it with
`_file_name` through staging and the fact (filters, dedupe, late-arriving incremental window).
</details>

## 6. Evidence

- [ ] `SHOW PIPES` with 10 pipes
- [ ] Verify section 1 row counts
- [ ] Corrupt file `Load failed` in COPY_HISTORY
- [ ] `DESC TABLE RETAIL_RAW.ECOM.ORDERS` showing `DELIVERY_METHOD`

## 7. My notes
