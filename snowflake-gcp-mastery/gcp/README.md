# GCP track for data engineers (weeks 1–4, in parallel with Stages 1–4)

You will learn just enough Google Cloud to run a Snowflake platform on it: identities, storage, events,
serverless jobs, BigQuery (to compare), and Terraform. Everything here becomes the **left side** of the
RetailOne architecture: sources → **GCS landing → Pub/Sub** → Snowflake.

## Where to run the commands

| Option | Pros | How |
| --- | --- | --- |
| **Cloud Shell** (recommended) | `gcloud`, `terraform`, `bq`, `docker` preinstalled, already logged in | console.cloud.google.com → `>_` icon (top right) → `git clone` your repo or upload the folder |
| Git Bash on Windows | Works with your local repo | Install Google Cloud SDK (00_setup), run `gcloud auth login` once |

All scripts read settings from [config.sh](config.sh). Set your project once:

```bash
export GCP_PROJECT_ID=<your-project-id>      # or replace YOUR_PROJECT_ID in config.sh
bash gcp/g0_enable_apis.sh                   # once per project
```

## AWS → GCP mapping (you already know the left column)

| GCP | AWS twin | Used for in RetailOne |
| --- | --- | --- |
| Project | Account | `retail-dp-lab` holds everything; billing + IAM boundary |
| Service account | IAM role for a workload | `sa-ingest` (extractors), Snowflake's own SAs |
| IAM role binding on a resource | Resource policy | "`sa-ingest` may create objects in this bucket" |
| Cloud Storage (GCS) | S3 | Landing zone, Iceberg lakehouse |
| Pub/Sub | SNS + SQS | Bucket events → Snowpipe auto-ingest |
| Cloud Run jobs | ECS Fargate tasks / Batch | Ads API extractor |
| Cloud Scheduler | EventBridge Scheduler | Daily trigger for the extractor |
| Artifact Registry | ECR | Container images |
| BigQuery | Redshift / Athena | GA4 export lives here |
| Cloud Composer | MWAA | Managed Airflow (read-through only; expensive) |
| Secret Manager | Secrets Manager | Snowflake private keys for Airflow/Composer |
| Datastream | DMS | CDC from Cloud SQL into GCS |

---

## G1 — IAM, projects, service accounts, GCS

**Concept.** Everything lives in a **project**. Identities are **users** (people) or **service accounts**
(workloads). Permissions are **roles** bound to an identity **on a resource** (project, bucket, topic…).
Bind at the smallest resource possible: least privilege.

**Run:**

```bash
bash gcp/g1_iam_gcs.sh
```

**What you should see:** two buckets (`<project>-landing`, `<project>-lakehouse`) in `us-central1`, and an IAM
binding giving `sa-ingest` the `roles/storage.objectCreator` role on the landing bucket only.

**Understand it:**

- `objectCreator` can create objects but **not overwrite or delete** them. That makes the landing zone
  *immutable* — a re-run writes a new file instead of silently replacing evidence. Staging dedupes.
- Uniform bucket-level access = IAM only (no legacy per-object ACLs). Public access prevention = can never be made public.
- Lifecycle rule = cheaper storage class after 30 days. Raw files are your replay source, so keep them, but cheaply.

**Try this:** impersonate the service account and try to delete a file. It should fail with 403.

```bash
gcloud storage cp /etc/hostname gs://$GCP_PROJECT_ID-landing/lab/test.txt
gcloud storage rm gs://$GCP_PROJECT_ID-landing/lab/test.txt \
  --impersonate-service-account=sa-ingest@$GCP_PROJECT_ID.iam.gserviceaccount.com
# (Impersonation needs roles/iam.serviceAccountTokenCreator on sa-ingest for your user — grant it in the console
#  under IAM → Service accounts → sa-ingest → Permissions, then retry. Remove the grant afterwards.)
```

## G2 — GCS events to Pub/Sub

**Concept.** A bucket can publish a message to a Pub/Sub **topic** every time an object is created
(`OBJECT_FINALIZE`). A **subscription** queues those messages for a consumer. Snowpipe on GCP is exactly that
consumer: Snowflake reads the subscription and loads each new file.

**Run:**

```bash
bash gcp/g2_pubsub_events.sh
```

**What you should see:** a table with one `OBJECT_FINALIZE` event for `lab/g2_test.csv`.

**Important:** after Stage 2 connects Snowflake to `landing-events-sub`, never `pull --auto-ack` from it
yourself — you would consume the messages Snowpipe needs. Create a second subscription for debugging:

```bash
gcloud pubsub subscriptions create landing-events-debug --topic=landing-events
```

## G3 — Cloud Run job extracting an API

**Concept.** A container that runs to completion on demand or on a schedule and scales to zero.
Code: [g3_cloud_run_ads/main.py](g3_cloud_run_ads/main.py). Read it before deploying. Notice:

- configuration from environment variables (12-factor),
- deterministic mock API (swap `fetch_ad_performance` for the real Google Ads / Meta client later),
- partitioned, immutable output path: `ads/dt=YYYY-MM-DD/ads_<platform>_<run_id>.json`,
- non-zero exit code on misconfiguration, so the scheduler marks the run failed.

**Run locally first (fast feedback):**

```bash
cd gcp/g3_cloud_run_ads
python -m pip install -r requirements.txt
LANDING_BUCKET=$GCP_PROJECT_ID-landing RUN_DATE=2026-10-01 python main.py
```

(PowerShell: `$env:LANDING_BUCKET="<project>-landing"; $env:RUN_DATE="2026-10-01"; python main.py`)

**Deploy, run, schedule:**

```bash
bash gcp/g3_cloud_run_ads/deploy.sh
```

**What you should see:** two new files per run under `gs://<project>-landing/ads/dt=…/`.

## G4 — BigQuery, enough to compare

1. Run the queries in [g4_bigquery/01_explore_ga4.sql](g4_bigquery/01_explore_ga4.sql) in the BigQuery console.
   Before each one, read the "This query will process X MB" estimate (top right). That is how BigQuery bills.
2. Run [g4_bigquery/02_export_to_gcs.sql](g4_bigquery/02_export_to_gcs.sql) to export a day of GA4 events to your
   landing bucket as Parquet. (If BigQuery complains about location, the public dataset is in the `US`
   multi-region: create the bucket in `US` instead, or export to a US-multi-region bucket and copy.)
3. Write your one-pager by editing [g4_bigquery/snowflake_vs_bigquery.md](g4_bigquery/snowflake_vs_bigquery.md).

## G5 — Terraform (GCP capstone: "Landing zone in code")

**Concept.** Everything you clicked or scripted in G1–G3 becomes declarative code you can `apply` and
`destroy` in minutes. The module [terraform/modules/landing_zone](terraform/modules/landing_zone/) creates:
landing + lakehouse buckets, topic, subscription, bucket notification (with the publisher grant),
`sa-ingest`, `sa-scheduler`, Artifact Registry, the Cloud Run job and its daily schedule.

**If you already ran g1–g3 by hand,** remove those resources first so Terraform can own them:

```bash
bash gcp/teardown.sh --buckets
cd gcp/terraform
terraform init
# service accounts survive teardown, so import them instead of recreating:
terraform import module.landing_zone.google_service_account.ingest    projects/$GCP_PROJECT_ID/serviceAccounts/sa-ingest@$GCP_PROJECT_ID.iam.gserviceaccount.com
terraform import module.landing_zone.google_service_account.scheduler projects/$GCP_PROJECT_ID/serviceAccounts/sa-scheduler@$GCP_PROJECT_ID.iam.gserviceaccount.com
```

**Run:**

```bash
cd gcp/terraform
cp terraform.tfvars.example terraform.tfvars    # edit project_id
terraform init
terraform fmt -recursive && terraform validate
terraform plan -out tf.plan                       # READ the plan: what will be created?
terraform apply tf.plan
```

Then build your real image and point the job at it (the commands are printed as the `next_steps` output):

```bash
gcloud builds submit ../g3_cloud_run_ads --tag us-central1-docker.pkg.dev/$GCP_PROJECT_ID/retail/ads-extract:latest
# set ads_image in terraform.tfvars, then
terraform apply
gcloud run jobs execute ads-extract --region us-central1 --wait
```

**Prove it:** `terraform destroy` then `terraform apply` rebuilds everything in a few minutes.

> After a destroy/apply the subscription is new, so re-run
> `bash gcp/grant_snowflake_access.sh pubsub <GCP_PUBSUB_SERVICE_ACCOUNT>` and
> `bash gcp/grant_snowflake_access.sh storage <STORAGE_GCP_SERVICE_ACCOUNT>` (Stage 2) so Snowpipe keeps working.
> The final capstone's Terraform does those grants for you.

## Cloud Composer (week 6, read-through only)

See [../stage_05_orchestration/composer_read_through.md](../stage_05_orchestration/composer_read_through.md).
Composer environments cost money every hour they exist, so we run Airflow locally in Docker instead.

## Interview check (GCP)

<details><summary>How does Snowflake read from a private GCS bucket without keys?</summary>

A storage integration makes Snowflake create (once per account) a Google service account. You grant that
service account a minimal custom role on the bucket. No keys are stored anywhere; access is revocable in GCP IAM.
</details>

<details><summary>How does Snowpipe know a file arrived on GCP?</summary>

The bucket publishes `OBJECT_FINALIZE` events to a Pub/Sub topic. A Snowflake notification integration
subscribes to the subscription (Snowflake's own service account has `pubsub.subscriber` + `monitoring.viewer`).
Each pipe with `AUTO_INGEST = TRUE` loads files whose path matches its stage.
</details>

<details><summary>Cloud Run job vs Cloud Function vs Composer task for an API extractor?</summary>

Cloud Run job: any container, long runtimes, retries, cheap, scales to zero — the default. Cloud Functions:
small event-driven handlers. A Composer/Airflow task that *calls* the Cloud Run job keeps orchestration in
Airflow while compute stays serverless; avoid running heavy extraction inside Airflow workers.
</details>

## My notes
