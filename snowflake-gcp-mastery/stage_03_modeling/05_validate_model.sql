/* =============================================================================
   Stage 3 · Step 05 — Validate the model (the tests dbt will automate in Stage 4)
   Each query should return ZERO rows (or the stated expectation).
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA RETAIL_LAB.STAR;

-- 1. GRAIN: the key is unique (if not, the grain is wrong or there are duplicates)
SELECT sales_line_key, COUNT(*) FROM FCT_SALES_LINE GROUP BY 1 HAVING COUNT(*) > 1;
SELECT inventory_key, COUNT(*) FROM FCT_INVENTORY_DAILY GROUP BY 1 HAVING COUNT(*) > 1;
SELECT ad_performance_key, COUNT(*) FROM FCT_AD_PERFORMANCE GROUP BY 1 HAVING COUNT(*) > 1;
SELECT customer_sk, COUNT(*) FROM DIM_CUSTOMER GROUP BY 1 HAVING COUNT(*) > 1;
SELECT product_sk, COUNT(*) FROM DIM_PRODUCT GROUP BY 1 HAVING COUNT(*) > 1;

-- 2. REFERENTIAL INTEGRITY: every FK finds its dimension row
SELECT COUNT(*) AS orphan_products  FROM FCT_SALES_LINE f LEFT JOIN DIM_PRODUCT p  ON p.product_sk  = f.product_sk  WHERE p.product_sk IS NULL;
SELECT COUNT(*) AS orphan_customers FROM FCT_SALES_LINE f LEFT JOIN DIM_CUSTOMER c ON c.customer_sk = f.customer_sk WHERE c.customer_sk IS NULL;
SELECT COUNT(*) AS orphan_stores    FROM FCT_SALES_LINE f LEFT JOIN DIM_STORE s    ON s.store_sk    = f.store_sk    WHERE s.store_sk IS NULL;

-- 3. How much maps to the UNKNOWN member? (expected: anonymous store shoppers + guest checkouts)
SELECT channel, ROUND(100 * COUNT_IF(customer_sk = '-1') / COUNT(*), 1) AS pct_unknown_customer,
       COUNT_IF(product_sk = '-1') AS unknown_products
FROM FCT_SALES_LINE GROUP BY 1;

-- 4. SCD2 integrity: exactly one current row, no overlapping versions
SELECT customer_id FROM DIM_CUSTOMER GROUP BY 1 HAVING COUNT_IF(is_current) <> 1;
SELECT sku FROM DIM_PRODUCT GROUP BY 1 HAVING COUNT_IF(is_current) <> 1;

-- 5. RECONCILIATION: warehouse totals vs the POS system's own Z-report, per store-day
WITH wh AS (
  SELECT sale_date, store_id, SUM(net_amount) AS wh_net
  FROM FCT_SALES_LINE WHERE channel = 'STORE' GROUP BY 1, 2
)
SELECT c.business_date, c.store_id, c.net_amount AS pos_net, wh.wh_net,
       ROUND(100 * (COALESCE(wh.wh_net, 0) - c.net_amount) / NULLIF(c.net_amount, 0), 3) AS diff_pct
FROM RETAIL_LAB.STG.POS_CONTROL_TOTALS c
LEFT JOIN wh ON wh.sale_date = c.business_date AND wh.store_id = c.store_id
WHERE ABS(COALESCE(wh.wh_net, 0) - c.net_amount) > 0.005 * ABS(c.net_amount)
ORDER BY 1 DESC;
-- Empty = every store-day within 0.5%. A late file (generator --late-store) shows up here as -100%.

-- 6. SEMI-ADDITIVE trap: summing stock across days is meaningless
SELECT store_id,
       SUM(closing_qty) AS wrong_total_stock_over_all_days,
       SUM(IFF(snapshot_date = (SELECT MAX(snapshot_date) FROM FCT_INVENTORY_DAILY), closing_qty, 0)) AS right_stock_today
FROM FCT_INVENTORY_DAILY GROUP BY 1 ORDER BY 1 LIMIT 5;

-- 7. NON-ADDITIVE trap: average of daily CTRs ≠ overall CTR
SELECT AVG(clicks / NULLIF(impressions, 0))      AS avg_of_ratios_wrong,
       SUM(clicks) / NULLIF(SUM(impressions), 0) AS ratio_of_sums_right
FROM FCT_AD_PERFORMANCE;
