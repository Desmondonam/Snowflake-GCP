#!/usr/bin/env bash
# Shared settings for every gcloud script in this folder.
# Usage: source gcp/config.sh   (the other scripts do this for you)
#
# Edit PROJECT_ID once (or run the YOUR_PROJECT_ID find/replace from the root README).

export PROJECT_ID="${GCP_PROJECT_ID:-YOUR_PROJECT_ID}"
export REGION="${GCP_REGION:-us-central1}"

export LANDING_BUCKET="${PROJECT_ID}-landing"
export LAKEHOUSE_BUCKET="${PROJECT_ID}-lakehouse"

export TOPIC="landing-events"
export SUBSCRIPTION="landing-events-sub"

export SA_INGEST="sa-ingest"
export SA_INGEST_EMAIL="${SA_INGEST}@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_SCHEDULER="sa-scheduler"
export SA_SCHEDULER_EMAIL="${SA_SCHEDULER}@${PROJECT_ID}.iam.gserviceaccount.com"

export AR_REPO="retail"
export ADS_JOB="ads-extract"

if [[ "${PROJECT_ID}" == "YOUR_PROJECT_ID" ]]; then
  echo "ERROR: set your project ID (export GCP_PROJECT_ID=... or edit gcp/config.sh)" >&2
  return 1 2>/dev/null || exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1
