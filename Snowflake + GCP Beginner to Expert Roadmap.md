# Snowflake + GCP: Beginner to Expert Roadmap

Oct 3, 2026 · @Desmond

## How to use this roadmap

You already know Python, Spark, Kafka, Airflow, dbt and AWS. The gap is Snowflake-specific engineering and GCP as the host cloud, so this plan runs 10 weeks: a short GCP track in parallel with 8 Snowflake stages, ending in one retail capstone you can talk through in any interview.

Every stage follows the same loop: **Concept → Example → Code → Capstone**. Each stage's capstone builds on the last, so by Stage 8 the pieces add up to the final retail platform.

### Accounts (free to start)

- **Snowflake trial:** sign up at signup.snowflake.com, pick **Enterprise edition** and **Google Cloud** as the cloud, region `us-central1` (Iowa). Enterprise unlocks multi-cluster warehouses, masking policies and 90-day Time Travel, which interviews ask about. The trial gives free credits for 30 days; confirm the current amount at signup.
- **GCP free trial:** console.cloud.google.com, new project `retail-dp-lab`. Set a **budget alert at $20** on day one.
- **dbt:** use `dbt-core` + `dbt-snowflake` locally (no dbt Cloud needed).
- **Airflow:** run locally with Docker (Astro CLI or the official docker-compose). Cloud Composer comes in Stage 5 only as a read-through, because it is expensive to leave running.
- **Cost discipline:** every warehouse you create gets `AUTO_SUSPEND = 60` and `AUTO_RESUME = TRUE`. Tear down GCP resources at the end of each session.

### VSCode repo layout

Create one repo, `snowflake-gcp-mastery`, and keep everything there.

```
snowflake-gcp-mastery/
├── 00_setup/            # account setup SQL, roles, warehouses, .env.example
├── gcp/                 # gcloud scripts, Terraform, Cloud Functions
├── stage_01_foundations/
├── stage_02_ingestion/
├── stage_03_modeling/
├── stage_04_dbt_snowpark/
├── stage_05_orchestration/
├── stage_06_performance/
├── stage_07_quality_governance/
├── stage_08_advanced/
├── capstone_retail_platform/
│   ├── data_generator/   # Python fake POS, customers, ads data
│   ├── terraform/
│   ├── dbt_retail/
│   ├── airflow/dags/
│   └── docs/architecture.md
└── interview/            # your spoken answers, diagrams, Q&A notes
```

### VSCode extensions and tools

- **Snowflake** extension (official): run SQL worksheets from VSCode, browse objects.
- **dbt Power User**, **Python**, **Docker**, **HashiCorp Terraform**.
- CLI: `snow` (Snowflake CLI), `gcloud`, `terraform`, `dbt`, `docker`.
- Python: `pip install snowflake-connector-python snowflake-snowpark-python dbt-snowflake faker google-cloud-storage google-cloud-pubsub`

Each stage folder gets its own `README.md` where you write the concept in your own words. That README becomes your interview notes.

## The interview answer: retail pipeline on Snowflake + GCP

The question was: *"Walk me through how you would build the pipeline on Snowflake. They have customer data, POS data and more."* The winning answer moves in one direction, left to right: **sources → land in GCS → load into Snowflake RAW → model in layers with dbt → serve BI, data science and ad activation**, with governance, quality and cost wrapped around it. Learn it as seven beats.

&#91;embedded content: retail data platform · sources → GCP → Snowflake layers → consumers\]

Draw this left to right as you talk: the dashed line is the Pub/Sub event that tells Snowpipe a new file has arrived; MARTS is the layer the business actually uses.

### Beat 1: Clarify before drawing (15 seconds)

Ask two or three questions. It signals seniority.

- How fresh does data need to be? Daily for finance, near-real-time for inventory or promotions?
- Rough volumes? Number of stores, POS transactions per day, history to backfill?
- Who consumes it? BI dashboards, data scientists, the ads team?

### Beat 2: Sources

| Source | Typical system | Shape | Freshness |
| --- | --- | --- | --- |
| POS transactions | Store POS / central POS database | Header + line items, returns, tenders | Nightly files, or streaming events |
| E-commerce orders | Web shop DB (Postgres / Cloud SQL) | Orders, order lines | CDC, minutes |
| Customers / loyalty | CRM, loyalty app | Profiles, PII, consent flags | CDC or daily |
| Products, stores, inventory | ERP | Reference data that changes slowly | Daily |
| Advertising | Google Ads, Meta, DV360 | Campaigns, spend, impressions, clicks | Daily via API |
| Web / app behaviour | GA4 → BigQuery export, or event SDK | Sessions, events, UTM parameters | Hourly / daily |

### Beat 3: Ingestion on GCP

"Everything lands first in a **GCS landing bucket**, partitioned by source and date, so we always have the raw files to replay."

- **Batch files** (POS nightly, ERP, ads exports) → GCS → **Snowpipe auto-ingest**. A Snowflake **storage integration** gives Snowflake a GCP service account; GCS sends object-created events to **Pub/Sub**; a Snowflake **notification integration** listens and loads new files automatically.
- **Database CDC** (orders, customers) → **Datastream** or a managed connector (Fivetran / Airbyte) → GCS or direct to Snowflake.
- **Streaming POS events** (if they need near-real-time) → **Pub/Sub** → Kafka connector / **Snowpipe Streaming** into Snowflake for second-to-minute latency.
- **Ads and API sources** → Python on **Cloud Run** jobs triggered by Airflow, writing JSON to GCS, or a managed connector.
- **GA4 data already in BigQuery** → export to GCS as Parquet on a schedule, or query it as an external/Iceberg table if volumes are large.

### Beat 4: Layers inside Snowflake

| Layer (database) | What lives there | Built by |
| --- | --- | --- |
| `RAW` | Exact copy of source, `VARIANT` for JSON, plus `_loaded_at`, `_file_name`. Append-only, never edited | Snowpipe / COPY INTO |
| `STAGING` | One clean view/table per source table: typed, renamed, deduplicated, PII tagged | dbt `stg_` models |
| `INTERMEDIATE` | Business logic: customer identity resolution (loyalty card ↔ email ↔ device), returns matched to sales, sessionisation | dbt `int_` models, Snowpark Python |
| `MARTS` | Star schemas by domain: Sales, Customer, Marketing | dbt `fct_` / `dim_` models |

### Beat 5: The data model (where they test you hardest)

- `fct_sales_line` — grain: **one row per POS or online line item**. Keys to date, store, product, customer, promotion; measures: quantity, gross, discount, net, cost, margin. Returns as negative lines.
- `fct_ad_performance` — grain: campaign × ad × day: spend, impressions, clicks.
- `fct_marketing_touchpoint` — grain: one row per customer touch (ad click, email open, site visit) with timestamp and channel.
- `fct_attribution` — order × touchpoint with credit weights (last-click, linear, time-decay). Built in Snowpark or SQL window functions.
- Dimensions: `dim_customer` (**SCD Type 2**, history of segment / address / loyalty tier), `dim_product` (SCD2 for price and category moves), `dim_store`, `dim_date`, `dim_campaign`, `dim_channel`.
- One **conformed `dim_customer`** across POS and online is the key retail insight: it's what unlocks customer 360, CLV and attribution.

### Beat 6: Serving

- **BI** (Looker / Tableau / Power BI) on marts, through its own multi-cluster `BI_WH`.
- **Data science**: Snowpark for feature engineering, churn / CLV / demand-forecast models, results written back as tables.
- **Advertising activation**: audience tables (e.g. lapsed high-value customers) pushed to Google Ads / Meta with reverse ETL; **Secure Data Sharing** or a data clean room for brand partners.

### Beat 7: Operating it (what makes you sound like the lead)

- **Orchestration:** Cloud Composer (Airflow) runs ingestion checks → `dbt build` → tests → notifications. In-warehouse near-real-time pieces use **Streams + Tasks** or **Dynamic Tables**.
- **Workload isolation:** `LOAD_WH`, `TRANSFORM_WH`, `BI_WH` (multi-cluster), `DS_WH` (Snowpark-optimized). Each has auto-suspend and a **resource monitor**.
- **Performance:** clustering key on `fct_sales_line(sale_date, store_id)`, incremental dbt models, check Query Profile for spilling and poor pruning.
- **Quality:** dbt tests (unique, not\_null, relationships, accepted values), source freshness, row-count reconciliation against POS totals per store per day.
- **Security / governance:** RBAC role hierarchy, **dynamic masking** on email and phone, **row access policies** by region, object tagging for PII.
- **Delivery:** Terraform for Snowflake + GCP objects, Git + CI running `dbt build` on a **zero-copy clone** of prod.

**Practice:** say this out loud in under 4 minutes while drawing the diagram below on paper. Record yourself. Do it until it feels boring.

## GCP track for data engineers (weeks 1–4, in parallel)

You know AWS, so learn GCP by mapping: most services have a direct twin. Spend about 30–40% of weeks 1–4 here, then GCP is used inside the Snowflake stages.

| GCP service | AWS twin | Why it matters for this role |
| --- | --- | --- |
| Projects, IAM, service accounts | Accounts, IAM roles | Snowflake's storage integration uses a GCP service account |
| Cloud Storage (GCS) | S3 | Landing zone for every source; Snowflake external stages |
| Pub/Sub | SNS + SQS / Kinesis | Snowpipe auto-ingest notifications; streaming POS events |
| Cloud Run / Cloud Functions | ECS Fargate / Lambda | API extractors (ads), event handlers |
| Datastream | DMS | CDC from Cloud SQL / Postgres into GCS |
| Dataflow | Kinesis Analytics / Glue streaming | Streaming transforms when needed (Apache Beam) |
| BigQuery | Redshift / Athena | GA4 lands here; you must explain Snowflake vs BigQuery |
| Cloud Composer | MWAA | Managed Airflow running the pipeline |
| Secret Manager | Secrets Manager | Snowflake keys for Airflow and dbt |
| Cloud Logging / Monitoring | CloudWatch | Pipeline alerts |
| Private Service Connect / VPC | PrivateLink / VPC | Private connectivity to Snowflake (Business Critical edition) |

### G1. IAM, projects, service accounts

- **Concept:** everything lives in a project; identities are users or service accounts; permissions are roles bound at project, bucket or resource level. Least privilege always.
- **Example:** a service account `sa-ingest` that can only write to the landing bucket.
- **Code:**

```bash
gcloud config set project retail-dp-lab
gcloud iam service-accounts create sa-ingest --display-name="Ingestion writer"
gcloud storage buckets create gs://retail-dp-landing --location=us-central1
gcloud storage buckets add-iam-policy-binding gs://retail-dp-landing \
  --member=serviceAccount:sa-ingest@retail-dp-lab.iam.gserviceaccount.com \
  --role=roles/storage.objectCreator
```

### G2. GCS + Pub/Sub events

- **Concept:** a bucket can publish a message to a Pub/Sub topic every time an object is created. Snowpipe on GCP uses exactly this.
- **Code:**

```bash
gcloud pubsub topics create landing-events
gcloud storage buckets notifications create gs://retail-dp-landing \
  --topic=landing-events --event-types=OBJECT_FINALIZE
gcloud pubsub subscriptions create landing-events-sub --topic=landing-events
```

### G3. Cloud Run job extracting an API

- **Concept:** containerised Python that runs on a schedule or on request, scaling to zero.
- **Example:** pull yesterday's ad spend from a mock API and write JSON to `gs://retail-dp-landing/ads/dt=YYYY-MM-DD/`.
- **Code:** `main.py` with `requests` + `google-cloud-storage`, a `Dockerfile`, then `gcloud run jobs deploy ads-extract --source . --region us-central1`.

### G4. BigQuery, enough to compare

- Load GA4 sample data (public dataset `bigquery-public-data.ga4_obfuscated_sample_ecommerce`), query it, export a table to GCS as Parquet with `EXPORT DATA`.
- Write a one-page comparison: storage/compute separation, pricing (slots vs credits), clustering vs partitioning, concurrency, data sharing. Interviewers on GCP Snowflake roles almost always ask "why Snowflake and not BigQuery?"

### G5. Terraform for GCP + Snowflake

- Providers: `hashicorp/google` and `snowflakedb/snowflake`. Manage buckets, topics, service accounts, warehouses, databases and roles from one repo.

### GCP capstone

**"Landing zone in code."** Terraform creates the landing bucket (folders per source), the Pub/Sub topic + bucket notification, `sa-ingest`, and a Cloud Run job that writes fake ads data daily. Output: `gcp/terraform/` you can `apply` and `destroy` in minutes. This becomes the left side of the final capstone.

## Snowflake track: 8 stages, beginner to expert

Each stage ends with a capstone that adds one layer to the retail platform, and an **interview check**: questions you must answer without notes before moving on.

### Stage 1 — Foundations (week 1)

**Concept**

- **Three-layer architecture:** central storage (compressed columnar **micro-partitions** of 50–500 MB uncompressed, in cloud object storage), compute (**virtual warehouses**, independent clusters), cloud services (metadata, optimizer, security, transactions). Storage and compute scale separately; that's the core selling point.
- **Object hierarchy:** organization → account → database → schema → tables, views, stages, file formats, pipes, streams, tasks, functions.
- **Warehouses:** sizes XS → 6XL, each size doubles credits per hour and compute. Billed per second after the first 60 seconds.
- **Table types:** permanent (Time Travel + 7-day Fail-safe), transient (no Fail-safe; cheaper for staging), temporary (session only).
- **Time Travel** (query or restore past data, up to 90 days on Enterprise), **Fail-safe** (7 days, Snowflake-only recovery), **zero-copy cloning** (instant copy that shares micro-partitions).
- **Three caches:** result cache (24h, same query + unchanged data = free), warehouse local disk cache (lost on suspend), metadata cache (`COUNT(*)`, `MIN/MAX` answered without compute).
- **System roles:** `ACCOUNTADMIN` > `SECURITYADMIN` > `USERADMIN`; `SYSADMIN` owns objects. Never build with `ACCOUNTADMIN`.
- **Semi-structured:** `VARIANT`, `OBJECT`, `ARRAY`; dot/bracket notation; `LATERAL FLATTEN`.

**Example:** a retailer clones production to test a new margin calculation. The clone costs nothing until rows change; if the change breaks something, Time Travel restores the table as it was 10 minutes ago.

**Code** (`stage_01_foundations/setup.sql`)

```sql
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS LAB_WH WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
CREATE DATABASE IF NOT EXISTS RETAIL_RAW;
CREATE DATABASE IF NOT EXISTS RETAIL_ANALYTICS;
CREATE SCHEMA IF NOT EXISTS RETAIL_ANALYTICS.SANDBOX;

-- Work with built-in sample data
USE WAREHOUSE LAB_WH;
CREATE TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- Time Travel
UPDATE RETAIL_ANALYTICS.SANDBOX.ORDERS SET O_TOTALPRICE = 0;   -- oops
SELECT COUNT(*) FROM RETAIL_ANALYTICS.SANDBOX.ORDERS AT(OFFSET => -60*2) WHERE O_TOTALPRICE > 0;
CREATE OR REPLACE TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS_FIXED
  CLONE RETAIL_ANALYTICS.SANDBOX.ORDERS AT(OFFSET => -60*2);

-- Semi-structured
CREATE TABLE RETAIL_ANALYTICS.SANDBOX.EVENTS (v VARIANT);
INSERT INTO RETAIL_ANALYTICS.SANDBOX.EVENTS SELECT PARSE_JSON(
  '{"order_id":1,"customer":{"id":42},"items":[{"sku":"A1","qty":2},{"sku":"B7","qty":1}]}');
SELECT v:order_id::INT, v:customer.id::INT, i.value:sku::STRING, i.value:qty::INT
FROM RETAIL_ANALYTICS.SANDBOX.EVENTS, LATERAL FLATTEN(input => v:items) i;
```

**Capstone 1 — "Retail lab account."** Script (in one rerunnable file): custom roles `RETAIL_ADMIN`, `RETAIL_ENGINEER`, `RETAIL_ANALYST` granted up to `SYSADMIN`; warehouses `LOAD_WH`, `TRANSFORM_WH`, `BI_WH`; databases `RETAIL_RAW`, `RETAIL_STAGING`, `RETAIL_MARTS`; a resource monitor capping monthly credits. Prove Time Travel, UNDROP and cloning work.

**Interview check:** Why is Snowflake's storage/compute separation useful for a retailer at Black Friday? What do you lose by using transient tables? Which cache answers a repeated dashboard query for free?

### Stage 2 — Ingestion from GCP (week 2)

**Concept**

- **Stages:** internal (user `@~`, table `@%t`, named `@s`) and **external** (a pointer to `gcs://bucket/path`).
- **Storage integration:** the secure way to reach GCS. Snowflake creates a GCP service account; you grant it access on the bucket. No keys in SQL.
- **File formats:** CSV, JSON, Parquet, Avro, ORC. Parquet is preferred for large loads.
- **COPY INTO:** bulk load; tracks loaded files for 64 days so the same file is not loaded twice. Key options: `ON_ERROR`, `VALIDATION_MODE`, `PATTERN`, `MATCH_BY_COLUMN_NAME`, `PURGE`. File sizing sweet spot: about 100–250 MB compressed.
- **Metadata columns:** `METADATA$FILENAME`, `METADATA$FILE_ROW_NUMBER`, `METADATA$FILE_LAST_MODIFIED` for lineage.
- **Snowpipe:** serverless, event-driven COPY. On GCP it uses a **notification integration** on a Pub/Sub subscription.
- **Snowpipe Streaming:** row-level, low-latency ingest via SDK or the Kafka connector, no files.
- **Schema detection:** `INFER_SCHEMA` + `CREATE TABLE … USING TEMPLATE`. Schema evolution with `ENABLE_SCHEMA_EVOLUTION`.
- **External tables:** query files in GCS without loading.
- **Monitoring:** `COPY_HISTORY`, `SYSTEM$PIPE_STATUS`, `VALIDATE`.

**Example:** 400 stores each upload a nightly POS CSV to `gs://retail-dp-landing/pos/dt=2026-10-03/store_017.csv`. Snowpipe loads each file within about a minute of arrival, stamping file name and load time on every row.

**Code** (`stage_02_ingestion/gcs_snowpipe.sql`)

```sql
USE ROLE ACCOUNTADMIN;  -- integrations need it (or CREATE INTEGRATION privilege)
CREATE STORAGE INTEGRATION GCS_INT
  TYPE = EXTERNAL_STAGE STORAGE_PROVIDER = 'GCS' ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://retail-dp-landing/');
DESC STORAGE INTEGRATION GCS_INT;  -- copy STORAGE_GCP_SERVICE_ACCOUNT
-- In GCP: grant that service account Storage Object Viewer on the bucket

CREATE NOTIFICATION INTEGRATION GCS_NOTIF
  TYPE = QUEUE NOTIFICATION_PROVIDER = GCP_PUBSUB ENABLED = TRUE
  GCP_PUBSUB_SUBSCRIPTION_NAME = 'projects/retail-dp-lab/subscriptions/landing-events-sub';
DESC NOTIFICATION INTEGRATION GCS_NOTIF;  -- copy GCP_PUBSUB_SERVICE_ACCOUNT
-- In GCP: grant it Pub/Sub Subscriber on the subscription + Monitoring Viewer on the project

GRANT USAGE ON INTEGRATION GCS_INT TO ROLE RETAIL_ENGINEER;
USE ROLE RETAIL_ENGINEER;
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.POS;
CREATE FILE FORMAT RETAIL_RAW.POS.CSV_FMT TYPE = CSV SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"' NULL_IF = ('', 'NULL');
CREATE STAGE RETAIL_RAW.POS.LANDING
  URL = 'gcs://retail-dp-landing/pos/' STORAGE_INTEGRATION = GCS_INT
  FILE_FORMAT = RETAIL_RAW.POS.CSV_FMT;
LIST @RETAIL_RAW.POS.LANDING;

CREATE TABLE RETAIL_RAW.POS.SALES_LINES (
  transaction_id STRING, line_no INT, store_id STRING, sku STRING,
  qty NUMBER(10,2), unit_price NUMBER(12,2), discount NUMBER(12,2),
  loyalty_id STRING, sold_at TIMESTAMP_NTZ,
  _file_name STRING, _loaded_at TIMESTAMP_LTZ);

CREATE PIPE RETAIL_RAW.POS.SALES_PIPE AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' AS
COPY INTO RETAIL_RAW.POS.SALES_LINES
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.POS.LANDING)
ON_ERROR = 'SKIP_FILE';

SELECT SYSTEM$PIPE_STATUS('RETAIL_RAW.POS.SALES_PIPE');
SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'RETAIL_RAW.POS.SALES_LINES', START_TIME => DATEADD(hour, -24, CURRENT_TIMESTAMP())));
```

**Capstone 2 — "Data lands itself."** Write `capstone_retail_platform/data_generator/generate.py` with Faker: 20 stores, 500 SKUs, 5,000 customers (JSON), daily POS lines (CSV), e-commerce orders (Parquet), ad spend (JSON). Upload to GCS by `source/dt=` folders. Snowpipe loads all of it into `RETAIL_RAW` with lineage columns. Inject one bad file and show `SKIP_FILE` + `COPY_HISTORY` catching it.

**Interview check:** COPY INTO vs Snowpipe vs Snowpipe Streaming, when each? How does Snowflake avoid loading a file twice? How would you handle a source that adds a new column?

### Stage 3 — Data modeling for retail (week 3)

**Concept**

- **Kimball dimensional modeling:** pick the business process → declare the **grain** → identify dimensions → identify facts. Grain first, always.
- **Fact table types:** transaction (each sale line), periodic snapshot (inventory on hand per store per day), accumulating snapshot (an online order moving through placed → picked → shipped → delivered).
- **Measures:** additive (revenue), semi-additive (inventory balance: sum across stores, not across days), non-additive (margin %: store the parts, compute the ratio).
- **Dimensions:** surrogate keys (hash keys work well in Snowflake: `MD5` or `HASH` of natural key + valid\_from), conformed dimensions shared across facts, role-playing dates (order date, ship date), junk dimensions for flags, degenerate dimension (transaction\_id on the fact).
- **SCD types:** Type 1 overwrite; **Type 2** new row with `valid_from`, `valid_to`, `is_current`; Type 3 previous-value column.
- **Bus matrix:** rows = business processes, columns = conformed dimensions. A one-page plan of the warehouse.
- **Alternatives you should be able to discuss:** Data Vault 2.0 (hubs, links, satellites; good for many changing sources and auditability), One Big Table (wide, denormalised for BI tools), medallion naming (bronze/silver/gold ≈ raw/staging/marts).

**Example (retail bus matrix)**

| Business process | Date | Store | Product | Customer | Promotion | Campaign | Channel |
| --- | --- | --- | --- | --- | --- | --- | --- |
| POS + online sales | ✓ | ✓ | ✓ | ✓ | ✓ |  | ✓ |
| Returns | ✓ | ✓ | ✓ | ✓ |  |  | ✓ |
| Inventory snapshot | ✓ | ✓ | ✓ |  |  |  |  |
| Ad performance | ✓ |  |  |  |  | ✓ | ✓ |
| Marketing touchpoints | ✓ |  |  | ✓ |  | ✓ | ✓ |

**Code** (`stage_03_modeling/scd2_merge.sql`) — the SCD2 pattern you must be able to write by hand:

```sql
-- Step 1: close rows whose tracked attributes changed
MERGE INTO RETAIL_MARTS.CORE.DIM_CUSTOMER d
USING RETAIL_STAGING.CRM.STG_CUSTOMERS s
  ON d.customer_id = s.customer_id AND d.is_current
WHEN MATCHED AND (d.segment <> s.segment OR d.loyalty_tier <> s.loyalty_tier OR d.city <> s.city) THEN
  UPDATE SET d.valid_to = CURRENT_TIMESTAMP(), d.is_current = FALSE;

-- Step 2: insert new versions + brand-new customers
INSERT INTO RETAIL_MARTS.CORE.DIM_CUSTOMER
  (customer_sk, customer_id, segment, loyalty_tier, city, valid_from, valid_to, is_current)
SELECT MD5(s.customer_id || '|' || CURRENT_TIMESTAMP()::STRING), s.customer_id, s.segment,
       s.loyalty_tier, s.city, CURRENT_TIMESTAMP(), '9999-12-31'::TIMESTAMP_NTZ, TRUE
FROM RETAIL_STAGING.CRM.STG_CUSTOMERS s
LEFT JOIN RETAIL_MARTS.CORE.DIM_CUSTOMER d
  ON d.customer_id = s.customer_id AND d.is_current
WHERE d.customer_id IS NULL;
```

Fact join pattern (point-in-time): join sales to the customer version that was valid at `sold_at BETWEEN valid_from AND valid_to`.

**Capstone 3 — "Retail star schema."** In `stage_03_modeling/`: the bus matrix, an ERD (draw.io or dbdiagram.io), DDL for `fct_sales_line`, `fct_inventory_daily`, `fct_ad_performance`, `dim_customer` (SCD2), `dim_product` (SCD2), `dim_store`, `dim_date`, `dim_campaign`. Load from your RAW tables with SQL only. Answer in the README: what is the grain of each fact and why?

**Interview check:** Grain of a POS fact? How do you model returns? Inventory: why is it semi-additive? When would you choose Data Vault over Kimball? How do you link an in-store loyalty customer to an online customer?

### Stage 4 — Transformation with dbt + Snowpark (weeks 4–5)

**Concept: dbt on Snowflake**

- Project layout: `models/staging` (1:1 with sources, views), `models/intermediate`, `models/marts` (tables / incremental). `sources.yml` with **freshness** checks.
- **Materializations:** view, table, **incremental** (`merge`, `delete+insert`, `append`, `microbatch`), ephemeral, **snapshot** (SCD2 for you), and `dynamic_table` on Snowflake.
- **Snowflake configs in dbt:** `cluster_by`, `transient`, `snowflake_warehouse` (per-model warehouse), `copy_grants`, `query_tag`, `incremental_predicates`.
- **Tests:** generic (`unique`, `not_null`, `relationships`, `accepted_values`), singular SQL tests, packages `dbt_utils` and `dbt_expectations`, unit tests. **Contracts** on marts to lock column types.
- **Macros** + Jinja for reuse; `dbt docs generate` for lineage; `dbt build --select state:modified+` for slim CI.

**Concept: Snowpark**

- Python DataFrame API that compiles to SQL and runs **inside Snowflake**; lazy until `.collect()` / `.save_as_table()`.
- UDFs, vectorised UDFs (pandas batches), UDTFs (return tables), **stored procedures** in Python; third-party packages from the Anaconda channel.
- **Snowpark-optimized warehouses** for memory-heavy work (ML training).
- dbt **Python models** run as Snowpark under the hood: good for attribution, identity resolution, ML features.

**Example:** dbt builds `fct_sales_line` incrementally every hour (only new transactions); a dbt snapshot tracks customer tier changes; a Snowpark Python model computes linear attribution because the logic is easier in Python.

**Code: incremental fact** (`models/marts/sales/fct_sales_line.sql`)

```sql
{{ config(
    materialized='incremental', unique_key=['transaction_id','line_no'],
    incremental_strategy='merge', cluster_by=['sale_date','store_id'],
    snowflake_warehouse='TRANSFORM_WH') }}

with lines as (
    select * from {{ ref('stg_pos__sales_lines') }}
    {% if is_incremental() %}
      where _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01') from {{ this }})
    {% endif %}
)
select
    l.transaction_id, l.line_no,
    l.sold_at::date                       as sale_date,
    l.store_id,
    p.product_sk,
    c.customer_sk,
    l.qty,
    l.qty * l.unit_price                  as gross_amount,
    l.discount,
    l.qty * l.unit_price - l.discount     as net_amount,
    l._loaded_at
from lines l
left join {{ ref('dim_product') }} p
  on p.sku = l.sku and l.sold_at between p.valid_from and p.valid_to
left join {{ ref('dim_customer') }} c
  on c.loyalty_id = l.loyalty_id and l.sold_at between c.valid_from and c.valid_to
```

**Code: snapshot** (`snapshots/customers_snapshot.sql`)

```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='snapshots', unique_key='customer_id',
          strategy='check', check_cols=['segment','loyalty_tier','city']) }}
select * from {{ source('crm', 'customers') }}
{% endsnapshot %}
```

**Code: Snowpark Python model** (`models/marts/marketing/fct_attribution_linear.py`)

```python
import snowflake.snowpark.functions as F
from snowflake.snowpark import Window

def model(dbt, session):
    dbt.config(materialized="table", snowflake_warehouse="TRANSFORM_WH")
    touches = dbt.ref("int_touchpoints_before_order")  # order_id, customer_id, channel, touched_at, order_net
    w = Window.partition_by("order_id")
    return (touches
        .with_column("n_touches", F.count("*").over(w))
        .with_column("credit", F.lit(1) / F.col("n_touches"))
        .with_column("attributed_revenue", F.col("credit") * F.col("order_net")))
```

**Capstone 4 — "dbt\_retail."** Full dbt project on your RAW data: sources with freshness, `stg_` for every source, `int_customer_identity` (loyalty\_id ↔ email match), marts from Stage 3 as dbt models, a snapshot for customers and products, tests on every primary key and foreign key, last-click + linear attribution (one SQL, one Python), and `dbt docs` lineage screenshot in the README.

**Interview check:** Incremental strategies and when `merge` gets expensive? How do you handle late-arriving POS files in an incremental model? dbt snapshot vs hand-written SCD2? When Snowpark instead of SQL?

### Stage 5 — Orchestration, CDC and near-real-time (week 6)

**Concept**

- **Streams:** change tracking on a table (offset-based). Standard (insert/update/delete), append-only (cheap, insert-only), insert-only for external tables. Metadata columns `METADATA$ACTION`, `METADATA$ISUPDATE`. A stream is consumed (advances) when used in a committed DML.
- **Tasks:** scheduled SQL or procedure calls; CRON or interval; chained into a **DAG** with `AFTER`; **serverless** (Snowflake-managed compute) or on a warehouse; `WHEN SYSTEM$STREAM_HAS_DATA(...)` skips empty runs at no warehouse cost.
- **Dynamic Tables:** declare the result query and a `TARGET_LAG`; Snowflake refreshes incrementally. Replaces many stream+task pipelines with one statement.
- **When to orchestrate where:** Airflow / Cloud Composer owns cross-system flow (GCS checks, APIs, dbt runs, alerts). Snowflake Tasks / Dynamic Tables own in-warehouse, low-latency steps.
- **Airflow + Snowflake:** `SnowflakeSqlApiOperator` / `SQLExecuteQueryOperator` with a Snowflake connection, **Astronomer Cosmos** to render each dbt model as an Airflow task, retries, SLAs, sensors.

**Example:** the merchandising team wants inventory per store refreshed every 5 minutes for flash sales. POS events land via Snowpipe Streaming; a Dynamic Table with a 5-minute lag recomputes stock positions. The nightly finance close stays in Airflow + dbt.

**Code: stream + task** (`stage_05_orchestration/stream_task.sql`)

```sql
CREATE STREAM RETAIL_RAW.POS.SALES_LINES_STRM ON TABLE RETAIL_RAW.POS.SALES_LINES APPEND_ONLY = TRUE;

CREATE TASK RETAIL_STAGING.POS.T_LOAD_SALES
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE = '5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RETAIL_RAW.POS.SALES_LINES_STRM')
AS
MERGE INTO RETAIL_STAGING.POS.SALES_LINES_CLEAN t
USING (SELECT * FROM RETAIL_RAW.POS.SALES_LINES_STRM
       QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id, line_no ORDER BY _loaded_at DESC) = 1) s
  ON t.transaction_id = s.transaction_id AND t.line_no = s.line_no
WHEN MATCHED THEN UPDATE SET t.qty = s.qty, t.unit_price = s.unit_price, t.discount = s.discount
WHEN NOT MATCHED THEN INSERT (transaction_id, line_no, store_id, sku, qty, unit_price, discount, sold_at)
  VALUES (s.transaction_id, s.line_no, s.store_id, s.sku, s.qty, s.unit_price, s.discount, s.sold_at);

ALTER TASK RETAIL_STAGING.POS.T_LOAD_SALES RESUME;  -- tasks start suspended
```

**Code: dynamic table**

```sql
CREATE OR REPLACE DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE
  TARGET_LAG = '5 minutes' WAREHOUSE = TRANSFORM_WH
AS
SELECT i.store_id, i.sku, i.opening_qty - COALESCE(SUM(s.qty), 0) AS on_hand
FROM RETAIL_STAGING.ERP.INVENTORY_OPENING i
LEFT JOIN RETAIL_STAGING.POS.SALES_LINES_CLEAN s
  ON s.store_id = i.store_id AND s.sku = i.sku AND s.sold_at::date = CURRENT_DATE()
GROUP BY i.store_id, i.sku, i.opening_qty;
```

**Code: Airflow DAG** (`capstone_retail_platform/airflow/dags/retail_daily.py`)

```python
from datetime import datetime
from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.operators.bash import BashOperator

with DAG("retail_daily", start_date=datetime(2026, 10, 1), schedule="0 4 * * *",
         catchup=False, default_args={"retries": 2}) as dag:
    check_loads = SQLExecuteQueryOperator(
        task_id="check_pos_loaded", conn_id="snowflake_default",
        sql="""SELECT IFF(COUNT(DISTINCT store_id) >= 20, 1, 1/0)
               FROM RETAIL_RAW.POS.SALES_LINES WHERE sold_at::date = '{{ ds }}'""")
    dbt_build = BashOperator(task_id="dbt_build",
        bash_command="cd /opt/dbt_retail && dbt build --target prod")
    check_loads >> dbt_build
```

**Capstone 5 — "Two speeds."** Near-real-time path: stream + task (or Dynamic Table) for store stock. Daily path: Airflow DAG in local Docker that checks every store's file arrived, runs `dbt build`, runs reconciliation, and posts a Slack or email message. Write in the README when you chose Tasks vs Dynamic Tables vs Airflow and why.

**Interview check:** How does a stream know what changed? What happens if two tasks read the same stream? Dynamic Table vs materialized view vs stream+task? How do you backfill a month of POS data safely?

### Stage 6 — Performance tuning and cost (week 7)

**Concept**

- **Query Profile** is your main tool. Read: most expensive operator, partitions scanned vs total (pruning), bytes spilled to local/remote storage, exploding joins (output rows ≫ input rows).
- **Pruning:** Snowflake keeps min/max per column per micro-partition. Filters on well-clustered columns skip partitions. Functions on the filter column (`TO_CHAR(sale_date)`) can block pruning.
- **Clustering keys:** for very large tables (multi-TB) queried by the same columns. Check with `SYSTEM$CLUSTERING_INFORMATION`. Automatic Clustering costs credits, so only cluster when queries benefit.
- **Warehouse sizing:** **scale up** (bigger size) for one heavy query or spilling; **scale out** (multi-cluster, Standard or Economy policy) for many concurrent users, e.g. Monday-morning BI load.
- **Accelerators:** Query Acceleration Service (outlier scan-heavy queries), Search Optimization Service (selective point lookups like one `loyalty_id`), materialized views (repeated aggregates on one table), result cache.
- **Cost control:** auto-suspend 60s, separate warehouses per workload, resource monitors, `QUERY_TAG` per tool, budgets, and `SNOWFLAKE.ACCOUNT_USAGE` views (`QUERY_HISTORY`, `WAREHOUSE_METERING_HISTORY`, `TABLE_STORAGE_METRICS`).
- **SQL anti-patterns:** `SELECT *` on wide tables, `ORDER BY` without `LIMIT` on huge sets, `UNION` where `UNION ALL` works, joins on mismatched types, row-by-row procedures instead of set-based SQL.

**Example:** the "weekly sales by store" dashboard takes 90 seconds. Query Profile shows 98% of partitions scanned and remote spilling. Fix: cluster `fct_sales_line` on `(sale_date, store_id)`, filter on `sale_date` directly, move the dashboard to `BI_WH` size M. Result: 6 seconds and fewer credits.

**Code** (`stage_06_performance/diagnostics.sql`)

```sql
-- Top 10 most expensive queries last 7 days
SELECT query_id, warehouse_name, total_elapsed_time/1000 AS secs,
       bytes_spilled_to_local_storage, bytes_spilled_to_remote_storage,
       partitions_scanned, partitions_total, LEFT(query_text, 120) AS q
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC LIMIT 10;

-- Credits by warehouse
SELECT warehouse_name, SUM(credits_used) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time > DATEADD(month, -1, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;

-- Clustering health
SELECT SYSTEM$CLUSTERING_INFORMATION('RETAIL_MARTS.SALES.FCT_SALES_LINE', '(sale_date, store_id)');
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE CLUSTER BY (sale_date, store_id);

-- Concurrency for BI
ALTER WAREHOUSE BI_WH SET MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD';

-- Guardrail
CREATE RESOURCE MONITOR RM_MONTHLY WITH CREDIT_QUOTA = 50
  TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE TRANSFORM_WH SET RESOURCE_MONITOR = RM_MONTHLY;
```

**Capstone 6 — "Make it fast and cheap."** Generate about 200M sales lines (Snowflake `GENERATOR` function, so nothing to upload). Write 5 typical retail queries. Record time, partitions scanned and credits before and after: clustering, rewriting filters, warehouse resizing, a materialized view. Put the results table in the README; this is a story you will tell in interviews.

**Interview check:** A query got slow overnight, walk me through debugging it. Scale up vs scale out? When is a clustering key a bad idea? How would you cut the Snowflake bill by 30%?

### Stage 7 — Data quality, security and governance (week 8)

**Concept**

- **RBAC design:** two role layers. **Access roles** hold privileges on objects (`AR_MARTS_SALES_READ`); **functional roles** map to people (`FR_ANALYST`, `FR_DATA_SCIENTIST`, `FR_MARKETING`) and are granted access roles. Use **future grants** and **managed access schemas** so new tables are covered automatically.
- **Authentication:** SSO / SAML, OAuth for BI tools, **key-pair auth** for service users (Airflow, dbt), MFA for humans, network policies to restrict IPs.
- **Column security:** **dynamic data masking** policies (email visible to marketing, masked for analysts); **tag-based masking** (tag a column `PII=email`, the policy follows the tag).
- **Row security:** **row access policies** (a regional manager only sees their region's stores) driven by a mapping table.
- **Governance views:** `ACCESS_HISTORY` (who read which column), `OBJECT_DEPENDENCIES`, tags, lineage in Snowsight. GDPR-style delete requests: know where PII lives.
- **Data quality:** dbt tests + source freshness, Snowflake **Data Metric Functions** (null count, duplicate count, freshness scheduled on tables), reconciliation (POS totals vs warehouse totals per store-day), anomaly checks on row counts, **data contracts** at the staging boundary.

**Example:** marketing needs customer emails for a campaign audience; analysts must never see them; the Kenya regional manager sees only Kenyan stores. Masking policy on `email`, row access policy on `store_region`, both enforced whichever tool runs the query.

**Code** (`stage_07_quality_governance/policies.sql`)

```sql
CREATE MASKING POLICY GOV.POLICIES.MASK_EMAIL AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('FR_MARKETING', 'RETAIL_ADMIN') THEN val
       ELSE REGEXP_REPLACE(val, '.+@', '*****@') END;
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN email
  SET MASKING POLICY GOV.POLICIES.MASK_EMAIL;

CREATE TABLE GOV.POLICIES.ROLE_REGION_MAP (role_name STRING, region STRING);
CREATE ROW ACCESS POLICY GOV.POLICIES.RAP_REGION AS (region STRING) RETURNS BOOLEAN ->
  CURRENT_ROLE() = 'RETAIL_ADMIN'
  OR EXISTS (SELECT 1 FROM GOV.POLICIES.ROLE_REGION_MAP m
             WHERE m.role_name = CURRENT_ROLE() AND m.region = region);
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE ADD ROW ACCESS POLICY GOV.POLICIES.RAP_REGION ON (store_region);

-- Future grants: analysts can read every new mart table automatically
GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_MARTS.SALES TO ROLE AR_MARTS_SALES_READ;
GRANT ROLE AR_MARTS_SALES_READ TO ROLE FR_ANALYST;
```

```yaml
# dbt: models/marts/sales/_sales.yml
models:
  - name: fct_sales_line
    config: {contract: {enforced: true}}
    columns:
      - name: transaction_id
        data_type: varchar
        tests: [not_null]
      - name: net_amount
        data_type: number(14,2)
        tests:
          - dbt_expectations.expect_column_values_to_be_between: {min_value: -100000, max_value: 100000}
      - name: customer_sk
        data_type: varchar
        tests:
          - relationships: {to: ref('dim_customer'), field: customer_sk, config: {severity: warn}}
```

**Capstone 7 — "Lock it down."** Implement the access-role / functional-role design for analyst, data scientist, marketing and engineer. Mask email and phone, add the region row policy, tag all PII columns, add DMFs on the two biggest tables, and a reconciliation model that fails `dbt build` if any store-day differs from source by more than 0.5%. Log in as each role and screenshot what they see.

**Interview check:** Design RBAC for 200 users across 5 teams. Masking vs row access vs secure views? How do you prove to an auditor who saw customer PII last month? What does a data contract protect against?

### Stage 8 — Expert topics (weeks 9–10)

**Concept** (go wide, then deep on 2–3 that match the job)

- **Secure Data Sharing:** share live tables with another account without copying; reader accounts for partners without Snowflake; **Marketplace** for third-party data (weather, demographics for retail); **data clean rooms** for joining retailer and brand data without exposing customers — directly relevant to retail media and advertising.
- **Apache Iceberg tables:** Snowflake-managed Iceberg stored in your own GCS bucket via an **external volume**; open format that BigQuery, Spark and others can also read. Strong answer to "we don't want lock-in."
- **Replication and failover:** database / account replication across regions and clouds, failover groups, client redirect. Business continuity story.
- **Snowflake AI:** Cortex functions (`SNOWFLAKE.CORTEX.SENTIMENT`, `SUMMARIZE`, `COMPLETE`, `CLASSIFY_TEXT`), Cortex Search, Cortex Analyst (natural-language to SQL on a semantic model); Snowflake ML (feature store, model registry); **Streamlit in Snowflake** for internal apps; **Snowpark Container Services** for custom containers. Use your LLM background here; it differentiates you.
- **DevOps:** Snowflake CLI (`snow`), Terraform provider, schema change tools (schemachange), Git integration in Snowflake, GitHub Actions running `dbt build` on a **zero-copy clone** of prod per pull request, blue/green deploys with `ALTER … SWAP WITH`.
- **Architecture judgement:** multi-account strategy (dev / prod accounts in an organization), cost attribution by team (tags + query tags), choosing ELT tools (Fivetran vs Airbyte vs custom), Snowflake vs BigQuery vs Databricks trade-offs.

**Example:** a beverage brand selling through the retailer wants to measure its in-store promotion. The retailer shares an aggregated sales mart through a clean room; the brand joins its ad exposure data; neither sees the other's customer rows. That's a revenue product, and the kind of initiative this role "takes the lead" on.

**Code** (`stage_08_advanced/advanced.sql`)

```sql
-- Share a mart with a partner account
CREATE SHARE BRAND_PARTNER_SHARE;
GRANT USAGE ON DATABASE RETAIL_MARTS TO SHARE BRAND_PARTNER_SHARE;
GRANT USAGE ON SCHEMA RETAIL_MARTS.SHARED TO SHARE BRAND_PARTNER_SHARE;
GRANT SELECT ON VIEW RETAIL_MARTS.SHARED.V_BRAND_WEEKLY_SALES TO SHARE BRAND_PARTNER_SHARE;  -- must be a secure view
ALTER SHARE BRAND_PARTNER_SHARE ADD ACCOUNTS = <org_name>.<partner_account>;

-- Iceberg table on your GCS bucket
CREATE EXTERNAL VOLUME GCS_ICEBERG_VOL STORAGE_LOCATIONS = ((
  NAME = 'gcs-us' STORAGE_PROVIDER = 'GCS'
  STORAGE_BASE_URL = 'gcs://retail-dp-lakehouse/iceberg/'));
CREATE ICEBERG TABLE RETAIL_MARTS.LAKE.FCT_SALES_DAILY
  CATALOG = 'SNOWFLAKE' EXTERNAL_VOLUME = 'GCS_ICEBERG_VOL' BASE_LOCATION = 'fct_sales_daily'
AS SELECT sale_date, store_id, SUM(net_amount) AS net_sales
   FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1, 2;

-- Cortex on product reviews
SELECT review_id, sku,
       SNOWFLAKE.CORTEX.SENTIMENT(review_text) AS sentiment,
       SNOWFLAKE.CORTEX.SUMMARIZE(review_text) AS summary
FROM RETAIL_STAGING.ECOM.PRODUCT_REVIEWS LIMIT 100;
```

Check Cortex function and model availability for your region in the docs before relying on it; it varies by region and changes often.

**Capstone 8 — "Platform features."** (a) Share a secure weekly-sales view with a second trial account. (b) Write one mart as an Iceberg table to GCS and read the files from BigQuery as a BigLake / external table. (c) Cortex sentiment on fake product reviews feeding a `dim_product` quality score. (d) A Streamlit in Snowflake app: store manager picks a store, sees sales, stock and review sentiment. (e) GitHub Actions: on pull request, clone prod → `dbt build --select state:modified+` → drop clone.

**Interview check:** How would you share data with a supplier securely? Why Iceberg? How do you promote changes from dev to prod in Snowflake? Snowflake vs BigQuery for this retailer, honestly?

## Final capstone: "RetailOne" data platform on Snowflake + GCP

The final capstone stitches capstones 1–8 into one public GitHub repo you can screen-share in an interview. It is the exact system described in the interview answer above, so you will be describing something you built, not something you read.

**Scenario:** RetailOne has 20 stores in Kenya and Qatar, an online shop, a loyalty app and paid ads on Google and Meta. Leadership wants: daily sales and margin by store, a single customer view across store and online, marketing ROI by channel, and live stock for flash sales.

**Must-have deliverables**

- [ ] `data_generator/`: realistic fake data for 90 days, plus a daily "new day" mode; includes late files, duplicates and one schema change on purpose
- [ ] `terraform/`: GCS landing + lakehouse buckets, Pub/Sub, service accounts, Snowflake warehouses, databases, roles, integrations, resource monitors
- [ ] Snowpipe auto-ingest for POS, orders, customers, products and ads into `RETAIL_RAW`
- [ ] `dbt_retail/`: staging → intermediate → marts; snapshots; tests; contracts; docs
- [ ] Marts: `fct_sales_line`, `fct_inventory_daily`, `fct_ad_performance`, `fct_attribution` (last-click + linear), `dim_customer` (SCD2, unified across channels), `dim_product`, `dim_store`, `dim_date`, `dim_campaign`
- [ ] Live stock Dynamic Table (5-minute lag)
- [ ] Airflow DAG (local Docker; Composer-ready): arrival checks → `dbt build` → reconciliation → alert
- [ ] Security: functional/access roles, PII masking, regional row access policy
- [ ] Performance write-up with before/after numbers from Stage 6
- [ ] A dashboard (Streamlit in Snowflake or Looker Studio): sales, margin, ROAS by channel, top customers
- [ ] `docs/architecture.md`: the diagram, the seven-beat explanation, design decisions and trade-offs
- [ ] CI: GitHub Actions running dbt on a zero-copy clone per pull request

**Acceptance test (do this before you call it done)**

1. Run the generator for a new day; within 10 minutes RAW is loaded with no manual step.
2. The DAG goes green; all dbt tests pass; reconciliation is within 0.5% per store-day.
3. Change one customer's loyalty tier at source; next run shows a new SCD2 row and old sales still map to the old tier.
4. Log in as `FR_ANALYST`: emails masked, only one region visible.
5. `terraform destroy` and `apply` rebuilds the platform from scratch.
6. Explain the whole thing out loud in 4 minutes, then answer "what would you change at 100× the volume?"

**Stretch goals:** Snowpipe Streaming for POS events; Iceberg mart read from BigQuery; Cortex sentiment on reviews; a demand-forecast model in Snowpark ML writing predictions back to a table.

Pin this repo on your GitHub profile and link it on your CV under a "Snowflake + GCP" project entry.

## Interview bank, certifications and 10-week timeline

### Questions a Snowflake lead role will ask, with the core of a good answer

| Question | The core of a strong answer |
| --- | --- |
| Walk me through the architecture for our retail data | The seven beats above: clarify → sources → GCS landing → RAW → staging/intermediate/marts → serve → operate |
| Why Snowflake over BigQuery on GCP? | Workload isolation per warehouse, predictable per-second credits, zero-copy cloning for dev/CI, cross-cloud sharing and clean rooms, strong governance. Be fair: BigQuery wins on native GCP integration and serverless simplicity |
| How do you load data from GCS? | Storage integration + external stage; Snowpipe auto-ingest via Pub/Sub notification integration; COPY for backfills; file sizing 100–250 MB |
| How do you handle late-arriving or duplicate POS data? | Lineage columns, dedupe with `QUALIFY ROW_NUMBER()`, incremental model with a lookback window (e.g. reprocess last 3 days) and `merge` on the natural key |
| SCD2 — how and where? | dbt snapshots or hand MERGE; point-in-time joins on `valid_from`/`valid_to`; customer and product dims |
| Fact grain for retail sales? | One row per transaction line item; returns as negative lines; transaction\_id as degenerate dimension |
| How would you build attribution? | Touchpoints table (ads + web + email) joined to orders within a lookback window; last-click, linear, time-decay; Snowpark if logic is complex; ad spend joined for ROAS |
| A dashboard is slow. Debug it | Query Profile → pruning, spilling, join explosion → fix filter/clustering → right-size or multi-cluster `BI_WH` → result cache / materialized view |
| How do you control cost? | Workload warehouses, auto-suspend 60s, resource monitors, query tags, ACCOUNT\_USAGE reporting, transient staging tables, avoid unneeded clustering |
| How do you secure PII? | Functional + access roles, masking and tag-based masking, row access policies, key-pair auth for services, ACCESS\_HISTORY for audits |
| Streams/Tasks vs Dynamic Tables vs Airflow? | Dynamic Tables for declarative near-real-time transforms; streams + tasks for custom CDC logic; Airflow for cross-system orchestration |
| How do you deploy changes safely? | Git, PR, CI on a zero-copy clone, dbt slim CI, Terraform for infra, swap or blue/green for big rebuilds |
| How would you lead this as the senior engineer? | Write the standards (naming, layers, tests, PR review), define SLAs per mart, data contracts with source owners, cost dashboard reviewed monthly |

Record a spoken answer to each in `interview/` and re-record until each is under 2 minutes.

### Certification path

1. **SnowPro Core** (after Stage 4–5). It covers architecture, loading, performance, cloning, Time Travel and sharing; it currently costs $175 ([Flexera, 2026](https://www.flexera.com/blog/finops/snowflake-certifications/)).
2. **SnowPro Advanced: Data Engineer** (after the final capstone). It's 65 questions at $375 and needs an active Core cert ([Flexera, 2026](https://www.flexera.com/blog/finops/snowflake-certifications/)). This one matches the role exactly.
3. Optional: **Google Cloud Professional Data Engineer**, if you plan to target GCP-heavy roles beyond Snowflake.
4. Free warm-up: Snowflake's **Hands-On Essentials** badge workshops (Data Warehousing, Data Engineering, Data Lake) on learn.snowflake.com — they are hands-on badges, not proctored exams.

### 10-week timeline

| Week | Snowflake | GCP | Deliverable |
| --- | --- | --- | --- |
| 1 | Stage 1 Foundations | G1 IAM, GCS | Capstone 1: lab account |
| 2 | Stage 2 Ingestion | G2 Pub/Sub, G3 Cloud Run | Capstone 2: data lands itself |
| 3 | Stage 3 Modeling | G4 BigQuery comparison | Capstone 3: star schema |
| 4 | Stage 4 dbt (part 1) | G5 Terraform | GCP capstone: landing zone in code |
| 5 | Stage 4 Snowpark (part 2) | — | Capstone 4: dbt\_retail; book SnowPro Core |
| 6 | Stage 5 Orchestration | Composer read-through | Capstone 5: two speeds |
| 7 | Stage 6 Performance | — | Capstone 6: before/after numbers; sit SnowPro Core |
| 8 | Stage 7 Governance | — | Capstone 7: lock it down |
| 9 | Stage 8 Advanced | Iceberg + BigLake | Capstone 8: platform features |
| 10 | Final capstone + mock interviews | — | RetailOne repo public; architecture talk recorded |

At about 2–3 focused hours a day, this is realistic alongside client work. If an interview lands earlier, jump to the interview answer, Stages 3, 4 and 6, and the question bank: those cover most of what a lead Snowflake interview probes.

### Sources

- [Snowflake certifications: which one to pursue in 2026 — Flexera](https://www.flexera.com/blog/finops/snowflake-certifications/)
- Official docs to keep open while working: docs.snowflake.com (Snowpipe auto-ingest for Google Cloud Storage, storage integrations, Dynamic Tables, Iceberg tables), docs.getdbt.com (Snowflake configs), cloud.google.com/docs
