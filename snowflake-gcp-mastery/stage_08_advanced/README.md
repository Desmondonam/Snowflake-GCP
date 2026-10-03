# Stage 8 — Expert topics (weeks 9–10)

**Goal:** go wide across the features that make a Snowflake lead stand out — sharing and clean rooms (retail media),
Iceberg on GCS read by BigQuery, Cortex AI, Streamlit apps, CI/CD on zero-copy clones, replication — then go deep on the
2–3 that match the job you're targeting.

**Prerequisites:** Capstones 1–7. A second Snowflake trial account (GCP us-central1) for sharing.

| # | File | Topic |
| --- | --- | --- |
| 01 | [01_secure_data_sharing.sql](01_secure_data_sharing.sql) | Multi-tenant secure view + share; consumer side; reader accounts |
| 02 | [02_clean_room_building_blocks.sql](02_clean_room_building_blocks.sql) | Projection + aggregation policies: overlap analysis without exposing rows |
| 03 | [03_iceberg_on_gcs.sql](03_iceberg_on_gcs.sql) → [03b_bigquery_read_iceberg.sql](03b_bigquery_read_iceberg.sql) | Iceberg table in your bucket, read from BigQuery |
| 04 | [04_cortex_ai.sql](04_cortex_ai.sql) | Sentiment, classification, summaries, completion; dbt model for scores |
| 05 | [05_streamlit_app/](05_streamlit_app/) | Streamlit in Snowflake: store manager app |
| 06 | [06_devops_and_replication.sql](06_devops_and_replication.sql) | Blue/green SWAP, Git integration, failover groups |
| CI | [../../.github/workflows/dbt_ci.yml](../../.github/workflows/dbt_ci.yml), [../ci/clone_env.py](../ci/clone_env.py) | PR → clone prod → dbt build modified+ → drop clone |
| — | [architecture_judgement.md](architecture_judgement.md) | Multi-account, cost attribution, tool choice, 100× volume |

---

## 1. Concepts in plain language

- **Secure Data Sharing**: the consumer gets a read-only database that points at *your* storage — no copies, no ETL, always live.
  Only **secure** objects can be shared. Different region/cloud → **listings** with auto-fulfilment. No Snowflake account → **reader account**.
- **Data clean room**: two parties join their customer data on a hashed key, but can only see approved aggregates.
  Snowflake's building blocks are **projection policies** (join on it, never select it) and **aggregation policies** (min group size);
  the Data Clean Rooms app wraps them in templates.
- **Iceberg tables**: open table format (Parquet + metadata) in **your** bucket via an **external volume**. Snowflake-managed
  (Snowflake is the catalog, full DML) or externally managed (another catalog, Snowflake reads). Answer to lock-in concerns.
- **Cortex**: LLM and ML functions in SQL; data stays in Snowflake; billed per token. Plus Search (RAG), Analyst (NL→SQL).
- **Streamlit in Snowflake**: Python apps hosted inside Snowflake, using Snowpark; governed by Snowflake roles. They run with
  the **owner's** privileges — create them with a role scoped to what the audience may see.
- **DevOps**: Terraform for account objects, migrations for schema objects, dbt for models, CI on zero-copy clones,
  blue/green with `SWAP`, Git repositories inside Snowflake.
- **Replication / failover**: replicate databases and account objects to another region/cloud; failover groups + client redirect for DR.

## 2. Step-by-step

1. **Sharing (01)**. In the second trial account run `SELECT CURRENT_ACCOUNT(), CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME();`.
   Put the locator in the mapping table, create the share, add the account, then run the CONSUMER section in the second account.
2. **Clean room (02)**: build the two tables, apply the policies, try the blocked queries (they should fail) and the aggregate one.
3. **Iceberg (03 → 03b)**: external volume, GCP grant, `SYSTEM$VERIFY_EXTERNAL_VOLUME`, table + MERGE, list the files in GCS,
   then BigQuery connection + external table. Compare totals in both engines (screenshot both).
4. **Cortex (04)**: run the exploratory queries with `LIMIT`, then build `product_review_scores` with dbt (`enable_cortex: true`).
5. **Streamlit (05)** — two ways:
   - *Snowsight*: Projects → Streamlit → **+ Streamlit App** → location `RETAIL_MARTS.APPS` (create the schema first:
     `CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.APPS;`), warehouse `BI_WH` → paste `streamlit_app.py` → Run.
   - *CLI*: `cd stage_08_advanced/05_streamlit_app; snow streamlit deploy --replace -c retail_engineer` (after creating the schema).
6. **CI** — push the repo to GitHub, then:
   1. Repo → Settings → Secrets and variables → Actions → add `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` (`SVC_RETAIL_PIPELINE`),
      `SNOWFLAKE_PRIVATE_KEY` (the full content of `svc_retail_pipeline_rsa_key.p8`), `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`.
   2. Create a branch, change a model (e.g. a description or a column in `fct_ad_performance`), open a PR.
   3. Watch the Actions tab: clone → `dbt build --select state:modified+` → drop clone. Screenshot it.
7. **DevOps (06)**: blue/green swap, Git repository stage (needs your public GitHub repo).
8. Read [architecture_judgement.md](architecture_judgement.md) and add your own numbers.

## 3. Capstone 8 — "Platform features"

- [ ] (a) Secure weekly-sales view shared with a second trial account (consumer screenshot)
- [ ] (b) A mart written as Iceberg to GCS and read from BigQuery (both screenshots, same totals)
- [ ] (c) Cortex sentiment on reviews feeding a product quality score
- [ ] (d) Streamlit store-manager app: pick a store → sales, stock, review sentiment
- [ ] (e) GitHub Actions: PR → clone prod → `dbt build --select state:modified+` → drop clone (green run)

## 4. Interview check

<details><summary>How would you share data with a supplier securely?</summary>

Secure Data Sharing of a secure, aggregated view filtered per consumer (CURRENT_ACCOUNT mapping), no PII, live and
zero-copy. Row access policies on base tables allow the share explicitly. Reader account if they lack Snowflake; listing for
other regions/clouds. For customer-level questions, a clean room with projection/aggregation policies, never raw rows.
Monitor access with ACCESS_HISTORY / listing usage.
</details>

<details><summary>Why Iceberg?</summary>

Open format in our own storage, readable by BigQuery/Spark/Trino — avoids lock-in, enables a multi-engine lakehouse and
keeps storage billing with our cloud. With Snowflake as catalog we keep full DML and performance; with an external catalog
other engines can write too. Trade-offs: catalog choice, metadata refresh for readers that pin files, some feature differences.
</details>

<details><summary>How do you promote changes from dev to prod?</summary>

Branch → PR → CI builds only modified models (+ downstream) against a zero-copy clone of prod and runs their tests → review →
merge → the orchestrator runs `dbt build --target prod`. Account objects via Terraform plan/apply in the same PR flow; schema
objects via versioned migrations. Big rebuilds go blue/green with SWAP for instant rollback.
</details>

<details><summary>Snowflake vs BigQuery for this retailer, honestly?</summary>

See [architecture_judgement.md](architecture_judgement.md) and [the G4 one-pager](../gcp/g4_bigquery/snowflake_vs_bigquery.md):
BigQuery wins on Google-native integration and zero ops; Snowflake wins on workload isolation, cloning for CI, governance and
cross-company sharing/clean rooms — which matter for a retailer with brand partners. Iceberg lets both read the same data.
</details>

## 5. My notes
