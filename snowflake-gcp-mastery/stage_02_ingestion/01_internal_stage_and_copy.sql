/* =============================================================================
   Stage 2 · Lesson 01 — Internal stages, file formats and COPY INTO
   -----------------------------------------------------------------------------
   Loading in Snowflake is always two steps:
     1. put files in a STAGE (a named location for files)
     2. COPY INTO a table FROM the stage
   This lesson uses an INTERNAL stage (storage managed by Snowflake) so you can
   learn COPY before GCS is involved.

   HOW TO RUN
     a) Run PART A in a worksheet (role RETAIL_ENGINEER).
     b) Upload the sample files from PowerShell (repo root):
          snow stage copy stage_02_ingestion/sample_data/pos_sample.csv @RETAIL_LAB.INGEST.INTERNAL_STG/pos/ -c retail_engineer
          snow stage copy stage_02_ingestion/sample_data/pos_bad.csv    @RETAIL_LAB.INGEST.INTERNAL_STG/pos/ -c retail_engineer
        (or Snowsight: Data → Databases → RETAIL_LAB → INGEST → Stages → INTERNAL_STG → "+ Files")
     c) Continue with PART B onwards, statement by statement.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

/* ---------------------------------------------------------------------------
   PART A — Schema, file format, stage, target table
   --------------------------------------------------------------------------- */
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.INGEST;
USE SCHEMA RETAIL_LAB.INGEST;

-- A FILE FORMAT describes how to parse files. Define it once, reuse everywhere.
CREATE OR REPLACE FILE FORMAT FF_CSV
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'   -- values may be quoted: "1250.00", "Doha, QA"
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE;

-- Three kinds of internal stage:
--   @~                 your USER stage (private to you)
--   @%POS_SALES_LINES  the TABLE stage (one per table)
--   @INTERNAL_STG      a NAMED stage (shareable, grantable, best practice)
CREATE STAGE IF NOT EXISTS INTERNAL_STG FILE_FORMAT = FF_CSV COMMENT = 'Lesson uploads';

CREATE OR REPLACE TABLE POS_SALES_LINES (
  transaction_id   STRING,
  line_no          INT,
  store_id         STRING,
  sku              STRING,
  qty              NUMBER(10,2),
  unit_price       NUMBER(12,2),
  discount         NUMBER(12,2),
  loyalty_id       STRING,
  sold_at          TIMESTAMP_NTZ,
  promo_code       STRING,
  tender_type      STRING,
  -- lineage columns: where did each row come from and when did it arrive?
  _file_name       STRING,
  _file_row_number NUMBER,
  _loaded_at       TIMESTAMP_LTZ
);

-- >>> Now upload the two sample files (see HOW TO RUN, step b). <<<

/* ---------------------------------------------------------------------------
   PART B — Look at files BEFORE loading them
   --------------------------------------------------------------------------- */
LIST @INTERNAL_STG;      -- PUT/snow may gzip files on upload (.csv.gz); COPY reads both

-- You can SELECT from staged files directly with $1, $2 … (column positions).
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1, $2, $5, $6, $9
FROM @INTERNAL_STG/pos/ (FILE_FORMAT => 'FF_CSV');

/* ---------------------------------------------------------------------------
   PART C — Dry run with VALIDATION_MODE (loads nothing, reports errors)
   Note: VALIDATION_MODE can't be combined with a SELECT transformation, so
   the dry run targets the 11 business columns only.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TEMPORARY TABLE POS_DRY_RUN LIKE POS_SALES_LINES;
ALTER TABLE POS_DRY_RUN DROP COLUMN _file_name, _file_row_number, _loaded_at;

COPY INTO POS_DRY_RUN FROM @INTERNAL_STG/pos/
  FILE_FORMAT = (FORMAT_NAME = 'FF_CSV')
  VALIDATION_MODE = RETURN_ERRORS;          -- shows 'abc' and 'not-a-date' in pos_bad.csv

/* ---------------------------------------------------------------------------
   PART D — Real load with lineage columns and an error policy
   ON_ERROR options:
     ABORT_STATEMENT (default for COPY)  stop everything on the first error
     CONTINUE                            load good rows, skip bad rows
     SKIP_FILE                           skip any file with an error (default for Snowpipe)
     SKIP_FILE_10%                       skip a file if >10% of its rows are bad
   For RAW we prefer SKIP_FILE: a half-loaded file is worse than a missing one,
   because missing files are easy to detect and replay.
   --------------------------------------------------------------------------- */
COPY INTO POS_SALES_LINES
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
         METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
  FROM @INTERNAL_STG/pos/
)
FILE_FORMAT = (FORMAT_NAME = 'FF_CSV')
ON_ERROR = 'SKIP_FILE';
-- Result grid: pos_sample.csv LOADED (5 rows), pos_bad.csv LOAD_FAILED (names may end in .gz).

SELECT * FROM POS_SALES_LINES;

-- What exactly failed in the last COPY?
SELECT * FROM TABLE(VALIDATE(POS_SALES_LINES, JOB_ID => '_last'));

/* ---------------------------------------------------------------------------
   PART E — Load metadata: Snowflake remembers loaded files for 64 days
   --------------------------------------------------------------------------- */
COPY INTO POS_SALES_LINES
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @INTERNAL_STG/pos/)
FILE_FORMAT = (FORMAT_NAME = 'FF_CSV') ON_ERROR = 'SKIP_FILE';
-- "Copy executed with 0 files processed." The good file was already loaded,
-- and the bad file is still skipped. No duplicates.

-- FORCE = TRUE ignores load metadata → duplicates. Never use it on RAW without dedupe downstream.
-- COPY INTO POS_SALES_LINES FROM (...) FILE_FORMAT = (...) FORCE = TRUE;

/* ---------------------------------------------------------------------------
   PART F — ON_ERROR = CONTINUE for comparison
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TEMPORARY TABLE POS_CONTINUE LIKE POS_SALES_LINES;
COPY INTO POS_CONTINUE
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @INTERNAL_STG/pos/)
FILE_FORMAT = (FORMAT_NAME = 'FF_CSV')
PATTERN = '.*pos_bad.*'
ON_ERROR = 'CONTINUE';
SELECT * FROM POS_CONTINUE;   -- 2 good rows loaded, 2 bad rows silently dropped. Dangerous for money data.

/* ---------------------------------------------------------------------------
   PART G — Load history for this table
   --------------------------------------------------------------------------- */
SELECT file_name, status, row_count, row_parsed, first_error_message, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'RETAIL_LAB.INGEST.POS_SALES_LINES',
  START_TIME => DATEADD(hour, -2, CURRENT_TIMESTAMP())));

-- Tidy up the stage (REMOVE deletes staged files; PURGE = TRUE on COPY does it automatically).
-- REMOVE @INTERNAL_STG/pos/;
