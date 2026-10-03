/* =============================================================================
   Stage 3 · Step 02 — Dimensions: date, store (SCD1), product & customer (SCD2),
                       campaign, channel, promotion
   -----------------------------------------------------------------------------
   SCD2 built from HISTORY with window functions ("batch" SCD2):
     1. hash the tracked attributes of every change record
     2. keep a record only if its hash differs from the previous one (a real change)
     3. valid_from = change time (first version: 1900-01-01, so old facts still match)
        valid_to   = next version's change time (or 9999-12-31)   ← EXCLUSIVE upper bound
   Because RAW keeps every change, this can be rebuilt from scratch at any time.
   Step 03 shows the other way: incremental MERGE when you only get today's snapshot.

   Surrogate keys: MD5(natural key | valid_from). Deterministic hash keys mean the
   same version always gets the same key, even after a full rebuild.
   Unknown member: key '-1' so facts never have NULL foreign keys.

   HOW TO RUN: snow sql -c retail_engineer -f stage_03_modeling/02_dimensions.sql
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA RETAIL_LAB.STAR;

/* ---------------------------------------------------------------------------
   DIM_DATE — generated, no source. Note the Qatar weekend is Fri–Sat.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE DIM_DATE AS
WITH spine AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-01-01'::DATE) AS date_day
  FROM TABLE(GENERATOR(ROWCOUNT => 1461))          -- 2024-01-01 .. 2027-12-31
)
SELECT TO_NUMBER(TO_CHAR(date_day, 'YYYYMMDD'))    AS date_key,
       date_day,
       YEAR(date_day)                              AS year,
       QUARTER(date_day)                           AS quarter,
       MONTH(date_day)                             AS month,
       MONTHNAME(date_day)                         AS month_name,
       WEEKISO(date_day)                           AS iso_week,
       DATE_TRUNC('week', date_day)                AS week_start,
       DATE_TRUNC('month', date_day)               AS month_start,
       DAYOFWEEKISO(date_day)                      AS day_of_week_iso,   -- 1 = Monday
       DAYNAME(date_day)                           AS day_name,
       DAYOFWEEKISO(date_day) IN (6, 7)            AS is_weekend_ke,
       DAYOFWEEKISO(date_day) IN (5, 6)            AS is_weekend_qa
FROM spine;

/* ---------------------------------------------------------------------------
   DIM_STORE — SCD Type 1 (overwrite). Plus one row for the online channel.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE DIM_STORE AS
SELECT MD5(store_id) AS store_sk, store_id, store_name, city, country_code, region,
       opened_date, size_sqm, 'PHYSICAL' AS store_type
FROM RETAIL_LAB.STG.ERP_STORES
UNION ALL
SELECT MD5('ONLINE'), 'ONLINE', 'RetailOne Online', NULL, NULL, NULL, NULL, NULL, 'ONLINE';

/* ---------------------------------------------------------------------------
   DIM_PRODUCT — SCD Type 2 (price and category history matter for margin)
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE DIM_PRODUCT AS
WITH hashed AS (
  SELECT *,
         MD5(CONCAT_WS('|', COALESCE(product_name, ''), COALESCE(category, ''), COALESCE(subcategory, ''),
                            COALESCE(brand, ''), COALESCE(unit_cost::STRING, ''), COALESCE(list_price::STRING, ''))) AS attr_hash
  FROM RETAIL_LAB.STG.ERP_PRODUCT_CHANGES
),
changes_only AS (
  SELECT * FROM hashed
  QUALIFY LAG(attr_hash) OVER (PARTITION BY sku ORDER BY updated_at) IS DISTINCT FROM attr_hash
),
versions AS (
  SELECT *,
         IFF(ROW_NUMBER() OVER (PARTITION BY sku ORDER BY updated_at) = 1,
             '1900-01-01'::TIMESTAMP_NTZ, updated_at)                                   AS valid_from,
         COALESCE(LEAD(updated_at) OVER (PARTITION BY sku ORDER BY updated_at),
                  '9999-12-31'::TIMESTAMP_NTZ)                                          AS valid_to
  FROM changes_only
)
SELECT MD5(sku || '|' || valid_from::STRING) AS product_sk,
       sku, product_name, category, subcategory, brand, unit_cost, list_price,
       attr_hash, valid_from, valid_to, valid_to = '9999-12-31'::TIMESTAMP_NTZ AS is_current
FROM versions
UNION ALL
SELECT '-1', 'UNKNOWN', 'Unknown product', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 0, 0,
       NULL, '1900-01-01'::TIMESTAMP_NTZ, '9999-12-31'::TIMESTAMP_NTZ, TRUE;

/* ---------------------------------------------------------------------------
   DIM_CUSTOMER — SCD Type 2 on segment, loyalty_tier, city, country_code.
   Contact details (email, phone, names, consent) are Type 1: always the latest
   value on every version (a "hybrid"/Type 6-style dimension). Why? A corrected
   email should apply to all history; a tier change should not.
   (Stage 3 keeps guest checkouts as the unknown member. Stage 4 adds them.)
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE DIM_CUSTOMER AS
WITH hashed AS (
  SELECT customer_id, segment, loyalty_tier, city, country_code, updated_at,
         MD5(CONCAT_WS('|', COALESCE(segment, ''), COALESCE(loyalty_tier, ''),
                            COALESCE(city, ''), COALESCE(country_code, ''))) AS attr_hash
  FROM RETAIL_LAB.STG.CRM_CUSTOMER_CHANGES
),
changes_only AS (
  SELECT * FROM hashed
  QUALIFY LAG(attr_hash) OVER (PARTITION BY customer_id ORDER BY updated_at) IS DISTINCT FROM attr_hash
),
versions AS (
  SELECT *,
         IFF(ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at) = 1,
             '1900-01-01'::TIMESTAMP_NTZ, updated_at)                                   AS valid_from,
         COALESCE(LEAD(updated_at) OVER (PARTITION BY customer_id ORDER BY updated_at),
                  '9999-12-31'::TIMESTAMP_NTZ)                                          AS valid_to
  FROM changes_only
)
SELECT MD5(v.customer_id || '|' || v.valid_from::STRING) AS customer_sk,
       v.customer_id, l.loyalty_id, l.email, l.phone, l.first_name, l.last_name, l.birth_date,
       v.city, v.country_code, v.segment, v.loyalty_tier, l.marketing_consent,
       v.attr_hash, v.valid_from, v.valid_to, v.valid_to = '9999-12-31'::TIMESTAMP_NTZ AS is_current
FROM versions v
JOIN RETAIL_LAB.STG.CRM_CUSTOMERS_LATEST l ON l.customer_id = v.customer_id
UNION ALL
SELECT '-1', 'UNKNOWN', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'UNKNOWN', NULL, NULL,
       NULL, '1900-01-01'::TIMESTAMP_NTZ, '9999-12-31'::TIMESTAMP_NTZ, TRUE;

/* ---------------------------------------------------------------------------
   Small dimensions
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE DIM_CAMPAIGN AS
SELECT MD5(campaign_id) AS campaign_sk, campaign_id,
       ANY_VALUE(campaign_name) AS campaign_name,   -- names are stable in our data
       ANY_VALUE(platform)      AS platform,
       IFF(ANY_VALUE(platform) = 'google', 'paid_search', 'paid_social') AS channel_code,
       MIN(ad_date) AS first_seen_date, MAX(ad_date) AS last_seen_date
FROM RETAIL_LAB.STG.ADS_AD_PERFORMANCE
GROUP BY campaign_id;

CREATE OR REPLACE TABLE DIM_CHANNEL AS
SELECT MD5(column1) AS channel_sk, column1 AS channel_code, column2 AS channel_name,
       column3 AS channel_group, column4 AS is_paid
FROM VALUES ('paid_search', 'Paid search', 'Paid media', TRUE),
            ('paid_social', 'Paid social', 'Paid media', TRUE),
            ('email',       'Email',       'Owned',      FALSE),
            ('organic',     'Organic search', 'Earned',  FALSE),
            ('direct',      'Direct',      'Earned',     FALSE),
            ('store',       'Physical store', 'Store',   FALSE),
            ('unattributed','Unattributed','Unknown',    FALSE);

CREATE OR REPLACE TABLE DIM_PROMOTION AS
SELECT MD5(column1) AS promotion_sk, column1 AS promo_code, column2 AS promo_name, column3 AS discount_pct
FROM VALUES ('PROMO10', '10% off basket', 0.10), ('WEEKEND15', 'Weekend 15%', 0.15),
            ('LOYAL20', 'Loyalty members 20%', 0.20), ('FLASH25', 'Flash sale 25%', 0.25),
            ('NONE', 'No promotion', 0.00);

/* ---------------------------------------------------------------------------
   Look at the SCD2 history you just built
   --------------------------------------------------------------------------- */
SELECT customer_id, COUNT(*) AS versions FROM DIM_CUSTOMER GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
SELECT customer_id, segment, loyalty_tier, city, valid_from, valid_to, is_current
FROM DIM_CUSTOMER
WHERE customer_id = (SELECT customer_id FROM DIM_CUSTOMER GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1)
ORDER BY valid_from;
SELECT sku, list_price, valid_from, valid_to, is_current FROM DIM_PRODUCT
WHERE sku = (SELECT sku FROM DIM_PRODUCT GROUP BY 1 ORDER BY COUNT(*) DESC LIMIT 1) ORDER BY valid_from;
