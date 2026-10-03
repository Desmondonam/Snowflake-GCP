/* =============================================================================
   Stage 5 · Lesson 04 — Dynamic Tables: declare the result, Snowflake keeps it fresh
   -----------------------------------------------------------------------------
   You write a SELECT and a TARGET_LAG ("never more than 5 minutes stale").
   Snowflake works out the dependency graph and refreshes INCREMENTALLY when it can.
   One statement replaces a stream + task + MERGE pipeline.

   Capstone 5 deliverable: RETAIL_MARTS.OPS.STORE_STOCK_LIVE (live stock per store × sku).

   PREREQUISITE: lesson 02 (REALTIME.SALES_LINES_CLEAN fed by the task).
   HOW TO RUN: worksheet. Role RETAIL_ENGINEER.
   COST: each refresh resumes TRANSFORM_WH (60 s minimum). A 5-minute lag running all day
         ≈ 12 refreshes/hour. SUSPEND dynamic tables at the end of your session.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.OPS;

-- 1. Latest opening stock per store × sku (from the ERP snapshot)
CREATE OR REPLACE DYNAMIC TABLE RETAIL_STAGING.REALTIME.INVENTORY_LATEST
  TARGET_LAG = DOWNSTREAM          -- refresh only when something downstream needs it
  WAREHOUSE = TRANSFORM_WH
  REFRESH_MODE = AUTO
AS
SELECT snapshot_date, store_id, sku, opening_qty
FROM RETAIL_RAW.ERP.INVENTORY
QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id, sku ORDER BY snapshot_date DESC, _loaded_at DESC) = 1;

-- 2. Live stock = opening stock − units sold since the snapshot date (5-minute lag)
CREATE OR REPLACE DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE
  TARGET_LAG = '5 minutes'
  WAREHOUSE = TRANSFORM_WH
  REFRESH_MODE = AUTO
  COMMENT = 'Live stock per store × sku for flash sales. Lag ≤ 5 min.'
AS
SELECT
  i.store_id,
  i.sku,
  i.snapshot_date                         AS stock_date,
  i.opening_qty,
  COALESCE(SUM(s.qty), 0)                 AS units_sold_since_open,
  i.opening_qty - COALESCE(SUM(s.qty), 0) AS on_hand,
  MAX(s.sold_at)                          AS last_sale_at
FROM RETAIL_STAGING.REALTIME.INVENTORY_LATEST i
LEFT JOIN RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN s
  ON s.store_id = i.store_id
 AND s.sku = i.sku
 AND s.sold_at >= i.snapshot_date::TIMESTAMP_NTZ
GROUP BY i.store_id, i.sku, i.snapshot_date, i.opening_qty;

-- 3. Inspect: refresh mode chosen (INCREMENTAL or FULL) and why
SHOW DYNAMIC TABLES IN DATABASE RETAIL_MARTS;
SHOW DYNAMIC TABLES IN SCHEMA RETAIL_STAGING.REALTIME;   -- refresh_mode, refresh_mode_reason, scheduling_state

-- 4. Use it: which SKUs are about to run out?
SELECT store_id, sku, on_hand, units_sold_since_open, last_sale_at
FROM RETAIL_MARTS.OPS.STORE_STOCK_LIVE
WHERE on_hand <= 5
ORDER BY on_hand, units_sold_since_open DESC
LIMIT 20;

-- 5. Refresh history and lag
SELECT name, state, refresh_action, refresh_trigger, data_timestamp, refresh_start_time, refresh_end_time
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE name IN ('STORE_STOCK_LIVE', 'INVENTORY_LATEST')
ORDER BY refresh_start_time DESC
LIMIT 20;

-- Force a refresh now (e.g. right after uploading a new day)
ALTER DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE REFRESH;

-- 6. End of session: stop refreshing (and paying)
ALTER DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE SUSPEND;
ALTER DYNAMIC TABLE RETAIL_STAGING.REALTIME.INVENTORY_LATEST SUSPEND;
-- Next session: ALTER DYNAMIC TABLE … RESUME;

/* CHOOSING THE TOOL
   | Need                                                   | Use                          |
   |--------------------------------------------------------|------------------------------|
   | Declarative transform, minutes of lag, chains of SQL   | Dynamic Tables               |
   | Custom CDC logic, procedures, side effects, exact runs | Streams + Tasks              |
   | Aggregate over ONE table, always current, simple SQL   | Materialized view (Stage 6)  |
   | Cross-system flow (files, APIs, dbt, alerts, SLAs)     | Airflow / Cloud Composer     |
   dbt can also create dynamic tables: materialized='dynamic_table', target_lag='5 minutes'. */
