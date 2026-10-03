/* =============================================================================
   Stage 3 · Step 01 — Staging views over RAW (hand-written; dbt replaces them in Stage 4)
   -----------------------------------------------------------------------------
   Staging = one clean view per source table: typed, renamed, de-duplicated.
   No joins across sources, no business logic. Every later model reads staging,
   never RAW directly.

   Dedupe rule used everywhere: keep ONE row per business key, preferring the
   most recently loaded copy:
       QUALIFY ROW_NUMBER() OVER (PARTITION BY <key> ORDER BY _loaded_at DESC) = 1

   PREREQUISITE: Capstone 2 (RAW tables loaded).
   HOW TO RUN:   snow sql -c retail_engineer -f stage_03_modeling/01_staging_views.sql
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.STG  COMMENT = 'Stage 3 hand-written staging views';
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.STAR COMMENT = 'Stage 3 hand-built star schema';
USE SCHEMA RETAIL_LAB.STG;

-- POS line items: duplicates come from re-sent files → keep the latest copy of each line.
CREATE OR REPLACE VIEW POS_SALES_LINES AS
SELECT transaction_id, line_no, store_id, sku,
       qty, unit_price, discount, NULLIF(loyalty_id, '') AS loyalty_id,
       sold_at, promo_code, tender_type, _file_name, _loaded_at
FROM RETAIL_RAW.POS.SALES_LINES
QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id, line_no ORDER BY _loaded_at DESC, _file_name DESC) = 1;

CREATE OR REPLACE VIEW POS_CONTROL_TOTALS AS
SELECT business_date, store_id, txn_count, line_count, gross_amount, discount_amount, net_amount, _loaded_at
FROM RETAIL_RAW.POS.CONTROL_TOTALS
QUALIFY ROW_NUMBER() OVER (PARTITION BY business_date, store_id ORDER BY _loaded_at DESC) = 1;

CREATE OR REPLACE VIEW ECOM_ORDER_LINES AS
SELECT order_id, order_line, web_customer_id, LOWER(TRIM(customer_email)) AS customer_email,
       sku, qty, unit_price, discount, ordered_at, order_status, ship_city, ship_country, _loaded_at
FROM RETAIL_RAW.ECOM.ORDERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id, order_line ORDER BY _loaded_at DESC) = 1;

-- CRM: every change record (history), typed out of VARIANT. Feeds SCD2.
CREATE OR REPLACE VIEW CRM_CUSTOMER_CHANGES AS
SELECT v:customer_id::STRING                AS customer_id,
       v:loyalty_id::STRING                 AS loyalty_id,
       LOWER(TRIM(v:email::STRING))         AS email,
       v:phone::STRING                      AS phone,
       v:first_name::STRING                 AS first_name,
       v:last_name::STRING                  AS last_name,
       v:birth_date::DATE                   AS birth_date,
       v:city::STRING                       AS city,
       v:country_code::STRING               AS country_code,
       UPPER(v:segment::STRING)             AS segment,
       UPPER(v:loyalty_tier::STRING)        AS loyalty_tier,
       v:marketing_consent::BOOLEAN         AS marketing_consent,
       v:created_at::TIMESTAMP_NTZ          AS created_at,
       v:updated_at::TIMESTAMP_NTZ          AS updated_at,
       _loaded_at
FROM RETAIL_RAW.CRM.CUSTOMERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY v:customer_id::STRING, v:updated_at::TIMESTAMP_NTZ ORDER BY _loaded_at DESC) = 1;

-- CRM: the current state of each customer (latest change wins).
CREATE OR REPLACE VIEW CRM_CUSTOMERS_LATEST AS
SELECT * FROM CRM_CUSTOMER_CHANGES
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1;

CREATE OR REPLACE VIEW ERP_PRODUCT_CHANGES AS
SELECT sku, product_name, category, subcategory, brand, unit_cost, list_price, updated_at, _loaded_at
FROM RETAIL_RAW.ERP.PRODUCTS
QUALIFY ROW_NUMBER() OVER (PARTITION BY sku, updated_at ORDER BY _loaded_at DESC) = 1;

CREATE OR REPLACE VIEW ERP_STORES AS
SELECT store_id, store_name, city, country_code, region, opened_date, size_sqm, updated_at
FROM RETAIL_RAW.ERP.STORES
QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY updated_at DESC, _loaded_at DESC) = 1;

CREATE OR REPLACE VIEW ERP_INVENTORY AS
SELECT snapshot_date, store_id, sku, opening_qty
FROM RETAIL_RAW.ERP.INVENTORY
QUALIFY ROW_NUMBER() OVER (PARTITION BY snapshot_date, store_id, sku ORDER BY _loaded_at DESC) = 1;

-- Ads: the extractor may run more than once a day (immutable files) → dedupe per (date, ad).
CREATE OR REPLACE VIEW ADS_AD_PERFORMANCE AS
SELECT v:date::DATE                  AS ad_date,
       v:platform::STRING            AS platform,
       v:campaign_id::STRING         AS campaign_id,
       v:campaign_name::STRING       AS campaign_name,
       v:ad_id::STRING               AS ad_id,
       v:ad_name::STRING             AS ad_name,
       v:spend::NUMBER(12,2)         AS spend,
       v:currency::STRING            AS currency,
       v:impressions::INT            AS impressions,
       v:clicks::INT                 AS clicks,
       v:conversions::INT            AS conversions,
       _loaded_at
FROM RETAIL_RAW.ADS.AD_PERFORMANCE
QUALIFY ROW_NUMBER() OVER (PARTITION BY v:date::DATE, v:ad_id::STRING ORDER BY _loaded_at DESC) = 1;

SHOW VIEWS IN SCHEMA RETAIL_LAB.STG;
SELECT COUNT(*) AS raw_rows, (SELECT COUNT(*) FROM POS_SALES_LINES) AS deduped_rows FROM RETAIL_RAW.POS.SALES_LINES;
