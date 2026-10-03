/* =============================================================================
   Stage 8 · Lesson 02 — Clean-room building blocks (retail media)
   -----------------------------------------------------------------------------
   Question from a beverage brand: "Of the customers who saw our ad, how many bought
   our products in RetailOne stores?" Neither side may see the other's customer rows.

   Building blocks (Enterprise):
     PROJECTION POLICY   the join key (hashed email) can be JOINED ON but never SELECTED
     AGGREGATION POLICY  results only as aggregates over groups of at least N people
   Snowflake Data Clean Rooms (a native app) packages these + templates + a UI.
   Here we build the principle by hand inside one account (the brand's exposure
   list is simulated) so you understand what the product does.
   HOW TO RUN: worksheet, step by step.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA RETAIL_MARTS.SHARED;

-- 1. RetailOne side: customers with a hashed identifier + coarse attributes + brand spend (no raw PII)
CREATE OR REPLACE TABLE CLEANROOM_RETAIL_CUSTOMERS AS
SELECT SHA2(LOWER(c.email), 256)                         AS email_sha256,
       c.segment,
       c.country_code,
       SUM(IFF(p.brand = 'Acacia', f.net_amount, 0))     AS acacia_spend_90d,
       COUNT_IF(p.brand = 'Acacia') > 0                  AS bought_acacia
FROM RETAIL_MARTS.SALES.FCT_SALES_LINE f
JOIN RETAIL_MARTS.CORE.DIM_CUSTOMER c ON c.customer_sk = f.customer_sk
JOIN RETAIL_MARTS.CORE.DIM_PRODUCT p  ON p.product_sk = f.product_sk
WHERE c.email IS NOT NULL
  AND f.sale_date >= DATEADD(day, -90, (SELECT MAX(sale_date) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE))
GROUP BY 1, 2, 3;

-- 2. Brand side (simulated): hashed emails of people exposed to the campaign
CREATE OR REPLACE TABLE CLEANROOM_BRAND_EXPOSURE AS
SELECT email_sha256, IFF(UNIFORM(1, 2, RANDOM()) = 1, 'video', 'display') AS creative
FROM CLEANROOM_RETAIL_CUSTOMERS SAMPLE (40);

-- 3. Policies
CREATE OR REPLACE PROJECTION POLICY PP_NO_PROJECT_JOIN_KEY
  AS () RETURNS PROJECTION_CONSTRAINT ->
    CASE WHEN IS_ROLE_IN_SESSION('RETAIL_ENGINEER') THEN PROJECTION_CONSTRAINT(ALLOW => TRUE)
         ELSE PROJECTION_CONSTRAINT(ALLOW => FALSE) END;

CREATE OR REPLACE AGGREGATION POLICY AP_MIN_GROUP_50
  AS () RETURNS AGGREGATION_CONSTRAINT ->
    CASE WHEN IS_ROLE_IN_SESSION('RETAIL_ENGINEER') THEN NO_AGGREGATION_CONSTRAINT()
         ELSE AGGREGATION_CONSTRAINT(MIN_GROUP_SIZE => 50) END;

ALTER TABLE CLEANROOM_RETAIL_CUSTOMERS MODIFY COLUMN email_sha256 SET PROJECTION POLICY PP_NO_PROJECT_JOIN_KEY;
ALTER TABLE CLEANROOM_RETAIL_CUSTOMERS SET AGGREGATION POLICY AP_MIN_GROUP_50;

-- Let marketing (standing in for the brand analyst) query it
USE ROLE SECURITYADMIN;
GRANT USAGE ON SCHEMA RETAIL_MARTS.SHARED TO ROLE AR_MARTS_MARKETING_READ;
GRANT SELECT ON TABLE RETAIL_MARTS.SHARED.CLEANROOM_RETAIL_CUSTOMERS TO ROLE AR_MARTS_MARKETING_READ;
GRANT SELECT ON TABLE RETAIL_MARTS.SHARED.CLEANROOM_BRAND_EXPOSURE  TO ROLE AR_MARTS_MARKETING_READ;

-- 4. Try it as the "analyst"
USE SECONDARY ROLES NONE;
USE ROLE FR_MARKETING;
USE WAREHOUSE BI_WH;

-- ✗ Row-level: blocked by the aggregation policy
-- SELECT * FROM RETAIL_MARTS.SHARED.CLEANROOM_RETAIL_CUSTOMERS LIMIT 10;
-- ✗ Selecting the join key: blocked by the projection policy
-- SELECT email_sha256, COUNT(*) FROM RETAIL_MARTS.SHARED.CLEANROOM_RETAIL_CUSTOMERS GROUP BY 1;

-- ✓ The overlap question, aggregated. Groups smaller than 50 people are folded into a NULL "other" group.
SELECT e.creative, r.segment,
       COUNT(*)                         AS exposed_customers,
       COUNT_IF(r.bought_acacia)        AS exposed_buyers,
       ROUND(100 * COUNT_IF(r.bought_acacia) / COUNT(*), 1) AS conversion_pct,
       SUM(r.acacia_spend_90d)          AS acacia_spend
FROM RETAIL_MARTS.SHARED.CLEANROOM_RETAIL_CUSTOMERS r
JOIN RETAIL_MARTS.SHARED.CLEANROOM_BRAND_EXPOSURE e ON e.email_sha256 = r.email_sha256
GROUP BY 1, 2;

USE SECONDARY ROLES ALL;

/* In production the brand's exposure table lives in THEIR account and arrives through a share
   (or both sides install the Snowflake Data Clean Rooms app). The policies travel with the data,
   so even the consumer can only run approved, aggregated queries. That's a retail-media revenue product. */
