/* =============================================================================
   CAPSTONE 1 (part 2) — Service user for pipelines (dbt prod, Airflow, CI)
   -----------------------------------------------------------------------------
   TYPE = SERVICE users cannot log in with a password or to Snowsight. They use
   key-pair auth only. One service user per system makes audit trails clear.

   BEFORE YOU RUN
     In Git Bash:  bash 00_setup/generate_keypair.sh svc_retail_pipeline
     Copy the public key body it prints and paste it below where it says PASTE_PUBLIC_KEY_HERE.

   HOW TO RUN: Snowsight worksheet, Run All.
   ============================================================================= */
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS SVC_RETAIL_PIPELINE
  TYPE = SERVICE
  DEFAULT_ROLE = RETAIL_ENGINEER
  DEFAULT_WAREHOUSE = TRANSFORM_WH
  COMMENT = 'dbt prod runs, Airflow, CI. Key-pair auth only.';

USE ROLE SECURITYADMIN;
ALTER USER SVC_RETAIL_PIPELINE SET RSA_PUBLIC_KEY = 'PASTE_PUBLIC_KEY_HERE';
GRANT ROLE RETAIL_ENGINEER TO USER SVC_RETAIL_PIPELINE;

DESC USER SVC_RETAIL_PIPELINE;   -- check TYPE = SERVICE and RSA_PUBLIC_KEY_FP is set

/* Test it from PowerShell (repo root, venv active):
     $env:SNOWFLAKE_USER = "SVC_RETAIL_PIPELINE"
     $env:SNOWFLAKE_PRIVATE_KEY_PATH = "$HOME/.snowflake/keys/svc_retail_pipeline_rsa_key.p8"
     $env:SNOWFLAKE_PRIVATE_KEY_PASSPHRASE = "<its passphrase>"
     python 00_setup/check_env.py
   Then set them back to your own user (. .\00_setup\load_env.ps1). */
