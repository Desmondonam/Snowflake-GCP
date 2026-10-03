#!/usr/bin/env bash
# G2 — Bucket events to Pub/Sub. This is the plumbing Snowpipe auto-ingest uses on GCP.
#   bash gcp/g2_pubsub_events.sh
#
# Flow: object created in landing bucket  ->  message on topic landing-events
#       ->  subscription landing-events-sub  ->  (Stage 2) Snowflake notification integration
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ">> 1. Topic ${TOPIC}"
gcloud pubsub topics describe "${TOPIC}" >/dev/null 2>&1 || gcloud pubsub topics create "${TOPIC}"

echo ">> 2. Bucket notification (OBJECT_FINALIZE = a new object finished uploading)"
# gcloud grants the Cloud Storage service agent publish rights on the topic automatically.
if gcloud storage buckets notifications list "gs://${LANDING_BUCKET}" --format="value(topic)" 2>/dev/null | grep -q "${TOPIC}"; then
  echo "   notification already exists"
else
  gcloud storage buckets notifications create "gs://${LANDING_BUCKET}" \
    --topic="${TOPIC}" --event-types=OBJECT_FINALIZE --payload-format=json
fi

echo ">> 3. Pull subscription ${SUBSCRIPTION} (Snowflake will read from this)"
gcloud pubsub subscriptions describe "${SUBSCRIPTION}" >/dev/null 2>&1 || \
  gcloud pubsub subscriptions create "${SUBSCRIPTION}" --topic="${TOPIC}" \
    --ack-deadline=60 --message-retention-duration=7d

echo ">> 4. Test: upload a file and pull the event"
echo "test,$(date +%s)" > /tmp/g2_test.csv
gcloud storage cp /tmp/g2_test.csv "gs://${LANDING_BUCKET}/lab/g2_test.csv"
sleep 5
gcloud pubsub subscriptions pull "${SUBSCRIPTION}" --auto-ack --limit=5 \
  --format="table(message.attributes.eventType, message.attributes.objectId)"
gcloud storage rm "gs://${LANDING_BUCKET}/lab/g2_test.csv"

cat <<EOF

You should see an OBJECT_FINALIZE event for lab/g2_test.csv above.
(If the table is empty, wait 10 seconds and run:
  gcloud pubsub subscriptions pull ${SUBSCRIPTION} --auto-ack --limit=5 )

NOTE: in Stage 2 Snowflake becomes the consumer of this subscription. From then on, do not
pull from it yourself, or you will steal the messages Snowpipe needs.
EOF
