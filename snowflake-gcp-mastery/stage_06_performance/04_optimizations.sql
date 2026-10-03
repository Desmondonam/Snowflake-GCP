/* =============================================================================
   Stage 6 · Step 04 — Fix it, one technique at a time, measuring after each
   -----------------------------------------------------------------------------
   A. Clustering            → pruning for date/store filters          (Q1, Q3, Q6)
   B. Rewrite the filter    → let pruning work                        (Q2)
   C. Scale up              → stop spilling for a heavy aggregation   (Q5)
   D. Materialized view     → precomputed aggregate for a hot query   (Q6)
   E. Search optimization   → point lookups on a high-cardinality col (Q4)
   F. Query acceleration    → offload scan-heavy outliers             (Q5)
   HOW TO RUN: worksheet, section by section. Each query is followed by its CALL.
   COST NOTE: sections E and F use serverless features that bill credits in the
   background. Do them, record, then run the CLEAN UP section.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE PERF_WH;
USE SCHEMA RETAIL_LAB.PERF;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'stage06_optimized';

/* ---------------------------------------------------------------------------
   A. CLUSTERING
   Lab shortcut: rewrite the table sorted by the clustering key (one-off cost),
   then declare the key so Automatic Clustering keeps it sorted as data arrives.
   In production on an existing table you'd only ALTER … CLUSTER BY and let the
   background service recluster (it bills credits — check before enabling).
   --------------------------------------------------------------------------- */
ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = MEDIUM;
CREATE OR REPLACE TABLE FCT_SALES_LINE_CLUSTERED
  CLUSTER BY (sale_date, store_id)
AS SELECT * FROM FCT_SALES_LINE_BIG ORDER BY sale_date, store_id;
ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = XSMALL;

SELECT SYSTEM$CLUSTERING_INFORMATION('RETAIL_LAB.PERF.FCT_SALES_LINE_CLUSTERED');  -- average_depth ≈ 1
ALTER TABLE FCT_SALES_LINE_CLUSTERED SUSPEND RECLUSTER;   -- lab: no background reclustering needed (no new data)

SELECT store_id, DATE_TRUNC('week', sale_date) AS week, SUM(net_amount) AS net_sales
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-12-01' AND sale_date < '2025-12-29' GROUP BY 1, 2;
CALL RECORD_RESULT('Q1 weekly store sales', 'clustered', LAST_QUERY_ID());

SELECT p.category, SUM(f.net_amount) AS net_sales, SUM(f.net_amount - f.cost_amount) AS margin
FROM FCT_SALES_LINE_CLUSTERED f JOIN DIM_PRODUCT_BIG p ON p.sku = f.sku
WHERE f.sale_date BETWEEN '2025-11-24' AND '2025-11-30' GROUP BY 1 ORDER BY 2 DESC;
CALL RECORD_RESULT('Q3 black friday by category', 'clustered', LAST_QUERY_ID());

SELECT sale_date, store_region, SUM(net_amount) AS net_sales, COUNT(*) AS lines
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' GROUP BY 1, 2;
CALL RECORD_RESULT('Q6 daily region dashboard', 'clustered', LAST_QUERY_ID());

/* ---------------------------------------------------------------------------
   B. REWRITE THE FILTER (Q2). Same question, two filters, same clustered table.
   --------------------------------------------------------------------------- */
SELECT store_region, SUM(net_amount) FROM FCT_SALES_LINE_CLUSTERED
WHERE TO_CHAR(sale_date, 'YYYY-MM') = '2025-11' GROUP BY 1;
CALL RECORD_RESULT('Q2 month by region', 'clustered, function filter', LAST_QUERY_ID());

SELECT store_region, SUM(net_amount) FROM FCT_SALES_LINE_CLUSTERED
WHERE sale_date >= '2025-11-01' AND sale_date < '2025-12-01' GROUP BY 1;
CALL RECORD_RESULT('Q2 month by region', 'clustered, range filter', LAST_QUERY_ID());
-- (Snowflake can sometimes prune through simple functions; a plain range on the column always works.)

/* ---------------------------------------------------------------------------
   C. SCALE UP for the spilling query (Q5). Bigger warehouse = more memory + local disk.
   Compare elapsed_s AND est_credits: if time halves when size doubles, cost is flat.
   --------------------------------------------------------------------------- */
ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = SMALL;
SELECT store_id, DATE_TRUNC('month', sale_date) AS month, COUNT(DISTINCT customer_id) AS customers
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' GROUP BY 1, 2;
CALL RECORD_RESULT('Q5 distinct customers', 'clustered S', LAST_QUERY_ID());

ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = MEDIUM;
SELECT store_id, DATE_TRUNC('month', sale_date) AS month, COUNT(DISTINCT customer_id) AS customers
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' GROUP BY 1, 2;
CALL RECORD_RESULT('Q5 distinct customers', 'clustered M', LAST_QUERY_ID());

-- Approximate alternative when exact counts aren't required (HyperLogLog: tiny memory)
SELECT store_id, DATE_TRUNC('month', sale_date) AS month, APPROX_COUNT_DISTINCT(customer_id) AS customers
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' GROUP BY 1, 2;
CALL RECORD_RESULT('Q5 distinct customers', 'approx M', LAST_QUERY_ID());
ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = XSMALL;

/* ---------------------------------------------------------------------------
   D. MATERIALIZED VIEW for the hot dashboard (Q6). Enterprise feature.
   The optimizer can answer queries on the BASE table from the MV automatically.
   MVs are maintained in the background (serverless credits) as the table changes.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE MATERIALIZED VIEW MV_DAILY_REGION_SALES AS
SELECT sale_date, store_region, SUM(net_amount) AS net_sales, COUNT(*) AS lines
FROM FCT_SALES_LINE_CLUSTERED
GROUP BY sale_date, store_region;

SELECT sale_date, store_region, SUM(net_amount) AS net_sales, COUNT(*) AS lines
FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' GROUP BY 1, 2;
CALL RECORD_RESULT('Q6 daily region dashboard', 'materialized view', LAST_QUERY_ID());
-- Query Profile should show MV_DAILY_REGION_SALES being scanned instead of the fact.

/* ---------------------------------------------------------------------------
   E. SEARCH OPTIMIZATION for the needle-in-a-haystack lookup (Q4).
   Builds a search access path in the background; check progress before measuring.
   --------------------------------------------------------------------------- */
ALTER TABLE FCT_SALES_LINE_CLUSTERED ADD SEARCH OPTIMIZATION ON EQUALITY(loyalty_id);
SHOW TABLES LIKE 'FCT_SALES_LINE_CLUSTERED';   -- wait until search_optimization_progress = 100 (can take a while)

SELECT sale_date, store_id, sku, quantity, net_amount
FROM FCT_SALES_LINE_CLUSTERED WHERE loyalty_id = 'L0012345' ORDER BY sale_date;
CALL RECORD_RESULT('Q4 point lookup loyalty_id', 'search optimization', LAST_QUERY_ID());

/* ---------------------------------------------------------------------------
   F. QUERY ACCELERATION SERVICE: would Q5's baseline benefit?
   --------------------------------------------------------------------------- */
SELECT query_id FROM BENCHMARK_RESULTS WHERE query_label LIKE 'Q5%' AND variant = 'baseline XS';
-- paste that id:
-- SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>'));
-- If eligible:
-- ALTER WAREHOUSE PERF_WH SET ENABLE_QUERY_ACCELERATION = TRUE QUERY_ACCELERATION_MAX_SCALE_FACTOR = 4;
-- rerun the baseline Q5 on FCT_SALES_LINE_BIG, CALL RECORD_RESULT('Q5 distinct customers', 'QAS XS', LAST_QUERY_ID());
-- ALTER WAREHOUSE PERF_WH SET ENABLE_QUERY_ACCELERATION = FALSE;

ALTER SESSION UNSET QUERY_TAG;

/* ---------------------------------------------------------------------------
   RESULTS — copy this into stage_06_performance/results.md
   --------------------------------------------------------------------------- */
SELECT query_label, variant, warehouse_size, elapsed_s, pct_scanned, bytes_scanned_mb,
       spilled_local_mb + spilled_remote_mb AS spilled_mb, ROUND(est_credits, 5) AS est_credits
FROM BENCHMARK_RESULTS
ORDER BY query_label, recorded_at;

/* ---------------------------------------------------------------------------
   CLEAN UP (stop background costs)
   --------------------------------------------------------------------------- */
-- ALTER TABLE FCT_SALES_LINE_CLUSTERED DROP SEARCH OPTIMIZATION;
-- DROP MATERIALIZED VIEW MV_DAILY_REGION_SALES;
-- ALTER WAREHOUSE PERF_WH SET WAREHOUSE_SIZE = XSMALL ENABLE_QUERY_ACCELERATION = FALSE;
-- After the interview prep is over: DROP SCHEMA RETAIL_LAB.PERF;
