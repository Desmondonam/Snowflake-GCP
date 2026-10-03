/* =============================================================================
   Stage 2 · Lesson 02 — Connect Snowflake to GCS and Pub/Sub (integrations)
   -----------------------------------------------------------------------------
   An INTEGRATION is an account-level object that stores the trust relationship
   with an external system. No keys or passwords are stored: Snowflake creates
   its own Google service accounts and YOU grant them access in GCP.

     GCS_INT   (storage integration)       → read files in your buckets
     GCS_NOTIF (notification integration)  → read Pub/Sub messages for Snowpipe

   PREREQUISITES: GCP track G1 + G2 done (buckets, topic, subscription exist),
                  YOUR_PROJECT_ID replaced everywhere.
   HOW TO RUN: Snowsight worksheet, statement by statement. Switch to Git Bash
               when told to run the gcloud grant script.
   ============================================================================= */
USE ROLE ACCOUNTADMIN;   -- creating integrations needs ACCOUNTADMIN (or CREATE INTEGRATION)

/* ---------------------------------------------------------------------------
   STEP 1 — Storage integration
   --------------------------------------------------------------------------- */
CREATE STORAGE INTEGRATION IF NOT EXISTS GCS_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://YOUR_PROJECT_ID-landing/', 'gcs://YOUR_PROJECT_ID-lakehouse/')
  COMMENT = 'RetailOne landing + lakehouse buckets';

DESC STORAGE INTEGRATION GCS_INT;
-- Copy the value of STORAGE_GCP_SERVICE_ACCOUNT (looks like xxxx@gcpuscentral1-xxxx.iam.gserviceaccount.com)

/* >>> In Git Bash (repo root):
       bash gcp/grant_snowflake_access.sh storage <STORAGE_GCP_SERVICE_ACCOUNT>
   This creates a custom GCP role with only storage.buckets.get, objects.get, objects.list
   and binds it on the landing bucket. Wait ~1 minute for IAM to propagate. <<< */

/* ---------------------------------------------------------------------------
   STEP 2 — Notification integration (for Snowpipe auto-ingest)
   --------------------------------------------------------------------------- */
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS GCS_NOTIF
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = GCP_PUBSUB
  ENABLED = TRUE
  GCP_PUBSUB_SUBSCRIPTION_NAME = 'projects/YOUR_PROJECT_ID/subscriptions/landing-events-sub'
  COMMENT = 'Object-created events from the landing bucket';

DESC NOTIFICATION INTEGRATION GCS_NOTIF;
-- Copy GCP_PUBSUB_SERVICE_ACCOUNT

/* >>> In Git Bash:
       bash gcp/grant_snowflake_access.sh pubsub <GCP_PUBSUB_SERVICE_ACCOUNT>
   Grants pubsub.subscriber on the subscription + monitoring.viewer on the project. <<< */

/* ---------------------------------------------------------------------------
   STEP 3 — Let the engineer role use the integrations (least privilege:
   the engineer can USE them but not change or drop them)
   --------------------------------------------------------------------------- */
GRANT USAGE ON INTEGRATION GCS_INT   TO ROLE RETAIL_ENGINEER;
GRANT USAGE ON INTEGRATION GCS_NOTIF TO ROLE RETAIL_ENGINEER;

SHOW INTEGRATIONS;

/* ---------------------------------------------------------------------------
   STEP 4 — Smoke test (after the grant script, as the engineer)
   --------------------------------------------------------------------------- */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LOAD_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_RAW.COMMON;

CREATE STAGE IF NOT EXISTS RETAIL_RAW.COMMON.LANDING
  URL = 'gcs://YOUR_PROJECT_ID-landing/'
  STORAGE_INTEGRATION = GCS_INT
  COMMENT = 'Root of the landing bucket; each pipe reads its own <source>/ prefix';

LIST @RETAIL_RAW.COMMON.LANDING;   -- empty list = OK. An error = permissions not ready yet.

/* TROUBLESHOOTING
   "Failed to access remote file: access denied"        → grant script not run / wrong SA / wait a minute
   "Location ... is not allowed by integration"          → URL not inside STORAGE_ALLOWED_LOCATIONS
   To add a location later:
     ALTER STORAGE INTEGRATION GCS_INT SET STORAGE_ALLOWED_LOCATIONS = ('gcs://a/', 'gcs://b/');
   Do NOT drop and recreate integrations casually: stages and pipes reference them by name. */
