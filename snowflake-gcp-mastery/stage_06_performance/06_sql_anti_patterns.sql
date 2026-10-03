/* =============================================================================
   Stage 6 · Step 06 — SQL anti-patterns and their fixes (on the perf tables)
   Run each pair, compare in Query Profile. Role RETAIL_ENGINEER, PERF_WH XSMALL.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE PERF_WH;
USE SCHEMA RETAIL_LAB.PERF;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 1. SELECT * on a wide table: columnar storage reads only the columns you name.
SELECT * FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-28' LIMIT 1000;          -- reads all columns
SELECT sale_date, store_id, net_amount FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-28' LIMIT 1000;

-- 2. ORDER BY without LIMIT on a huge result: a global sort of millions of rows nobody reads.
-- SELECT * FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01' ORDER BY net_amount DESC;   -- don't
SELECT sales_line_id, net_amount FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date >= '2025-01-01'
ORDER BY net_amount DESC LIMIT 100;                                                             -- top-N is cheap

-- 3. UNION where UNION ALL is correct: UNION adds a de-duplication step (sort/hash of everything).
SELECT store_id FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-28'
UNION
SELECT store_id FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-29';
SELECT store_id FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-28'
UNION ALL
SELECT store_id FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-29';

-- 4. Joining on mismatched types forces a cast on every row and can block pruning/join optimizations.
CREATE OR REPLACE TEMPORARY TABLE STORE_NUMBERS AS SELECT ROW_NUMBER() OVER (ORDER BY store_id) AS store_no, store_id FROM DIM_STORE_BIG;
-- bad: SUBSTR(...)::INT compared with a number on every fact row
SELECT COUNT(*) FROM FCT_SALES_LINE_CLUSTERED f JOIN STORE_NUMBERS s ON SUBSTR(f.store_id, 2)::INT = s.store_no
WHERE f.sale_date = '2025-11-28';
-- good: join on the same typed key
SELECT COUNT(*) FROM FCT_SALES_LINE_CLUSTERED f JOIN STORE_NUMBERS s ON f.store_id = s.store_id
WHERE f.sale_date = '2025-11-28';

-- 5. Exploding join: joining a fact to a NON-unique side multiplies rows (and revenue!).
--    Query Profile: join output rows ≫ input rows. Always know the grain of both sides.
CREATE OR REPLACE TEMPORARY TABLE PRODUCT_PRICES_DUP AS
SELECT sku, 1 AS v FROM DIM_PRODUCT_BIG UNION ALL SELECT sku, 2 FROM DIM_PRODUCT_BIG;   -- 2 rows per sku
SELECT SUM(f.net_amount) FROM FCT_SALES_LINE_CLUSTERED f JOIN PRODUCT_PRICES_DUP p ON p.sku = f.sku
WHERE f.sale_date = '2025-11-28';                                                       -- doubled revenue
SELECT SUM(net_amount) FROM FCT_SALES_LINE_CLUSTERED WHERE sale_date = '2025-11-28';    -- the truth

-- 6. Row-by-row processing (a loop of single-row UPDATEs in a procedure or app) instead of ONE set-based statement.
--    Every statement has overhead and creates new micro-partitions. Use one UPDATE/MERGE with a join.

-- 7. Dashboards that defeat the result cache: CURRENT_TIMESTAMP() / RANDOM() in the SQL text,
--    or a different literal each refresh. Parameterise on dates, not timestamps.
