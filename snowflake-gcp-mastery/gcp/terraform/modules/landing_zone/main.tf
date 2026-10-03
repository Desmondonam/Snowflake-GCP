# Landing zone module: everything on the GCP side of RetailOne's ingestion.
#
#   landing bucket --(OBJECT_FINALIZE)--> Pub/Sub topic --> subscription --> (Snowflake notification integration)
#   Cloud Scheduler --> Cloud Run job (ads extractor, runs as sa-ingest) --> landing bucket
#   lakehouse bucket (Iceberg tables, Stage 8)

# ---------------------------------------------------------------------------
# Buckets
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "landing" {
  name                        = var.landing_bucket_name
  project                     = var.project_id
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = var.labels

  lifecycle_rule {
    condition { age = 30 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  lifecycle_rule {
    condition { age = 365 }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "lakehouse" {
  name                        = var.lakehouse_bucket_name
  project                     = var.project_id
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = var.labels
}

# ---------------------------------------------------------------------------
# Pub/Sub: bucket events for Snowpipe auto-ingest
# ---------------------------------------------------------------------------
resource "google_pubsub_topic" "landing_events" {
  name    = "landing-events"
  project = var.project_id
  labels  = var.labels
}

resource "google_pubsub_subscription" "landing_events" {
  name                       = "landing-events-sub"
  project                    = var.project_id
  topic                      = google_pubsub_topic.landing_events.id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  labels                     = var.labels
}

# The Cloud Storage service agent must be allowed to publish to the topic
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.landing_events.id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_notification" "landing_finalize" {
  bucket         = google_storage_bucket.landing.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.landing_events.id
  event_types    = ["OBJECT_FINALIZE"]
  depends_on     = [google_pubsub_topic_iam_member.gcs_publisher]
}

# ---------------------------------------------------------------------------
# Identities
# ---------------------------------------------------------------------------
resource "google_service_account" "ingest" {
  project      = var.project_id
  account_id   = "sa-ingest"
  display_name = "Ingestion writer"
}

resource "google_storage_bucket_iam_member" "ingest_writer" {
  bucket = google_storage_bucket.landing.name
  role   = "roles/storage.objectCreator" # create only: landing files are immutable
  member = "serviceAccount:${google_service_account.ingest.email}"
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "sa-scheduler"
  display_name = "Scheduler invoker"
}

# ---------------------------------------------------------------------------
# Container registry + ads extractor job + daily schedule
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "retail" {
  project       = var.project_id
  location      = var.region
  repository_id = "retail"
  format        = "DOCKER"
  labels        = var.labels
}

resource "google_cloud_run_v2_job" "ads_extract" {
  name                = "ads-extract"
  project             = var.project_id
  location            = var.region
  deletion_protection = false # lab: let terraform destroy remove it
  labels              = var.labels

  template {
    task_count = 1
    template {
      service_account = google_service_account.ingest.email
      max_retries     = 2
      timeout         = "600s"
      containers {
        image = var.ads_image
        env {
          name  = "LANDING_BUCKET"
          value = google_storage_bucket.landing.name
        }
        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.ads_extract.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "ads_daily" {
  name      = "ads-extract-daily"
  project   = var.project_id
  region    = var.region
  schedule  = var.ads_schedule
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.ads_extract.name}:run"
    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_invoker]
}
