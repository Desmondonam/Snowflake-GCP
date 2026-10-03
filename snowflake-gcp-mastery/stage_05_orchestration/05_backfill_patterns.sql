/* =============================================================================
   Stage 5 · Lesson 05 — Backfilling a month of POS data SAFELY
   -----------------------------------------------------------------------------
   Scenario: the POS vendor re-sends September with corrected prices. You must
   reload and rebuild without breaking dashboards or creating duplicates.

   The safe recipe
     1. Protect: zero-copy clone the affected tables (instant rollback point)
     2. Land:    the corrected files go to a NEW prefix (landing is immutable)
     3. Load:    COPY INTO RAW for exactly that prefix, on a right-sized warehouse
     4. Rebuild: dbt re-merges the date range (backfill vars) — idempotent
     5. Verify:  reconciliation + row counts vs the clone
     6. Clean:   drop the clone after sign-off
   HOW TO RUN: read first; run statement by statement only when you have files to backfill.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

-- 1. Protect
CREATE OR REPLACE TABLE RETAIL_RAW.POS.SALES_LINES_BKP_BEFORE_BACKFILL CLONE RETAIL_RAW.POS.SALES_LINES;
CREATE OR REPLACE TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE_BKP CLONE RETAIL_MARTS.SALES.FCT_SALES_LINE;

-- 2. Land (Git Bash): corrected files in a new, clearly named prefix, e.g.
--    gs://YOUR_PROJECT_ID-landing/pos_sales_resend/2026-09/dt=2026-09-01/store_S001.csv …
--    (a separate prefix means the regular Snowpipe does NOT pick them up)

-- 3. Load explicitly, with a temporary bigger warehouse
ALTER WAREHOUSE LOAD_WH SET WAREHOUSE_SIZE = SMALL;
ALTER SESSION SET QUERY_TAG = 'backfill_pos_2026_09';

COPY INTO RETAIL_RAW.POS.SALES_LINES
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/pos_sales_resend/2026-09/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv'
ON_ERROR = 'ABORT_STATEMENT';     -- for a planned backfill, fail loudly rather than skip

ALTER WAREHOUSE LOAD_WH SET WAREHOUSE_SIZE = XSMALL;
ALTER SESSION UNSET QUERY_TAG;

-- The new rows have newer _loaded_at, so staging's dedupe (latest load wins) prefers them.

-- 4. Rebuild (PowerShell, dbt project folder):
--    dbt build --target prod -s fct_sales_line+ --vars "{backfill_start: '2026-09-01', backfill_end: '2026-09-30'}"

-- 5. Verify
SELECT 'before' AS v, SUM(net_amount) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE_BKP WHERE sale_date BETWEEN '2026-09-01' AND '2026-09-30'
UNION ALL
SELECT 'after', SUM(net_amount) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE WHERE sale_date BETWEEN '2026-09-01' AND '2026-09-30';
SELECT status, COUNT(*) FROM RETAIL_MARTS.OPS.RPT_POS_RECONCILIATION
WHERE business_date BETWEEN '2026-09-01' AND '2026-09-30' GROUP BY 1;

-- Rollback if needed (instant, metadata only):
--   ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE SWAP WITH RETAIL_MARTS.SALES.FCT_SALES_LINE_BKP;

-- 6. Clean up after sign-off
DROP TABLE IF EXISTS RETAIL_RAW.POS.SALES_LINES_BKP_BEFORE_BACKFILL;
DROP TABLE IF EXISTS RETAIL_MARTS.SALES.FCT_SALES_LINE_BKP;

/* Other backfill tools to know
   * ALTER PIPE … REFRESH PREFIX = 'pos_sales/dt=2026-09-2' MODIFIED_AFTER = '…'  (≤ 7 days old files)
   * dbt microbatch models: dbt run --event-time-start 2026-09-01 --event-time-end 2026-10-01
   * Airflow: catchup / `airflow dags backfill` replays scheduled runs (each run = one business date). */
