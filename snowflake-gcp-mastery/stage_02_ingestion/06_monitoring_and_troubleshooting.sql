/* =============================================================================
   Stage 2 · Lesson 06 — Monitoring loads and troubleshooting Snowpipe
   -----------------------------------------------------------------------------
   Keep this file open whenever data "didn't arrive". Work top to bottom:
   file in GCS? → event received? → pipe running? → load errors? → permissions?
   HOW TO RUN: worksheet. Role RETAIL_ENGINEER (ACCOUNT_USAGE parts need RETAIL_ADMIN).
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

-- 1. Is the file actually in the stage path the pipe reads?
LIST @RETAIL_RAW.COMMON.LANDING/pos_sales/ PATTERN = '.*dt=2026-10-0.*';

-- 2. Is the pipe running, and is it receiving notifications?
SELECT PARSE_JSON(SYSTEM$PIPE_STATUS('RETAIL_RAW.POS.PIPE_POS_SALES')) AS status;
-- executionState     RUNNING | PAUSED | STOPPED_* (e.g. integration permissions lost)
-- pendingFileCount   files queued but not loaded yet
-- lastReceivedMessageTimestamp / lastForwardedMessageTimestamp
--                    if these are old while files keep arriving: Pub/Sub permissions or subscription problem

-- 3. Load outcome per file (last 24h). Statuses: LOADED, LOAD_FAILED, PARTIALLY_LOADED.
SELECT file_name, status, row_count, error_count, first_error_message, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'RETAIL_RAW.POS.SALES_LINES',
  START_TIME => DATEADD(hour, -24, CURRENT_TIMESTAMP())))
WHERE status <> 'Loaded'
ORDER BY last_load_time DESC;

-- 4. Row-level errors for a pipe over a time window.
SELECT * FROM TABLE(INFORMATION_SCHEMA.VALIDATE_PIPE_LOAD(
  PIPE_NAME  => 'RETAIL_RAW.POS.PIPE_POS_SALES',
  START_TIME => DATEADD(hour, -24, CURRENT_TIMESTAMP())));

-- 5. Did every expected file arrive? (expected = 20 stores per business day)
SELECT TO_DATE(REGEXP_SUBSTR(_file_name, 'dt=(\\d{4}-\\d{2}-\\d{2})', 1, 1, 'e', 1)) AS business_date,
       COUNT(DISTINCT store_id) AS stores_loaded,
       COUNT(DISTINCT _file_name) AS files_loaded
FROM RETAIL_RAW.POS.SALES_LINES
GROUP BY 1
HAVING COUNT(DISTINCT store_id) < 20
ORDER BY 1 DESC;

-- 6. Pipe cost (ACCOUNT_USAGE lags up to ~3h). Snowpipe bills serverless compute + a per-file overhead,
--    which is why thousands of tiny files are expensive.
USE ROLE RETAIL_ADMIN;
SELECT pipe_name, DATE_TRUNC('day', start_time) AS day,
       SUM(credits_used) AS credits, SUM(files_inserted) AS files, SUM(bytes_inserted) / 1e6 AS mb
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 2 DESC, 3 DESC;

-- 7. Account-wide load history (also ACCOUNT_USAGE, 365 days)
SELECT table_name, status, COUNT(*) AS files, SUM(row_count) AS rows_
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE last_load_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 1, 2;

/* TROUBLESHOOTING TABLE
   Symptom                                         | Likely cause → fix
   ------------------------------------------------+-------------------------------------------------------
   pendingFileCount stuck > 0                      | warehouse-less, so not compute: check error_count above
   lastReceivedMessageTimestamp never changes      | GCS_NOTIF SA lacks pubsub.subscriber / monitoring.viewer,
                                                   |   or you pulled the messages yourself with --auto-ack
   executionState = STOPPED_*                      | integration disabled/dropped or permissions removed
   LOAD_FAILED "Numeric value 'abc' is not recognized" | bad source file → fix at source, re-upload under a new name
   Files exist but never loaded, uploaded before pipe | ALTER PIPE … REFRESH (≤ 7 days) or COPY INTO (older)
   Loaded twice                                    | pipe recreated + REFRESH, or COPY + pipe on the same files
                                                   |   → dedupe in staging (QUALIFY ROW_NUMBER()) */
