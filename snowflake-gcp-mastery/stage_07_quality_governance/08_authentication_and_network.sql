/* =============================================================================
   Stage 7 · Step 08 — Authentication, key rotation, network rules (READ FIRST)
   -----------------------------------------------------------------------------
   Statements that can lock you out are commented. Understand before running.
   ============================================================================= */
USE ROLE SECURITYADMIN;

-- 1. Key-pair rotation without downtime (users support two public keys at once)
--    a) generate a new key:   bash 00_setup/generate_keypair.sh svc_retail_pipeline_v2
--    b) add it as the SECOND key, deploy the new private key to Airflow/CI, verify logins
-- ALTER USER SVC_RETAIL_PIPELINE SET RSA_PUBLIC_KEY_2 = 'MIIB...';
--    c) remove the old one
-- ALTER USER SVC_RETAIL_PIPELINE UNSET RSA_PUBLIC_KEY;
DESC USER SVC_RETAIL_PIPELINE;     -- RSA_PUBLIC_KEY_FP and RSA_PUBLIC_KEY_2_FP

-- 2. Service users can't use passwords or Snowsight at all (TYPE = SERVICE, Capstone 1).
SHOW USERS;                         -- check the "type" column

-- 3. Network policy: restrict where a USER can connect from (here: the service user only).
--    For CI/Airflow on GCP, allow the egress IPs of your Cloud NAT / Composer.
USE ROLE ACCOUNTADMIN;
CREATE NETWORK RULE IF NOT EXISTS GOV.POLICIES.NR_PIPELINE_EGRESS
  MODE = INGRESS TYPE = IPV4
  VALUE_LIST = ('203.0.113.10/32')        -- example IP (documentation range). Replace with real egress IPs.
  COMMENT = 'Allowed source IPs for SVC_RETAIL_PIPELINE';
CREATE NETWORK POLICY IF NOT EXISTS NP_PIPELINE
  ALLOWED_NETWORK_RULE_LIST = ('GOV.POLICIES.NR_PIPELINE_EGRESS')
  COMMENT = 'Pipeline service user only';
-- ⚠ Only attach it when the IPs are right, or the pipeline is locked out:
-- ALTER USER SVC_RETAIL_PIPELINE SET NETWORK_POLICY = NP_PIPELINE;
-- Never set an untested network policy at ACCOUNT level: you can lock out everyone, including yourself.

-- 4. Authentication policy: humans must use MFA; services must use key pairs.
-- CREATE AUTHENTICATION POLICY GOV.POLICIES.AP_HUMANS
--   MFA_ENROLLMENT = REQUIRED  CLIENT_TYPES = ('SNOWFLAKE_UI', 'SNOWSQL', 'DRIVERS', 'SNOWFLAKE_CLI');
-- ALTER USER <analyst_user> SET AUTHENTICATION POLICY GOV.POLICIES.AP_HUMANS;

-- 5. BI tools: OAuth (Snowflake OAuth or External OAuth via your IdP) so dashboards run as the viewer's role
--    and row/column policies apply per person. SSO for humans through SAML (Okta / Entra ID / Google Workspace).

-- 6. Private connectivity on GCP: Private Service Connect (Business Critical edition) keeps traffic off the internet.
