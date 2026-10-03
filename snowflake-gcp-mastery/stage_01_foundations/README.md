# Stage 1 — Foundations (week 1)

**Goal:** understand how Snowflake is built and billed, create your first objects, recover from mistakes with
Time Travel, and finish with a properly structured account (roles, warehouses, databases, cost guardrail)
that every later stage builds on.

**Prerequisite:** [00_setup](../00_setup/README.md) complete.

| # | File | What you learn | Time |
| --- | --- | --- | --- |
| 01 | [01_setup.sql](01_setup.sql) | Warehouse, database, schema, session context, sample data | 30 min |
| 02 | [02_warehouses_and_caching.sql](02_warehouses_and_caching.sql) | Sizes, billing, the 3 caches, scale up vs out | 60 min |
| 03 | [03_time_travel_and_cloning.sql](03_time_travel_and_cloning.sql) | Time Travel, restore, UNDROP, zero-copy clone | 60 min |
| 04 | [04_table_types.sql](04_table_types.sql) | Permanent / transient / temporary, views | 30 min |
| 05 | [05_semi_structured.sql](05_semi_structured.sql) | VARIANT, path notation, FLATTEN | 60 min |
| C1 | [capstone_01_retail_lab_account.sql](capstone_01_retail_lab_account.sql) → [capstone_01_service_user.sql](capstone_01_service_user.sql) → [capstone_01_verify.sql](capstone_01_verify.sql) | The account skeleton for RetailOne | 2 h |

---

## 1. Concepts in plain language

### 1.1 What Snowflake is

A cloud data warehouse delivered as a service. You never install, patch or tune servers. You create
**objects** with SQL and pay for **storage** (per TB per month) and **compute** (credits per second).

### 1.2 The three-layer architecture (the most important idea in this course)

```
┌──────────────────────────────────────────────────────────────┐
│ CLOUD SERVICES  metadata · optimizer · security · transactions│  ← always on, mostly free
├──────────────────────────────────────────────────────────────┤
│ COMPUTE         LOAD_WH   TRANSFORM_WH   BI_WH   (warehouses) │  ← you pay per second while running
├──────────────────────────────────────────────────────────────┤
│ STORAGE         micro-partitions in GCS (columnar, compressed)│  ← you pay per TB per month
└──────────────────────────────────────────────────────────────┘
```

- **Storage**: tables are split into **micro-partitions** (50–500 MB uncompressed each), stored by column and
  compressed. Snowflake records the **min/max of every column in every micro-partition**; that metadata lets
  queries skip partitions ("pruning", Stage 6).
- **Compute**: a **virtual warehouse** is a cluster of machines that runs queries. It holds no data. Many
  warehouses can read the same tables at the same time without competing.
- **Cloud services**: the brain — parses SQL, optimises it, enforces security, stores metadata, handles transactions.

Why a retailer cares: on Black Friday, BI dashboards can scale out on `BI_WH` while the nightly finance load
runs on `LOAD_WH`, and neither slows the other — because compute is separate from storage.

### 1.3 Object hierarchy

```
Organization
└── Account
    ├── Users, Roles, Warehouses, Integrations, Resource monitors   (account-level)
    └── Database
        └── Schema
            └── Tables, Views, Stages, File formats, Pipes, Streams, Tasks, Functions, Procedures
```

Fully qualified name: `DATABASE.SCHEMA.OBJECT`, e.g. `RETAIL_RAW.POS.SALES_LINES`.

### 1.4 Warehouses and billing

| Size | XS | S | M | L | XL | 2XL | 3XL | 4XL | 5XL | 6XL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Credits / hour | 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512 |

- Billed **per second**, with a **60-second minimum** each time a warehouse resumes.
- `AUTO_SUSPEND = 60`: stops after 60 s idle. `AUTO_RESUME = TRUE`: starts when a query arrives.
- **Scale up** (bigger size): one heavy query is faster / stops spilling to disk.
- **Scale out** (multi-cluster, Enterprise): more clusters of the same size for **many concurrent** users.

### 1.5 Table types

| Type | Time Travel | Fail-safe | Use for |
| --- | --- | --- | --- |
| Permanent | 0–90 days (Enterprise) | 7 days | RAW, MARTS: data you can't rebuild |
| Transient | 0–1 day | none | STAGING, dev, lab: rebuildable data (cheaper) |
| Temporary | 0–1 day | none | Scratch inside one session |

### 1.6 Time Travel, Fail-safe, cloning

```
 change ──► [ Time Travel: you can query/restore (1–90 days) ] ──► [ Fail-safe: 7 days, Snowflake Support only ] ──► gone
```

- **Time Travel**: `AT(TIMESTAMP => …)`, `AT(OFFSET => -60)`, `BEFORE(STATEMENT => '<query id>')`; `UNDROP`.
- **Zero-copy clone**: `CREATE … CLONE …` copies metadata only; storage is shared until one side changes.
  Used for dev environments, CI (a full prod clone per pull request) and safe experiments.

### 1.7 The three caches

| Cache | Where | Lifetime | What it gives you |
| --- | --- | --- | --- |
| Result cache | Cloud services | 24 h (reset on reuse, max 31 days) | Identical query + unchanged data = instant, **free** |
| Local disk cache | Warehouse SSD | Until the warehouse suspends | Faster repeated scans of the same data |
| Metadata cache | Cloud services | Always | `COUNT(*)`, `MIN/MAX` answered with no warehouse |

### 1.8 System roles

```
ACCOUNTADMIN  (top: billing, account parameters — use rarely, never to build objects)
├── SECURITYADMIN  (manages grants; inherits USERADMIN)
│   └── USERADMIN  (creates users and roles)
└── SYSADMIN       (creates and owns databases and warehouses)
    └── your custom roles (RETAIL_ADMIN → RETAIL_ENGINEER → RETAIL_ANALYST)
PUBLIC (every user has it)
```

Privileges are granted **to roles**, roles are granted **to users** (and to other roles). A parent role
inherits everything its child roles can do.

### 1.9 Semi-structured data

`VARIANT` holds any JSON value. Query with `v:customer.id::INT`; explode arrays with `LATERAL FLATTEN`.
Always cast (`::STRING`, `::NUMBER(10,2)`) when you pull values out.

---

## 2. Step-by-step

1. Open Snowsight → **Projects → Worksheets → +**. Top of the worksheet: choose role `SYSADMIN`, warehouse `LAB_WH` (after lesson 01 creates it).
2. Run lessons **01 → 05** statement by statement (**Ctrl+Enter**). Read every result.
3. In lesson 02, after each query open **Query Profile** (the `…` next to the result → *View Query Profile*). Look at *Bytes scanned*, *Percentage scanned from cache*, and the operator tree.
4. Run the capstone: [capstone_01_retail_lab_account.sql](capstone_01_retail_lab_account.sql) with **Run All**.
5. Generate the service-user key (Git Bash: `bash 00_setup/generate_keypair.sh svc_retail_pipeline`), paste it into [capstone_01_service_user.sql](capstone_01_service_user.sql), run it.
6. Run [capstone_01_verify.sql](capstone_01_verify.sql) statement by statement and screenshot the results.
7. Re-run `python 00_setup/check_env.py` — "Capstone 1 roles exist" should now be OK.

From now on, switch your `.env` role to `RETAIL_ENGINEER` (already the default in `.env.example`).

## 3. Try this (break it on purpose)

- Run the capstone script **twice**. Nothing should fail: that is what "rerunnable" means.
- Run `CREATE TABLE …` as `ACCOUNTADMIN`, then try to query it as `RETAIL_ENGINEER`. Why does it fail? (Ownership.) Fix it with `GRANT OWNERSHIP`.
- In lesson 03, try `AT(OFFSET => -3600)` on a table created 5 minutes ago. Read the error.
- Set `DATA_RETENTION_TIME_IN_DAYS = 0` on a scratch table, drop it, try `UNDROP`.
- Resize `LAB_WH` to `MEDIUM`, rerun the TPC-H query with the result cache off, compare time. Set it back to XSMALL!

## 4. Common errors

| Error | Meaning / fix |
| --- | --- |
| `No active warehouse selected` | `USE WAREHOUSE LAB_WH;` |
| `Object does not exist or not authorized` | Wrong role or missing grant. Check `SELECT CURRENT_ROLE();` and `SHOW GRANTS TO ROLE …` |
| `Insufficient privileges to operate on account` | You need ACCOUNTADMIN for that statement (resource monitors, integrations) |
| `Time travel data is not available` | The point in time is before the table existed or outside retention |

## 5. Interview check — answer out loud first, then open

<details><summary>Why is storage/compute separation useful for a retailer at Black Friday?</summary>

Each workload gets its own warehouse over the same single copy of data. BI can scale out (multi-cluster)
for thousands of dashboard users while ingestion and dbt keep their own compute; nobody queues behind anybody,
and you pay for the extra compute only during the peak, by the second. Storage doesn't need resizing at all.
</details>

<details><summary>What do you lose by using transient tables?</summary>

Fail-safe (the 7-day Snowflake-recoverable period) and Time Travel beyond 1 day. You gain lower storage cost
for high-churn data. Right for staging and rebuildable models, wrong for RAW (your replay source) or anything
you can't regenerate.
</details>

<details><summary>Which cache answers a repeated dashboard query for free?</summary>

The result cache in the cloud services layer: same query text, same role access, underlying data unchanged,
within 24 hours → returned without a warehouse, zero credits. Tip: dashboards that inject `CURRENT_TIMESTAMP()`
or random values into SQL defeat it.
</details>

<details><summary>How does zero-copy cloning work and when do you pay?</summary>

The clone copies metadata pointers to existing micro-partitions. You pay only for micro-partitions that are
written afterwards on either side. Used for dev/test environments, CI per pull request and pre-change backups.
</details>

<details><summary>Someone ran UPDATE without WHERE on a prod table 20 minutes ago. What do you do?</summary>

Find the query ID in Query History, check the data with `SELECT … BEFORE(STATEMENT => '<id>')`, then either
`INSERT OVERWRITE INTO t SELECT * FROM t BEFORE(STATEMENT => '<id>')` (keeps grants/policies on the object) or
clone-at-time + `ALTER TABLE … SWAP WITH`. Then add a process fix (PR review, least privilege, no DML on prod by people).
</details>

## 6. Evidence (paste screenshots / results here)

- [ ] Capstone script ran twice without errors
- [ ] `SHOW WAREHOUSES` with resource monitor attached
- [ ] Time Travel restore result
- [ ] Clone vs original row counts
- [ ] Analyst access denied

## 7. My notes (in my own words)
