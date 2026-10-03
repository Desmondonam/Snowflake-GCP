/* =============================================================================
   Stage 8 · Lesson 06 — DevOps on Snowflake: blue/green, Git integration, replication
   HOW TO RUN: worksheet, section by section. Sections C is read-only for a trial.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;

/* ---------------------------------------------------------------------------
   A. Blue/green deploy of a big rebuild with SWAP (atomic, metadata only)
      Build the new version next to the live one, validate, swap, keep the old one
      for instant rollback, drop it later.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE_GREEN CLONE RETAIL_MARTS.SALES.FCT_SALES_LINE;
-- … imagine a full rebuild / backfill / column change applied to _GREEN here …
SELECT (SELECT COUNT(*) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE)       AS blue_rows,
       (SELECT COUNT(*) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE_GREEN) AS green_rows;
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE SWAP WITH RETAIL_MARTS.SALES.FCT_SALES_LINE_GREEN;  -- go live
-- Rollback = the same SWAP again. Clean up when happy:
DROP TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE_GREEN;
-- Whole schemas/databases swap the same way: ALTER SCHEMA … SWAP WITH …, ALTER DATABASE … SWAP WITH …
-- Note: grants and policies belong to the table object and move with it. Re-check them after a swap
-- (the dbt post-hook re-applies tags/RAP on the next build anyway).

/* ---------------------------------------------------------------------------
   B. Git integration: run versioned SQL straight from your GitHub repo
      (public repo shown; a private repo needs a SECRET with a token)
   --------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE API INTEGRATION GITHUB_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/<your-github-user>')
  ENABLED = TRUE;
GRANT USAGE ON INTEGRATION GITHUB_API TO ROLE RETAIL_ENGINEER;

USE ROLE RETAIL_ENGINEER;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.DEVOPS;
CREATE OR REPLACE GIT REPOSITORY RETAIL_LAB.DEVOPS.MASTERY_REPO
  API_INTEGRATION = GITHUB_API
  ORIGIN = 'https://github.com/<your-github-user>/snowflake-gcp-mastery.git';
ALTER GIT REPOSITORY RETAIL_LAB.DEVOPS.MASTERY_REPO FETCH;
SHOW GIT BRANCHES IN RETAIL_LAB.DEVOPS.MASTERY_REPO;
LS @RETAIL_LAB.DEVOPS.MASTERY_REPO/branches/main/stage_02_ingestion/;
-- Deploy a reviewed, idempotent script from main:
-- EXECUTE IMMEDIATE FROM @RETAIL_LAB.DEVOPS.MASTERY_REPO/branches/main/stage_02_ingestion/capstone_02_raw_layer.sql;

/* ---------------------------------------------------------------------------
   C. Replication & failover (needs 2 accounts in the same ORGANIZATION; failover needs Business Critical)
   --------------------------------------------------------------------------- */
-- On the PRIMARY account:
-- CREATE FAILOVER GROUP RETAIL_FG
--   OBJECT_TYPES = DATABASES, ROLES, WAREHOUSES, RESOURCE MONITORS
--   ALLOWED_DATABASES = RETAIL_RAW, RETAIL_MARTS
--   ALLOWED_ACCOUNTS = <org>.<dr_account>          -- e.g. a DR account on AWS eu-west or GCP europe-west
--   REPLICATION_SCHEDULE = '10 MINUTE';
-- On the SECONDARY account:
-- CREATE FAILOVER GROUP RETAIL_FG AS REPLICA OF <org>.<primary_account>.RETAIL_FG;
-- During an outage, on the secondary:
-- ALTER FAILOVER GROUP RETAIL_FG PRIMARY;
-- Client redirect (CONNECTION objects) moves BI/dbt/Airflow to the new primary without changing their config:
-- CREATE CONNECTION RETAIL_CONN;  ALTER CONNECTION RETAIL_CONN ENABLE FAILOVER TO ACCOUNTS <org>.<dr_account>;

/* ---------------------------------------------------------------------------
   D. The delivery toolbox (what each tool owns in this repo)
   --------------------------------------------------------------------------- */
-- Terraform          : account objects — warehouses, databases, roles, grants, integrations, monitors (capstone terraform/)
-- SQL migrations     : schema objects dbt doesn't own — RAW tables, pipes, streams, tasks (capstone snowflake/deploy.py;
--                      schemachange is the community tool for versioned migrations)
-- dbt                : every model in STAGING/MARTS + tests + docs
-- GitHub Actions     : PR → zero-copy clone of prod → dbt build state:modified+ → drop clone (.github/workflows/dbt_ci.yml)
-- snow CLI           : scripted SQL, Streamlit deploys, connection management
