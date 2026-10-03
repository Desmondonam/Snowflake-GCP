# Stage 5 — Orchestration, CDC and near-real-time (week 6)

**Goal:** run RetailOne at **two speeds**: a near-real-time path inside Snowflake (streams, tasks, dynamic tables) for
live store stock, and a nightly path in Airflow (arrival checks → dbt → reconciliation → alert) for finance-grade numbers.

**Prerequisites:** Capstone 4 (`dbt build --target prod` has run), Stage 4 Snowpark lesson 03 (for the task graph).

| # | File | What you learn |
| --- | --- | --- |
| 01 | [01_streams_basics.sql](01_streams_basics.sql) | Streams, offsets, metadata columns, consumption, append-only, staleness |
| 02 | [02_stream_task_pipeline.sql](02_stream_task_pipeline.sql) | Snowpipe → stream → task → MERGE (the near-real-time path) |
| 03 | [03_task_graph.sql](03_task_graph.sql) | Task DAGs, serverless tasks, finalizers, monitoring |
| 04 | [04_dynamic_tables.sql](04_dynamic_tables.sql) | Dynamic tables, target lag, refresh modes — live stock |
| 05 | [05_backfill_patterns.sql](05_backfill_patterns.sql) | Backfilling a month safely (clone → load → rebuild → verify) |
| — | [../capstone_retail_platform/airflow/](../capstone_retail_platform/airflow/) | The nightly Airflow DAG (Astro, local Docker) |
| — | [composer_read_through.md](composer_read_through.md) | What changes on Cloud Composer |

---

## 1. Concepts in plain language

### Streams
A **stream** is a bookmark on a table. Reading it shows rows changed since the bookmark, with `METADATA$ACTION`
(INSERT/DELETE) and `METADATA$ISUPDATE`. The bookmark advances only when a **DML statement that reads the stream commits**.
Types: **standard** (inserts, updates, deletes), **append-only** (inserts only, cheaper — ideal for RAW), **insert-only**
(external tables). Two consumers need two streams.

### Tasks
Scheduled SQL (or `CALL procedure`). Schedules are an interval (`'5 MINUTE'`) or CRON with a time zone. Tasks chain into a
**graph** with `AFTER`; a **finalizer** runs at the end regardless of outcome. Compute is a warehouse **or serverless**.
`WHEN SYSTEM$STREAM_HAS_DATA(...)` skips a run without resuming a warehouse. Tasks start **suspended**.

### Dynamic tables
Declare `SELECT …` + `TARGET_LAG`. Snowflake builds the dependency graph and refreshes — incrementally where it can. One
statement replaces stream + task + MERGE. `TARGET_LAG = DOWNSTREAM` refreshes only when a downstream table needs it.

### Where to orchestrate

| Situation | Tool |
| --- | --- |
| Cross-system: wait for files, call APIs (Cloud Run), run dbt, reconcile, alert, SLAs | **Airflow / Cloud Composer** |
| In-warehouse, declarative, minutes of latency | **Dynamic Tables** |
| In-warehouse custom CDC logic, procedures, exact control | **Streams + Tasks** |
| Seconds of latency from an event stream | **Snowpipe Streaming** → dynamic table |

### Airflow + Snowflake essentials
`SQLExecuteQueryOperator` / `SqlSensor` with a Snowflake connection (key-pair), dbt via `BashOperator` (one task) or
**Astronomer Cosmos** (one task per model), sensors in `reschedule` mode, retries, failure callbacks, parameterised runs.

---

## 2. Step-by-step

1. **Lesson 01** in a worksheet: watch the stream contents after each DML.
2. **Lesson 02** with `snow sql -f` (creates the near-real-time pipeline), then run the "WATCH IT" queries. Upload a new day
   (`python capstone_retail_platform/data_generator/generate.py new-day --upload`) and watch the task go from `SKIPPED` to `SUCCEEDED`.
3. **Lesson 03** in a worksheet: build the graph, `EXECUTE TASK`, look at Snowsight → Monitoring → Task History. **Suspend it.**
4. **Lesson 04**: create the dynamic tables, query `STORE_STOCK_LIVE`, upload another day, `ALTER DYNAMIC TABLE … REFRESH`, see stock drop.
5. **Airflow**: follow [airflow/README.md](../capstone_retail_platform/airflow/README.md) — set up Astro, trigger `retail_daily`, run the chaos drill.
6. **Lesson 05**: read it; run it only if you want to practice with a re-sent month.
7. Read [composer_read_through.md](composer_read_through.md).

**End of every session:**

```sql
ALTER TASK RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES SUSPEND;
ALTER TASK RETAIL_LAB.TASKS_DEMO.T_ROOT_HOURLY SUSPEND;
ALTER DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE SUSPEND;
ALTER DYNAMIC TABLE RETAIL_STAGING.REALTIME.INVENTORY_LATEST SUSPEND;
```

and `astro dev stop`.

## 3. Capstone 5 — "Two speeds"

- [ ] Near-real-time: stream + task into `REALTIME.SALES_LINES_CLEAN`, dynamic table `RETAIL_MARTS.OPS.STORE_STOCK_LIVE` (5-minute lag)
- [ ] Nightly: `retail_daily` DAG green for one business date (screenshot of the Grid view)
- [ ] Chaos drill: late store file → sensor waits → file arrives → green (screenshots)
- [ ] Slack (or log) message with the reconciliation summary
- [ ] Below: when you chose Tasks vs Dynamic Tables vs Airflow, and why

**My design decisions:**

| Piece | Tool chosen | Why |
| --- | --- | --- |
| Live stock | | |
| Dedup of POS lines for live stock | | |
| Nightly finance build | | |
| RFM refresh | | |

## 4. Try this

- Create a second task reading the *same* stream. Run both. Which one gets the rows?
- Let a stream go unconsumed past the table's retention (set `DATA_RETENTION_TIME_IN_DAYS = 0` on a scratch table and `MAX_DATA_EXTENSION_TIME_IN_DAYS = 0`) and read `SHOW STREAMS` → `stale`.
- Change `STORE_STOCK_LIVE` to use `CURRENT_DATE()` and check `refresh_mode_reason` — why did it change?
- In the DAG, set `retries=0` on `wait_for_pos_files` and a 1-minute `timeout`; trigger a date that doesn't exist. Read the failure callback output.

## 5. Interview check

<details><summary>How does a stream know what changed?</summary>

It stores an offset (a point in the table's version history). Snowflake keeps table versions for Time Travel; the stream
compares the current version with its offset and returns the net row-level changes, with metadata columns. No triggers, no
copies. Consuming DML that commits moves the offset to the version it read.
</details>

<details><summary>What happens if two tasks read the same stream?</summary>

The first to commit a DML consuming the stream advances the offset; the second sees only changes after that, so it misses
rows. Give each consumer its own stream on the table.
</details>

<details><summary>Dynamic Table vs materialized view vs stream + task?</summary>

Materialized view: one table, limited SQL (no joins), always current, Snowflake-maintained — great for a hot aggregate.
Dynamic table: joins/unions/windows, chains of tables, target lag you choose, incremental when possible — declarative pipelines.
Stream + task: full procedural control (MERGE with custom logic, procedures, side effects), you own the scheduling and
error handling.
</details>

<details><summary>How do you backfill a month of POS data safely?</summary>

Clone the affected tables first (instant rollback), land corrected files in a new prefix (landing is immutable), load with an
explicit COPY for that prefix on a temporarily larger warehouse, re-merge the date range in dbt (idempotent backfill vars),
verify with reconciliation and before/after totals, then drop the clones. Communicate the restatement to finance.
</details>

<details><summary>Why sensors in reschedule mode?</summary>

In `poke` mode a sensor occupies a worker slot for its whole wait. `reschedule` releases the slot between checks, so 400
store-arrival sensors don't starve the cluster.
</details>

## 6. My notes
