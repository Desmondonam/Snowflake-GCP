/* =============================================================================
   Stage 1 · Lesson 04 — Permanent, transient and temporary tables (+ views)
   -----------------------------------------------------------------------------
   | Type      | Time Travel        | Fail-safe | Lives until        | Use for                  |
   |-----------|--------------------|-----------|--------------------|--------------------------|
   | Permanent | 0–90 days (Ent.)   | 7 days    | dropped            | RAW, MARTS               |
   | Transient | 0–1 day            | none      | dropped            | STAGING, rebuildable     |
   | Temporary | 0–1 day            | none      | end of the session | scratch inside a session |
   HOW TO RUN: worksheet or `snow sql -f`. Role SYSADMIN.
   ============================================================================= */
USE ROLE SYSADMIN;
USE WAREHOUSE LAB_WH;
USE SCHEMA RETAIL_ANALYTICS.SANDBOX;

CREATE OR REPLACE TABLE PERM_ORDERS AS
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 10000;

CREATE OR REPLACE TRANSIENT TABLE STG_ORDERS AS
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 10000;

CREATE OR REPLACE TEMPORARY TABLE TMP_ORDERS AS
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 10000;

-- The "kind" column shows TABLE / TRANSIENT / TEMPORARY; retention_time shows the Time Travel days.
SHOW TABLES LIKE '%ORDERS' IN SCHEMA RETAIL_ANALYTICS.SANDBOX;

-- Transient tables cannot keep more than 1 day of Time Travel. Uncomment to see the error:
-- ALTER TABLE STG_ORDERS SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- A whole schema or database can be transient: every table created in it is transient.
CREATE TRANSIENT SCHEMA IF NOT EXISTS RETAIL_ANALYTICS.SCRATCH;
CREATE OR REPLACE TABLE RETAIL_ANALYTICS.SCRATCH.T1 (id INT);
SHOW TABLES IN SCHEMA RETAIL_ANALYTICS.SCRATCH;    -- kind = TRANSIENT
DROP SCHEMA RETAIL_ANALYTICS.SCRATCH;

/* ---------------------------------------------------------------------------
   Views: a saved query. Secure views hide their definition and block some
   optimizer shortcuts that could leak data (required for data sharing, Stage 8).
   Materialized views store results and refresh automatically (Enterprise; Stage 6).
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW V_ORDERS_1996 AS
  SELECT o_orderkey, o_custkey, o_totalprice, o_orderdate
  FROM PERM_ORDERS
  WHERE o_orderdate BETWEEN '1996-01-01' AND '1996-12-31';

CREATE OR REPLACE SECURE VIEW SV_ORDERS_1996 AS
  SELECT o_orderkey, o_totalprice FROM PERM_ORDERS WHERE YEAR(o_orderdate) = 1996;

SHOW VIEWS IN SCHEMA RETAIL_ANALYTICS.SANDBOX;   -- is_secure column
SELECT GET_DDL('VIEW', 'V_ORDERS_1996');          -- you can see the SQL of your own views

-- Temporary tables disappear when you close the worksheet/session. Prove it:
-- open a NEW worksheet and run: SELECT COUNT(*) FROM RETAIL_ANALYTICS.SANDBOX.TMP_ORDERS;  -- does not exist
