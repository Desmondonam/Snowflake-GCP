#!/usr/bin/env bash
# Remove the resources created by the g*.sh scripts (NOT the Terraform ones; use terraform destroy for those).
#   bash gcp/teardown.sh            # keeps buckets and their data
#   bash gcp/teardown.sh --buckets  # ALSO deletes both buckets and all files in them
set -uo pipefail
source "$(dirname "$0")/config.sh"

echo ">> Cloud Scheduler + Cloud Run job"
gcloud scheduler jobs delete "${ADS_JOB}-daily" --location="${REGION}" --quiet 2>/dev/null
gcloud run jobs delete "${ADS_JOB}" --region="${REGION}" --quiet 2>/dev/null

echo ">> Pub/Sub (Snowpipe auto-ingest stops working after this)"
gcloud storage buckets notifications delete "gs://${LANDING_BUCKET}" --quiet 2>/dev/null
gcloud pubsub subscriptions delete "${SUBSCRIPTION}" --quiet 2>/dev/null
gcloud pubsub topics delete "${TOPIC}" --quiet 2>/dev/null

if [[ "${1:-}" == "--buckets" ]]; then
  echo ">> Buckets (and all data)"
  gcloud storage rm -r "gs://${LANDING_BUCKET}" --quiet 2>/dev/null
  gcloud storage rm -r "gs://${LAKEHOUSE_BUCKET}" --quiet 2>/dev/null
fi

echo "Teardown finished. Service accounts and custom roles are kept (they cost nothing)."
