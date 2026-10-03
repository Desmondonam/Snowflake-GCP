/* =============================================================================
   Stage 6 · Step 02 — A measurement harness: record every experiment as data
   -----------------------------------------------------------------------------
   After each benchmark query you run:
       CALL RETAIL_LAB.PERF.RECORD_RESULT('Q1', 'baseline', LAST_QUERY_ID());
   and the procedure stores elapsed time, partitions scanned/total (pruning),
   bytes scanned, spilling and an estimated credit cost in BENCHMARK_RESULTS.
   Your before/after table for the README is then one SELECT away.

   Sources: INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION (timings, sizes) and
            GET_QUERY_OPERATOR_STATS (per-operator pruning + spilling, the Query Profile as data).
   HOW TO RUN: snow sql -c retail_engineer -f stage_06_performance/02_measurement_harness.sql
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE PERF_WH;
USE SCHEMA RETAIL_LAB.PERF;

CREATE TABLE IF NOT EXISTS BENCHMARK_RESULTS (
  recorded_at        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
  query_label        STRING,
  variant            STRING,
  query_id           STRING,
  warehouse_size     STRING,
  elapsed_s          NUMBER(10,2),
  partitions_scanned NUMBER,
  partitions_total   NUMBER,
  pct_scanned        NUMBER(6,2),
  bytes_scanned_mb   NUMBER(14,1),
  spilled_local_mb   NUMBER(14,1),
  spilled_remote_mb  NUMBER(14,1),
  est_credits        NUMBER(12,6)   -- execution time × size rate; ignores the 60 s resume minimum and idle time
);

CREATE OR REPLACE PROCEDURE RECORD_RESULT(QUERY_LABEL STRING, VARIANT_LABEL STRING, QID STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER          -- needs the caller's session to see its query history
AS
$$
BEGIN
  INSERT INTO RETAIL_LAB.PERF.BENCHMARK_RESULTS
    (query_label, variant, query_id, warehouse_size, elapsed_s, partitions_scanned, partitions_total,
     pct_scanned, bytes_scanned_mb, spilled_local_mb, spilled_remote_mb, est_credits)
  WITH h AS (
    SELECT query_id, warehouse_size, total_elapsed_time, execution_time, bytes_scanned
    FROM TABLE(RETAIL_LAB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 1000))
    WHERE query_id = :QID
  ),
  ops AS (
    SELECT SUM(operator_statistics:pruning:partitions_scanned::NUMBER)          AS partitions_scanned,
           SUM(operator_statistics:pruning:partitions_total::NUMBER)            AS partitions_total,
           SUM(operator_statistics:spilling:bytes_spilled_local_storage::NUMBER)  AS spill_local,
           SUM(operator_statistics:spilling:bytes_spilled_remote_storage::NUMBER) AS spill_remote
    FROM TABLE(GET_QUERY_OPERATOR_STATS(:QID))
  )
  SELECT :QUERY_LABEL, :VARIANT_LABEL, h.query_id, h.warehouse_size,
         h.total_elapsed_time / 1000,
         ops.partitions_scanned, ops.partitions_total,
         100 * ops.partitions_scanned / NULLIF(ops.partitions_total, 0),
         h.bytes_scanned / 1e6,
         COALESCE(ops.spill_local, 0) / 1e6,
         COALESCE(ops.spill_remote, 0) / 1e6,
         h.execution_time / 1000 / 3600 *
           DECODE(h.warehouse_size, 'X-Small', 1, 'Small', 2, 'Medium', 4, 'Large', 8, 'X-Large', 16, '2X-Large', 32, NULL)
  FROM h CROSS JOIN ops;
  RETURN 'recorded ' || :QUERY_LABEL || ' / ' || :VARIANT_LABEL;
END;
$$;

-- Smoke test
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT COUNT(*) FROM DIM_STORE_BIG WHERE store_region = 'KE';
CALL RECORD_RESULT('SMOKE', 'test', LAST_QUERY_ID());
SELECT * FROM BENCHMARK_RESULTS ORDER BY recorded_at DESC;
DELETE FROM BENCHMARK_RESULTS WHERE query_label = 'SMOKE';
