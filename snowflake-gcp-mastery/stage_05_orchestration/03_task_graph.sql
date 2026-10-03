/* =============================================================================
   Stage 5 · Lesson 03 — Task graphs (DAGs inside Snowflake), serverless tasks,
                         finalizers and monitoring
   -----------------------------------------------------------------------------
   Graph:   T_ROOT_HOURLY (schedule)
              ├── T_RFM_REFRESH     CALL the Snowpark procedure from Stage 4
              └── T_DQ_FRESHNESS    record freshness of RAW feeds
                     (both finished) → T_PUBLISH_LOG
            T_FINALIZE (runs after the graph, success OR failure — like try/finally)

   PREREQUISITE: Stage 4 lesson 03 created RETAIL_LAB.SNOWPARK.BUILD_RFM.
   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.TASKS_DEMO;
USE SCHEMA RETAIL_LAB.TASKS_DEMO;

CREATE TABLE IF NOT EXISTS PIPELINE_LOG (
  run_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), step STRING, detail VARIANT);

-- Root task: serverless (no WAREHOUSE), CRON schedule with a time zone.
CREATE OR REPLACE TASK T_ROOT_HOURLY
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SCHEDULE = 'USING CRON 0 * * * * Africa/Nairobi'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3            -- stop hammering a broken pipeline
  COMMENT = 'Hourly in-warehouse refresh graph'
AS
  INSERT INTO PIPELINE_LOG (step, detail) SELECT 'root', OBJECT_CONSTRUCT('graph_run', SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'));

CREATE OR REPLACE TASK T_RFM_REFRESH
  WAREHOUSE = TRANSFORM_WH
  AFTER T_ROOT_HOURLY
AS
  CALL RETAIL_LAB.SNOWPARK.BUILD_RFM('RETAIL_LAB.SNOWPARK.CUSTOMER_RFM');

CREATE OR REPLACE TASK T_DQ_FRESHNESS
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  AFTER T_ROOT_HOURLY
AS
  INSERT INTO PIPELINE_LOG (step, detail)
  SELECT 'freshness', OBJECT_CONSTRUCT(
    'pos_minutes_since_load',  DATEDIFF('minute', (SELECT MAX(_loaded_at) FROM RETAIL_RAW.POS.SALES_LINES), CURRENT_TIMESTAMP()),
    'crm_minutes_since_load',  DATEDIFF('minute', (SELECT MAX(_loaded_at) FROM RETAIL_RAW.CRM.CUSTOMERS), CURRENT_TIMESTAMP()),
    'ads_minutes_since_load',  DATEDIFF('minute', (SELECT MAX(_loaded_at) FROM RETAIL_RAW.ADS.AD_PERFORMANCE), CURRENT_TIMESTAMP()));

-- A task with TWO predecessors runs after both have succeeded.
CREATE OR REPLACE TASK T_PUBLISH_LOG
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  AFTER T_RFM_REFRESH, T_DQ_FRESHNESS
AS
  INSERT INTO PIPELINE_LOG (step, detail) SELECT 'published', OBJECT_CONSTRUCT('ok', TRUE);

-- Finalizer: always runs at the end of the graph (cleanup, notifications).
CREATE OR REPLACE TASK T_FINALIZE
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  FINALIZE = T_ROOT_HOURLY
AS
  INSERT INTO PIPELINE_LOG (step, detail) SELECT 'finalize', OBJECT_CONSTRUCT('note', 'graph finished');

-- Resume every task in the graph (children first is required; this function does it for you)
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('RETAIL_LAB.TASKS_DEMO.T_ROOT_HOURLY');
SHOW TASKS IN SCHEMA RETAIL_LAB.TASKS_DEMO;        -- state = started; predecessors column shows the graph

-- Run the whole graph now instead of waiting for the hour
EXECUTE TASK T_ROOT_HOURLY;

-- Monitor (wait ~1 minute)
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP())))
WHERE database_name = 'RETAIL_LAB'
ORDER BY scheduled_time DESC;

SELECT * FROM TABLE(INFORMATION_SCHEMA.COMPLETE_TASK_GRAPHS()) ORDER BY scheduled_time DESC LIMIT 5;
SELECT * FROM PIPELINE_LOG ORDER BY run_at DESC;

-- Snowsight: Monitoring → Task History shows the graph visually. Open it.

-- IMPORTANT: suspend the graph when you're done (root first)
ALTER TASK T_ROOT_HOURLY SUSPEND;

/* NOTES
   * To change a task in a running graph: suspend the ROOT, alter/recreate, re-enable.
   * Tasks run as the task OWNER's role → grants matter (the owner needs privileges on everything it touches).
   * Error notifications: ALTER TASK … SET ERROR_INTEGRATION = <notification integration to Pub/Sub>.
   * Serverless vs warehouse tasks: serverless sizes itself and bills per second of compute (1.2x multiplier,
     no 60 s minimum) — good for short frequent jobs; warehouse tasks share a warehouse you already pay for. */
