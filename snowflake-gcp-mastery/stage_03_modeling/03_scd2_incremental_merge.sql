/* =============================================================================
   Stage 3 · Step 03 — The SCD Type 2 MERGE you must be able to write by hand
   -----------------------------------------------------------------------------
   Situation: the source only gives you TODAY's snapshot (no history), so you
   compare it with the current dimension rows and:
     Step 1  close the current version of every customer whose tracked attributes changed
     Step 2  insert a new current version for changed customers AND brand-new customers

   Improvements over the textbook version (say these in an interview):
     * compare a HASH of tracked attributes, not "a <> b OR c <> d" (NULL-safe, scales to 30 columns)
     * one fixed run timestamp ($run_ts) so valid_to of the old row = valid_from of the new row
     * both statements inside ONE transaction: readers never see a customer with no current row
     * idempotent: running it twice with the same snapshot changes nothing the second time

   HOW TO RUN: worksheet, statement by statement (session variables + transaction).
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA RETAIL_LAB.STAR;

-- A playground copy of the dimension: zero-copy clone, instant and free.
CREATE OR REPLACE TABLE DIM_CUSTOMER_INC CLONE DIM_CUSTOMER;

-- "Today's snapshot" from the CRM = latest state per customer…
CREATE OR REPLACE TEMPORARY TABLE CRM_SNAPSHOT_TODAY AS
SELECT customer_id, loyalty_id, email, phone, first_name, last_name, birth_date,
       city, country_code, segment, loyalty_tier, marketing_consent
FROM RETAIL_LAB.STG.CRM_CUSTOMERS_LATEST;

-- …with two changes simulated: C00042 upgrades tier, and a brand-new customer appears.
UPDATE CRM_SNAPSHOT_TODAY SET loyalty_tier = 'PLATINUM' WHERE customer_id = 'C00042';
INSERT INTO CRM_SNAPSHOT_TODAY
  SELECT 'C99999', 'L099999', 'new.person.99999@example.com', '+254700000000', 'New', 'Person',
         '1990-01-01', 'Nairobi', 'KE', 'MAINSTREAM', 'BRONZE', TRUE;

SELECT customer_id, loyalty_tier, valid_from, valid_to, is_current
FROM DIM_CUSTOMER_INC WHERE customer_id IN ('C00042', 'C99999') ORDER BY 1, valid_from;   -- before

/* ---------------------------------------------------------------------------
   THE PATTERN
   --------------------------------------------------------------------------- */
SET run_ts = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

BEGIN;

-- Step 1: close current rows whose tracked attributes changed
MERGE INTO DIM_CUSTOMER_INC d
USING (
  SELECT customer_id,
         MD5(CONCAT_WS('|', COALESCE(segment, ''), COALESCE(loyalty_tier, ''),
                            COALESCE(city, ''), COALESCE(country_code, ''))) AS attr_hash
  FROM CRM_SNAPSHOT_TODAY
) s
  ON d.customer_id = s.customer_id AND d.is_current
WHEN MATCHED AND d.attr_hash <> s.attr_hash THEN
  UPDATE SET d.valid_to = $run_ts, d.is_current = FALSE;

-- Step 2: insert new versions (changed customers now have no current row) + brand-new customers
INSERT INTO DIM_CUSTOMER_INC
  (customer_sk, customer_id, loyalty_id, email, phone, first_name, last_name, birth_date,
   city, country_code, segment, loyalty_tier, marketing_consent, attr_hash, valid_from, valid_to, is_current)
SELECT MD5(s.customer_id || '|' || $run_ts::STRING),
       s.customer_id, s.loyalty_id, s.email, s.phone, s.first_name, s.last_name, s.birth_date,
       s.city, s.country_code, s.segment, s.loyalty_tier, s.marketing_consent,
       MD5(CONCAT_WS('|', COALESCE(s.segment, ''), COALESCE(s.loyalty_tier, ''),
                          COALESCE(s.city, ''), COALESCE(s.country_code, ''))),
       IFF(d_any.customer_id IS NULL, '1900-01-01'::TIMESTAMP_NTZ, $run_ts),   -- brand-new: valid from the start
       '9999-12-31'::TIMESTAMP_NTZ, TRUE
FROM CRM_SNAPSHOT_TODAY s
LEFT JOIN DIM_CUSTOMER_INC d
  ON d.customer_id = s.customer_id AND d.is_current
LEFT JOIN (SELECT DISTINCT customer_id FROM DIM_CUSTOMER_INC) d_any
  ON d_any.customer_id = s.customer_id
WHERE d.customer_id IS NULL;

COMMIT;

-- After: C00042 has an old (closed) and a new (current) row; C99999 has one current row.
SELECT customer_id, loyalty_tier, valid_from, valid_to, is_current
FROM DIM_CUSTOMER_INC WHERE customer_id IN ('C00042', 'C99999') ORDER BY 1, valid_from;

-- Idempotency check: run the BEGIN … COMMIT block again (new $run_ts is fine). Nothing changes:
SELECT COUNT(*) AS rows_now FROM DIM_CUSTOMER_INC;

-- Integrity: exactly one current row per customer, no overlapping versions.
SELECT customer_id, COUNT_IF(is_current) AS current_rows FROM DIM_CUSTOMER_INC
GROUP BY 1 HAVING COUNT_IF(is_current) <> 1;
SELECT a.customer_id FROM DIM_CUSTOMER_INC a
JOIN DIM_CUSTOMER_INC b ON a.customer_id = b.customer_id AND a.customer_sk <> b.customer_sk
 AND a.valid_from < b.valid_to AND b.valid_from < a.valid_to
LIMIT 10;   -- must be empty

/* POINT-IN-TIME JOIN (how facts use SCD2)
     JOIN dim_customer c
       ON c.customer_id = f.customer_id
      AND f.sold_at >= c.valid_from AND f.sold_at < c.valid_to     -- half-open interval: no gaps, no overlaps
   BETWEEN is inclusive on both ends: a sale at exactly the change timestamp would match TWO versions. */

DROP TABLE DIM_CUSTOMER_INC;
