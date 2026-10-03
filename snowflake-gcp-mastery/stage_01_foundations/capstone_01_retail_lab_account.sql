/* =============================================================================
   CAPSTONE 1 — "Retail lab account"   (rerunnable: safe to run again and again)
   -----------------------------------------------------------------------------
   Creates the account skeleton every later stage depends on:

     Roles (custom, granted up to SYSADMIN):
         SYSADMIN
           └── RETAIL_ADMIN          platform owner
                 └── RETAIL_ENGINEER builds pipelines, owns RAW/STAGING/MARTS
                       └── RETAIL_ANALYST reads MARTS via BI_WH
     Warehouses: LOAD_WH, TRANSFORM_WH, BI_WH (multi-cluster), LAB_WH
     Databases:  RETAIL_RAW, RETAIL_STAGING, RETAIL_MARTS (permanent)
                 RETAIL_DEV, RETAIL_LAB (transient: rebuildable, cheaper)
     Guardrail:  resource monitor RM_RETAIL_MONTHLY on every warehouse

   HOW TO RUN
     Easiest: Snowsight worksheet → paste → "Run All" (Ctrl+Shift+Enter).
     CLI:     snow sql -c retail_admin -f stage_01_foundations/capstone_01_retail_lab_account.sql
   You need ACCOUNTADMIN granted to your user (true for the trial's first user).
   Each section switches to the LEAST powerful role that can do the job.
   ============================================================================= */

/* ---------------------------------------------------------------------------
   SECTION A — Roles (USERADMIN creates roles and users)
   --------------------------------------------------------------------------- */
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS RETAIL_ADMIN    COMMENT = 'RetailOne platform owner';
CREATE ROLE IF NOT EXISTS RETAIL_ENGINEER COMMENT = 'Builds and runs pipelines; owns RetailOne databases';
CREATE ROLE IF NOT EXISTS RETAIL_ANALYST  COMMENT = 'Reads curated marts';

/* ---------------------------------------------------------------------------
   SECTION B — Role hierarchy (SECURITYADMIN manages grants)
   Privileges flow UP: a parent role inherits everything its children can do.
   Always attach custom roles to SYSADMIN, otherwise SYSADMIN can't manage
   the objects they own ("orphaned" hierarchy).
   --------------------------------------------------------------------------- */
USE ROLE SECURITYADMIN;

GRANT ROLE RETAIL_ANALYST  TO ROLE RETAIL_ENGINEER;
GRANT ROLE RETAIL_ENGINEER TO ROLE RETAIL_ADMIN;
GRANT ROLE RETAIL_ADMIN    TO ROLE SYSADMIN;

-- Give yourself the admin role (and therefore everything below it).
SET my_user = CURRENT_USER();
GRANT ROLE RETAIL_ADMIN TO USER IDENTIFIER($my_user);

/* ---------------------------------------------------------------------------
   SECTION C — Warehouses (SYSADMIN), one per workload
   --------------------------------------------------------------------------- */
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS LOAD_WH
  WITH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
       STATEMENT_TIMEOUT_IN_SECONDS = 3600
       COMMENT = 'COPY INTO / backfills (Snowpipe itself is serverless)';

CREATE WAREHOUSE IF NOT EXISTS TRANSFORM_WH
  WITH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
       STATEMENT_TIMEOUT_IN_SECONDS = 3600
       COMMENT = 'dbt, tasks, dynamic tables';

CREATE WAREHOUSE IF NOT EXISTS BI_WH
  WITH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
       MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 2 SCALING_POLICY = 'STANDARD'
       STATEMENT_TIMEOUT_IN_SECONDS = 600
       COMMENT = 'Dashboards and analysts; multi-cluster for concurrency';

CREATE WAREHOUSE IF NOT EXISTS LAB_WH
  WITH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
       COMMENT = 'Learning / lab work';

/* ---------------------------------------------------------------------------
   SECTION D — Databases (SYSADMIN creates, then hands ownership to the engineer role)
   --------------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS RETAIL_RAW
  DATA_RETENTION_TIME_IN_DAYS = 7 COMMENT = 'Exact copies of sources + lineage columns. Append-only.';
CREATE DATABASE IF NOT EXISTS RETAIL_STAGING
  DATA_RETENTION_TIME_IN_DAYS = 1 COMMENT = 'Typed, cleaned, deduplicated (dbt stg_/int_)';
CREATE DATABASE IF NOT EXISTS RETAIL_MARTS
  DATA_RETENTION_TIME_IN_DAYS = 7 COMMENT = 'Star schemas used by the business';
CREATE TRANSIENT DATABASE IF NOT EXISTS RETAIL_DEV
  COMMENT = 'Personal dbt development schemas';
CREATE TRANSIENT DATABASE IF NOT EXISTS RETAIL_LAB
  COMMENT = 'Hand-built models, experiments, performance tests';

-- Transfer ownership so the engineer role can create schemas/tables freely.
-- COPY CURRENT GRANTS keeps any existing grants on the object.
GRANT OWNERSHIP ON DATABASE RETAIL_RAW     TO ROLE RETAIL_ENGINEER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RETAIL_STAGING TO ROLE RETAIL_ENGINEER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RETAIL_MARTS   TO ROLE RETAIL_ENGINEER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RETAIL_DEV     TO ROLE RETAIL_ENGINEER COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE RETAIL_LAB     TO ROLE RETAIL_ENGINEER COPY CURRENT GRANTS;

-- Warehouse privileges: USAGE = run queries, OPERATE = suspend/resume, MONITOR = see load.
GRANT USAGE, OPERATE, MONITOR ON WAREHOUSE LOAD_WH      TO ROLE RETAIL_ENGINEER;
GRANT USAGE, OPERATE, MONITOR ON WAREHOUSE TRANSFORM_WH TO ROLE RETAIL_ENGINEER;
GRANT USAGE, OPERATE, MONITOR ON WAREHOUSE LAB_WH       TO ROLE RETAIL_ENGINEER;
GRANT USAGE                   ON WAREHOUSE BI_WH        TO ROLE RETAIL_ANALYST;   -- engineer inherits
GRANT MODIFY ON WAREHOUSE TRANSFORM_WH TO ROLE RETAIL_ADMIN;  -- admin may resize
GRANT MODIFY ON WAREHOUSE BI_WH        TO ROLE RETAIL_ADMIN;

/* ---------------------------------------------------------------------------
   SECTION E — Analyst read access to MARTS, including FUTURE objects
   Future grants mean tables dbt creates next month are readable automatically.
   (Database-level future grants need MANAGE GRANTS → SECURITYADMIN.)
   --------------------------------------------------------------------------- */
USE ROLE SECURITYADMIN;

GRANT USAGE  ON DATABASE RETAIL_MARTS                       TO ROLE RETAIL_ANALYST;
GRANT USAGE  ON ALL SCHEMAS    IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT SELECT ON ALL TABLES     IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT SELECT ON FUTURE TABLES  IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT SELECT ON ALL VIEWS      IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT SELECT ON FUTURE VIEWS   IN DATABASE RETAIL_MARTS     TO ROLE RETAIL_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE RETAIL_MARTS TO ROLE RETAIL_ANALYST;

-- Engineer may create databases: needed for zero-copy CI clones (Stage 8).
GRANT CREATE DATABASE ON ACCOUNT TO ROLE RETAIL_ENGINEER;

/* ---------------------------------------------------------------------------
   SECTION F — Account-level privileges and the cost guardrail (ACCOUNTADMIN only)
   --------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

-- Run tasks on a warehouse (Stage 5) and serverless tasks.
GRANT EXECUTE TASK         ON ACCOUNT TO ROLE RETAIL_ENGINEER;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE RETAIL_ENGINEER;

-- Read SNOWFLAKE.ACCOUNT_USAGE (query history, metering, access history) — Stages 6–7.
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE RETAIL_ADMIN;

-- Resource monitor: notify at 75%, suspend at 90% (running queries finish),
-- suspend immediately at 100% (running queries are cancelled).
-- 30 credits/month is plenty for this course; raise it in Stage 6 if needed.
CREATE RESOURCE MONITOR IF NOT EXISTS RM_RETAIL_MONTHLY
  WITH CREDIT_QUOTA = 30
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS ON 75 PERCENT DO NOTIFY
                ON 90 PERCENT DO SUSPEND
                ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE LOAD_WH      SET RESOURCE_MONITOR = RM_RETAIL_MONTHLY;
ALTER WAREHOUSE TRANSFORM_WH SET RESOURCE_MONITOR = RM_RETAIL_MONTHLY;
ALTER WAREHOUSE BI_WH        SET RESOURCE_MONITOR = RM_RETAIL_MONTHLY;
ALTER WAREHOUSE LAB_WH       SET RESOURCE_MONITOR = RM_RETAIL_MONTHLY;

/* ---------------------------------------------------------------------------
   SECTION G — Quick look at what you built
   --------------------------------------------------------------------------- */
USE ROLE RETAIL_ADMIN;
SHOW WAREHOUSES LIKE '%_WH';
SHOW DATABASES LIKE 'RETAIL_%';
SHOW GRANTS TO ROLE RETAIL_ENGINEER;
SHOW GRANTS OF ROLE RETAIL_ADMIN;
-- Next: capstone_01_service_user.sql, then capstone_01_verify.sql
