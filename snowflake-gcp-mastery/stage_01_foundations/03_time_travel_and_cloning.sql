/* =============================================================================
   Stage 1 · Lesson 03 — Time Travel, UNDROP and zero-copy cloning
   -----------------------------------------------------------------------------
   Scenario: a retailer tests a new margin calculation on a CLONE of production.
   Someone runs an UPDATE without a WHERE clause. We recover with Time Travel.

   HOW TO RUN: Snowsight worksheet, statement by statement. Role SYSADMIN.
   Session variables (SET x = ...) only live in this worksheet session.
   ============================================================================= */
USE ROLE SYSADMIN;
USE WAREHOUSE LAB_WH;
USE SCHEMA RETAIL_ANALYTICS.SANDBOX;

-- Fresh copy of ORDERS so the lesson is repeatable.
CREATE OR REPLACE TABLE ORDERS AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
SELECT COUNT(*) AS rows_, SUM(o_totalprice) AS total FROM ORDERS;   -- write the total down

/* ---------------------------------------------------------------------------
   PART A — The accident
   --------------------------------------------------------------------------- */
UPDATE ORDERS SET o_totalprice = 0;          -- oops: no WHERE clause
SET bad_update_qid = LAST_QUERY_ID();        -- remember the query ID of the mistake
SELECT $bad_update_qid;
SELECT SUM(o_totalprice) FROM ORDERS;        -- 0. Panic.

/* ---------------------------------------------------------------------------
   PART B — Time Travel: query the past
   Three ways to point at the past:
     AT(TIMESTAMP => ...)    a point in time
     AT(OFFSET => -N)        N seconds ago (the table must be older than N seconds)
     BEFORE(STATEMENT => id) just before a specific query ran  <- most precise
   --------------------------------------------------------------------------- */
SELECT SUM(o_totalprice) FROM ORDERS BEFORE(STATEMENT => $bad_update_qid);  -- the original total

-- Wait ~60 seconds after creating the table, then this also works:
-- SELECT SUM(o_totalprice) FROM ORDERS AT(OFFSET => -30);

/* ---------------------------------------------------------------------------
   PART C — Restore. Option 1: clone the past version, then SWAP (atomic, instant)
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE ORDERS_RESTORED CLONE ORDERS BEFORE(STATEMENT => $bad_update_qid);
SELECT SUM(o_totalprice) FROM ORDERS_RESTORED;       -- correct total
ALTER TABLE ORDERS SWAP WITH ORDERS_RESTORED;         -- names exchanged in one metadata operation
SELECT SUM(o_totalprice) FROM ORDERS;                 -- fixed
-- ORDERS_RESTORED now holds the broken version; drop it.
DROP TABLE ORDERS_RESTORED;

-- Option 2 (keeps the same table object and its grants/policies):
--   INSERT OVERWRITE INTO ORDERS SELECT * FROM ORDERS BEFORE(STATEMENT => $bad_update_qid);

/* ---------------------------------------------------------------------------
   PART D — UNDROP
   Dropped objects stay recoverable for the Time Travel retention period.
   --------------------------------------------------------------------------- */
SHOW TABLES HISTORY LIKE 'ORDERS%' IN SCHEMA RETAIL_ANALYTICS.SANDBOX;   -- see dropped_on
UNDROP TABLE ORDERS_RESTORED;
SHOW TABLES LIKE 'ORDERS%';
DROP TABLE ORDERS_RESTORED;

-- Works for schemas and databases too:
CREATE SCHEMA IF NOT EXISTS RETAIL_ANALYTICS.TO_BE_DROPPED;
DROP SCHEMA RETAIL_ANALYTICS.TO_BE_DROPPED;
UNDROP SCHEMA RETAIL_ANALYTICS.TO_BE_DROPPED;
DROP SCHEMA RETAIL_ANALYTICS.TO_BE_DROPPED;

/* ---------------------------------------------------------------------------
   PART E — Zero-copy cloning
   A clone copies METADATA only; both objects point at the same micro-partitions.
   You pay for storage only when one side changes data (new micro-partitions).
   --------------------------------------------------------------------------- */
CREATE OR REPLACE SCHEMA RETAIL_ANALYTICS.SANDBOX_DEV CLONE RETAIL_ANALYTICS.SANDBOX;

-- Test the "new margin calculation" on the clone only.
ALTER TABLE RETAIL_ANALYTICS.SANDBOX_DEV.ORDERS ADD COLUMN est_margin NUMBER(12,2);
UPDATE RETAIL_ANALYTICS.SANDBOX_DEV.ORDERS SET est_margin = o_totalprice * 0.23;

SELECT 'prod' AS env, COUNT(*) AS cols FROM RETAIL_ANALYTICS.INFORMATION_SCHEMA.COLUMNS
  WHERE table_schema = 'SANDBOX' AND table_name = 'ORDERS'
UNION ALL
SELECT 'dev', COUNT(*) FROM RETAIL_ANALYTICS.INFORMATION_SCHEMA.COLUMNS
  WHERE table_schema = 'SANDBOX_DEV' AND table_name = 'ORDERS';     -- dev has one more column

-- Storage view: clones share a CLONE_GROUP_ID with the original.
SELECT table_schema, table_name, id, clone_group_id, active_bytes, time_travel_bytes
FROM RETAIL_ANALYTICS.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_name = 'ORDERS' AND table_dropped IS NULL;

/* ---------------------------------------------------------------------------
   PART F — Retention settings
   Standard edition: max 1 day. Enterprise: up to 90 days for permanent tables.
   Longer retention = more storage cost for changed/deleted data.
   --------------------------------------------------------------------------- */
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS;
ALTER TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS SET DATA_RETENTION_TIME_IN_DAYS = 30;
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS;

-- Clean up the dev clone.
DROP SCHEMA RETAIL_ANALYTICS.SANDBOX_DEV;

/* After the retention period, data moves to FAIL-SAFE (7 days, permanent tables only).
   Fail-safe is NOT queryable by you: only Snowflake Support can recover from it. */
