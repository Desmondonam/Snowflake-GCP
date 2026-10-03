# Final capstone — "RetailOne" data platform on Snowflake + GCP

This folder is the system you'll screen-share in interviews. Capstones 1–8 built every piece; this runbook wires them into
one platform, adds Terraform for everything account-level, and proves it with acceptance tests.

| Folder | What | Built in |
| --- | --- | --- |
| [data_generator/](data_generator/) | Fake POS, orders, CRM, ERP, ads, web, reviews; daily "new day" mode with late files, duplicates, schema change | Stage 2 |
| [terraform/](terraform/) | GCS, Pub/Sub, SAs, Cloud Run + Snowflake warehouses, DBs, roles, monitor, integrations, cross-cloud IAM | G5 + final |
| [snowflake/](snowflake/) | `deploy.py`: RAW objects, realtime pipeline, governance, in order | final |
| [dbt_retail/](dbt_retail/) | staging → intermediate → marts, snapshots, tests, contracts, attribution, reconciliation | Stage 4 |
| [airflow/](airflow/) | `retail_daily` DAG (Astro local; Composer-ready) + Cosmos variant | Stage 5 |
| [docs/](docs/) | [architecture.md](docs/architecture.md), [acceptance_tests.md](docs/acceptance_tests.md) | final |

## Deliverables checklist (from the roadmap)

- [ ] `data_generator/`: 90 days + daily mode; late files, duplicates and one schema change on purpose
- [ ] `terraform/`: GCS landing + lakehouse, Pub/Sub, SAs, Snowflake warehouses, databases, roles, integrations, resource monitor
- [ ] Snowpipe auto-ingest for POS, orders, customers, products, ads (and the rest) into `RETAIL_RAW`
- [ ] `dbt_retail/`: staging → intermediate → marts; snapshots; tests; contracts; docs
- [ ] Marts: `fct_sales_line`, `fct_inventory_daily`, `fct_ad_performance`, `fct_attribution` (last-click + linear), `dim_customer` (SCD2, unified), `dim_product`, `dim_store`, `dim_date`, `dim_campaign`
- [ ] Live stock dynamic table (5-minute lag)
- [ ] Airflow DAG: arrival checks → `dbt build` → reconciliation → alert
- [ ] Security: functional/access roles, PII masking, regional row access policy
- [ ] Performance write-up with before/after numbers ([stage_06_performance/results.md](../stage_06_performance/results.md))
- [ ] Dashboard: Streamlit store-manager app (or Looker Studio): sales, margin, ROAS by channel, top customers
- [ ] `docs/architecture.md`: diagram, seven beats, decisions and trade-offs
- [ ] CI: GitHub Actions running dbt on a zero-copy clone per PR

## Runbook

### Path A — you completed Stages 1–8 with SQL (most people)

Everything already exists. Do the **Terraform takeover** once, so the platform is reproducible from code:

1. Read and run [terraform/handover_from_sql.sql](terraform/handover_from_sql.sql) (destructive by design; RAW reloads from GCS).
2. `terraform destroy` in `gcp/terraform` if you applied the GCP capstone there.
3. Apply [terraform/](terraform/README.md), then follow its `next_steps` output:

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery"
.\.venv\Scripts\Activate.ps1; . .\00_setup\load_env.ps1

python capstone_retail_platform/snowflake/deploy.py --phase pre
python capstone_retail_platform/data_generator/generate.py backfill --days 90 --upload   # buckets are new after Terraform
python capstone_retail_platform/snowflake/deploy.py --phase backfill                      # only if files pre-dated the pipes
cd capstone_retail_platform/dbt_retail
dbt deps; dbt seed --target prod
dbt build --target prod --vars "{enable_governance: false}"
cd ../..
python capstone_retail_platform/snowflake/deploy.py --phase post
cd capstone_retail_platform/dbt_retail; dbt build --target prod; cd ../..
```

4. Re-register the pipeline user's key if you changed it (Terraform sets it from `pipeline_public_key`).
5. Start Airflow (`capstone_retail_platform/airflow`, `astro dev start`), redeploy Streamlit (Stage 8 step 5).

### Path B — fresh start straight into the capstone

00_setup → GCP G0 → Terraform apply → the same commands as Path A step 3 → Airflow → Streamlit → CI.

### Daily operation (what "production" looks like here)

```powershell
python capstone_retail_platform/data_generator/generate.py new-day --upload   # the stores close
# Snowpipe loads within minutes; the task + dynamic table refresh live stock
# Airflow retail_daily runs at 04:00 UTC (or trigger it): sensor → dbt build → reconciliation → summary
```

## Acceptance tests

Work through [docs/acceptance_tests.md](docs/acceptance_tests.md). All six must pass.

## Stretch goals

- **Snowpipe Streaming** for POS events (Python SDK or Kafka connector into a new `RAW.POS.SALES_EVENTS`; point the dynamic table at it).
- **Iceberg mart read from BigQuery** (Stage 8 lesson 03) — automate with a daily MERGE task.
- **Cortex sentiment** in the Streamlit app (Stage 8 lesson 04 + `product_review_scores`).
- **Demand forecast**: `SNOWFLAKE.ML.FORECAST` on daily units per store × category, predictions written to `RETAIL_MARTS.OPS.DEMAND_FORECAST`, shown next to live stock.

## Publish it

Push to a public GitHub repo (check `.gitignore` first — no `.env`, keys or tfvars), pin it on your profile, and add a
"Snowflake + GCP: RetailOne data platform" entry to your CV with 3 bullet points and numbers (rows/day, latency, performance gains).
