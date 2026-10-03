# Snowflake vs BigQuery on GCP: one page

> Interviewers on GCP-hosted Snowflake roles almost always ask: *"Why Snowflake and not BigQuery?"*
> A strong answer is **fair**: say where BigQuery wins, then explain why Snowflake still fits *this* retailer.
> Rewrite this page in your own words after you have used both (G4 + Stages 1–6).

## Side by side

| Dimension | Snowflake | BigQuery |
| --- | --- | --- |
| Architecture | Storage, compute (virtual warehouses) and cloud services separated; you choose warehouse sizes | Fully serverless; storage (Colossus) and compute (Dremel slots) separated; no clusters to size |
| Compute pricing | Credits per second per warehouse (60 s minimum), size doubles each step | On-demand: per TiB scanned. Capacity: slots (Editions) with autoscaling |
| What makes cost predictable | Warehouse size × uptime; auto-suspend; resource monitors | Capacity reservations and slot caps; on-demand can surprise with large scans |
| Workload isolation | Separate warehouses per workload (load / transform / BI / DS); multi-cluster for concurrency | Reservations and assignments per project/folder |
| Data layout | Micro-partitions (automatic) + optional clustering keys | Partitioning (date/int/ingestion time) + clustering (up to 4 columns) |
| Semi-structured | `VARIANT` + `FLATTEN`, schema-on-read | Native `STRUCT`/`ARRAY` + `JSON` type, `UNNEST` |
| Dev/test copies | **Zero-copy clone** of tables/schemas/databases, instant | Table clones and snapshots (table level); no whole-dataset clone |
| Time Travel | Up to 90 days (Enterprise) + 7-day Fail-safe | 2–7 days time travel + 7-day fail-safe |
| Data sharing | Secure Data Sharing across accounts, regions and **clouds**, Marketplace, clean rooms | Analytics Hub (listings), BigQuery data clean rooms; within Google Cloud |
| Governance | RBAC with role hierarchy, masking and row access policies, tags, access history | IAM, policy tags (column-level), row-level security, data masking via Dataplex |
| Streaming ingest | Snowpipe (files) and Snowpipe Streaming (rows) | Storage Write API, native Pub/Sub subscriptions to BigQuery |
| GCP integration | Via storage/notification integrations, external volumes | **Native**: GA4/Ads exports, Pub/Sub, Dataflow, Looker, Vertex AI |
| Multi-cloud | Runs on AWS, Azure and GCP with the same features; cross-cloud replication | GCP only (BigQuery Omni reads S3/Azure in limited regions) |
| Open formats | Iceberg tables (Snowflake-managed or external catalog) | BigLake Iceberg tables |
| ML / AI | Snowpark, Snowflake ML, Cortex AI functions | BigQuery ML, Vertex AI integration, Gemini in BigQuery |

## Where BigQuery honestly wins

- Zero infrastructure: no warehouse sizing, no suspend settings.
- Native Google integrations: GA4, Google Ads and Search Console exports land in BigQuery for free.
- Pub/Sub → BigQuery subscriptions make simple streaming trivially easy.
- For a company that is 100% Google, one bill and one IAM model.

## Why Snowflake can still be the right call for RetailOne

1. **Workload isolation with predictable cost.** Finance close, dbt, BI and data science each get their own warehouse and budget; Monday-morning BI load scales out without slowing dbt.
2. **Zero-copy cloning** makes CI (a full prod clone per pull request) and safe backfills cheap and fast.
3. **Sharing and clean rooms** with suppliers and brands (retail media) work across clouds and accounts; many CPG brands already use Snowflake.
4. **Multi-cloud / no single-cloud lock-in**, and Iceberg keeps the data in an open format on our own GCS bucket that BigQuery can also read.
5. **Governance in one place**: masking, row access, tags and access history enforced whatever tool runs the query.

## The one-sentence answer

> "If the business were purely Google-native with spiky ad-hoc analytics, BigQuery would be a great default.
> For a retailer that needs isolated, budgeted workloads, cheap prod clones for CI, and secure sharing with
> brand partners — while keeping GA4 in BigQuery and reading it via export or Iceberg — Snowflake on GCP is the
> better fit, and the two can coexist."

## My notes after doing G4

- Bytes scanned by query 3 in BigQuery: ______ ; same logic on Snowflake XS took ______ s.
- What surprised me:
