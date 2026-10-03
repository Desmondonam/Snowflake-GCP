/* =============================================================================
   Hand over Capstone 1 / Stage 2 objects to Terraform (run ONCE, before the first apply)
   -----------------------------------------------------------------------------
   Terraform can only manage objects it created (or imported). Capstone 1 created the
   same warehouses, databases, roles and integrations with SQL, so we drop them and
   let Terraform recreate them.

   ⚠ What you lose: everything inside RETAIL_RAW / STAGING / MARTS / DEV / LAB.
     * RAW is reloaded from GCS (files are still there) by deploy.py --phase backfill
     * STAGING/MARTS are rebuilt by dbt
     * dbt SNAPSHOT history and Stage 3/6 lab tables are lost (snapshots restart from now)
   Prefer to keep them? Use `terraform import` for each object instead (see the provider docs'
   "Import" section per resource) — slower, but non-destructive.

   ALSO: if you applied gcp/terraform (the GCP capstone), run `terraform destroy` there first —
   this configuration creates the same GCP resources through the same module.

   HOW TO RUN: Snowsight worksheet → Run All.
   ============================================================================= */
USE ROLE ACCOUNTADMIN;

-- Tasks and dynamic tables first, so nothing is running
ALTER TASK IF EXISTS RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES SUSPEND;
ALTER TASK IF EXISTS RETAIL_LAB.TASKS_DEMO.T_ROOT_HOURLY SUSPEND;

DROP DATABASE IF EXISTS RETAIL_RAW;
DROP DATABASE IF EXISTS RETAIL_STAGING;
DROP DATABASE IF EXISTS RETAIL_MARTS;
DROP DATABASE IF EXISTS RETAIL_DEV;
DROP DATABASE IF EXISTS RETAIL_LAB;

DROP WAREHOUSE IF EXISTS LOAD_WH;
DROP WAREHOUSE IF EXISTS TRANSFORM_WH;
DROP WAREHOUSE IF EXISTS BI_WH;
DROP WAREHOUSE IF EXISTS LAB_WH;

DROP RESOURCE MONITOR IF EXISTS RM_RETAIL_MONTHLY;
DROP RESOURCE MONITOR IF EXISTS RM_TRANSFORM_DAILY;

DROP INTEGRATION IF EXISTS GCS_NOTIF;
DROP INTEGRATION IF EXISTS GCS_INT;

DROP USER IF EXISTS SVC_RETAIL_PIPELINE;

DROP ROLE IF EXISTS RETAIL_ANALYST;
DROP ROLE IF EXISTS RETAIL_ENGINEER;
DROP ROLE IF EXISTS RETAIL_ADMIN;

-- Stage 7 objects (GOV database, FR_/AR_ roles, GOVERNANCE_ADMIN) are NOT managed by this
-- Terraform and survive. deploy.py --phase post re-runs the Stage 7 scripts to re-wire them.
SHOW DATABASES LIKE 'RETAIL_%';   -- should be empty now
