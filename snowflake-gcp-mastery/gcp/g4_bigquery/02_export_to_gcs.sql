-- G4 — Export GA4 sample data from BigQuery to GCS as Parquet, ready for Snowflake to load.
--
-- Before running: replace YOUR_PROJECT_ID (root README step) and make sure the landing bucket exists (G1).
-- Run in the BigQuery console, or:  bq query --use_legacy_sql=false < gcp/g4_bigquery/02_export_to_gcs.sql
--
-- This is the "GA4 lives in BigQuery, the warehouse is Snowflake" pattern from the interview answer (Beat 3):
-- schedule this export daily (BigQuery scheduled query or an Airflow task), then Snowpipe loads the files.

EXPORT DATA OPTIONS (
  uri = 'gs://YOUR_PROJECT_ID-landing/ga4_events/dt=2021-01-31/events_*.parquet',
  format = 'PARQUET',
  compression = 'SNAPPY',
  overwrite = true
) AS
SELECT
  PARSE_DATE('%Y%m%d', event_date)             AS event_date,
  TIMESTAMP_MICROS(event_timestamp)            AS event_ts,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  traffic_source.source                        AS traffic_source,
  traffic_source.medium                        AS traffic_medium,
  traffic_source.name                          AS traffic_campaign,
  device.category                              AS device_category,
  geo.country                                  AS country,
  ecommerce.transaction_id                     AS transaction_id,
  ecommerce.purchase_revenue_in_usd            AS purchase_revenue_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`;

-- Check the files from Git Bash / Cloud Shell:
--   gcloud storage ls -l gs://YOUR_PROJECT_ID-landing/ga4_events/dt=2021-01-31/
--
-- Then in Snowflake (after Stage 2 lesson 02 created the stage), peek without loading:
--   SELECT $1 FROM @RETAIL_RAW.COMMON.LANDING/ga4_events/ (FILE_FORMAT => 'RETAIL_RAW.COMMON.FF_PARQUET') LIMIT 10;
