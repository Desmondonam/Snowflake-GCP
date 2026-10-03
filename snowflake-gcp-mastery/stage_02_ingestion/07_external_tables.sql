/* =============================================================================
   Stage 2 · Lesson 07 — External tables: query GCS files without loading them
   -----------------------------------------------------------------------------
   When to use: exploring a big archive, rarely queried history, or data another
   engine also owns. Queries are slower than native tables (no micro-partition
   metadata beyond what you define), so for hot data you still load.
   PREREQUISITE: the 90-day backfill is in GCS (capstone 2) — or at least a few days.
   HOW TO RUN: worksheet. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LAB_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.EXTERNAL;
USE SCHEMA RETAIL_LAB.EXTERNAL;

-- An external table exposes each file row as VALUE (a VARIANT: c1, c2, … for CSV).
-- Partition columns derived from the path let Snowflake skip whole folders.
CREATE OR REPLACE EXTERNAL TABLE EXT_POS_SALES (
  business_date DATE   AS TO_DATE(REGEXP_SUBSTR(METADATA$FILENAME, 'dt=(\\d{4}-\\d{2}-\\d{2})', 1, 1, 'e', 1)),
  transaction_id STRING AS (VALUE:c1::STRING),
  store_id       STRING AS (VALUE:c3::STRING),
  sku            STRING AS (VALUE:c4::STRING),
  qty            NUMBER(10,2) AS (TRY_TO_NUMBER(VALUE:c5::STRING, 10, 2)),
  unit_price     NUMBER(12,2) AS (TRY_TO_NUMBER(VALUE:c6::STRING, 12, 2)),
  discount       NUMBER(12,2) AS (TRY_TO_NUMBER(VALUE:c7::STRING, 12, 2))
)
PARTITION BY (business_date)
LOCATION = @RETAIL_RAW.COMMON.LANDING/pos_sales/
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv'
AUTO_REFRESH = FALSE          -- on GCS, auto-refresh would need its own notification integration
COMMENT = 'Read-only view over landing files';

-- External tables keep a list of files; refresh it after new files land.
ALTER EXTERNAL TABLE EXT_POS_SALES REFRESH;

SELECT business_date, store_id, SUM(qty * unit_price - discount) AS net_sales
FROM EXT_POS_SALES
WHERE business_date = (SELECT MAX(business_date) FROM EXT_POS_SALES)   -- partition pruning on the path
GROUP BY 1, 2 ORDER BY 2;

-- Which files back the table?
SELECT * FROM TABLE(INFORMATION_SCHEMA.EXTERNAL_TABLE_FILES(TABLE_NAME => 'EXT_POS_SALES')) LIMIT 20;

/* COMPARE (write the numbers in the README):
   * Same aggregate on RETAIL_RAW.POS.SALES_LINES vs EXT_POS_SALES: time and bytes scanned.
   * Stage 8 introduces ICEBERG tables: open format on your bucket, but with full Snowflake
     performance and DML. They replace most external-table use cases today. */
