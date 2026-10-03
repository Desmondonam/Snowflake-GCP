/* =============================================================================
   Stage 2 · Lesson 03 — External stage on GCS, shared file formats, COPY from GCS
   -----------------------------------------------------------------------------
   PREREQUISITE: lesson 02 (integration + RETAIL_RAW.COMMON.LANDING stage).
   UPLOAD the sample file to the lab/ prefix first (Git Bash, repo root):
     gcloud storage cp stage_02_ingestion/sample_data/pos_sample.csv \
       gs://YOUR_PROJECT_ID-landing/lab/pos_sales/dt=2026-10-01/store_S001.csv
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

/* ---------------------------------------------------------------------------
   PART A — Shared file formats in RETAIL_RAW.COMMON (used by every RAW pipe)
   --------------------------------------------------------------------------- */
CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_CSV
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL') EMPTY_FIELD_AS_NULL = TRUE TRIM_SPACE = TRUE
  COMMENT = 'Header row, optional double quotes, empty = NULL';

CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_JSON
  TYPE = JSON STRIP_OUTER_ARRAY = FALSE   -- our JSON files are newline-delimited (one object per line)
  COMMENT = 'NDJSON';

CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_PARQUET
  TYPE = PARQUET USE_LOGICAL_TYPE = TRUE  -- read Parquet timestamp/decimal logical types correctly
  COMMENT = 'Parquet';

SHOW FILE FORMATS IN SCHEMA RETAIL_RAW.COMMON;

/* ---------------------------------------------------------------------------
   PART B — Browse and query files in GCS without loading them
   --------------------------------------------------------------------------- */
LIST @RETAIL_RAW.COMMON.LANDING/lab/;

SELECT METADATA$FILENAME AS file, METADATA$FILE_ROW_NUMBER AS row_no,
       METADATA$FILE_LAST_MODIFIED AS file_modified,
       $1 AS transaction_id, $4 AS sku, $5 AS qty, $9 AS sold_at
FROM @RETAIL_RAW.COMMON.LANDING/lab/pos_sales/ (FILE_FORMAT => 'RETAIL_RAW.COMMON.FF_CSV');

-- Partition value from the path (dt=YYYY-MM-DD) — useful for lineage and external tables.
SELECT DISTINCT METADATA$FILENAME,
       TO_DATE(REGEXP_SUBSTR(METADATA$FILENAME, 'dt=(\\d{4}-\\d{2}-\\d{2})', 1, 1, 'e', 1)) AS dt
FROM @RETAIL_RAW.COMMON.LANDING/lab/pos_sales/ (FILE_FORMAT => 'RETAIL_RAW.COMMON.FF_CSV');

/* ---------------------------------------------------------------------------
   PART C — COPY INTO from GCS into the lab table (same table as lesson 01)
   PATTERN filters files by regex; it is matched against the path.
   --------------------------------------------------------------------------- */
COPY INTO RETAIL_LAB.INGEST.POS_SALES_LINES
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
         METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
  FROM @RETAIL_RAW.COMMON.LANDING/lab/pos_sales/
)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*dt=2026-10-01/.*[.]csv'
ON_ERROR = 'SKIP_FILE';

SELECT _file_name, COUNT(*) FROM RETAIL_LAB.INGEST.POS_SALES_LINES GROUP BY 1;

/* ---------------------------------------------------------------------------
   PART D — Other useful COPY options (read, then try the ones you're curious about)
     PURGE = TRUE               delete files from the stage after a successful load
                                (needs storage.objects.delete — we deliberately DON'T grant it: landing is immutable)
     MATCH_BY_COLUMN_NAME       map Parquet/JSON/CSV-with-header columns by name instead of position
     SIZE_LIMIT = 1000000000    stop after ~1 GB in one COPY (useful for controlled backfills)
     FILES = ('a.csv','b.csv')  load an explicit list of files
     LOAD_UNCERTAIN_FILES       load files whose load status is unknown (older than 64 days)
   File sizing rule: aim for 100–250 MB compressed per file. Thousands of tiny
   files waste overhead; one 10 GB file can't be parallelised well.
   --------------------------------------------------------------------------- */
