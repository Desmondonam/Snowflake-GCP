# "Walk me through how you'd build the pipeline on Snowflake" — the 4-minute script

Draw left to right while you talk: **sources → GCS landing → Snowflake RAW → staging/intermediate/marts → consumers**,
with governance, quality and cost around it. Times are targets. Rehearse until it's boring, then make it yours.

---

**Beat 1 · Clarify (0:00–0:15)**
> "Before I draw, three quick questions: how fresh does each consumer need data — daily for finance, minutes for stock?
> Rough volumes — stores, receipts per day, years of history? And who consumes it — BI, data science, the ads team?
> I'll assume nightly POS files from ~400 stores, near-real-time stock for promotions, and all three consumers."

**Beat 2 · Sources (0:15–0:35)**
> "Sources are POS line items plus the till's daily totals, the web shop's orders, the loyalty CRM with PII and consent,
> the ERP for products, stores and stock, Google and Meta ads via API, and web behaviour from GA4 in BigQuery."

**Beat 3 · Ingestion on GCP (0:35–1:15)**
> "Everything lands first in a GCS landing bucket, partitioned by source and date, and those files are immutable — that's
> my replay source. Snowflake reads the bucket through a storage integration, so no keys anywhere. The bucket publishes
> object-created events to Pub/Sub; a notification integration lets Snowpipe auto-ingest each file within about a minute.
> Ads are pulled by a small Cloud Run job, GA4 is exported from BigQuery, database CDC comes through Datastream or a managed
> connector, and if stock needs seconds, POS events go through Snowpipe Streaming."

**Beat 4 · Layers (1:15–1:45)**
> "In Snowflake: RAW is an exact, append-only copy — JSON stays VARIANT — with file name and load time on every row.
> Staging, built with dbt, types, renames and deduplicates one model per source. Intermediate holds the business logic:
> identity resolution between loyalty card and email, SCD2 versions, attribution inputs. Marts are star schemas by domain."

**Beat 5 · The model (1:45–2:30)**
> "The core fact is sales at line-item grain — one row per receipt line or online order line, returns as negative lines,
> transaction id as a degenerate dimension. It joins point-in-time to an SCD2 customer and product dimension, so margin uses
> the cost valid on the day and sales by tier use the tier the customer had then. The key retail insight is one conformed
> customer across store and online — that unlocks customer 360, CLV and attribution. Around it: inventory as a daily
> snapshot, which is semi-additive; ad performance at campaign-ad-day; and attribution with last-click, linear and time-decay."

**Beat 6 · Serving (2:30–3:00)**
> "BI hits the marts on its own multi-cluster warehouse. Data science uses Snowpark and Cortex in place. Marketing gets
> audience tables — like lapsed high-value customers with consent — pushed to ad platforms by reverse ETL. Brand partners get
> secure shares, and a clean room when they want to join their ad exposure to our sales without seeing customers."

**Beat 7 · Operating it (3:00–4:00)**
> "Airflow on Composer runs the nightly flow: wait until every store's file is in, dbt build with tests, then reconcile against
> the tills' own totals — within half a percent per store-day or we don't publish — and alert. Live stock is a dynamic table
> with a five-minute lag. Each workload has its own warehouse with auto-suspend and a resource monitor; the big fact is
> clustered on date and store and built incrementally with a lookback for late files. Security is access roles composed into
> functional roles, PII masked by tag, a row policy by region, key-pair auth for services. Everything is in Terraform and Git,
> and every pull request runs dbt on a zero-copy clone of production."

---

## Follow-up: "What would you change at 100× the volume?" (≤ 45 s)

> "Streaming ingestion for POS instead of nightly files, and bigger, fewer batch files. The sales fact moves to microbatch
> incremental by day, with clustering budgeted. Dashboards read aggregate marts or dynamic tables, not the line-level fact.
> The transform warehouse is sized up only for the heavy models, BI scales out, and cost is attributed per team with
> budgets and alerts. And I'd add cross-region replication with failover for the business-critical marts."

## Delivery tips

- Draw as you speak; label boxes with the real object names (`RETAIL_RAW.POS.SALES_LINES`, `fct_sales_line`).
- Give one number per beat from your capstone ("~6,000 lines a day per 20 stores", "Q1 went from 14 s to 0.8 s").
- Stop at 4 minutes and ask: "Where would you like me to go deeper?"
