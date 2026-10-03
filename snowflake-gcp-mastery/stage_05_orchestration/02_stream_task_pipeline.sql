/* =============================================================================
   Stage 5 · Lesson 02 — Near-real-time path: Snowpipe → STREAM → TASK → clean table
   -----------------------------------------------------------------------------
   POS lines land in RETAIL_RAW.POS.SALES_LINES (Snowpipe, ~1 min). An append-only
   stream tracks new rows; a task wakes every 5 minutes, but only spends warehouse
   time when the stream has data (WHEN SYSTEM$STREAM_HAS_DATA), and MERGEs the
   new rows (deduplicated) into a clean table used by the live-stock dynamic table.

   HOW TO RUN: snow sql -c retail_engineer -f stage_05_orchestration/02_stream_task_pipeline.sql
               then watch with the queries at the bottom.
   COST: the task's WHEN check runs in cloud services; the warehouse only resumes
         when there is data. SUSPEND the task at the end of your session.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_STAGING.REALTIME COMMENT = 'Near-real-time objects maintained by tasks / dynamic tables';

-- 1. Target table
CREATE TABLE IF NOT EXISTS RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN (
  transaction_id STRING, line_no INT, store_id STRING, sku STRING,
  qty NUMBER(10,2), unit_price NUMBER(12,2), discount NUMBER(12,2),
  loyalty_id STRING, sold_at TIMESTAMP_NTZ,
  _loaded_at TIMESTAMP_LTZ, _merged_at TIMESTAMP_LTZ
) CLUSTER BY (TO_DATE(sold_at), store_id)
  COMMENT = 'Deduplicated POS lines, refreshed every 5 minutes by T_MERGE_POS_SALES';

-- 2. Stream on RAW (append-only: RAW is insert-only by design).
--    SHOW_INITIAL_ROWS = TRUE → the first task run also loads everything already in RAW.
CREATE STREAM IF NOT EXISTS RETAIL_RAW.POS.SALES_LINES_STRM
  ON TABLE RETAIL_RAW.POS.SALES_LINES
  APPEND_ONLY = TRUE
  SHOW_INITIAL_ROWS = TRUE
  COMMENT = 'Consumed only by RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES';

-- 3. Task: scheduled MERGE, skipped when there is nothing new
CREATE OR REPLACE TASK RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE = '5 MINUTE'
  COMMENT = 'Near-real-time POS lines for live stock'
  WHEN SYSTEM$STREAM_HAS_DATA('RETAIL_RAW.POS.SALES_LINES_STRM')
AS
MERGE INTO RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN t
USING (
  SELECT * FROM RETAIL_RAW.POS.SALES_LINES_STRM
  QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id, line_no ORDER BY _loaded_at DESC) = 1
) s
  ON t.transaction_id = s.transaction_id AND t.line_no = s.line_no
WHEN MATCHED THEN UPDATE SET
  t.qty = s.qty, t.unit_price = s.unit_price, t.discount = s.discount,
  t._loaded_at = s._loaded_at, t._merged_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
  (transaction_id, line_no, store_id, sku, qty, unit_price, discount, loyalty_id, sold_at, _loaded_at, _merged_at)
VALUES
  (s.transaction_id, s.line_no, s.store_id, s.sku, s.qty, s.unit_price, s.discount, s.loyalty_id, s.sold_at,
   s._loaded_at, CURRENT_TIMESTAMP());

-- 4. Tasks are created SUSPENDED. Resume to start the schedule.
ALTER TASK RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES RESUME;

-- 5. Don't wait 5 minutes for the first run: execute it now.
EXECUTE TASK RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES;

/* ---------------------------------------------------------------------------
   WATCH IT (run these after ~1 minute, and again after uploading a new day:
     python capstone_retail_platform/data_generator/generate.py new-day --upload )
   --------------------------------------------------------------------------- */
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(RETAIL_STAGING.INFORMATION_SCHEMA.TASK_HISTORY(
  TASK_NAME => 'T_MERGE_POS_SALES', SCHEDULED_TIME_RANGE_START => DATEADD(hour, -2, CURRENT_TIMESTAMP())))
ORDER BY scheduled_time DESC;
-- state SKIPPED = the WHEN condition was false (no new data) → no warehouse cost.

SELECT COUNT(*) AS clean_rows, MAX(_merged_at) AS last_merge FROM RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN;
SELECT SYSTEM$STREAM_HAS_DATA('RETAIL_RAW.POS.SALES_LINES_STRM') AS pending;

/* End of session (keeps credits safe):
   ALTER TASK RETAIL_STAGING.REALTIME.T_MERGE_POS_SALES SUSPEND;

   SERVERLESS alternative: omit WAREHOUSE and Snowflake sizes the compute for you
   (needs EXECUTE MANAGED TASK, granted in Capstone 1):
     CREATE OR REPLACE TASK … USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL' SCHEDULE = '5 MINUTE' … */
