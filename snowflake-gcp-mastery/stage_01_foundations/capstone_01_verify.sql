/* =============================================================================
   CAPSTONE 1 (part 3) — Prove it works: roles, Time Travel, UNDROP, cloning
   -----------------------------------------------------------------------------
   HOW TO RUN: Snowsight worksheet, statement by statement. Take screenshots of
   the key results for stage_01_foundations/README.md ("Evidence" section).
   ============================================================================= */

-- 1. The engineer role can build in RETAIL_LAB.
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LAB_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.CAPSTONE_01;
USE SCHEMA RETAIL_LAB.CAPSTONE_01;

CREATE OR REPLACE TABLE STORES (store_id STRING, city STRING, country_code STRING, region STRING);
INSERT INTO STORES VALUES
  ('S001','Nairobi','KE','KE'), ('S002','Mombasa','KE','KE'), ('S013','Doha','QA','QA');
SELECT * FROM STORES;

-- 2. Time Travel: change data, then read the past and restore.
UPDATE STORES SET city = 'UNKNOWN';
SET qid = LAST_QUERY_ID();
SELECT * FROM STORES;                                   -- broken
SELECT * FROM STORES BEFORE(STATEMENT => $qid);         -- the past
INSERT OVERWRITE INTO STORES SELECT * FROM STORES BEFORE(STATEMENT => $qid);
SELECT * FROM STORES;                                   -- restored

-- 3. UNDROP.
DROP TABLE STORES;
UNDROP TABLE STORES;
SELECT COUNT(*) AS rows_after_undrop FROM STORES;      -- 3

-- 4. Zero-copy clone of the whole schema, change the clone, original untouched.
CREATE OR REPLACE SCHEMA RETAIL_LAB.CAPSTONE_01_CLONE CLONE RETAIL_LAB.CAPSTONE_01;
DELETE FROM RETAIL_LAB.CAPSTONE_01_CLONE.STORES WHERE country_code = 'QA';
SELECT 'original' AS which, COUNT(*) FROM RETAIL_LAB.CAPSTONE_01.STORES
UNION ALL
SELECT 'clone', COUNT(*) FROM RETAIL_LAB.CAPSTONE_01_CLONE.STORES;   -- 3 vs 2
DROP SCHEMA RETAIL_LAB.CAPSTONE_01_CLONE;

-- 5. The analyst role cannot write to RETAIL_LAB and cannot see RAW.
-- IMPORTANT: new users default to DEFAULT_SECONDARY_ROLES = ('ALL'), which means every role
-- granted to you is active at once and the tests below would wrongly succeed.
-- Turn secondary roles off so ONLY the primary role counts:
USE SECONDARY ROLES NONE;
USE ROLE RETAIL_ANALYST;
USE WAREHOUSE BI_WH;
-- Each of these should FAIL with "does not exist or not authorized". Run one at a time:
-- SELECT * FROM RETAIL_LAB.CAPSTONE_01.STORES;
-- CREATE SCHEMA RETAIL_MARTS.HACK;
SHOW DATABASES LIKE 'RETAIL_%';   -- analyst only sees RETAIL_MARTS

-- 6. Guardrail is attached.
USE SECONDARY ROLES ALL;   -- back to the default
USE ROLE ACCOUNTADMIN;
SHOW RESOURCE MONITORS;
SHOW WAREHOUSES;   -- resource_monitor column = RM_RETAIL_MONTHLY for the four warehouses

-- 7. Role hierarchy as a table (who inherits whom).
SHOW GRANTS OF ROLE RETAIL_ANALYST;
SHOW GRANTS OF ROLE RETAIL_ENGINEER;
SHOW GRANTS OF ROLE RETAIL_ADMIN;
