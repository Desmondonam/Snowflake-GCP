# Cloud Composer read-through (do not leave it running)

Cloud Composer is Google's managed Airflow. It's what RetailOne would run in production on GCP. An environment costs
money every hour it exists (even idle), so in this course you **read** this page, optionally create one for an hour,
take screenshots, and delete it.

## What changes from local Astro to Composer

| Concern | Local (Astro) | Cloud Composer 3 |
| --- | --- | --- |
| DAG files | `airflow/dags/` mounted | uploaded to the environment's GCS bucket `gs://<composer-bucket>/dags/` |
| Python packages | `requirements.txt` → image | `gcloud composer environments update --update-pypi-packages-from-file requirements.txt` |
| dbt | venv in the image | Prefer running dbt as a **Cloud Run job** (container with the dbt project) triggered by Airflow; or install dbt via PyPI packages (dependency conflicts risk) |
| Snowflake key | file in `include/keys`, passphrase in `.env` | **Secret Manager** backend: secret `airflow-connections-snowflake_default` holds the connection JSON |
| Identity | your laptop | the environment's service account (least privilege: Secret Manager accessor, Run invoker, GCS) |
| Scaling | one machine | workers autoscale; environment size S/M/L |

## Commands (for reference)

```bash
source gcp/config.sh
gcloud services enable composer.googleapis.com

# ~25 minutes to create. Pick IMAGE_VERSION from the "Cloud Composer versions" docs page:
# choose a Composer 3 image with Airflow 3 (our DAGs use Airflow 3 imports), e.g. composer-3-airflow-3.x.y-build.z
gcloud composer environments create retail-composer \
  --location "$REGION" \
  --image-version "$IMAGE_VERSION" \
  --environment-size small \
  --service-account "sa-composer@${PROJECT_ID}.iam.gserviceaccount.com"

# Use Secret Manager for connections and variables
gcloud composer environments update retail-composer --location "$REGION" \
  --update-airflow-configs=secrets-backend=airflow.providers.google.cloud.secrets.secret_manager.CloudSecretManagerBackend,secrets-backend_kwargs='{"connections_prefix":"airflow-connections","variables_prefix":"airflow-variables"}'

# Store the Snowflake connection as a secret (contents = the JSON from airflow/.env.example)
gcloud secrets create airflow-connections-snowflake_default --data-file=snowflake_conn.json

# Upload DAGs
gcloud composer environments storage dags import --environment retail-composer --location "$REGION" \
  --source capstone_retail_platform/airflow/dags/retail_daily.py

# DELETE when done (this is the step that saves money)
gcloud composer environments delete retail-composer --location "$REGION"
```

## dbt on Composer: the production pattern

```
Composer task (CloudRunExecuteJobOperator) ──► Cloud Run job "dbt-retail" (image = dbt + this repo's dbt project)
                                                  └── key from Secret Manager, runs `dbt build --target prod`
```

Why: Composer workers stay light and conflict-free, dbt gets its own CPU/memory and logs, and the same image runs in CI.

## Interview angle

*"Airflow on Composer orchestrates cross-system steps — file arrival, API extracts on Cloud Run, the dbt build, reconciliation,
alerts. In-warehouse low-latency steps stay in Snowflake (Dynamic Tables / Tasks). I keep Airflow tasks thin and run heavy work
where it belongs: Snowflake warehouses or Cloud Run."*
