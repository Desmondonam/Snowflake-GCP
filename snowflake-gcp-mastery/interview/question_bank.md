# Interview question bank (Snowflake lead on GCP)

Answer out loud first. Then read the model answer. Then record yourself and log it in [practice_log.md](practice_log.md).
Stage-specific checks (with longer answers) live at the bottom of each stage README.

## Architecture and platform

| Question | Core of a strong answer |
| --- | --- |
| Walk me through the architecture for our retail data | The seven beats: [seven_beats_script.md](seven_beats_script.md) |
| Why Snowflake over BigQuery on GCP? | Workload isolation per warehouse, predictable per-second credits, zero-copy cloning for dev/CI, cross-cloud sharing and clean rooms, governance in one place. Be fair: BigQuery wins on native GCP integration and serverless simplicity. Iceberg lets both read the same data. |
| Explain Snowflake's architecture | Storage (compressed columnar micro-partitions in cloud storage) / compute (independent virtual warehouses) / cloud services (metadata, optimizer, security, transactions). Scale each independently. |
| What's a micro-partition and why care? | 50–500 MB uncompressed, columnar, immutable; Snowflake keeps min/max per column → pruning. Load order and clustering determine how well filters skip partitions. |
| Which cache answers a repeated dashboard query for free? | Result cache (24 h, same query + unchanged data + same access). Warehouse cache helps repeated scans; metadata cache answers COUNT/MIN/MAX. |

## Ingestion

| Question | Core of a strong answer |
| --- | --- |
| How do you load data from GCS? | Storage integration (Snowflake's own Google SA, least-privilege custom role) + external stage; Snowpipe auto-ingest via Pub/Sub notification integration; COPY for backfills; files 100–250 MB compressed. |
| COPY vs Snowpipe vs Snowpipe Streaming? | Warehouse-controlled bulk/backfill vs serverless event-driven files (~1 min) vs row streaming (seconds) from SDK/Kafka. |
| How does Snowflake avoid loading a file twice? | Load metadata (COPY 64 days per table; Snowpipe 14 days per pipe). Gaps: separate histories, recreated pipes, renamed files → dedupe in staging anyway. |
| A source adds a column — what happens? | JSON → VARIANT absorbs it; Parquet → MATCH_BY_COLUMN_NAME + ENABLE_SCHEMA_EVOLUTION adds it; CSV → contract + versioned layout; contract tests at staging catch drift. |
| How do you handle late-arriving or duplicate POS data? | Lineage columns; dedupe with `QUALIFY ROW_NUMBER()` on the natural key; incremental on load time with a lookback window and `merge`; reconciliation vs till totals proves completeness. |

## Modeling

| Question | Core of a strong answer |
| --- | --- |
| Fact grain for retail sales? | One row per transaction line item; returns as negative lines; transaction_id as degenerate dimension. |
| SCD2 — how and where? | Customer (tier, segment, address) and product (price, category). dbt snapshots or hand MERGE (hash diff, fixed run timestamp, one transaction); point-in-time joins with half-open intervals. |
| Why is inventory semi-additive? | It's a balance: sum across stores/products, never across time (use period-end or average). |
| Data Vault vs Kimball? | DV as an auditable integration layer for many changing sources; Kimball stars for presentation. Small/medium teams usually go straight to stars. |
| How do you link in-store and online customers? | Identity map from CRM (customer_id ↔ loyalty_id ↔ email), guests keyed by hashed email, probabilistic matching later; one conformed dim_customer. |
| How would you build attribution? | Touchpoints (ads, email, web) joined to orders within a lookback window; last-click, linear, time-decay (credits sum to 1); Snowpark for Markov/Shapley; join spend for ROAS. |

## Transformation and orchestration

| Question | Core of a strong answer |
| --- | --- |
| dbt incremental strategies; when is merge expensive? | merge / delete+insert / append / microbatch. MERGE scans the target for matches → cluster on the slice, incremental_predicates, or microbatch. |
| dbt snapshot vs hand-written SCD2? | Snapshot = easy but only sees what it sees at run time; history-based rebuild = exact and rebuildable. |
| Streams/Tasks vs Dynamic Tables vs Airflow? | DTs for declarative near-real-time SQL; streams + tasks for custom CDC/procedures; Airflow for cross-system orchestration, SLAs, alerts. |
| What happens if two tasks read the same stream? | The first committing consumer advances the offset; the other misses rows → one stream per consumer. |
| How do you backfill a month safely? | Clone first, land corrected files in a new prefix, explicit COPY, dbt re-merge by date range, verify with reconciliation, swap/rollback ready, drop clones. |

## Performance and cost

| Question | Core of a strong answer |
| --- | --- |
| A dashboard is slow. Debug it. | Query Profile → most expensive node, pruning (scanned/total), spilling, join explosion, queuing → fix filter/clustering → right-size or multi-cluster BI_WH → MV/aggregate/result cache. |
| A query got slow overnight. | Compare runs in QUERY_HISTORY (bytes, partitions, spill, queue, size) and both profiles; usual suspects: volume, degraded clustering, changed filter, contention, cache miss. |
| Scale up vs scale out? | Up for one heavy/spilling query; out (multi-cluster) for concurrency/queuing. |
| When is a clustering key a bad idea? | Small tables, many different filter columns, very high cardinality, constant rewrites, natural order already good. |
| How do you control cost / cut the bill 30%? | Measure (metering, attribution by tag, serverless, storage) → auto-suspend, consolidate/right-size, incremental models, kill unused schedules/features, transient staging → resource monitors + monthly review. |

## Security and governance

| Question | Core of a strong answer |
| --- | --- |
| How do you secure PII? | Access + functional roles, tag-based masking at marts, row access policies, key-pair for services, SSO/MFA for people, ACCESS_HISTORY for audit; RAW/STAGING closed to people. |
| Design RBAC for 200 users / 5 teams | Access roles per schema/privilege with future grants in managed-access schemas; functional roles per team; SCIM from the IdP; Terraform; SYSADMIN hierarchy. |
| Masking vs row access vs secure views? | Column values vs whole rows vs curated projection (and sharing). Policies protect every path to the base table. |
| Prove who saw PII last month | ACCESS_HISTORY column-level reads + roles from QUERY_HISTORY + policies_referenced; 365 days retained. |
| What does a data contract protect against? | Silent breaking changes from producers; explicit, versioned expectations enforced by tests at the boundary. |

## Delivery and leadership

| Question | Core of a strong answer |
| --- | --- |
| How do you deploy changes safely? | Git + PR, CI on a zero-copy clone with `state:modified+`, Terraform plan/apply, migrations for schema objects, blue/green SWAP for big rebuilds. |
| How would you share data with a supplier? | Secure (aggregated, per-consumer filtered) view in a share; reader account if needed; listings cross-region; clean room for customer-level questions. |
| Why Iceberg? | Open format on our bucket, multi-engine (BigQuery/Spark), no lock-in; catalog choice is the key decision. |
| How would you lead this as the senior engineer? | Standards (naming, layers, tests, PR review), SLAs and owners per mart, data contracts with sources, cost and quality reviews, decision log, mentoring/on-call. |

## Snowflake trivia that still comes up (SnowPro Core)

- Editions: Standard / Enterprise (multi-cluster, 90-day Time Travel, masking, MVs, search optimization) / Business Critical (PrivateLink/PSC, HIPAA/PCI, failover) / VPS.
- Time Travel max 90 days (Enterprise, permanent tables); Fail-safe 7 days, not user-accessible; transient/temporary: 0–1 day, no Fail-safe.
- Warehouse billing per second after a 60-second minimum; sizes double credits.
- COPY load metadata 64 days; Snowpipe 14 days.
- Stream offset; stale after retention (+ up to 14 days extension).
- `SYSTEM$CLUSTERING_INFORMATION`, `SYSTEM$PIPE_STATUS`, `SYSTEM$STREAM_HAS_DATA`, `GET_QUERY_OPERATOR_STATS`.
- `ACCOUNT_USAGE` (365 days, latency) vs `INFORMATION_SCHEMA` (real-time, shorter retention).
