/* =============================================================================
   Stage 6 · Step 01 — Build a 200M-row sales fact with GENERATOR (nothing to upload)
   -----------------------------------------------------------------------------
   The rows are generated in RANDOM order, so the table is badly clustered on
   sale_date — exactly like a fact table loaded out of order over years. That's
   the baseline we will fix.

   COST: ~3–5 minutes on a MEDIUM warehouse (4 credits/h) ≈ 0.3 credits.
         Short on credits? Change 200000000 to 50000000 below (results scale down too).
   HOW TO RUN: snow sql -c retail_admin -f stage_06_performance/01_build_perf_dataset.sql
               (needs SYSADMIN for the warehouse and ACCOUNTADMIN for the monitor)
   ============================================================================= */

-- A dedicated warehouse for experiments, so resizing never disturbs anything else
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS PERF_WH
  WITH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
       COMMENT = 'Stage 6 performance experiments';
GRANT USAGE, OPERATE, MODIFY, MONITOR ON WAREHOUSE PERF_WH TO ROLE RETAIL_ENGINEER;

USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE PERF_WH SET RESOURCE_MONITOR = RM_RETAIL_MONTHLY;

USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE PERF_WH;
ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = MEDIUM;     -- generation only; back to XSMALL at the end
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.PERF;
USE SCHEMA RETAIL_LAB.PERF;

-- Dimensions: 400 stores, 20,000 products
CREATE OR REPLACE TABLE DIM_STORE_BIG AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS i FROM TABLE(GENERATOR(ROWCOUNT => 400)))
SELECT 'S' || LPAD(i::STRING, 3, '0') AS store_id,
       IFF(i <= 240, 'KE', 'QA')       AS store_region,
       IFF(i <= 240, 'Nairobi', 'Doha') || ' ' || i AS store_name
FROM n;

CREATE OR REPLACE TABLE DIM_PRODUCT_BIG AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS i FROM TABLE(GENERATOR(ROWCOUNT => 20000)))
SELECT 'SKU-' || LPAD(i::STRING, 5, '0') AS sku,
       DECODE(MOD(i, 6), 0, 'Grocery', 1, 'Beverages', 2, 'Household', 3, 'Personal Care', 4, 'Electronics', 'Apparel') AS category,
       'Brand ' || MOD(i, 50) AS brand
FROM n;

-- The fact: 2 years (2024–2025), 400 stores, 20k SKUs, 2M customers, random order
CREATE OR REPLACE TABLE FCT_SALES_LINE_BIG AS
WITH g AS (
  SELECT UNIFORM(0, 730, RANDOM())         AS day_offset,
         UNIFORM(1, 400, RANDOM())         AS store_no,
         UNIFORM(1, 20000, RANDOM())       AS product_no,
         UNIFORM(1, 2000000, RANDOM())     AS customer_no,
         UNIFORM(1, 100, RANDOM())         AS r,
         UNIFORM(1, 5, RANDOM())           AS qty,
         UNIFORM(50, 50000, RANDOM()) / 100 AS unit_price
  FROM TABLE(GENERATOR(ROWCOUNT => 200000000))
)
SELECT SEQ8()                                          AS sales_line_id,
       DATEADD(day, day_offset, '2024-01-01'::DATE)    AS sale_date,
       'S' || LPAD(store_no::STRING, 3, '0')           AS store_id,
       IFF(store_no <= 240, 'KE', 'QA')                AS store_region,
       'SKU-' || LPAD(product_no::STRING, 5, '0')      AS sku,
       'C' || LPAD(customer_no::STRING, 7, '0')        AS customer_id,
       IFF(r <= 60, 'L' || LPAD(customer_no::STRING, 7, '0'), NULL) AS loyalty_id,
       qty::NUMBER(10,2)                               AS quantity,
       unit_price::NUMBER(12,2)                        AS unit_price,
       (qty * unit_price)::NUMBER(14,2)                AS net_amount,
       (qty * unit_price * 0.7)::NUMBER(14,2)          AS cost_amount
FROM g;

ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = XSMALL;

-- How big is it, and how badly clustered on the column every query filters by?
SELECT COUNT(*) AS rows_ FROM FCT_SALES_LINE_BIG;
SELECT table_name, row_count, ROUND(bytes / POWER(1024, 3), 2) AS gb
FROM RETAIL_LAB.INFORMATION_SCHEMA.TABLES WHERE table_schema = 'PERF';
SELECT SYSTEM$CLUSTERING_INFORMATION('RETAIL_LAB.PERF.FCT_SALES_LINE_BIG', '(sale_date)');
-- Look at average_depth: with random order almost every micro-partition contains almost every date
-- (depth close to the total partition count). Well clustered ≈ 1–2.
