/* =============================================================================
   Stage 7 · Step 07 — "Log in" as each role and screenshot what it sees
   -----------------------------------------------------------------------------
   Run statement by statement in a worksheet. Screenshot each role's two results
   for the README (Capstone 7 evidence, acceptance test 4).
   ============================================================================= */

-- CRUCIAL: with secondary roles ALL (the default for new users) every role granted to you is
-- active at once, so you'd see clear emails and all regions in every test. Turn them off:
USE SECONDARY ROLES NONE;

-- ---- Analyst: masked PII, Kenya only -------------------------------------------
USE ROLE FR_ANALYST;
USE WAREHOUSE BI_WH;
SELECT customer_id, email, phone, first_name, birth_date, loyalty_tier
FROM RETAIL_MARTS.CORE.DIM_CUSTOMER WHERE customer_source = 'CRM' AND is_current LIMIT 5;
SELECT store_region, COUNT(*) AS lines, SUM(net_amount) AS net FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1;
-- expect: *****@example.com, ********1234, ***, 19xx-01-01 · only KE
-- SELECT * FROM RETAIL_MARTS.MARKETING.AUD_LAPSED_HIGH_VALUE LIMIT 5;   -- should FAIL: no access to MARKETING

-- ---- Qatar regional manager: Qatar only ------------------------------------------
USE ROLE FR_REGION_QA_MANAGER;
SELECT store_region, COUNT(*) AS lines, SUM(net_amount) AS net FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1;
-- expect: only QA

-- ---- Marketing: clear PII (activation), both regions, audience table -------------
USE ROLE FR_MARKETING;
SELECT customer_id, email, phone FROM RETAIL_MARTS.MARKETING.AUD_LAPSED_HIGH_VALUE LIMIT 5;
SELECT store_region, COUNT(*) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1;
-- expect: clear emails · KE and QA

-- ---- Data scientist: masked PII, both regions, staging allowed -------------------
USE ROLE FR_DATA_SCIENTIST;
USE WAREHOUSE LAB_WH;
SELECT customer_id, email, birth_date FROM RETAIL_MARTS.CORE.DIM_CUSTOMER WHERE is_current LIMIT 5;
SELECT store_region, COUNT(*) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1;
SELECT COUNT(*) FROM RETAIL_STAGING.POS.STG_POS__SALES_LINES;
-- SELECT COUNT(*) FROM RETAIL_RAW.POS.SALES_LINES;   -- should FAIL: nobody human reads RAW

-- ---- Engineer (pipeline role): everything -----------------------------------------
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
SELECT store_region, COUNT(*) FROM RETAIL_MARTS.SALES.FCT_SALES_LINE GROUP BY 1;

-- Back to normal
USE SECONDARY ROLES ALL;
