/* =============================================================================
   Stage 1 · Lesson 05 — Semi-structured data: VARIANT, OBJECT, ARRAY, FLATTEN
   -----------------------------------------------------------------------------
   Retail sources send JSON (CRM customers, web events, ads APIs). Snowflake stores
   JSON in a VARIANT column and lets you query it with path notation, without
   defining a schema first ("schema-on-read").
   HOW TO RUN: worksheet, statement by statement. Role SYSADMIN.
   ============================================================================= */
USE ROLE SYSADMIN;
USE WAREHOUSE LAB_WH;
USE SCHEMA RETAIL_ANALYTICS.SANDBOX;

CREATE OR REPLACE TABLE EVENTS (v VARIANT, loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

-- PARSE_JSON turns text into VARIANT. INSERT ... SELECT is needed (VALUES can't call PARSE_JSON).
INSERT INTO EVENTS (v)
SELECT PARSE_JSON(column1) FROM VALUES
 ('{"order_id":1,"channel":"web","customer":{"id":42,"tier":"GOLD"},
    "items":[{"sku":"A1","qty":2,"price":3.50},{"sku":"B7","qty":1,"price":12.00}]}'),
 ('{"order_id":2,"channel":"app","customer":{"id":7},
    "items":[{"sku":"A1","qty":1,"price":3.50}],"coupon":"WEEKEND15"}'),
 ('{"order_id":3,"channel":"web","customer":{"id":42,"tier":"GOLD"},"items":[]}');

SELECT * FROM EVENTS;

-- 1. Path notation: colon for the first level, dot (or brackets) below. Always CAST with ::
SELECT v:order_id::INT              AS order_id,
       v:channel::STRING            AS channel,
       v:customer.id::INT           AS customer_id,
       v:customer.tier::STRING      AS tier,          -- NULL when the key is missing
       v['coupon']::STRING          AS coupon,        -- bracket notation works too
       v:items[0].sku::STRING       AS first_sku,     -- arrays are 0-based
       ARRAY_SIZE(v:items)          AS n_items
FROM EVENTS;

-- Without ::STRING you get a VARIANT, which prints with quotes. Compare:
SELECT v:channel, v:channel::STRING FROM EVENTS;

-- 2. LATERAL FLATTEN: one output row per array element (explode the line items).
SELECT v:order_id::INT        AS order_id,
       i.index                AS line_index,
       i.value:sku::STRING    AS sku,
       i.value:qty::INT       AS qty,
       i.value:price::NUMBER(10,2) AS price
FROM EVENTS e,
     LATERAL FLATTEN(input => e.v:items) i;
-- Order 3 disappeared (empty array). Keep it with OUTER => TRUE:
SELECT v:order_id::INT AS order_id, i.value:sku::STRING AS sku
FROM EVENTS e, LATERAL FLATTEN(input => e.v:items, OUTER => TRUE) i;

-- 3. Discover the keys present in the data (useful on unfamiliar JSON).
SELECT DISTINCT f.path, TYPEOF(f.value) AS type
FROM EVENTS e, LATERAL FLATTEN(input => e.v, RECURSIVE => TRUE) f
ORDER BY 1;

-- 4. Build JSON from relational data (the reverse direction).
SELECT OBJECT_CONSTRUCT('order_id', o_orderkey, 'total', o_totalprice, 'status', o_orderstatus) AS doc
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 5;

SELECT o_custkey, ARRAY_AGG(o_orderkey) WITHIN GROUP (ORDER BY o_orderkey) AS order_ids
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE o_custkey < 5 GROUP BY 1;

-- 5. Bad JSON: PARSE_JSON errors, TRY_PARSE_JSON returns NULL. Use TRY_ for untrusted input.
SELECT TRY_PARSE_JSON('{"broken": ') AS safe_result;
-- SELECT PARSE_JSON('{"broken": ');   -- uncomment to see the error

-- 6. Typing JSON into a relational table: the pattern used in every staging model later.
CREATE OR REPLACE TABLE ORDER_LINES AS
SELECT v:order_id::INT AS order_id, v:customer.id::INT AS customer_id,
       i.value:sku::STRING AS sku, i.value:qty::INT AS qty, i.value:price::NUMBER(10,2) AS price,
       i.value:qty::INT * i.value:price::NUMBER(10,2) AS line_amount
FROM EVENTS e, LATERAL FLATTEN(input => e.v:items) i;
SELECT * FROM ORDER_LINES;
