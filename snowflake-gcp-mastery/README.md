# snowflake-gcp-mastery

A hands-on path from **absolute beginner to expert** in Snowflake data engineering on Google Cloud.
Everything builds one system: **RetailOne**, a retail data platform with stores in Kenya and Qatar,
an online shop, a loyalty programme and paid ads on Google and Meta.

> The plan behind this repo is `../Snowflake + GCP Beginner to Expert Roadmap.md`.
> This repo is the *material*: the guides, the code, the run instructions, the exercises and the interview notes.

---

## 1. How to work through this repo

Each stage follows the same loop:

1. **Read** the stage `README.md` top to bottom (concepts in plain language).
2. **Run** the numbered files in order (`01_…`, `02_…`). Every file says *how* to run it and *what you should see*.
3. **Break it on purpose.** Each README has a "Try this" section. Mistakes teach you more than the happy path.
4. **Build the capstone** for the stage. It adds one layer to RetailOne.
5. **Answer the interview check out loud, without notes**, then compare with the model answers.
6. **Write your own notes** in the "My notes" section at the bottom of the stage README.

Do not copy and paste blindly. The fastest way to learn is: read a file, close it, rewrite the key parts yourself, then compare.

**Open this folder (`snowflake-gcp-mastery`) as your VSCode workspace** (File → Open Folder), not its parent, so the
workspace settings and recommended extensions apply.

## 2. Order of work (10 weeks, about 2–3 hours a day)

| Week | Do this | Folder |
| --- | --- | --- |
| 0 (day 1–2) | Accounts, tools, keys, connection test | [00_setup/](00_setup/) |
| 1 | Snowflake foundations + GCP IAM & GCS | [stage_01_foundations/](stage_01_foundations/), [gcp/](gcp/) G1 |
| 2 | Ingestion from GCS, Snowpipe + Pub/Sub, Cloud Run | [stage_02_ingestion/](stage_02_ingestion/), [gcp/](gcp/) G2–G3 |
| 3 | Dimensional modeling, hand-written SCD2 + BigQuery comparison | [stage_03_modeling/](stage_03_modeling/), [gcp/](gcp/) G4 |
| 4 | dbt part 1 + Terraform landing zone | [stage_04_dbt_snowpark/](stage_04_dbt_snowpark/), [gcp/terraform/](gcp/terraform/) |
| 5 | dbt part 2 + Snowpark | [stage_04_dbt_snowpark/](stage_04_dbt_snowpark/) |
| 6 | Streams, Tasks, Dynamic Tables, Airflow | [stage_05_orchestration/](stage_05_orchestration/) |
| 7 | Performance tuning and cost | [stage_06_performance/](stage_06_performance/) |
| 8 | Data quality, security, governance | [stage_07_quality_governance/](stage_07_quality_governance/) |
| 9 | Sharing, Iceberg, Cortex, Streamlit, CI/CD | [stage_08_advanced/](stage_08_advanced/) |
| 10 | Final capstone + mock interviews | [capstone_retail_platform/](capstone_retail_platform/), [interview/](interview/) |

## 3. Repo map

```
snowflake-gcp-mastery/
├── README.md                 ← you are here
├── STANDARDS.md              ← data engineering standards used everywhere in this repo
├── requirements.txt          ← one Python environment for the whole course
├── .vscode/                  ← workspace settings (.sql = Snowflake SQL) + recommended extensions
├── (../.github/workflows/)   ← CI lives at the Git repo root: dbt on a zero-copy clone per PR (Stage 8)
├── ci/                       ← helper scripts used by CI
├── 00_setup/                 ← accounts, installs, key-pair auth, connection checks
├── gcp/                      ← GCP track G1–G5 (gcloud scripts, Cloud Run job, BigQuery, Terraform)
├── stage_01_foundations/     ← architecture, warehouses, Time Travel, cloning, VARIANT
├── stage_02_ingestion/       ← stages, storage integration, COPY, Snowpipe on GCS
├── stage_03_modeling/        ← Kimball, bus matrix, star schema, hand-written SCD2
├── stage_04_dbt_snowpark/    ← dbt walkthrough + Snowpark Python lessons
├── stage_05_orchestration/   ← streams, tasks, dynamic tables, Airflow, backfills
├── stage_06_performance/     ← Query Profile, pruning, clustering, sizing, cost
├── stage_07_quality_governance/ ← RBAC, masking, row access, tags, DMFs, audit
├── stage_08_advanced/        ← sharing, clean rooms, Iceberg, Cortex, Streamlit, DevOps
├── capstone_retail_platform/ ← the final RetailOne platform
│   ├── data_generator/       ← fake POS, orders, customers, products, ads, web, reviews
│   ├── terraform/            ← GCP + Snowflake infrastructure in one apply
│   ├── dbt_retail/           ← the dbt project (staging → intermediate → marts)
│   ├── airflow/              ← Astro (local Docker) Airflow project
│   ├── snowflake/            ← deploy order for SQL objects not owned by Terraform/dbt
│   └── docs/                 ← architecture, acceptance tests, performance results
└── interview/                ← seven-beat script, question bank, practice log
```

## 4. One-time placeholder replacement (do this on day 1)

GCS bucket names are global, so your names must be unique. This repo uses one placeholder:

| Placeholder | Replace with | Example |
| --- | --- | --- |
| `YOUR_PROJECT_ID` | Your GCP project ID (lowercase) | `retail-dp-lab-4821` |

In VSCode: **Ctrl+Shift+H** (Replace in Files) → find `YOUR_PROJECT_ID` → replace with your project ID → **Replace All**.
Bucket names then become `<project-id>-landing` and `<project-id>-lakehouse`.

Your Snowflake account identifier, user name and key paths **never** go into code. They live in `.env`
(see [00_setup/README.md](00_setup/README.md)), which Git ignores.

## 5. Three ways to run Snowflake SQL (pick per situation)

| Way | When | How |
| --- | --- | --- |
| **Snowsight worksheet** (browser) | Stage 1–2 while learning; seeing results in a grid | Snowsight → Projects → Worksheets → `+` → paste file → run one statement with **Ctrl+Enter**, or all with **Ctrl+Shift+Enter** |
| **VSCode Snowflake extension** | Daily work inside the repo | Open the `.sql` file → sign in from the Snowflake panel → put the cursor in a statement → **Ctrl+Enter** |
| **Snowflake CLI** (`snow`) | Automation, scripts, CI | `snow sql -f stage_01_foundations/01_setup.sql` |

Rule of thumb: **learn statement by statement** (worksheet or VSCode), **deploy file by file** (`snow sql -f`).

## 6. Session routine (cost discipline)

Start of session:

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery"
.\.venv\Scripts\Activate.ps1
. .\00_setup\load_env.ps1          # loads .env into this PowerShell window
```

End of session:

- Snowflake: warehouses auto-suspend after 60 seconds. Suspend any **tasks** you resumed (`ALTER TASK … SUSPEND`).
- GCP: run `gcp/teardown.sh` if you created resources by hand, or `terraform destroy` if you used Terraform.
- Check the bill weekly: Snowsight → Admin → Cost Management, and GCP → Billing → Reports.

## 7. Progress tracker

Tick as you go (edit this file and commit; your Git history becomes your learning log).

- [ ] 00 Setup complete, `python 00_setup/check_env.py` all green
- [ ] G1–G2 GCS bucket + Pub/Sub notifications working
- [ ] Capstone 1 — Retail lab account
- [ ] G3 Cloud Run ads extractor deployed
- [ ] Capstone 2 — Data lands itself
- [ ] G4 Snowflake vs BigQuery one-pager written
- [ ] Capstone 3 — Retail star schema
- [ ] GCP capstone — Landing zone in Terraform
- [ ] Capstone 4 — dbt_retail
- [ ] Capstone 5 — Two speeds
- [ ] Capstone 6 — Fast and cheap (before/after table)
- [ ] Capstone 7 — Locked down
- [ ] Capstone 8 — Platform features
- [ ] Final capstone — all acceptance tests pass
- [ ] SnowPro Core booked / passed
