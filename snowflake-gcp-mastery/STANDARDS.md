# Data Engineering Standards (RetailOne)

These are the rules every file in this repo follows. They are also what a lead engineer is expected to
*write down* for a team. Read this once now, and again after Stage 4 when it will make much more sense.

---

## 1. Environments and naming

### Snowflake objects

| Object | Convention | Examples |
| --- | --- | --- |
| Databases (one per layer) | `RETAIL_<LAYER>` | `RETAIL_RAW`, `RETAIL_STAGING`, `RETAIL_MARTS` |
| Dev / CI databases | `RETAIL_DEV`, `<DB>_PR_<n>` | `RETAIL_MARTS_PR_42` (zero-copy clone) |
| Lab / scratch | `RETAIL_LAB` | experiments, perf tests, hand-built models |
| Governance | `GOV` | `GOV.POLICIES`, `GOV.TAGS`, `GOV.DQ` |
| Schemas in RAW / STAGING | by **source system** | `POS`, `ECOM`, `CRM`, `ERP`, `ADS`, `WEB` |
| Schemas in MARTS | by **business domain** | `CORE`, `SALES`, `MARKETING`, `OPS`, `SHARED` |
| Warehouses | `<WORKLOAD>_WH` | `LOAD_WH`, `TRANSFORM_WH`, `BI_WH`, `LAB_WH` |
| Functional roles (people) | `FR_<TEAM>` | `FR_ANALYST`, `FR_MARKETING` |
| Access roles (privileges) | `AR_<DB>_<SCHEMA>_<LEVEL>` | `AR_MARTS_SALES_READ` |
| Service users | `SVC_<PURPOSE>` | `SVC_RETAIL_PIPELINE` |
| Integrations | `<TARGET>_<KIND>` | `GCS_INT`, `GCS_NOTIF` |
| Pipes / streams / tasks | `PIPE_`, `_STRM`, `T_` | `PIPE_POS_SALES`, `SALES_LINES_STRM`, `T_LOAD_SALES` |

Identifiers are **unquoted** and therefore stored UPPERCASE. Never create `"MixedCase"` quoted identifiers:
they force everyone to quote forever.

### dbt models

| Prefix | Layer | Materialization | Example |
| --- | --- | --- | --- |
| `stg_<source>__<entity>` | staging (1:1 with source) | view | `stg_pos__sales_lines` |
| `int_<entity>_<verb/desc>` | intermediate (business logic) | view / table | `int_customer_identity` |
| `dim_<entity>` | marts dimension | table | `dim_customer` |
| `fct_<process>` | marts fact | incremental / table | `fct_sales_line` |
| `rpt_<topic>` | report / reconciliation | table / view | `rpt_pos_reconciliation` |
| `aud_<audience>` | activation audience | table | `aud_lapsed_high_value` |

### GCS layout

```
gs://<project>-landing/<source>/dt=YYYY-MM-DD/<file>    ← immutable, append-only
gs://<project>-lakehouse/iceberg/<table>/               ← open-format tables
```

## 2. Layer contract

| Layer | Allowed | Not allowed |
| --- | --- | --- |
| RAW | Exact copy of source + `_file_name`, `_file_row_number`, `_loaded_at` | Updates, deletes, business logic |
| STAGING | Rename, cast, dedupe, light cleaning, one model per source table | Joins across sources, aggregations |
| INTERMEDIATE | Joins, identity resolution, sessionisation, versioning | Being queried by BI tools |
| MARTS | Star schemas, documented, tested, contracted | Raw identifiers without meaning, `SELECT *` |

**Only MARTS is exposed to people.** RAW and STAGING are for engineers and service accounts.

## 3. SQL style

- One statement does one thing. Prefer CTEs over nested subqueries.
- dbt models use the *import → logic → final* CTE pattern:

```sql
with
sales as (select * from {{ ref('stg_pos__sales_lines') }}),   -- imports first
enriched as ( ... ),                                          -- logic
final as ( ... )
select * from final
```

- List columns explicitly in marts. `SELECT *` is fine in staging imports only.
- Filter on columns directly (`sale_date >= '2026-01-01'`), never on functions of columns (`TO_CHAR(sale_date)`): it kills pruning.
- `UNION ALL` unless you truly need de-duplication.
- Compare nullable values with `IS DISTINCT FROM` or `EQUAL_NULL`, not `<>`.
- Money is `NUMBER(14,2)`, never `FLOAT`.
- Timestamps: `TIMESTAMP_NTZ` for business event time (local store time), `TIMESTAMP_LTZ` for system/load time.

## 4. Idempotent, rerunnable scripts

Every setup script in this repo can be run twice without breaking:

- `CREATE … IF NOT EXISTS` for things that hold data (databases, tables, stages).
- `CREATE OR REPLACE` only for stateless objects (views, file formats, policies before they are attached, procedures).
- Never `CREATE OR REPLACE` a table with data in a deploy script.
- Grants are idempotent by nature, so re-granting is safe.

## 5. Secrets and authentication

- **Nothing secret in Git.** `.env`, `*.p8`, `*.pem`, `terraform.tfvars`, `profiles.yml` with literals are all git-ignored.
- Humans: SSO or password + MFA in Snowsight; **key-pair** for CLI and tools.
- Services (dbt, Airflow, CI, Terraform): `TYPE = SERVICE` users with **key-pair auth**, one user per system.
- In cloud: keys live in **GCP Secret Manager** / GitHub Actions secrets, never in images.
- Rotate keys with `RSA_PUBLIC_KEY_2` (zero-downtime rotation; see Stage 7).

## 6. Git workflow

- `main` is always deployable. Work on branches: `feat/stage-03-scd2`, `fix/pipe-pattern`.
- Commit messages: `type(scope): summary`, e.g. `feat(dbt): add fct_inventory_daily`.
- Every PR runs CI (`dbt build` on a zero-copy clone) and uses the PR template checklist.
- Never commit generated output: `target/`, `dbt_packages/`, `logs/`, `.terraform/`, `output/`.

## 7. Testing and quality (minimum bar)

| What | Test |
| --- | --- |
| Every model primary key | `unique` + `not_null` |
| Every foreign key in a fact | `relationships` (warn on facts, error on dims) |
| Every source | `freshness` with warn/error thresholds |
| Enumerations | `accepted_values` |
| Money totals | reconciliation against source control totals (tolerance 0.5%) |
| Marts | `contract: enforced: true` (column names and types locked) |
| Business logic | dbt unit tests for tricky models (attribution, SCD2) |

## 8. Cost

- Every warehouse: `AUTO_SUSPEND = 60`, `AUTO_RESUME = TRUE`, `INITIALLY_SUSPENDED = TRUE`.
- One warehouse per workload (load / transform / BI / data science) so cost is attributable.
- Every warehouse is attached to a **resource monitor**.
- Every tool sets a `QUERY_TAG` (dbt, Airflow, Streamlit) so you can report cost per tool.
- Staging tables are **transient** (no Fail-safe storage cost). RAW and MARTS are permanent.
- Clustering, search optimization and materialized views are opt-in, justified with before/after numbers.

## 9. Observability and lineage

- Every RAW row carries `_file_name`, `_file_row_number`, `_loaded_at`.
- Every mart row carries `_loaded_at` (from RAW) so you can trace a number back to the file it came from.
- Pipelines alert on failure (Airflow callback → Slack/email), and on silence (source freshness).

## 10. Documentation

- Every stage folder has a `README.md` written in your own words. These are your interview notes.
- Every dbt model has a description; every mart column has a description.
- Architecture decisions are recorded in `capstone_retail_platform/docs/architecture.md` (decision, options, why).

## 11. Data handling

- This repo only uses **synthetic** data from the generator. Never put real customer data in a learning repo.
- PII columns are **tagged** (`GOV.TAGS.PII`) and masked by policy in MARTS.
- Masking is applied at the **MARTS** layer. Pipelines read RAW/STAGING unmasked under engineer roles; people never get RAW access.
