# Stage 4 — Transformation with dbt + Snowpark (weeks 4–5)

**Goal:** turn the hand-written SQL from Stage 3 into a tested, documented, incremental dbt project — the
production transformation layer of RetailOne — and learn Snowpark for the logic that is easier in Python.

**Prerequisites:** Capstone 2 (RAW loaded), Stage 3 understood (you'll recognise every model).

| Part | Where | Week |
| --- | --- | --- |
| dbt walkthrough (steps 1–12 below) | [capstone_retail_platform/dbt_retail/](../capstone_retail_platform/dbt_retail/) | 4 |
| Snowpark lessons | [snowpark/](snowpark/) `01_dataframes.py` → `03_stored_procedure_rfm.py` | 5 |
| dbt Python model + unit tests + slim CI concepts | steps 10–12 | 5 |

---

## 1. Concepts: dbt on Snowflake

**dbt** compiles SQL `SELECT` statements (with Jinja) into `CREATE TABLE/VIEW … AS` (or `MERGE`) and runs them in
dependency order. You write *what* a model is; dbt handles *how* to build it, tests it and documents it.

```
models/staging/       1:1 with sources · views · rename/cast/dedupe        → stg_<source>__<entity>
models/intermediate/  business logic · identity · SCD2 versions           → int_<entity>_<what>
models/marts/         star schemas for people · tables/incremental        → dim_ / fct_ / rpt_ / aud_
```

- `{{ source('pos', 'sales_lines') }}` points at RAW; `{{ ref('stg_pos__sales_lines') }}` points at another model.
  `ref` is how dbt learns the DAG (lineage).
- **Sources** declare RAW tables and their **freshness** (`dbt source freshness`).

### Materializations

| Materialization | What dbt does | Use for |
| --- | --- | --- |
| `view` | `CREATE VIEW` | staging (cheap, always fresh) |
| `table` | `CREATE OR REPLACE TABLE … AS` | small/medium marts |
| `incremental` | first run: table; later: only new/changed rows | big facts (`fct_sales_line`) |
| `ephemeral` | inlined as a CTE, nothing created | tiny helper logic |
| `snapshot` | SCD2 history of a table over runs | sources without history |
| `dynamic_table` | Snowflake Dynamic Table with a target lag | near-real-time (Stage 5) |

### Incremental strategies on Snowflake

| Strategy | How | When | Watch out |
| --- | --- | --- | --- |
| `merge` (default) | `MERGE` on `unique_key` | updates + inserts, late data | scans the target to match keys → expensive on huge tables (use `incremental_predicates` / clustering) |
| `delete+insert` | delete matching keys, insert | big batches replacing a slice | two statements |
| `append` | `INSERT` only | immutable event logs | duplicates if rows repeat |
| `insert_overwrite` | replace the whole table | rarely | it's effectively a full refresh |
| `microbatch` | one query per time batch (`event_time`) | very large time-series, backfills per day | needs `event_time` config |

**Late-arriving data** (a store's file arrives tomorrow): filter on *load time* with a **lookback window**
(`_loaded_at > max(_loaded_at) - 3 days`) and `merge` on the natural key — late rows are picked up, re-sent rows are updated
not duplicated. That's exactly what [fct_sales_line.sql](../capstone_retail_platform/dbt_retail/models/marts/sales/fct_sales_line.sql) does.

### Snowflake-specific configs used in this project

`cluster_by`, `transient` (default **true** for dbt-snowflake tables — we set marts to permanent), `snowflake_warehouse`
(per model), `copy_grants`, `query_tag`, `incremental_predicates`, `python_version` (Python models).

### Tests and contracts

- **Generic tests**: `unique`, `not_null`, `relationships`, `accepted_values` (+ `dbt_utils`, `dbt_expectations`, and our own `one_current_row`).
- **Singular tests**: a SQL file in `tests/` that returns failing rows (reconciliation, attribution credits).
- **Unit tests**: fixed input rows → expected output rows, for tricky logic (last-click attribution).
- **Contracts** (`contract: {enforced: true}`): column names and types are locked; a change that breaks BI fails the build.

## 2. Concepts: Snowpark

- A Python **DataFrame API that compiles to SQL** and runs inside Snowflake. Lazy until an action
  (`collect`, `show`, `to_pandas`, `save_as_table`).
- **UDFs** (scalar), **vectorised UDFs** (pandas batches), **UDTFs** (return rows), **stored procedures** — all Python executing in Snowflake,
  with packages from the Anaconda channel.
- **Snowpark-optimized warehouses**: 16× memory per node for ML training (minimum size and cost are higher — create one only when you need it).
- **dbt Python models** run as Snowpark: return a DataFrame, dbt saves it.
- *When Snowpark instead of SQL?* Logic that's iterative or library-based (ML, Markov/Shapley attribution, fuzzy matching,
  parsing), or a team that's stronger in Python. When SQL is natural, SQL is faster to read and review.

---

## 3. The dbt walkthrough (do it in order)

> **Learning method:** for each step, open the files mentioned, read them, then delete one model and rewrite it
> from memory. Run `dbt build -s <model>` until it passes. That's how the patterns stick.

All commands run from the dbt project folder with your `.env` loaded:

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery"
.\.venv\Scripts\Activate.ps1; . .\00_setup\load_env.ps1
cd capstone_retail_platform\dbt_retail
```

**Step 1 — Connect.** `dbt debug` → "All checks passed!". Read [profiles.yml](../capstone_retail_platform/dbt_retail/profiles.yml):
three targets (dev/prod/ci), secrets from env vars.

**Step 2 — Packages and seeds.** `dbt deps` then `dbt seed`. Look at `RETAIL_DEV.DBT_<YOU>_SEEDS.CHANNELS` in Snowsight.

**Step 3 — Sources and staging.** Read `models/staging/pos/` (sources YAML, models YAML, SQL).
`dbt build -s staging` builds the 10 staging views and runs their tests. Then:
`dbt source freshness`. Compare `stg_pos__sales_lines` with `RETAIL_LAB.STG.POS_SALES_LINES` from Stage 3 — same idea.

**Step 4 — Where did it go?** Read [generate_schema_name.sql](../capstone_retail_platform/dbt_retail/macros/generate_schema_name.sql)
and [generate_database_name.sql](../capstone_retail_platform/dbt_retail/macros/generate_database_name.sql). Find your views in `RETAIL_DEV`.

**Step 5 — Intermediate.** Read the SCD2 macro [scd2_from_changes.sql](../capstone_retail_platform/dbt_retail/macros/scd2_from_changes.sql)
(the Stage 3 logic, reusable), then `int_customer_identity` and `int_sales_lines_unioned`. `dbt build -s intermediate`.

**Step 6 — Marts.** `dbt build -s marts`. Open `fct_sales_line.sql`: incremental config, lookback filter, point-in-time joins, final casts for the contract.

**Step 7 — Test what you built.** `dbt test`. Then break something on purpose: change `accepted_values` for tender types to drop `MPESA` and rerun. Revert.

**Step 8 — Snapshots.** Read [snapshots/snapshots.yml](../capstone_retail_platform/dbt_retail/snapshots/snapshots.yml). `dbt snapshot`.
Then `python ../data_generator/generate.py change-tier --customer-id C00042 --tier PLATINUM`, `… new-day --upload`, wait 2 minutes, `dbt snapshot` again,
and query `SNAP_CRM__CUSTOMERS` for C00042: two rows. Compare with `dim_customer` for C00042.

**Step 9 — Incremental in action.**

```powershell
dbt build -s fct_sales_line                       # incremental run: watch the log say "merge"
python ..\data_generator\generate.py new-day --upload --duplicate-file --late-store S007
# wait ~2 minutes for Snowpipe
dbt build -s +fct_sales_line+                     # duplicates are merged, not added
dbt test -s rpt_pos_reconciliation                # fails: S007 is MISSING for the new day
python ..\data_generator\generate.py new-day --upload   # the late file arrives
dbt build -s +rpt_pos_reconciliation              # lookback window picks it up → test passes
```

**Step 10 — Python model.** Read [fct_attribution_linear.py](../capstone_retail_platform/dbt_retail/models/marts/marketing/fct_attribution_linear.py).
First run needs the Anaconda terms accepted (Snowsight → Admin → Billing & Terms → Anaconda). `dbt build -s fct_attribution+`.
Compare `last_click`, `linear` and `time_decay` revenue by channel:

```sql
select attribution_model, channel_code, round(sum(attributed_revenue)) as revenue
from RETAIL_DEV.DBT_<YOU>_MARKETING.FCT_ATTRIBUTION group by 1, 2 order by 1, 3 desc;
```

**Step 11 — Unit test.** The last-click unit test lives at the bottom of `_marketing.yml`. `dbt test -s test_type:unit`.

**Step 12 — Docs and lineage.** `dbt docs generate` then `dbt docs serve`. Open the lineage graph for `fct_sales_line`
and screenshot it into this README (Capstone 4 deliverable).

**Step 13 — Production build.** `dbt build --target prod` builds `RETAIL_STAGING` / `RETAIL_MARTS`. Later stages (Airflow, governance, Streamlit) use prod.

## 4. Snowpark lessons (week 5)

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery\stage_04_dbt_snowpark\snowpark"
python 01_dataframes.py           # lazy DataFrames, generated SQL, windows, save_as_table, VARIANT
python 02_udfs_and_udtfs.py       # scalar UDF, vectorised UDF, UDTF (market-basket pairs)
python 03_stored_procedure_rfm.py # Python stored procedure: RFM segmentation, callable from SQL
```

After lesson 03, call it from a worksheet: `CALL RETAIL_LAB.SNOWPARK.BUILD_RFM('RETAIL_LAB.SNOWPARK.CUSTOMER_RFM');`
Open **Query History** in Snowsight while the scripts run: you'll see the SQL Snowpark generated.

## 5. Capstone 4 — "dbt_retail"

- [ ] Sources with freshness for every RAW table
- [ ] `stg_` model for every source, with PK tests
- [ ] `int_customer_identity` (loyalty_id ↔ email ↔ customer_id)
- [ ] Stage 3 marts rebuilt as dbt models (`dim_*`, `fct_sales_line`, `fct_inventory_daily`, `fct_ad_performance`)
- [ ] Snapshots for customers and stores
- [ ] Tests on every PK and FK; contracts on `dim_customer` and `fct_sales_line`
- [ ] Last-click (SQL) + linear (Python) attribution (+ time-decay bonus)
- [ ] `dbt docs` lineage screenshot below
- [ ] `dbt build --target prod` green

Lineage screenshot: *(paste here)*

## 6. Try this

- Change `lookback_days` to 0 and replay the late-file scenario. What breaks, and why is 0 a bad default?
- Add `incremental_predicates=["DBT_INTERNAL_DEST.sale_date >= dateadd(day, -30, current_date)"]` to `fct_sales_line` and read the generated MERGE in Query History. What risk does it introduce for files later than 30 days?
- Convert `fct_sales_line` to `incremental_strategy='microbatch'` with `event_time='sold_at'` on a branch and backfill one week with `--event-time-start/--event-time-end`.
- Add a column to `dim_customer` without updating the YAML. Read the contract error.

## 7. Interview check

<details><summary>Incremental strategies — and when does merge get expensive?</summary>

merge (upsert on a key), delete+insert (replace a slice), append (immutable events), microbatch (per time batch).
MERGE must find matching keys in the target; on a multi-TB fact that's a big scan every run. Mitigate with clustering on
the date the source slice covers, `incremental_predicates` to restrict the target scan, delete+insert by partition, or microbatch.
</details>

<details><summary>How do you handle late-arriving POS files in an incremental model?</summary>

Select by **load time** (`_loaded_at`), not business date, with a lookback window, and `merge` on the natural key. Late files
are loaded whenever they arrive and picked up next run; re-sent files update instead of duplicating. Reconciliation against
POS control totals proves completeness per store-day. For very late data, a targeted backfill by date range.
</details>

<details><summary>dbt snapshot vs hand-written SCD2?</summary>

Snapshot: zero code, captures state at each run — but only what it sees when it runs (misses intra-day changes, can't be rebuilt).
Hand-written / history-based SCD2 (our `int_customer_versions`): rebuildable from RAW history, exact change timestamps, testable,
but more code. Use snapshots for sources with no history; rebuild from history when RAW keeps every change.
</details>

<details><summary>When Snowpark instead of SQL?</summary>

When the logic is naturally procedural or needs Python libraries: ML features/training, Markov or Shapley attribution, fuzzy
identity matching, complex parsing. Keep set-based transformations in SQL: easier to review, and the optimizer is excellent at it.
</details>

<details><summary>How does dbt decide dev vs prod database/schema here?</summary>

`generate_database_name` / `generate_schema_name` macros use `target.name`: prod → layer databases with clean schema names,
ci → per-PR clone databases, dev → `RETAIL_DEV` with `DBT_<USER>_` prefixes. Same code, isolated environments.
</details>

## 8. My notes
