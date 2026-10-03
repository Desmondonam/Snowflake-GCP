/* =============================================================================
   Stage 1 · Lesson 02 — Warehouses, billing and the three caches
   -----------------------------------------------------------------------------
   HOW TO RUN: Snowsight worksheet, statement by statement (you need to look at
   the timings and Query Profile). Role SYSADMIN, warehouse LAB_WH.
   After each SELECT, open: Query details (… menu → "View Query Profile").
   ============================================================================= */
USE ROLE SYSADMIN;
USE WAREHOUSE LAB_WH;
USE SCHEMA RETAIL_ANALYTICS.SANDBOX;

/* ---------------------------------------------------------------------------
   PART A — Warehouse sizes
   Size:      XS  S  M  L   XL  2XL 3XL 4XL  5XL  6XL
   Credits/h:  1  2  4  8   16  32  64  128  256  512
   Each step doubles compute AND cost per hour. If a query is CPU-bound it often
   runs ~2x faster on the next size up, so the cost per query stays similar.
   --------------------------------------------------------------------------- */
SHOW WAREHOUSES LIKE 'LAB_WH';

-- Resize instantly (running queries finish on the old size; new ones use the new size).
ALTER WAREHOUSE LAB_WH SET WAREHOUSE_SIZE = SMALL;
ALTER WAREHOUSE LAB_WH SET WAREHOUSE_SIZE = XSMALL;

-- Manually suspend / resume (you rarely need this with AUTO_SUSPEND/AUTO_RESUME).
ALTER WAREHOUSE LAB_WH SUSPEND;
ALTER WAREHOUSE LAB_WH RESUME IF SUSPENDED;

/* ---------------------------------------------------------------------------
   PART B — Cache 1: RESULT CACHE (cloud services layer, 24 hours)
   Same query text + same role privileges + data unchanged => result returned
   instantly, no warehouse needed, zero credits.
   --------------------------------------------------------------------------- */
-- TPC-H Query 1 on 60M rows. Run it, note the time.
SELECT l_returnflag, l_linestatus,
       SUM(l_quantity)                          AS sum_qty,
       SUM(l_extendedprice)                     AS sum_base_price,
       SUM(l_extendedprice * (1 - l_discount))  AS sum_disc_price,
       COUNT(*)                                 AS count_order
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
WHERE l_shipdate <= '1998-09-02'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Run the EXACT same query again. It should return in milliseconds.
-- Query Profile shows a single node: "QUERY RESULT REUSE".
SELECT l_returnflag, l_linestatus,
       SUM(l_quantity)                          AS sum_qty,
       SUM(l_extendedprice)                     AS sum_base_price,
       SUM(l_extendedprice * (1 - l_discount))  AS sum_disc_price,
       COUNT(*)                                 AS count_order
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
WHERE l_shipdate <= '1998-09-02'
GROUP BY 1, 2
ORDER BY 1, 2;

/* ---------------------------------------------------------------------------
   PART C — Cache 2: WAREHOUSE LOCAL DISK CACHE (lost when the warehouse suspends)
   Turn the result cache off for this session so we measure the warehouse.
   --------------------------------------------------------------------------- */
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Run 1 (warm-ish): data may already be on the warehouse SSD from Part B.
SELECT l_returnflag, SUM(l_extendedprice) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM GROUP BY 1;
-- Run 2: should be faster. Query Profile → "Percentage scanned from cache" is high.
SELECT l_returnflag, SUM(l_extendedprice) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM GROUP BY 1;

-- Suspend: the local cache is dropped.
ALTER WAREHOUSE LAB_WH SUSPEND;
-- Run 3 (cold): slower again; scanned-from-cache near 0%.
SELECT l_returnflag, SUM(l_extendedprice) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM GROUP BY 1;

-- Compare the three runs with SQL instead of eyeballing.
SELECT query_id, LEFT(query_text, 60) AS q, warehouse_size,
       total_elapsed_time / 1000 AS seconds,
       bytes_scanned, percentage_scanned_from_cache
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 20))
WHERE query_text ILIKE 'SELECT l_returnflag, SUM(l_extendedprice)%'
ORDER BY start_time;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

/* ---------------------------------------------------------------------------
   PART D — Cache 3: METADATA CACHE (cloud services)
   Snowflake stores row counts and per-column MIN/MAX for every micro-partition,
   so these are answered without a warehouse.
   --------------------------------------------------------------------------- */
ALTER WAREHOUSE LAB_WH SUSPEND;
SELECT COUNT(*), MIN(l_shipdate), MAX(l_shipdate) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM;
SHOW WAREHOUSES LIKE 'LAB_WH';   -- state is still SUSPENDED: no compute was used

/* ---------------------------------------------------------------------------
   PART E — Scale UP vs scale OUT (concept; multi-cluster needs Enterprise)
   Scale UP  (bigger size)          -> one heavy query runs faster / stops spilling.
   Scale OUT (more clusters, same size) -> more concurrent queries without queueing.
   --------------------------------------------------------------------------- */
CREATE WAREHOUSE IF NOT EXISTS DEMO_MC_WH
  WITH WAREHOUSE_SIZE = XSMALL MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3
       SCALING_POLICY = 'STANDARD' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
SHOW WAREHOUSES LIKE 'DEMO_MC_WH';   -- min_cluster_count / max_cluster_count columns
DROP WAREHOUSE DEMO_MC_WH;

/* ---------------------------------------------------------------------------
   PART F — How many credits have I used? (ACCOUNT_USAGE lags up to ~3 hours)
   Needs ACCOUNTADMIN or IMPORTED PRIVILEGES on the SNOWFLAKE database
   (granted to RETAIL_ADMIN in the capstone).
   --------------------------------------------------------------------------- */
-- USE ROLE ACCOUNTADMIN;
-- SELECT warehouse_name, DATE_TRUNC('day', start_time) AS day, SUM(credits_used) AS credits
-- FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
-- WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
-- GROUP BY 1, 2 ORDER BY 2, 1;
