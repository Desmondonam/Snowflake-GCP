/* =============================================================================
   Stage 6 · Step 05 — Account-wide diagnostics and cost control
   -----------------------------------------------------------------------------
   SNOWFLAKE.ACCOUNT_USAGE keeps 365 days of history but lags (45 min – 3 h).
   Use INFORMATION_SCHEMA table functions for the last few hours/days in real time.
   HOW TO RUN: worksheet. Role RETAIL_ADMIN (has IMPORTED PRIVILEGES on SNOWFLAKE).
   ============================================================================= */
USE ROLE RETAIL_ADMIN;
USE WAREHOUSE LAB_WH;

-- 1. Top 10 most expensive (longest) queries, last 7 days — the roadmap query
SELECT query_id, warehouse_name, warehouse_size, user_name, role_name, query_tag,
       total_elapsed_time / 1000 AS secs,
       bytes_spilled_to_local_storage, bytes_spilled_to_remote_storage,
       partitions_scanned, partitions_total, LEFT(query_text, 120) AS q
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
ORDER BY total_elapsed_time DESC
LIMIT 10;

-- 2. Credits by warehouse, last month
SELECT warehouse_name, SUM(credits_used) AS credits,
       SUM(credits_used_compute) AS compute, SUM(credits_used_cloud_services) AS cloud_services
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time > DATEADD(month, -1, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;

-- 3. Cost per TOOL / TEAM via query tags (dbt sets dbt_retail_*, Airflow and Streamlit set their own)
SELECT query_tag, warehouse_name, SUM(credits_attributed_compute) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 3 DESC;

-- 4. Concurrency pressure: are BI users queueing? (justifies multi-cluster scale-OUT)
SELECT warehouse_name, DATE_TRUNC('hour', start_time) AS hour,
       COUNT(*) AS queries,
       SUM(queued_overload_time) / 1000 AS queued_overload_s,
       AVG(total_elapsed_time) / 1000 AS avg_s
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP()) AND warehouse_name = 'BI_WH'
GROUP BY 1, 2 HAVING SUM(queued_overload_time) > 0 ORDER BY 2 DESC;

-- 5. Spilling = warehouse too small for the query (justifies scale-UP or a rewrite)
SELECT warehouse_name, warehouse_size, COUNT(*) AS spilling_queries,
       SUM(bytes_spilled_to_remote_storage) / 1e9 AS remote_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP()) AND bytes_spilled_to_local_storage > 0
GROUP BY 1, 2 ORDER BY 3 DESC;

-- 6. Poor pruning: big scans that read most partitions of big tables
SELECT query_id, warehouse_name, partitions_scanned, partitions_total,
       ROUND(100 * partitions_scanned / NULLIF(partitions_total, 0), 1) AS pct_scanned,
       LEFT(query_text, 100) AS q
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP()) AND partitions_total > 1000
ORDER BY partitions_scanned DESC LIMIT 20;

-- 7. Storage: biggest tables, and how much is Time Travel / Fail-safe (transient saves the latter)
SELECT table_catalog || '.' || table_schema || '.' || table_name AS tbl,
       ROUND(active_bytes / 1e9, 2) AS active_gb, ROUND(time_travel_bytes / 1e9, 2) AS tt_gb,
       ROUND(failsafe_bytes / 1e9, 2) AS failsafe_gb, is_transient
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE deleted = FALSE
ORDER BY active_bytes + time_travel_bytes + failsafe_bytes DESC LIMIT 20;

-- 8. Serverless features you may be paying for in the background
SELECT 'auto clustering' AS feature, SUM(credits_used) AS credits FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
UNION ALL SELECT 'materialized views', SUM(credits_used) FROM SNOWFLAKE.ACCOUNT_USAGE.MATERIALIZED_VIEW_REFRESH_HISTORY WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
UNION ALL SELECT 'search optimization', SUM(credits_used) FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_HISTORY WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
UNION ALL SELECT 'snowpipe', SUM(credits_used) FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
UNION ALL SELECT 'serverless tasks', SUM(credits_used) FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY WHERE start_time > DATEADD(day, -30, CURRENT_TIMESTAMP());

-- 9. Clustering health of the real fact (after dbt built it with cluster_by)
SELECT SYSTEM$CLUSTERING_INFORMATION('RETAIL_MARTS.SALES.FCT_SALES_LINE', '(sale_date, store_id)');

/* ---------------------------------------------------------------------------
   GUARDRAILS (ACCOUNTADMIN)
   --------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;
-- Concurrency for BI: scale OUT on Monday mornings, back to 1 cluster when quiet
ALTER WAREHOUSE BI_WH SET MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD';
-- A daily monitor for the transformation workload.
-- NOTE: a warehouse can have only ONE resource monitor, so this replaces RM_RETAIL_MONTHLY on TRANSFORM_WH.
-- To keep an overall monthly cap as well, add an ACCOUNT-level monitor:
--   CREATE RESOURCE MONITOR IF NOT EXISTS RM_ACCOUNT_MONTHLY WITH CREDIT_QUOTA = 40 FREQUENCY = MONTHLY
--     START_TIMESTAMP = IMMEDIATELY TRIGGERS ON 90 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
--   ALTER ACCOUNT SET RESOURCE_MONITOR = RM_ACCOUNT_MONTHLY;
CREATE RESOURCE MONITOR IF NOT EXISTS RM_TRANSFORM_DAILY
  WITH CREDIT_QUOTA = 5 FREQUENCY = DAILY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE TRANSFORM_WH SET RESOURCE_MONITOR = RM_TRANSFORM_DAILY;
-- Kill runaway queries
ALTER WAREHOUSE TRANSFORM_WH SET STATEMENT_TIMEOUT_IN_SECONDS = 3600 STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600;
SHOW RESOURCE MONITORS;
