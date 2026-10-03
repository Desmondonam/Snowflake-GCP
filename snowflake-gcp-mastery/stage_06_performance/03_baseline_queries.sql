/* =============================================================================
   Stage 6 · Step 03 — Baseline: five typical retail queries on the unclustered table
   -----------------------------------------------------------------------------
   HOW TO RUN: Snowsight worksheet, ONE query at a time, each followed by its CALL.
   After each query, ALSO open its Query Profile (… → View Query Profile) and note:
     * the most expensive operator (% of time)
     * "Partitions scanned" vs "Partitions total" on the TableScan
     * "Bytes spilled to local/remote storage"
     * rows in vs rows out on joins (explosions)
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE PERF_WH;                       -- XSMALL
USE SCHEMA RETAIL_LAB.PERF;
ALTER SESSION SET USE_CACHED_RESULT = FALSE; -- measure compute, not the result cache
ALTER SESSION SET QUERY_TAG = 'stage06_baseline';

-- Q1 · Weekly sales by store, last 4 weeks of 2025 (the dashboard that "takes 90 seconds")
SELECT store_id, DATE_TRUNC('week', sale_date) AS week, SUM(net_amount) AS net_sales
FROM FCT_SALES_LINE_BIG
WHERE sale_date >= '2025-12-01' AND sale_date < '2025-12-29'
GROUP BY 1, 2;
CALL RECORD_RESULT('Q1 weekly store sales', 'baseline', LAST_QUERY_ID());

-- Q2 · Same month, filter written with a FUNCTION on the column (common anti-pattern)
SELECT store_region, SUM(net_amount) AS net_sales
FROM FCT_SALES_LINE_BIG
WHERE TO_CHAR(sale_date, 'YYYY-MM') = '2025-11'
GROUP BY 1;
CALL RECORD_RESULT('Q2 month by region', 'baseline (function filter)', LAST_QUERY_ID());

-- Q3 · Black Friday week by category (join to a dimension)
SELECT p.category, SUM(f.net_amount) AS net_sales, SUM(f.net_amount - f.cost_amount) AS margin
FROM FCT_SALES_LINE_BIG f
JOIN DIM_PRODUCT_BIG p ON p.sku = f.sku
WHERE f.sale_date BETWEEN '2025-11-24' AND '2025-11-30'
GROUP BY 1 ORDER BY 2 DESC;
CALL RECORD_RESULT('Q3 black friday by category', 'baseline', LAST_QUERY_ID());

-- Q4 · One loyalty customer's history (customer service screen: a needle in a haystack)
SELECT sale_date, store_id, sku, quantity, net_amount
FROM FCT_SALES_LINE_BIG
WHERE loyalty_id = 'L0012345'
ORDER BY sale_date;
CALL RECORD_RESULT('Q4 point lookup loyalty_id', 'baseline', LAST_QUERY_ID());

-- Q5 · Distinct customers per store per month for 2025 (memory-hungry: watch for spilling)
SELECT store_id, DATE_TRUNC('month', sale_date) AS month, COUNT(DISTINCT customer_id) AS customers
FROM FCT_SALES_LINE_BIG
WHERE sale_date >= '2025-01-01'
GROUP BY 1, 2;
CALL RECORD_RESULT('Q5 distinct customers', 'baseline XS', LAST_QUERY_ID());

-- Q6 · Daily sales by region for 2025 (the executive dashboard, run 500x a day)
SELECT sale_date, store_region, SUM(net_amount) AS net_sales, COUNT(*) AS lines
FROM FCT_SALES_LINE_BIG
WHERE sale_date >= '2025-01-01'
GROUP BY 1, 2;
CALL RECORD_RESULT('Q6 daily region dashboard', 'baseline', LAST_QUERY_ID());

ALTER SESSION UNSET QUERY_TAG;

SELECT query_label, variant, warehouse_size, elapsed_s, partitions_scanned, partitions_total, pct_scanned,
       bytes_scanned_mb, spilled_local_mb, spilled_remote_mb, est_credits
FROM BENCHMARK_RESULTS ORDER BY recorded_at;
-- Expect pct_scanned near 100% for Q1–Q3 and Q6 even though they ask for days/weeks: no pruning.
