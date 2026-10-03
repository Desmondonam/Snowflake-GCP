/* =============================================================================
   CAPSTONE 2 (part 3) — Verify that data landed itself
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;

-- 1. Row counts, files and freshness per RAW table
SELECT 'POS.SALES_LINES' AS tbl, COUNT(*) AS rows_, COUNT(DISTINCT _file_name) AS files, MAX(_loaded_at) AS last_load FROM RETAIL_RAW.POS.SALES_LINES
UNION ALL SELECT 'POS.CONTROL_TOTALS', COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.POS.CONTROL_TOTALS
UNION ALL SELECT 'ECOM.ORDERS',        COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ECOM.ORDERS
UNION ALL SELECT 'ECOM.REVIEWS',       COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ECOM.REVIEWS
UNION ALL SELECT 'CRM.CUSTOMERS',      COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.CRM.CUSTOMERS
UNION ALL SELECT 'ERP.PRODUCTS',       COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ERP.PRODUCTS
UNION ALL SELECT 'ERP.STORES',         COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ERP.STORES
UNION ALL SELECT 'ERP.INVENTORY',      COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ERP.INVENTORY
UNION ALL SELECT 'ADS.AD_PERFORMANCE', COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.ADS.AD_PERFORMANCE
UNION ALL SELECT 'WEB.EVENTS',         COUNT(*), COUNT(DISTINCT _file_name), MAX(_loaded_at) FROM RETAIL_RAW.WEB.EVENTS
ORDER BY 1;
-- Expect for 90 days: ~1,800 POS files (20/day), 90 control files, 90 order files, etc.

-- 2. Every store, every day? (should return no rows once all files have landed)
SELECT business_date, COUNT(*) AS stores_in_control
FROM RETAIL_RAW.POS.CONTROL_TOTALS GROUP BY 1 HAVING COUNT(*) <> 20;

SELECT TO_DATE(REGEXP_SUBSTR(_file_name, 'dt=(\\d{4}-\\d{2}-\\d{2})', 1, 1, 'e', 1)) AS business_date,
       COUNT(DISTINCT store_id) AS stores_loaded
FROM RETAIL_RAW.POS.SALES_LINES GROUP BY 1 HAVING COUNT(DISTINCT store_id) < 20 ORDER BY 1;

-- 3. Schema evolution happened: DELIVERY_METHOD exists now.
DESC TABLE RETAIL_RAW.ECOM.ORDERS;
SELECT TO_DATE(ordered_at) AS d, COUNT_IF(delivery_method IS NOT NULL) AS with_method, COUNT(*) AS lines
FROM RETAIL_RAW.ECOM.ORDERS GROUP BY 1 ORDER BY 1 DESC LIMIT 35;

-- 4. Peek at the JSON feeds (schema-on-read)
SELECT v:customer_id::STRING, v:loyalty_tier::STRING, v:updated_at::TIMESTAMP_NTZ, _file_name
FROM RETAIL_RAW.CRM.CUSTOMERS LIMIT 10;
SELECT v:platform::STRING AS platform, SUM(v:spend::NUMBER(12,2)) AS spend
FROM RETAIL_RAW.ADS.AD_PERFORMANCE GROUP BY 1;
SELECT v:event_type::STRING AS event_type, COUNT(*) FROM RETAIL_RAW.WEB.EVENTS GROUP BY 1;

/* 5. CHAOS TEST — run this after:
        python capstone_retail_platform/data_generator/generate.py new-day --upload --inject-bad-file --duplicate-file
      Wait ~2 minutes. */
SELECT file_name, status, row_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'RETAIL_RAW.POS.SALES_LINES', START_TIME => DATEADD(hour, -2, CURRENT_TIMESTAMP())))
WHERE file_name ILIKE '%S999%' OR file_name ILIKE '%resend%';
-- store_S999_corrupt.csv → Load failed (SKIP_FILE); store_S001_resend.csv → Loaded (duplicates in RAW!)

-- The duplicates are real in RAW (append-only by design). Staging will remove them in Stage 4:
SELECT transaction_id, line_no, COUNT(*) AS copies, ARRAY_AGG(DISTINCT _file_name) AS files
FROM RETAIL_RAW.POS.SALES_LINES
GROUP BY 1, 2 HAVING COUNT(*) > 1 LIMIT 10;
