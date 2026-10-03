/* =============================================================================
   Stage 7 · Step 03 — Row access policy: regional managers see only their region
   -----------------------------------------------------------------------------
   A mapping table says which role may see which region; the policy checks it for
   every row, whatever tool runs the query (BI, notebook, Streamlit, dbt).

     FR_ANALYST            → KE          (the acceptance test: analyst sees one region)
     FR_REGION_QA_MANAGER  → QA
     FR_MARKETING          → KE, QA
     FR_DATA_SCIENTIST     → KE, QA
     RETAIL_ENGINEER       → everything  (pipelines MUST see all rows, or incremental MERGEs
                                          and tests would silently work on a subset)
     BRAND_PARTNER_SHARE   → everything  (Stage 8 share exposes only an aggregated secure view)

   HOW TO RUN: worksheet, Run All. Role GOVERNANCE_ADMIN.
   ============================================================================= */
USE ROLE GOVERNANCE_ADMIN;

CREATE TABLE IF NOT EXISTS GOV.POLICIES.ROLE_REGION_MAP (
  role_name STRING NOT NULL,
  region    STRING NOT NULL,
  granted_by STRING DEFAULT CURRENT_USER(),
  granted_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Which functional role may see which store region. Changes are audited by Time Travel.';

MERGE INTO GOV.POLICIES.ROLE_REGION_MAP t
USING (SELECT column1 AS role_name, column2 AS region FROM VALUES
        ('FR_ANALYST', 'KE'),
        ('FR_REGION_QA_MANAGER', 'QA'),
        ('FR_MARKETING', 'KE'), ('FR_MARKETING', 'QA'),
        ('FR_DATA_SCIENTIST', 'KE'), ('FR_DATA_SCIENTIST', 'QA')) s
  ON t.role_name = s.role_name AND t.region = s.region
WHEN NOT MATCHED THEN INSERT (role_name, region) VALUES (s.role_name, s.region);

-- The policy. The argument name (p_region) must not clash with the mapping table's column name.
-- IF NOT EXISTS: an attached policy can't be replaced. Change it later with
--   ALTER ROW ACCESS POLICY GOV.POLICIES.RAP_STORE_REGION SET BODY -> …;
CREATE ROW ACCESS POLICY IF NOT EXISTS GOV.POLICIES.RAP_STORE_REGION
  AS (p_region STRING) RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('RETAIL_ENGINEER')
    OR INVOKER_SHARE() = 'BRAND_PARTNER_SHARE'
    OR EXISTS (
         SELECT 1 FROM GOV.POLICIES.ROLE_REGION_MAP m
         WHERE m.region = p_region
           AND IS_ROLE_IN_SESSION(m.role_name)
       )
  COMMENT = 'Rows visible only for regions mapped to an active role';

-- dbt's post-hook (engineer, table owner) re-attaches it after rebuilds
GRANT APPLY ON ROW ACCESS POLICY GOV.POLICIES.RAP_STORE_REGION TO ROLE RETAIL_ENGINEER;

-- Attach it now, as the table owner (the same path dbt's post-hook uses)
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE DROP ALL ROW ACCESS POLICIES;
ALTER TABLE RETAIL_MARTS.SALES.FCT_SALES_LINE ADD ROW ACCESS POLICY GOV.POLICIES.RAP_STORE_REGION ON (store_region);

-- Where is it attached?
SELECT policy_name, policy_kind, ref_entity_name, ref_column_name, ref_arg_column_names
FROM TABLE(RETAIL_MARTS.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'RETAIL_MARTS.SALES.FCT_SALES_LINE', REF_ENTITY_DOMAIN => 'table'));

/* Other ways to restrict rows — and why we chose this one
   * Secure views per region: one view per region per table → explosion of objects; BI must pick the right view.
   * Separate tables per region: duplication and drift.
   * Row access policy: ONE table, ONE rule, enforced everywhere; access changes are a row in a mapping table. */
