/* =============================================================================
   Stage 7 · Step 05 — Data Metric Functions (DMFs): quality measured by Snowflake
   -----------------------------------------------------------------------------
   dbt tests run when dbt runs. DMFs run ON THE TABLE, on a schedule or whenever
   it changes, whoever writes to it — a second line of defence, and results are
   queryable history (SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS).

   System DMFs: NULL_COUNT, NULL_PERCENT, DUPLICATE_COUNT, UNIQUE_COUNT, ROW_COUNT,
                FRESHNESS, AVG/MIN/MAX/STDDEV, BLANK_COUNT, ACCEPTED_VALUES…
   Custom DMFs: your own SQL returning a number.

   HOW TO RUN: worksheet, section by section. Run sections 1–2 ONCE: adding the same DMF twice errors
               (check what's attached with the DATA_METRIC_FUNCTION_REFERENCES query below).
   ============================================================================= */

-- Privileges (once)
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE RETAIL_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE RETAIL_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE RETAIL_ADMIN;

USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;

/* ---------------------------------------------------------------------------
   1. The two biggest tables: RAW POS lines and the sales fact
   --------------------------------------------------------------------------- */
-- RAW: check hourly
ALTER TABLE RETAIL_RAW.POS.SALES_LINES SET DATA_METRIC_SCHEDULE = '60 MINUTE';
ALTER TABLE RETAIL_RAW.POS.SALES_LINES ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();
ALTER TABLE RETAIL_RAW.POS.SALES_LINES ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (_loaded_at);
ALTER TABLE RETAIL_RAW.POS.SALES_LINES ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (store_id);

-- FACT: check whenever it changes (after each dbt incremental run)
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (sales_line_key);
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (store_region);

/* ---------------------------------------------------------------------------
   2. A custom DMF: non-return lines with negative net amount (should be 0)
   --------------------------------------------------------------------------- */
CREATE DATA METRIC FUNCTION IF NOT EXISTS RETAIL_MARTS.OPS.DMF_NEGATIVE_NET_NON_RETURN(
  arg_t TABLE(arg_net NUMBER, arg_is_return BOOLEAN))
RETURNS NUMBER
AS
$$
  SELECT COUNT_IF(arg_net < 0 AND NOT arg_is_return) FROM arg_t
$$;

ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE
  ADD DATA METRIC FUNCTION RETAIL_MARTS.OPS.DMF_NEGATIVE_NET_NON_RETURN ON (net_amount, is_return);

-- What is attached?
SELECT metric_name, ref_arguments, schedule, schedule_status
FROM TABLE(RETAIL_MARTS.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME => 'RETAIL_MARTS.SALES.FCT_SALES_LINE', REF_ENTITY_DOMAIN => 'table'));

-- Run a DMF ad hoc (no schedule needed) — handy while developing
SELECT SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT sales_line_key FROM RETAIL_MARTS.SALES.FCT_SALES_LINE) AS dup_keys;
SELECT RETAIL_MARTS.OPS.DMF_NEGATIVE_NET_NON_RETURN(SELECT net_amount, is_return FROM RETAIL_MARTS.SALES.FCT_SALES_LINE) AS bad_lines;

/* ---------------------------------------------------------------------------
   3. Results (populate after the schedule fires: hourly / after the next dbt run)
   --------------------------------------------------------------------------- */
USE ROLE RETAIL_ADMIN;
SELECT measurement_time, table_database || '.' || table_schema || '.' || table_name AS tbl,
       metric_name, argument_names, value
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
ORDER BY measurement_time DESC
LIMIT 50;

/* NOTES
   * DMF schedules bill serverless credits. In a lab, '60 MINUTE' on RAW is plenty; remove when done:
       ALTER TABLE RETAIL_RAW.POS.SALES_LINES UNSET DATA_METRIC_SCHEDULE;
   * A dbt --full-refresh of FCT_SALES_LINE recreates the table and drops its DMFs: re-run this section,
     or attach DMFs from a dbt post-hook like apply_governance does for tags.
   * Alerting: CREATE ALERT … IF (EXISTS (SELECT … FROM DATA_QUALITY_MONITORING_RESULTS WHERE value > 0 …))
     THEN CALL SYSTEM$SEND_EMAIL(…) — or let Airflow query the results table. */
