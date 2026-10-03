#!/usr/bin/env bash
# Grant Snowflake's Google service accounts access to your GCP resources.
# Used in Stage 2 (storage + notification integrations) and Stage 8 (Iceberg external volume).
#
#   bash gcp/grant_snowflake_access.sh storage  <STORAGE_GCP_SERVICE_ACCOUNT>
#   bash gcp/grant_snowflake_access.sh pubsub   <GCP_PUBSUB_SERVICE_ACCOUNT>
#   bash gcp/grant_snowflake_access.sh iceberg  <STORAGE_GCP_SERVICE_ACCOUNT of the external volume>
#
# The service-account emails come from:
#   DESC STORAGE INTEGRATION GCS_INT;          -> STORAGE_GCP_SERVICE_ACCOUNT
#   DESC NOTIFICATION INTEGRATION GCS_NOTIF;   -> GCP_PUBSUB_SERVICE_ACCOUNT
#   DESC EXTERNAL VOLUME GCS_ICEBERG_VOL;      -> STORAGE_GCP_SERVICE_ACCOUNT (inside the JSON)
set -euo pipefail
source "$(dirname "$0")/config.sh"

MODE="${1:?mode: storage | pubsub | iceberg}"
SF_SA="${2:?Snowflake service account email}"

ensure_role () {
  # Custom roles give Snowflake exactly the permissions it needs, nothing more.
  local role_id="$1" title="$2" perms="$3"
  if gcloud iam roles describe "${role_id}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud iam roles update "${role_id}" --project="${PROJECT_ID}" --permissions="${perms}" --quiet >/dev/null
  else
    gcloud iam roles create "${role_id}" --project="${PROJECT_ID}" --title="${title}" --permissions="${perms}" --stage=GA
  fi
}

case "${MODE}" in
  storage)
    # Read-only: what COPY INTO / Snowpipe / external tables need
    ensure_role snowflakeGcsReader "Snowflake GCS reader" \
      "storage.buckets.get,storage.objects.get,storage.objects.list"
    gcloud storage buckets add-iam-policy-binding "gs://${LANDING_BUCKET}" \
      --member="serviceAccount:${SF_SA}" \
      --role="projects/${PROJECT_ID}/roles/snowflakeGcsReader" >/dev/null
    echo "Granted snowflakeGcsReader on gs://${LANDING_BUCKET} to ${SF_SA}"
    ;;
  pubsub)
    gcloud pubsub subscriptions add-iam-policy-binding "${SUBSCRIPTION}" \
      --member="serviceAccount:${SF_SA}" --role="roles/pubsub.subscriber" >/dev/null
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SF_SA}" --role="roles/monitoring.viewer" --condition=None >/dev/null
    echo "Granted pubsub.subscriber on ${SUBSCRIPTION} and monitoring.viewer on ${PROJECT_ID} to ${SF_SA}"
    ;;
  iceberg)
    # Read + write: Snowflake-managed Iceberg tables write data and metadata files
    ensure_role snowflakeGcsWriter "Snowflake GCS writer" \
      "storage.buckets.get,storage.objects.get,storage.objects.list,storage.objects.create,storage.objects.delete"
    gcloud storage buckets add-iam-policy-binding "gs://${LAKEHOUSE_BUCKET}" \
      --member="serviceAccount:${SF_SA}" \
      --role="projects/${PROJECT_ID}/roles/snowflakeGcsWriter" >/dev/null
    echo "Granted snowflakeGcsWriter on gs://${LAKEHOUSE_BUCKET} to ${SF_SA}"
    ;;
  *)
    echo "unknown mode ${MODE}" >&2; exit 1 ;;
esac

echo "IAM changes can take up to a minute to propagate. Then retry the Snowflake command."
