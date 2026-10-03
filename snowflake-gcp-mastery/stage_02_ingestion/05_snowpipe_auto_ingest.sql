/* =============================================================================
   Stage 2 · Lesson 05 — Snowpipe auto-ingest from GCS (lab version)
   -----------------------------------------------------------------------------
   Snowpipe = a COPY statement that Snowflake runs for you, serverlessly, every
   time a matching file lands. On GCP the trigger chain is:

     file lands in gs://<landing>/lab/pos_sales/...
       → bucket notification (OBJECT_FINALIZE) → Pub/Sub topic → subscription
       → GCS_NOTIF integration → every AUTO_INGEST pipe whose stage path matches
       → COPY INTO the pipe's table (serverless compute, billed per second + per file)

   PREREQUISITE: lesson 02 (both integrations + grants), lesson 03 (file formats).
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;
USE SCHEMA RETAIL_LAB.INGEST;

-- A separate target table so you can see exactly what the pipe loads.
CREATE OR REPLACE TABLE POS_SALES_PIPED LIKE RETAIL_LAB.INGEST.POS_SALES_LINES;

CREATE OR REPLACE PIPE PIPE_LAB_POS_SALES
  AUTO_INGEST = TRUE
  INTEGRATION = 'GCS_NOTIF'
  COMMENT = 'Lab: loads lab/pos_sales/*.csv'
AS
COPY INTO RETAIL_LAB.INGEST.POS_SALES_PIPED
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
         METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
  FROM @RETAIL_RAW.COMMON.LANDING/lab/pos_sales/
)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv'
ON_ERROR = 'SKIP_FILE';

SHOW PIPES IN SCHEMA RETAIL_LAB.INGEST;
SELECT SYSTEM$PIPE_STATUS('RETAIL_LAB.INGEST.PIPE_LAB_POS_SALES');
-- Expect "executionState":"RUNNING". notificationChannelName = your subscription.

/* ---------------------------------------------------------------------------
   Files that were ALREADY in the bucket before the pipe existed are not loaded
   automatically (no event will come for them). REFRESH queues files staged in
   the last 7 days. For older files use a one-off COPY INTO.
   --------------------------------------------------------------------------- */
ALTER PIPE PIPE_LAB_POS_SALES REFRESH;
-- Wait ~30–60 seconds, then:
SELECT _file_name, COUNT(*) FROM POS_SALES_PIPED GROUP BY 1;

/* >>> Now upload NEW files and watch them arrive by themselves (Git Bash):
     gcloud storage cp stage_02_ingestion/sample_data/pos_sample.csv \
       gs://YOUR_PROJECT_ID-landing/lab/pos_sales/dt=2026-10-02/store_S002.csv
     gcloud storage cp stage_02_ingestion/sample_data/pos_bad.csv \
       gs://YOUR_PROJECT_ID-landing/lab/pos_sales/dt=2026-10-02/store_S003.csv
   Wait about a minute. <<< */

SELECT _file_name, COUNT(*), MAX(_loaded_at) FROM POS_SALES_PIPED GROUP BY 1 ORDER BY 3 DESC;

-- What did the pipe do? (status LOADED / LOAD_FAILED and the first error)
SELECT file_name, status, row_count, first_error_message, pipe_received_time, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'RETAIL_LAB.INGEST.POS_SALES_PIPED',
  START_TIME => DATEADD(hour, -1, CURRENT_TIMESTAMP())))
ORDER BY last_load_time DESC;

/* ---------------------------------------------------------------------------
   Pausing, and the one rule about changing a pipe
   --------------------------------------------------------------------------- */
ALTER PIPE PIPE_LAB_POS_SALES SET PIPE_EXECUTION_PAUSED = TRUE;    -- stop loading (events still queue for 14 days)
SELECT SYSTEM$PIPE_STATUS('RETAIL_LAB.INGEST.PIPE_LAB_POS_SALES'); -- PAUSED
ALTER PIPE PIPE_LAB_POS_SALES SET PIPE_EXECUTION_PAUSED = FALSE;

/* RULE: CREATE OR REPLACE PIPE resets the pipe's load history (kept 14 days per pipe).
   A later REFRESH would then reload files → duplicates. To change a pipe safely:
     1) pause it, 2) wait for pendingFileCount = 0, 3) recreate it,
     4) ALTER PIPE … REFRESH MODIFIED_AFTER = '<timestamp of the pause>'   */

-- Clean up the lab pipe when you are done (it costs nothing idle, but keep things tidy).
-- DROP PIPE PIPE_LAB_POS_SALES;

/* ---------------------------------------------------------------------------
   SNOWPIPE STREAMING (concept — used in the final capstone stretch goal)
   No files at all: an SDK client (Java/Python) or the Kafka connector writes ROWS
   through a channel straight into a table, with second-level latency.
     Files on a schedule / per event, minutes ok   → Snowpipe (this lesson)
     Rows from Kafka / Pub/Sub, seconds matter      → Snowpipe Streaming
     Big historical backfill, you control timing    → COPY INTO on a warehouse
   --------------------------------------------------------------------------- */
