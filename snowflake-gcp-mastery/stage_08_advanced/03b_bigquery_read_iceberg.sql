-- Stage 8 · Lesson 03b — Read Snowflake's Iceberg table from BigQuery (BigLake)
-- BigQuery Standard SQL. Same data files, second engine, no copy.
--
-- One-time setup in Git Bash / Cloud Shell (source gcp/config.sh first):
--
--   # 1. A BigQuery connection = a Google service account BigQuery uses to read GCS
--   bq mk --connection --location=us-central1 --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE lakehouse_conn
--   bq show --connection $PROJECT_ID.us-central1.lakehouse_conn          # copy serviceAccountId
--
--   # 2. Let that service account read the lakehouse bucket
--   gcloud storage buckets add-iam-policy-binding gs://$LAKEHOUSE_BUCKET \
--     --member=serviceAccount:<serviceAccountId> --role=roles/storage.objectViewer
--
--   # 3. A dataset in the same region as the bucket and connection
--   bq mk --dataset --location=us-central1 $PROJECT_ID:retail_lake
--
-- Then run the SQL below in the BigQuery console. Replace the metadata URI with the
-- metadataLocation from SYSTEM$GET_ICEBERG_TABLE_INFORMATION (change gcs:// to gs://).

CREATE OR REPLACE EXTERNAL TABLE `YOUR_PROJECT_ID.retail_lake.fct_sales_daily`
WITH CONNECTION `YOUR_PROJECT_ID.us-central1.lakehouse_conn`
OPTIONS (
  format = 'ICEBERG',
  uris = ['gs://YOUR_PROJECT_ID-lakehouse/iceberg/fct_sales_daily/metadata/REPLACE_WITH_LATEST.metadata.json']
);

-- Same numbers as Snowflake's SELECT store_region, SUM(net_sales) … ?
SELECT store_region, ROUND(SUM(net_sales), 2) AS net_sales
FROM `YOUR_PROJECT_ID.retail_lake.fct_sales_daily`
GROUP BY store_region
ORDER BY store_region;

-- Join with GA4 data that lives natively in BigQuery (the "best of both" story)
SELECT d.sale_date, SUM(d.net_sales) AS store_and_online_sales
FROM `YOUR_PROJECT_ID.retail_lake.fct_sales_daily` d
GROUP BY 1
ORDER BY 1 DESC
LIMIT 14;

-- After Snowflake writes new data, point the table at the NEW metadata file (re-run CREATE OR REPLACE with the
-- new URI). For automatic sync, use a shared Iceberg catalog instead of pinning a metadata file.
