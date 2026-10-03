/* =============================================================================
   CAPSTONE 2 — "Data lands itself": the RAW layer for every RetailOne source
   -----------------------------------------------------------------------------
   One schema per source system, one table + one auto-ingest pipe per feed.
   RAW rules: exact copy of the source, append-only, lineage columns on every row.

     source folder (gs://<landing>/...)  → table                          format
     pos_sales/                          → RETAIL_RAW.POS.SALES_LINES      CSV  (typed)
     pos_control/                        → RETAIL_RAW.POS.CONTROL_TOTALS   CSV  (typed)
     ecom_orders/                        → RETAIL_RAW.ECOM.ORDERS          Parquet (by name, schema evolution)
     reviews/                            → RETAIL_RAW.ECOM.REVIEWS         NDJSON (VARIANT)
     crm_customers/                      → RETAIL_RAW.CRM.CUSTOMERS        NDJSON (VARIANT)
     erp_products/                       → RETAIL_RAW.ERP.PRODUCTS         CSV
     erp_stores/                         → RETAIL_RAW.ERP.STORES           CSV
     erp_inventory/                      → RETAIL_RAW.ERP.INVENTORY        CSV
     ads/                                → RETAIL_RAW.ADS.AD_PERFORMANCE   NDJSON (VARIANT)
     web_events/                         → RETAIL_RAW.WEB.EVENTS           NDJSON (VARIANT)

   Why typed tables for CSV but VARIANT for JSON?
     CSV has no types or names → we must declare them, and a bad value should fail the file.
     JSON is self-describing and changes shape often → land it whole, type it in staging.

   PREREQUISITES: lessons 02 + 03 done (integrations, RETAIL_RAW.COMMON stage and file formats).
   HOW TO RUN:  snow sql -c retail_engineer -f stage_02_ingestion/capstone_02_raw_layer.sql
                (or worksheet → Run All). Rerunnable: IF NOT EXISTS everywhere.
   THEN:        upload data (README, capstone step 3). Pipes must exist BEFORE the upload.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.POS  COMMENT = 'Store point of sale';
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.ECOM COMMENT = 'Web shop';
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.CRM  COMMENT = 'Customers / loyalty';
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.ERP  COMMENT = 'Products, stores, inventory';
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.ADS  COMMENT = 'Google Ads, Meta';
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.WEB  COMMENT = 'Clickstream';

/* ===========================================================================
   POS
   =========================================================================== */
CREATE TABLE IF NOT EXISTS RETAIL_RAW.POS.SALES_LINES (
  transaction_id   STRING        COMMENT 'T-<store>-<yyyymmdd>-<n>; R- prefix = return',
  line_no          INT,
  store_id         STRING,
  sku              STRING,
  qty              NUMBER(10,2)  COMMENT 'negative for returns',
  unit_price       NUMBER(12,2),
  discount         NUMBER(12,2),
  loyalty_id       STRING        COMMENT 'NULL for anonymous shoppers',
  sold_at          TIMESTAMP_NTZ COMMENT 'store local time',
  promo_code       STRING,
  tender_type      STRING,
  _file_name       STRING,
  _file_row_number NUMBER,
  _loaded_at       TIMESTAMP_LTZ
) COMMENT = 'RAW POS line items, one file per store per day';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.POS.PIPE_POS_SALES
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'pos_sales/*.csv'
AS COPY INTO RETAIL_RAW.POS.SALES_LINES
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
             METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/pos_sales/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.POS.CONTROL_TOTALS (
  business_date    DATE,
  store_id         STRING,
  txn_count        INT,
  line_count       INT,
  gross_amount     NUMBER(14,2),
  discount_amount  NUMBER(14,2),
  net_amount       NUMBER(14,2),
  _file_name       STRING,
  _file_row_number NUMBER,
  _loaded_at       TIMESTAMP_LTZ
) COMMENT = 'POS Z-report totals per store-day: the source of truth for reconciliation';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.POS.PIPE_POS_CONTROL
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'pos_control/*.csv'
AS COPY INTO RETAIL_RAW.POS.CONTROL_TOTALS
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/pos_control/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv' ON_ERROR = 'SKIP_FILE';

/* ===========================================================================
   ECOM — orders in Parquet: load by column NAME, let new columns appear
   =========================================================================== */
CREATE TABLE IF NOT EXISTS RETAIL_RAW.ECOM.ORDERS (
  order_id         STRING,
  order_line       INT,
  web_customer_id  STRING,
  customer_email   STRING,
  sku              STRING,
  qty              NUMBER(10,2),
  unit_price       NUMBER(12,2),
  discount         NUMBER(12,2),
  ordered_at       TIMESTAMP_NTZ,
  order_status     STRING,
  ship_city        STRING,
  ship_country     STRING,
  _file_name       STRING,
  _file_row_number NUMBER,
  _loaded_at       TIMESTAMP_LTZ
) ENABLE_SCHEMA_EVOLUTION = TRUE
  COMMENT = 'RAW online order lines; new source columns are added automatically';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ECOM.PIPE_ECOM_ORDERS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'ecom_orders/*.parquet'
AS COPY INTO RETAIL_RAW.ECOM.ORDERS
FROM @RETAIL_RAW.COMMON.LANDING/ecom_orders/
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_PARQUET')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (_file_name = METADATA$FILENAME,
                    _file_row_number = METADATA$FILE_ROW_NUMBER,
                    _loaded_at = METADATA$START_SCAN_TIME)
PATTERN = '.*[.]parquet' ON_ERROR = 'SKIP_FILE';

/* ===========================================================================
   JSON feeds — one VARIANT column + lineage. Same shape for all four.
   =========================================================================== */
CREATE TABLE IF NOT EXISTS RETAIL_RAW.ECOM.REVIEWS (
  v VARIANT, _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW product reviews (NDJSON)';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ECOM.PIPE_ECOM_REVIEWS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'reviews/*.json'
AS COPY INTO RETAIL_RAW.ECOM.REVIEWS
FROM (SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/reviews/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_JSON')
PATTERN = '.*[.]json' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.CRM.CUSTOMERS (
  v VARIANT, _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW CRM extract: full on day 1, then changes only. Contains PII.';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.CRM.PIPE_CRM_CUSTOMERS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'crm_customers/*.json'
AS COPY INTO RETAIL_RAW.CRM.CUSTOMERS
FROM (SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/crm_customers/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_JSON')
PATTERN = '.*[.]json' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.ADS.AD_PERFORMANCE (
  v VARIANT, _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW daily ad performance from Google Ads and Meta';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ADS.PIPE_ADS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'ads/*.json'
AS COPY INTO RETAIL_RAW.ADS.AD_PERFORMANCE
FROM (SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/ads/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_JSON')
PATTERN = '.*[.]json' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.WEB.EVENTS (
  v VARIANT, _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW clickstream: ad clicks, email opens, page views, purchases';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.WEB.PIPE_WEB_EVENTS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'web_events/*.json'
AS COPY INTO RETAIL_RAW.WEB.EVENTS
FROM (SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/web_events/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_JSON')
PATTERN = '.*[.]json' ON_ERROR = 'SKIP_FILE';

/* ===========================================================================
   ERP — reference data in CSV
   =========================================================================== */
CREATE TABLE IF NOT EXISTS RETAIL_RAW.ERP.PRODUCTS (
  sku STRING, product_name STRING, category STRING, subcategory STRING, brand STRING,
  unit_cost NUMBER(12,2), list_price NUMBER(12,2), updated_at TIMESTAMP_NTZ,
  _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW product master: full on day 1, then price changes';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ERP.PIPE_ERP_PRODUCTS
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'erp_products/*.csv'
AS COPY INTO RETAIL_RAW.ERP.PRODUCTS
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/erp_products/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.ERP.STORES (
  store_id STRING, store_name STRING, city STRING, country_code STRING, region STRING,
  opened_date DATE, size_sqm INT, updated_at TIMESTAMP_NTZ,
  _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW store master';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ERP.PIPE_ERP_STORES
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'erp_stores/*.csv'
AS COPY INTO RETAIL_RAW.ERP.STORES
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/erp_stores/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv' ON_ERROR = 'SKIP_FILE';

CREATE TABLE IF NOT EXISTS RETAIL_RAW.ERP.INVENTORY (
  snapshot_date DATE, store_id STRING, sku STRING, opening_qty INT,
  _file_name STRING, _file_row_number NUMBER, _loaded_at TIMESTAMP_LTZ
) COMMENT = 'RAW opening stock per store x sku x day';

CREATE PIPE IF NOT EXISTS RETAIL_RAW.ERP.PIPE_ERP_INVENTORY
  AUTO_INGEST = TRUE INTEGRATION = 'GCS_NOTIF' COMMENT = 'erp_inventory/*.csv'
AS COPY INTO RETAIL_RAW.ERP.INVENTORY
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
      FROM @RETAIL_RAW.COMMON.LANDING/erp_inventory/)
FILE_FORMAT = (FORMAT_NAME = 'RETAIL_RAW.COMMON.FF_CSV')
PATTERN = '.*[.]csv' ON_ERROR = 'SKIP_FILE';

/* ===========================================================================
   Check
   =========================================================================== */
SHOW PIPES IN DATABASE RETAIL_RAW;   -- 10 pipes, notification_channel = your subscription
SELECT 'PIPE_POS_SALES' AS pipe, PARSE_JSON(SYSTEM$PIPE_STATUS('RETAIL_RAW.POS.PIPE_POS_SALES')):executionState::STRING AS state
UNION ALL SELECT 'PIPE_ECOM_ORDERS', PARSE_JSON(SYSTEM$PIPE_STATUS('RETAIL_RAW.ECOM.PIPE_ECOM_ORDERS')):executionState::STRING
UNION ALL SELECT 'PIPE_CRM_CUSTOMERS', PARSE_JSON(SYSTEM$PIPE_STATUS('RETAIL_RAW.CRM.PIPE_CRM_CUSTOMERS')):executionState::STRING;
