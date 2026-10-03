/* =============================================================================
   Stage 7 · Step 06 — Prove it to an auditor: who read customer PII?
   -----------------------------------------------------------------------------
   ACCESS_HISTORY records, per query, which objects AND COLUMNS were read
   (directly or through views) and written, plus which policies were applied.
   Latency up to ~3 hours, retained 365 days. Enterprise edition.
   HOW TO RUN: worksheet. Role GOVERNANCE_ADMIN (imported privileges on SNOWFLAKE).
   ============================================================================= */
USE ROLE GOVERNANCE_ADMIN;
USE WAREHOUSE LAB_WH;

-- 1. Who read DIM_CUSTOMER.EMAIL in the last 30 days, with which role, and was a masking policy applied?
WITH reads AS (
  SELECT ah.query_id, ah.query_start_time, ah.user_name,
         obj.value:"objectName"::STRING AS object_name,
         col.value:"columnName"::STRING AS column_name
  FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
       LATERAL FLATTEN(input => ah.base_objects_accessed) obj,
       LATERAL FLATTEN(input => obj.value:"columns") col
  WHERE ah.query_start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
)
SELECT r.query_start_time, r.user_name, q.role_name, r.object_name, r.column_name,
       ah.policies_referenced IS NOT NULL AS policy_applied,
       LEFT(q.query_text, 120) AS query
FROM reads r
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q ON q.query_id = r.query_id
JOIN SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah ON ah.query_id = r.query_id
WHERE r.object_name = 'RETAIL_MARTS.CORE.DIM_CUSTOMER'
  AND r.column_name IN ('EMAIL', 'PHONE')
ORDER BY r.query_start_time DESC;

-- 2. Where does PII live across the account? (input for GDPR "right to be forgotten" requests)
SELECT object_database, object_schema, object_name, column_name, tag_value
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'GOV' AND tag_schema = 'TAGS' AND tag_name = 'PII'
ORDER BY 1, 2, 3, 4;
-- Remember: RAW (CRM.CUSTOMERS VARIANT) and staging also contain PII but aren't tagged columns —
-- a deletion request must cover RAW files/tables too. Document that path in the data catalogue.

-- 3. Which policies protect which columns/tables?
SELECT policy_name, policy_kind, ref_database_name, ref_schema_name, ref_entity_name, ref_column_name, tag_name
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
ORDER BY policy_kind, ref_entity_name;

-- 4. Lineage at object level: what depends on DIM_CUSTOMER? (views, MVs, dynamic tables)
SELECT referencing_database, referencing_schema, referencing_object_name, referencing_object_domain
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE referenced_object_name = 'DIM_CUSTOMER';
-- (dbt docs lineage covers model-to-model lineage; Snowsight's Lineage tab on a table shows column lineage too.)

-- 5. Data written: which queries wrote to the audience table that goes to ad platforms?
SELECT ah.query_start_time, ah.user_name, om.value:"objectName"::STRING AS written_object
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
     LATERAL FLATTEN(input => ah.objects_modified) om
WHERE om.value:"objectName"::STRING = 'RETAIL_MARTS.MARKETING.AUD_LAPSED_HIGH_VALUE'
ORDER BY 1 DESC LIMIT 20;

-- 6. Logins: who connected, how (password / key pair / SSO), from where
SELECT event_timestamp, user_name, first_authentication_factor, second_authentication_factor,
       client_ip, reported_client_type, is_success
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE event_timestamp > DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY event_timestamp DESC LIMIT 50;
