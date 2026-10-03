/* =============================================================================
   Stage 8 · Lesson 03 — Apache Iceberg tables on your own GCS bucket
   -----------------------------------------------------------------------------
   A Snowflake-managed Iceberg table stores Parquet data + Iceberg metadata in
   YOUR bucket (gs://<project>-lakehouse/iceberg/...). Snowflake gives full DML
   and performance; other engines (BigQuery, Spark, Trino) can read the same files.
   Answer to "we don't want lock-in": open format, our storage, Snowflake as one engine.

   PREREQUISITE: lakehouse bucket exists (G1), YOUR_PROJECT_ID replaced.
   HOW TO RUN: worksheet, step by step (one GCP grant in the middle).
   ============================================================================= */
USE ROLE ACCOUNTADMIN;

-- 1. External volume = where Iceberg files go
CREATE EXTERNAL VOLUME IF NOT EXISTS GCS_ICEBERG_VOL
  STORAGE_LOCATIONS = ((
    NAME = 'gcs-us-central1'
    STORAGE_PROVIDER = 'GCS'
    STORAGE_BASE_URL = 'gcs://YOUR_PROJECT_ID-lakehouse/iceberg/'
  ))
  ALLOW_WRITES = TRUE
  COMMENT = 'Snowflake-managed Iceberg tables in the RetailOne lakehouse bucket';

DESC EXTERNAL VOLUME GCS_ICEBERG_VOL;
-- In the STORAGE_LOCATION_1 row, the JSON contains "STORAGE_GCP_SERVICE_ACCOUNT": "...". Copy it.

/* >>> Git Bash:  bash gcp/grant_snowflake_access.sh iceberg <STORAGE_GCP_SERVICE_ACCOUNT>
       (custom role with objects get/list/create/delete + buckets.get on the lakehouse bucket) <<< */

SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('GCS_ICEBERG_VOL');     -- "success": true when permissions are right

GRANT USAGE ON EXTERNAL VOLUME GCS_ICEBERG_VOL TO ROLE RETAIL_ENGINEER;

-- 2. Create the Iceberg table and load it
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.LAKE COMMENT = 'Open-format (Iceberg) marts readable by other engines';

CREATE ICEBERG TABLE IF NOT EXISTS RETAIL_MARTS.LAKE.FCT_SALES_DAILY (
  sale_date     DATE,
  store_id      STRING,
  store_region  STRING,
  sales_channel STRING,
  net_sales     NUMBER(18, 2),
  margin        NUMBER(18, 2),
  lines         NUMBER(18, 0)
)
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'GCS_ICEBERG_VOL'
  BASE_LOCATION = 'fct_sales_daily'
  COMMENT = 'Daily sales per store, Iceberg format in GCS';

-- Idempotent refresh (run daily from Airflow/Task, or materialise from dbt with table_format='iceberg')
MERGE INTO RETAIL_MARTS.LAKE.FCT_SALES_DAILY t
USING (
  SELECT sale_date, store_id, store_region, sales_channel,
         SUM(net_amount) AS net_sales, SUM(margin_amount) AS margin, COUNT(*) AS lines
  FROM RETAIL_MARTS.SALES.FCT_SALES_LINE
  GROUP BY 1, 2, 3, 4
) s
  ON t.sale_date = s.sale_date AND t.store_id = s.store_id AND t.sales_channel = s.sales_channel
WHEN MATCHED THEN UPDATE SET t.net_sales = s.net_sales, t.margin = s.margin, t.lines = s.lines
WHEN NOT MATCHED THEN INSERT VALUES (s.sale_date, s.store_id, s.store_region, s.sales_channel, s.net_sales, s.margin, s.lines);

SELECT store_region, SUM(net_sales) FROM RETAIL_MARTS.LAKE.FCT_SALES_DAILY GROUP BY 1;

-- 3. Where are the files? (metadataLocation = the Iceberg metadata JSON other engines read)
SELECT PARSE_JSON(SYSTEM$GET_ICEBERG_TABLE_INFORMATION('RETAIL_MARTS.LAKE.FCT_SALES_DAILY')) AS info;
-- Copy metadataLocation (gcs://…/metadata/000NN-….metadata.json) for the BigQuery step;
-- BigQuery wants it with the gs:// prefix instead of gcs://.

/* >>> Git Bash:  gcloud storage ls -r gs://YOUR_PROJECT_ID-lakehouse/iceberg/ | head -40
       You'll see data/*.parquet and metadata/*.json — plain open files in your bucket. <<<

   Then continue with 03b_bigquery_read_iceberg.sql (BigQuery console).

   NOTES
   * Storage for Iceberg tables is billed by Google (your bucket), not Snowflake.
   * Each commit writes a new metadata.json; readers that pin a metadata file (BigQuery external tables)
     need it refreshed — or use a catalog both sides understand (Snowflake Open Catalog / Polaris, BigLake metastore).
   * dbt: {{ config(materialized='table', table_format='iceberg', external_volume='GCS_ICEBERG_VOL') }} */
