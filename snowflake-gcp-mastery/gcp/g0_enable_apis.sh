#!/usr/bin/env bash
# G0 — Enable the Google Cloud APIs used in this course. Run once per project.
#   bash gcp/g0_enable_apis.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ">> Enabling APIs in ${PROJECT_ID} (takes 1–2 minutes)"
gcloud services enable \
  iam.googleapis.com \
  storage.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudscheduler.googleapis.com \
  bigquery.googleapis.com \
  bigqueryconnection.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com

gcloud services list --enabled --format="value(config.name)" | sort
