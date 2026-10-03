# Architecture judgement — the questions a lead gets asked

Short, defensible positions. Rewrite each in your own words and add numbers from your own capstone.

## Multi-account strategy

- **One organization, several accounts**: `retailone-prod`, `retailone-dev` (and a sandbox). Separate accounts give hard
  isolation of data, cost and blast radius (a dev ACCOUNTADMIN can't touch prod). Use **database replication** or
  **zero-copy clones within prod** for realistic test data, never copies of PII into dev without masking.
- In this course everything is one trial account with `RETAIL_DEV` + per-PR clone databases — the same idea, cheaper.

## Cost attribution by team

- One warehouse per workload/team (`BI_WH`, `TRANSFORM_WH`, `DS_WH` …) → `WAREHOUSE_METERING_HISTORY` gives cost per team.
- `QUERY_TAG` set by every tool (dbt, Airflow, Streamlit) → `QUERY_ATTRIBUTION_HISTORY` gives cost per tool/model/dashboard.
- **Object tags** (`COST_CENTER`) on warehouses and databases for chargeback; Snowflake **budgets** per tag/team.
- Review monthly with owners; publish a cost dashboard (it changes behaviour more than any setting).

## Choosing the ingestion tool

| Option | When | Watch out |
| --- | --- | --- |
| Fivetran / Airbyte Cloud / Snowflake connectors | SaaS & database CDC with standard schemas, small team | per-row pricing; less control over the shape |
| Datastream → GCS → Snowpipe | Cloud SQL / Postgres CDC on GCP, cheap and native | you own the merge logic downstream |
| Custom Cloud Run jobs (G3) | APIs without good connectors (ads platforms), special logic | you own retries, schemas, monitoring |
| Kafka / Pub/Sub → Snowpipe Streaming | seconds-latency event streams (POS events, clickstream) | operating the streaming stack |

Rule: buy for standard sources, build only where it differentiates.

## Snowflake vs BigQuery vs Databricks (for RetailOne)

- **BigQuery**: serverless, native to GA4/Ads/Pub/Sub, great for a Google-only shop. Less workload isolation by default; sharing within Google Cloud.
- **Databricks**: strongest for heavy Spark/ML engineering on a lakehouse (Delta/Iceberg), notebooks-first teams.
- **Snowflake**: SQL-first platform with workload isolation, zero-copy cloning for CI, governance and cross-cloud sharing/clean rooms (retail media). With Iceberg on our bucket, the data stays open for BigQuery/Spark too.
- Honest position: for RetailOne (SQL-heavy analytics team, brand partnerships, strong governance needs, GCP host), Snowflake on GCP with GA4 kept in BigQuery and Iceberg for openness.

## "What would you change at 100× the volume?" (final capstone question)

1. **Ingestion**: POS events via Snowpipe Streaming instead of nightly files; fewer, larger files (100–250 MB) for batch; monitor Snowpipe per-file overhead.
2. **Modeling**: `fct_sales_line` as **microbatch** incremental by day; clustering on `(sale_date, store_id)` with Automatic Clustering budgeted; consider partition-level `insert_overwrite`/delete+insert instead of MERGE.
3. **Compute**: bigger `TRANSFORM_WH` only for the heavy models (`snowflake_warehouse` per model); multi-cluster `BI_WH` with Economy policy off-peak; QAS for outliers.
4. **Serving**: aggregate marts / dynamic tables for dashboards instead of hitting the line-level fact; result-cache-friendly dashboards.
5. **Governance at scale**: tag-based masking already scales; move role management to SCIM + Terraform.
6. **Cost**: per-team budgets, query-tag chargeback, a weekly anomaly alert on credits.
7. **Reliability**: replication/failover group to a second region; SLAs per mart with freshness alerts.

## Leading the team (the "lead" in the job title)

- Write the standards (this repo's [STANDARDS.md](../STANDARDS.md)) and enforce them in PR review and CI.
- Define SLAs and owners per mart; publish freshness and reconciliation status where the business can see it.
- Data contracts with every source owner; a change process that isn't "we found out from a broken dashboard".
- A monthly cost and quality review with stakeholders.
- Grow people: pair on hard models, rotate on-call, keep a decision log (architecture.md).
