-- G4 — BigQuery: explore the public GA4 sample (BigQuery Standard SQL, NOT Snowflake SQL)
--
-- How to run:
--   * Console: BigQuery → + (new query) → paste one query → Run. Check "bytes processed" BEFORE running.
--   * CLI (Git Bash / Cloud Shell): bq query --use_legacy_sql=false < gcp/g4_bigquery/01_explore_ga4.sql
--
-- Cost note: BigQuery on-demand bills by bytes scanned (first 1 TiB/month free). Selecting fewer
-- columns and filtering on _TABLE_SUFFIX (the sharded date) is how you keep scans small.
-- Compare that with Snowflake, which bills by warehouse time.

-- 1. What does a GA4 event look like? (one day only = small scan)
SELECT event_date, event_timestamp, event_name, user_pseudo_id,
       traffic_source.source, traffic_source.medium, traffic_source.name AS campaign
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
LIMIT 20;

-- 2. Nested/repeated fields: event_params is an ARRAY<STRUCT>. UNNEST is BigQuery's LATERAL FLATTEN.
SELECT event_name, ep.key, COUNT(*) AS n
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`,
     UNNEST(event_params) AS ep
GROUP BY 1, 2
ORDER BY n DESC
LIMIT 25;

-- 3. Daily purchases and revenue by traffic medium for January 2021 (wildcard table + suffix filter)
SELECT PARSE_DATE('%Y%m%d', event_date) AS day,
       traffic_source.medium AS medium,
       COUNTIF(event_name = 'purchase') AS purchases,
       ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2) AS revenue_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210131'
GROUP BY 1, 2
ORDER BY 1, 2;

-- 4. Sessions with campaign attribution (the shape we need for touchpoints in Snowflake)
SELECT user_pseudo_id,
       (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
       MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
       ANY_VALUE(traffic_source.source) AS source,
       ANY_VALUE(traffic_source.medium) AS medium,
       ANY_VALUE(traffic_source.name) AS campaign,
       COUNTIF(event_name = 'purchase') AS purchases
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
GROUP BY 1, 2
ORDER BY purchases DESC
LIMIT 50;
