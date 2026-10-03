#!/usr/bin/env bash
# G3 — Build and deploy the ads extractor as a Cloud Run JOB, run it once, and schedule it daily.
#   bash gcp/g3_cloud_run_ads/deploy.sh
#
# A Cloud Run *job* runs to completion and exits (batch). A Cloud Run *service* answers HTTP requests.
# Extractors are jobs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../config.sh"

echo ">> 1. Deploy from source (Cloud Build builds the Dockerfile and pushes to Artifact Registry)"
# First time only, gcloud may ask to create the 'cloud-run-source-deploy' repository: answer Y.
gcloud run jobs deploy "${ADS_JOB}" \
  --source "${HERE}" \
  --region "${REGION}" \
  --service-account "${SA_INGEST_EMAIL}" \
  --set-env-vars "LANDING_BUCKET=${LANDING_BUCKET}" \
  --tasks 1 --max-retries 2 --task-timeout 600s

echo ">> 2. Execute once and wait"
gcloud run jobs execute "${ADS_JOB}" --region "${REGION}" --wait

echo ">> 3. Backfill a specific date (shows how to pass parameters per execution)"
gcloud run jobs execute "${ADS_JOB}" --region "${REGION}" --wait \
  --update-env-vars "RUN_DATE=$(date -d 'yesterday -1 day' +%F 2>/dev/null || date -v-2d +%F)"

echo ">> 4. Schedule daily at 03:00 UTC with Cloud Scheduler"
if ! gcloud iam service-accounts describe "${SA_SCHEDULER_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_SCHEDULER}" --display-name="Scheduler invoker"
fi
gcloud run jobs add-iam-policy-binding "${ADS_JOB}" --region "${REGION}" \
  --member="serviceAccount:${SA_SCHEDULER_EMAIL}" --role="roles/run.invoker" >/dev/null

JOB_URI="https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/jobs/${ADS_JOB}:run"
if gcloud scheduler jobs describe "${ADS_JOB}-daily" --location "${REGION}" >/dev/null 2>&1; then
  echo "   scheduler job exists"
else
  gcloud scheduler jobs create http "${ADS_JOB}-daily" \
    --location "${REGION}" \
    --schedule "0 3 * * *" --time-zone "Etc/UTC" \
    --uri "${JOB_URI}" --http-method POST \
    --oauth-service-account-email "${SA_SCHEDULER_EMAIL}"
fi

echo ">> 5. Verify the files landed"
gcloud storage ls -r "gs://${LANDING_BUCKET}/ads/" | tail -n 10

cat <<EOF

Useful commands:
  gcloud run jobs executions list --job ${ADS_JOB} --region ${REGION}
  gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="${ADS_JOB}"' --limit 20 --format="value(textPayload)"
  gcloud scheduler jobs run ${ADS_JOB}-daily --location ${REGION}     # trigger the schedule now
  gcloud scheduler jobs pause ${ADS_JOB}-daily --location ${REGION}   # stop daily runs
EOF
