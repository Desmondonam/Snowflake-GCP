/* =============================================================================
   Stage 8 · Lesson 01 — Secure Data Sharing with a brand partner
   -----------------------------------------------------------------------------
   Share LIVE data with another Snowflake account without copying it: the consumer
   queries your tables with their own compute; you pay only for storage you already have.

   Multi-tenant pattern: ONE secure view, filtered by CURRENT_ACCOUNT() through a
   mapping table, so each brand partner sees only its own brand. Add a partner =
   insert a row + add the account to the share.

   PREREQUISITE: a second Snowflake trial account (the "brand"), ALSO on GCP us-central1
   (direct shares need the same region; other regions/clouds need a listing with auto-fulfilment).
   In the consumer account run: SELECT CURRENT_ACCOUNT(), CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME();
   HOW TO RUN: worksheet, step by step.
   ============================================================================= */

/* ---------------------------------------------------------------------------
   PROVIDER (RetailOne account)
   --------------------------------------------------------------------------- */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.SHARED COMMENT = 'Objects exposed to external partners';

-- Which consumer account may see which brand. CURRENT_ACCOUNT() returns the ACCOUNT LOCATOR (e.g. XY12345).
CREATE TABLE IF NOT EXISTS RETAIL_MARTS.SHARED.PARTNER_BRAND_MAP (consumer_account_locator STRING, brand STRING);
-- Replace with the consumer's locator (from the query in the header):
MERGE INTO RETAIL_MARTS.SHARED.PARTNER_BRAND_MAP t
USING (SELECT 'CONSUMER_LOCATOR' AS consumer_account_locator, 'Acacia' AS brand) s
  ON t.consumer_account_locator = s.consumer_account_locator AND t.brand = s.brand
WHEN NOT MATCHED THEN INSERT VALUES (s.consumer_account_locator, s.brand);
-- Also map YOUR OWN locator so you can test the view as the provider:
INSERT INTO RETAIL_MARTS.SHARED.PARTNER_BRAND_MAP
SELECT CURRENT_ACCOUNT(), 'Acacia' WHERE NOT EXISTS (
  SELECT 1 FROM RETAIL_MARTS.SHARED.PARTNER_BRAND_MAP WHERE consumer_account_locator = CURRENT_ACCOUNT());

-- SECURE view: the definition is hidden and the optimizer can't leak filtered rows. Aggregated: no customer data.
CREATE OR REPLACE SECURE VIEW RETAIL_MARTS.SHARED.V_BRAND_WEEKLY_SALES
  COMMENT = 'Weekly sales of the consumer''s own brand by region and category'
AS
SELECT DATE_TRUNC('week', f.sale_date)        AS week_start,
       p.brand,
       p.category,
       f.store_region,
       f.sales_channel,
       COUNT(DISTINCT f.transaction_id)       AS baskets,
       SUM(f.quantity)                        AS units,
       SUM(f.net_amount)                      AS net_sales
FROM RETAIL_MARTS.SALES.FCT_SALES_LINE f
JOIN RETAIL_MARTS.CORE.DIM_PRODUCT p ON p.product_sk = f.product_sk
JOIN RETAIL_MARTS.SHARED.PARTNER_BRAND_MAP m
  ON m.brand = p.brand AND m.consumer_account_locator = CURRENT_ACCOUNT()
GROUP BY 1, 2, 3, 4, 5;

SELECT * FROM RETAIL_MARTS.SHARED.V_BRAND_WEEKLY_SALES ORDER BY week_start DESC LIMIT 10;   -- provider test

-- The share itself (ACCOUNTADMIN, or a role with CREATE SHARE)
USE ROLE ACCOUNTADMIN;
CREATE SHARE IF NOT EXISTS BRAND_PARTNER_SHARE COMMENT = 'RetailOne → brand partners: weekly brand sales';
GRANT USAGE ON DATABASE RETAIL_MARTS TO SHARE BRAND_PARTNER_SHARE;
GRANT USAGE ON SCHEMA RETAIL_MARTS.SHARED TO SHARE BRAND_PARTNER_SHARE;
GRANT SELECT ON VIEW RETAIL_MARTS.SHARED.V_BRAND_WEEKLY_SALES TO SHARE BRAND_PARTNER_SHARE;

-- Simulate a consumer before adding a real one: what would account X see?
ALTER SESSION SET SIMULATED_DATA_SHARING_CONSUMER = 'CONSUMER_LOCATOR';
SELECT COUNT(*) FROM RETAIL_MARTS.SHARED.V_BRAND_WEEKLY_SALES;
ALTER SESSION UNSET SIMULATED_DATA_SHARING_CONSUMER;

-- Add the consumer (identifier ORGNAME.ACCOUNTNAME of the brand's account)
-- ALTER SHARE BRAND_PARTNER_SHARE ADD ACCOUNTS = <consumer_org>.<consumer_account>;
SHOW SHARES LIKE 'BRAND_PARTNER_SHARE';
DESC SHARE BRAND_PARTNER_SHARE;

/* The fact table carries the row access policy from Stage 7. Its body allows
   INVOKER_SHARE() = 'BRAND_PARTNER_SHARE', so the share sees the rows the secure view selects.

   Partner WITHOUT a Snowflake account? A READER account (you pay its compute):
   CREATE MANAGED ACCOUNT BRAND_READER ADMIN_NAME = 'brand_admin', ADMIN_PASSWORD = '<strong pw>', TYPE = READER;
   then ALTER SHARE BRAND_PARTNER_SHARE ADD ACCOUNTS = <reader locator>; */

/* ---------------------------------------------------------------------------
   CONSUMER (run in the BRAND's trial account)
   --------------------------------------------------------------------------- */
-- USE ROLE ACCOUNTADMIN;
-- SHOW SHARES;                                             -- the inbound share appears
-- CREATE DATABASE RETAILONE_SALES FROM SHARE <provider_org>.<provider_account>.BRAND_PARTNER_SHARE;
-- GRANT IMPORTED PRIVILEGES ON DATABASE RETAILONE_SALES TO ROLE SYSADMIN;
-- SELECT * FROM RETAILONE_SALES.SHARED.V_BRAND_WEEKLY_SALES ORDER BY week_start DESC;
-- Data is live: when RetailOne's dbt run finishes, the brand sees new weeks immediately.
