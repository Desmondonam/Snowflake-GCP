#!/usr/bin/env bash
# G1 — IAM, service accounts and the landing bucket.
#   bash gcp/g1_iam_gcs.sh
#
# What it creates (all idempotent: safe to run twice):
#   * service account sa-ingest  (identity for extract jobs)
#   * bucket <project>-landing   (every source lands here first)
#   * bucket <project>-lakehouse (Iceberg tables in Stage 8)
#   * sa-ingest gets objectCreator on the landing bucket ONLY (least privilege)
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ">> 1. Service account ${SA_INGEST}"
if ! gcloud iam service-accounts describe "${SA_INGEST_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_INGEST}" --display-name="Ingestion writer"
fi

create_bucket () {
  local bucket="$1"
  if ! gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    # uniform access = IAM only, no per-object ACLs; public access prevention = never public
    gcloud storage buckets create "gs://${bucket}" \
      --location="${REGION}" \
      --uniform-bucket-level-access \
      --public-access-prevention
  else
    echo "   bucket gs://${bucket} already exists"
  fi
}

echo ">> 2. Buckets"
create_bucket "${LANDING_BUCKET}"
create_bucket "${LAKEHOUSE_BUCKET}"

echo ">> 3. Lifecycle: landing files move to Nearline after 30 days (cheaper), deleted after 365"
cat > /tmp/landing_lifecycle.json <<'EOF'
{
  "rule": [
    {"action": {"type": "SetStorageClass", "storageClass": "NEARLINE"}, "condition": {"age": 30}},
    {"action": {"type": "Delete"}, "condition": {"age": 365}}
  ]
}
EOF
gcloud storage buckets update "gs://${LANDING_BUCKET}" --lifecycle-file=/tmp/landing_lifecycle.json

echo ">> 4. Least privilege: ${SA_INGEST} may only CREATE objects in the landing bucket"
gcloud storage buckets add-iam-policy-binding "gs://${LANDING_BUCKET}" \
  --member="serviceAccount:${SA_INGEST_EMAIL}" \
  --role="roles/storage.objectCreator" >/dev/null

echo ">> 5. Verify"
gcloud storage buckets describe "gs://${LANDING_BUCKET}" --format="table(name,location,storage_class)"
gcloud storage buckets get-iam-policy "gs://${LANDING_BUCKET}" --format=json | grep -A2 objectCreator || true

cat <<EOF

Done. Try it:
  echo "hello" > /tmp/hello.txt
  gcloud storage cp /tmp/hello.txt gs://${LANDING_BUCKET}/lab/hello.txt
  gcloud storage ls -r gs://${LANDING_BUCKET}/
  gcloud storage rm gs://${LANDING_BUCKET}/lab/hello.txt
EOF
