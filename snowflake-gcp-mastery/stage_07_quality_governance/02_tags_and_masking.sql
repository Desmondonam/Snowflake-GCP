/* =============================================================================
   Stage 7 · Step 02 — Classify PII with a TAG and mask it by tag
   -----------------------------------------------------------------------------
   Tag-based masking: attach masking policies to the tag GOV.TAGS.PII once.
   Every column that gets the tag is masked automatically — including columns
   dbt creates next month. The policy reads the tag VALUE to decide how to mask.

       column tagged PII='email'  → j*****@example.com style:  *****@example.com
       column tagged PII='phone'  → ********0123
       column tagged PII='name'   → ***
       DATE column tagged PII='birth_date' → year only (1st of January)

   Who sees clear text?  FR_MARKETING (activation needs it) and RETAIL_ENGINEER
   (the pipeline role must move real values from staging into marts and audiences).
   Humans use functional roles, so analysts and data scientists see masked values.

   HOW TO RUN: worksheet, Run All. Role GOVERNANCE_ADMIN.
   ============================================================================= */
USE ROLE GOVERNANCE_ADMIN;
USE WAREHOUSE LAB_WH;   -- granted to GOVERNANCE_ADMIN via AR_WH_LAB_USE in step 01

CREATE SCHEMA IF NOT EXISTS GOV.TAGS     COMMENT = 'Classification tags';
CREATE SCHEMA IF NOT EXISTS GOV.POLICIES COMMENT = 'Masking and row access policies';

CREATE TAG IF NOT EXISTS GOV.TAGS.PII
  ALLOWED_VALUES 'email', 'phone', 'name', 'birth_date', 'address'
  COMMENT = 'Personal data classification. Masking policies are attached to this tag.';

-- Policies use IF NOT EXISTS: once attached (to the tag), a policy can't be CREATE OR REPLACEd.
-- To change a body later:  ALTER MASKING POLICY GOV.POLICIES.MASK_PII_STRING SET BODY -> …;
-- String PII
CREATE MASKING POLICY IF NOT EXISTS GOV.POLICIES.MASK_PII_STRING AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('FR_MARKETING') OR IS_ROLE_IN_SESSION('RETAIL_ENGINEER') THEN val
    WHEN val IS NULL THEN NULL
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOV.TAGS.PII') = 'email' THEN REGEXP_REPLACE(val, '^[^@]+', '*****')
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOV.TAGS.PII') = 'phone' THEN REPEAT('*', GREATEST(LENGTH(val) - 4, 0)) || RIGHT(val, 4)
    ELSE '***'
  END
  COMMENT = 'Clear text for marketing and pipelines; partial masks by PII type for everyone else';

-- Date PII (a tag can carry one masking policy per data type)
CREATE MASKING POLICY IF NOT EXISTS GOV.POLICIES.MASK_PII_DATE AS (val DATE) RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('FR_MARKETING') OR IS_ROLE_IN_SESSION('RETAIL_ENGINEER') THEN val
    ELSE DATE_FROM_PARTS(YEAR(val), 1, 1)       -- keep age band analysis possible, hide the exact birthday
  END;

-- FORCE makes this re-runnable (replaces whatever policy of that data type the tag already has)
ALTER TAG GOV.TAGS.PII SET MASKING POLICY GOV.POLICIES.MASK_PII_STRING,
                           MASKING POLICY GOV.POLICIES.MASK_PII_DATE FORCE;

-- Let the engineer role (dbt post-hook) put this tag on the tables it owns
GRANT USAGE ON DATABASE GOV TO ROLE RETAIL_ENGINEER;
GRANT USAGE ON SCHEMA GOV.TAGS TO ROLE RETAIL_ENGINEER;
GRANT USAGE ON SCHEMA GOV.POLICIES TO ROLE RETAIL_ENGINEER;
GRANT APPLY ON TAG GOV.TAGS.PII TO ROLE RETAIL_ENGINEER;

-- Tag the current tables right away (from now on dbt re-applies tags after every build).
-- Done as the table OWNER, which now holds APPLY on the tag: the same path dbt's post-hook uses.
USE ROLE RETAIL_ENGINEER;
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN email      SET TAG GOV.TAGS.PII = 'email';
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN phone      SET TAG GOV.TAGS.PII = 'phone';
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN first_name SET TAG GOV.TAGS.PII = 'name';
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN last_name  SET TAG GOV.TAGS.PII = 'name';
ALTER TABLE RETAIL_MARTS.CORE.DIM_CUSTOMER MODIFY COLUMN birth_date SET TAG GOV.TAGS.PII = 'birth_date';
ALTER TABLE RETAIL_MARTS.MARKETING.AUD_LAPSED_HIGH_VALUE MODIFY COLUMN email SET TAG GOV.TAGS.PII = 'email';
ALTER TABLE RETAIL_MARTS.MARKETING.AUD_LAPSED_HIGH_VALUE MODIFY COLUMN phone SET TAG GOV.TAGS.PII = 'phone';

-- Where is PII? (real-time view of tags on one table)
SELECT column_name, tag_name, tag_value
FROM TABLE(RETAIL_MARTS.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('RETAIL_MARTS.CORE.DIM_CUSTOMER', 'table'));

/* ---------------------------------------------------------------------------
   For comparison: a classic DIRECT masking policy (attached to one column).
   Fine for a single column; tag-based scales better. Shown, not applied.
   --------------------------------------------------------------------------- */
USE ROLE GOVERNANCE_ADMIN;
CREATE OR REPLACE MASKING POLICY GOV.POLICIES.MASK_EMAIL_DIRECT AS (val STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('FR_MARKETING') THEN val ELSE REGEXP_REPLACE(val, '.+@', '*****@') END;
-- ALTER TABLE … MODIFY COLUMN email SET MASKING POLICY GOV.POLICIES.MASK_EMAIL_DIRECT;

/* NOTES
   * IS_ROLE_IN_SESSION respects the role hierarchy (and secondary roles). CURRENT_ROLE() only checks the primary role.
   * Masking is applied in MARTS only. If you masked RAW/STAGING, dbt (reading as a masked role) would copy
     masked values into marts. Protect RAW/STAGING with RBAC instead: people have no access there.
   * Change a policy body later with ALTER MASKING POLICY … SET BODY -> …  (no need to detach it). */
