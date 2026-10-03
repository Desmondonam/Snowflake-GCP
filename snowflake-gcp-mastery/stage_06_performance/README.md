# Stage 6 — Performance tuning and cost (week 7)

**Goal:** diagnose slow queries with the Query Profile, fix them with pruning, clustering, sizing and Snowflake's
accelerators — and prove every change with numbers (time, partitions scanned, credits). You'll finish with a
before/after table and a 60-second story for interviews.

**Prerequisite:** Capstone 1 (warehouses, monitor). This stage uses its own synthetic 200M-row table, independent of RetailOne data.

| # | File | What you do |
| --- | --- | --- |
| 01 | [01_build_perf_dataset.sql](01_build_perf_dataset.sql) | Create `PERF_WH`; generate 200M unclustered sales lines with `GENERATOR` |
| 02 | [02_measurement_harness.sql](02_measurement_harness.sql) | A procedure that records time, pruning, spilling, credits per experiment |
| 03 | [03_baseline_queries.sql](03_baseline_queries.sql) | Six typical retail queries, measured before tuning |
| 04 | [04_optimizations.sql](04_optimizations.sql) | Clustering, filter rewrite, scale up, MV, search optimization, QAS — measured after each |
| 05 | [05_cost_and_diagnostics.sql](05_cost_and_diagnostics.sql) | ACCOUNT_USAGE diagnostics, cost by tag, guardrails |
| 06 | [06_sql_anti_patterns.sql](06_sql_anti_patterns.sql) | Common SQL mistakes side by side with fixes |
| — | [results.md](results.md) | Your before/after table + story (Capstone 6 deliverable) |

---

## 1. Concepts in plain language

### The Query Profile (Snowsight → Query details → Query Profile)

Read it in this order:

1. **Most expensive node** (percentage of time). Is it the TableScan, a Join, an Aggregate, a Sort?
2. **Pruning** on each TableScan: *Partitions scanned* vs *Partitions total*. Asking for one week of two years should scan ~1%.
3. **Spilling**: *Bytes spilled to local storage* (slower) and *remote storage* (much slower) = the warehouse ran out of memory.
4. **Join explosion**: a join whose output rows ≫ its input rows — usually a wrong or non-unique join key.
5. **Queuing** (in query details): time waiting for a warehouse = concurrency problem, not query problem.

### Pruning and clustering

Snowflake stores min/max of every column for every micro-partition. A filter `sale_date BETWEEN …` skips partitions whose
range can't match — **if** rows for the same dates sit together. Data loaded in time order is naturally clustered by date.
Random order (or many late updates) destroys that. A **clustering key** tells Automatic Clustering to keep the table sorted
on those columns, in the background, for credits.

`SYSTEM$CLUSTERING_INFORMATION('<table>', '(cols)')` → `average_depth` (≈1 is perfect; close to the partition count is useless).

Cluster only when: the table is large (multi-TB / many thousands of partitions), queries filter on the same few columns,
and the table isn't rewritten constantly. Order keys low → high cardinality: `(sale_date, store_id)`.

### Scale up vs scale out

| Symptom | Fix |
| --- | --- |
| One heavy query is slow / spills | **Scale up** (bigger size): more memory, CPU, local disk |
| Many users, queries queue | **Scale out** (multi-cluster, `MIN/MAX_CLUSTER_COUNT`, `SCALING_POLICY`) |
| A few outlier scan-heavy queries | **Query Acceleration Service** (serverless helpers) |
| Selective lookups on a high-cardinality column | **Search Optimization Service** |
| Same aggregate on one table, over and over | **Materialized view** (or a dbt incremental aggregate / dynamic table) |
| Exact same query, unchanged data | **Result cache** (free) |

### Cost control checklist

Auto-suspend 60 s · one warehouse per workload · resource monitors · `QUERY_TAG` per tool · transient staging ·
review `ACCOUNT_USAGE` monthly (warehouse metering, query attribution, serverless features, storage) · right-size by evidence.

## 2. Step-by-step

1. `snow sql -c retail_admin -f stage_06_performance/01_build_perf_dataset.sql` (≈5 min).
2. `snow sql -c retail_engineer -f stage_06_performance/02_measurement_harness.sql`.
3. Open [03_baseline_queries.sql](03_baseline_queries.sql) in a worksheet. Run each query, then its `CALL`, then look at its Query Profile. Screenshot Q1's profile (the "before").
4. Open [04_optimizations.sql](04_optimizations.sql). Section by section, same routine. Screenshot Q1's profile again (the "after").
5. Paste the RESULTS output into [results.md](results.md) and write the story. Run the CLEAN UP block.
6. Run [05_cost_and_diagnostics.sql](05_cost_and_diagnostics.sql) as `RETAIL_ADMIN` (ACCOUNT_USAGE lags up to ~3 hours; best the day after).
7. Work through [06_sql_anti_patterns.sql](06_sql_anti_patterns.sql).

## 3. Capstone 6 — "Make it fast and cheap"

- [ ] 200M-row dataset built
- [ ] Baseline + optimized measurements recorded in `BENCHMARK_RESULTS`
- [ ] `results.md` table filled + story written
- [ ] Before/after Query Profile screenshots for Q1
- [ ] Background features cleaned up

## 4. Try this

- Cluster by `(store_id, sale_date)` instead. Which queries get better or worse? Why does key order matter?
- Run Q6 twice with `USE_CACHED_RESULT = TRUE`. What does the second Query Profile show?
- Run five copies of Q5 at once from five worksheets on an XS warehouse; check queuing in Query History. Then set `MAX_CLUSTER_COUNT = 3` and repeat.

## 5. Interview check

<details><summary>A query got slow overnight. Walk me through debugging it.</summary>

1) Compare today's and yesterday's runs in QUERY_HISTORY (same query_hash/parameterized hash): elapsed, bytes scanned,
partitions, spilling, queued time, warehouse size. 2) Open both Query Profiles: did the plan change (join order, a scan
without pruning)? 3) Typical causes: data volume jump, clustering degraded after a big out-of-order load, a changed filter
(function on a column), stats/plan change from a new join, warehouse resized or contended (queuing), result cache no longer
hit. 4) Fix the cause, not the symptom; re-measure.
</details>

<details><summary>Scale up vs scale out?</summary>

Up = a bigger warehouse for one heavy query (spilling, CPU-bound): time roughly halves per size, cost per query similar.
Out = more clusters of the same size for concurrency (queuing): Standard policy adds clusters quickly, Economy waits to fill
them. They solve different problems; check spilling vs queuing to decide.
</details>

<details><summary>When is a clustering key a bad idea?</summary>

Small tables; tables queried by many different columns; very high-cardinality keys (a unique id); tables rewritten or
heavily updated all the time (reclustering cost never ends); when natural load order already gives good pruning. Always
check `SYSTEM$CLUSTERING_INFORMATION` and the Automatic Clustering bill.
</details>

<details><summary>How would you cut the Snowflake bill by 30%?</summary>

Measure first: WAREHOUSE_METERING + QUERY_ATTRIBUTION by tag/team, serverless features, storage. Typical wins: auto-suspend 60 s,
consolidate idle/oversized warehouses, right-size by spilling evidence, incremental dbt instead of full rebuilds, kill
unneeded schedules (dashboards refreshing every 5 min nobody opens), transient staging, shorter Time Travel on churny tables,
drop unused clustering/search optimization/MVs, result-cache-friendly dashboards. Then resource monitors and a monthly review
so it stays down.
</details>

## 6. My notes
