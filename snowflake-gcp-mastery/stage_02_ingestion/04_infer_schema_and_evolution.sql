/* =============================================================================
   Stage 2 · Lesson 04 — Schema detection (INFER_SCHEMA) and schema evolution
   -----------------------------------------------------------------------------
   Parquet/Avro/ORC (and CSV with headers) carry column names and types, so
   Snowflake can build the table for you and add new columns automatically.

   PREREQUISITE: generate sample data with the generator (writes locally only):
     python capstone_retail_platform/data_generator/generate.py backfill --days 65 --output-dir output_sample
   Upload two order files: one BEFORE and one AFTER the schema change (day 61 adds delivery_method):
     (Git Bash; use the dates that `ls output_sample/ecom_orders` shows: the 1st and the 65th)
     gcloud storage cp output_sample/ecom_orders/dt=<DAY1>/orders.parquet  gs://YOUR_PROJECT_ID-landing/lab/ecom_orders/dt=<DAY1>/orders.parquet
     gcloud storage cp output_sample/ecom_orders/dt=<DAY65>/orders.parquet gs://YOUR_PROJECT_ID-landing/lab/ecom_orders/dt=<DAY65>/orders.parquet
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;
USE SCHEMA RETAIL_LAB.INGEST;

-- 1. What does Snowflake detect? (one row per column)
SELECT column_name, type, nullable, expression, filenames
FROM TABLE(INFER_SCHEMA(
  LOCATION    => '@RETAIL_RAW.COMMON.LANDING/lab/ecom_orders/',
  FILE_FORMAT => 'RETAIL_RAW.COMMON.FF_PARQUET'));
-- Notice: delivery_method appears only in the newer file (see FILENAMES).

-- 2. Create a table from the detected schema (USING TEMPLATE).
CREATE OR REPLACE TABLE ORDERS_INFERRED
  USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY order_id)
    FROM TABLE(INFER_SCHEMA(
      LOCATION    => '@RETAIL_RAW.COMMON.LANDING/lab/ecom_orders/',
      FILE_FORMAT => 'RETAIL_RAW.COMMON.FF_PARQUET',
      FILES       => ('dt=<DAY1>/orders.parquet'))));   -- <- replace <DAY1>: build from the OLD file only
DESC TABLE ORDERS_INFERRED;   -- no delivery_method yet

-- 3. Turn on schema evolution and load BOTH files by column name.
ALTER TABLE ORDERS_INFERRED SET ENABLE_SCHEMA_EVOLUTION = TRUE;

COPY INTO ORDERS_INFERRED
FROM @RETAIL_RAW.COMMON.LANDING/lab/ecom_orders/
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_PARQUET')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = 'ABORT_STATEMENT';

DESC TABLE ORDERS_INFERRED;   -- delivery_method was ADDED automatically
SELECT delivery_method, COUNT(*) FROM ORDERS_INFERRED GROUP BY 1;   -- NULL for old rows

-- 4. INCLUDE_METADATA: lineage columns together with MATCH_BY_COLUMN_NAME.
ALTER TABLE ORDERS_INFERRED ADD COLUMN _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ;
TRUNCATE TABLE ORDERS_INFERRED;   -- note: TRUNCATE also clears the load metadata
COPY INTO ORDERS_INFERRED
FROM @RETAIL_RAW.COMMON.LANDING/lab/ecom_orders/
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_PARQUET')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (_file_name = METADATA$FILENAME,
                    _file_row_number = METADATA$FILE_ROW_NUMBER,
                    _loaded_at = METADATA$START_SCAN_TIME);
SELECT _file_name, COUNT(*), MIN(_loaded_at) FROM ORDERS_INFERRED GROUP BY 1;

/* DESIGN NOTES
   * In RAW we prefer an explicit DDL (reviewed in Git) + ENABLE_SCHEMA_EVOLUTION, rather than
     USING TEMPLATE at deploy time: templates need a file to exist before the table can be created.
   * Schema evolution only ADDS columns (and drops NOT NULL). Renames and type changes still need a
     human: detect them with a data contract at the staging boundary (Stage 7).
   * JSON sources sidestep the problem entirely: they land in a VARIANT column, and staging
     decides which keys to extract. */
