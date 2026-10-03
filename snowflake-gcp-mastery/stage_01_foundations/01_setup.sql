/* =============================================================================
   Stage 1 · Lesson 01 — First objects: a warehouse, a database, a schema
   -----------------------------------------------------------------------------
   HOW TO RUN
     Snowsight: Projects → Worksheets → + → paste this file → run each statement
                with Ctrl+Enter, reading the result before moving on.
     CLI:       snow sql -f stage_01_foundations/01_setup.sql
   ROLE: SYSADMIN (the role that should own databases and warehouses).
   COST: an XSMALL warehouse = 1 credit/hour, billed per second (60 s minimum
         each time it resumes). With AUTO_SUSPEND = 60 an idle warehouse stops
         after one minute.
   ============================================================================= */

-- 0. Who and where am I? Every session has a role, a warehouse, a database and a schema.
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();

-- 1. Never build objects as ACCOUNTADMIN. SYSADMIN is the system role meant to own objects.
USE ROLE SYSADMIN;

-- 2. A virtual warehouse = compute. It holds no data; it only runs queries.
CREATE WAREHOUSE IF NOT EXISTS LAB_WH
  WITH WAREHOUSE_SIZE = XSMALL
       AUTO_SUSPEND = 60            -- seconds idle before it stops billing
       AUTO_RESUME = TRUE           -- starts automatically when a query needs it
       INITIALLY_SUSPENDED = TRUE   -- don't start billing at creation
       COMMENT = 'Learning / lab work';

-- 3. Database and schema = containers for tables, views, stages, etc.
CREATE DATABASE IF NOT EXISTS RETAIL_ANALYTICS COMMENT = 'Stage 1 sandbox';
CREATE SCHEMA IF NOT EXISTS RETAIL_ANALYTICS.SANDBOX COMMENT = 'Throwaway experiments';

-- 4. Set the session context so later statements don't need fully qualified names.
USE WAREHOUSE LAB_WH;
USE SCHEMA RETAIL_ANALYTICS.SANDBOX;
SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();

-- 5. Look around the object hierarchy: account → database → schema → objects.
SHOW WAREHOUSES;
SHOW DATABASES;
SHOW SCHEMAS IN DATABASE RETAIL_ANALYTICS;   -- note PUBLIC and INFORMATION_SCHEMA are created for you

-- 6. Snowflake ships sample data as a shared database.
--    If this fails with "does not exist", run (as ACCOUNTADMIN, once):
--      CREATE DATABASE SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
--      GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE SYSADMIN;
SHOW SCHEMAS IN DATABASE SNOWFLAKE_SAMPLE_DATA;
SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;   -- 1.5M rows

-- 7. Copy sample data into your own table (CTAS = CREATE TABLE AS SELECT).
CREATE OR REPLACE TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT * FROM RETAIL_ANALYTICS.SANDBOX.ORDERS LIMIT 10;

-- 8. Describe the table: column names and types.
DESC TABLE RETAIL_ANALYTICS.SANDBOX.ORDERS;

-- 9. INFORMATION_SCHEMA: every database has a read-only catalog you can query with SQL.
SELECT table_name, table_type, row_count, bytes
FROM RETAIL_ANALYTICS.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SANDBOX';
