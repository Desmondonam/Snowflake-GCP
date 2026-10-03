/* RAW common objects: schema, shared file formats, the landing stage.
   Deploy-only version of stage_02 lessons 02 (step 4) and 03 (part A). Idempotent.
   Requires the GCS_INT integration (Terraform) and USAGE on it for RETAIL_ENGINEER. */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.COMMON COMMENT = 'Shared file formats and the landing stage';

CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_CSV
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL') EMPTY_FIELD_AS_NULL = TRUE TRIM_SPACE = TRUE
  COMMENT = 'Header row, optional double quotes, empty = NULL';

CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_JSON
  TYPE = JSON STRIP_OUTER_ARRAY = FALSE COMMENT = 'NDJSON';

CREATE OR REPLACE FILE FORMAT RETAIL_RAW.COMMON.FF_PARQUET
  TYPE = PARQUET USE_LOGICAL_TYPE = TRUE COMMENT = 'Parquet';

CREATE STAGE IF NOT EXISTS RETAIL_RAW.COMMON.LANDING
  URL = 'gcs://YOUR_PROJECT_ID-landing/'
  STORAGE_INTEGRATION = GCS_INT
  COMMENT = 'Root of the landing bucket; each pipe reads its own <source>/ prefix';

LIST @RETAIL_RAW.COMMON.LANDING PATTERN = '.*erp_stores.*';
