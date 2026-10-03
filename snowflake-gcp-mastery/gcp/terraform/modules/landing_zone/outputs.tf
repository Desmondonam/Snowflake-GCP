output "landing_bucket" {
  value = google_storage_bucket.landing.name
}

output "landing_bucket_url" {
  description = "Use this in Snowflake STORAGE_ALLOWED_LOCATIONS / stage URL"
  value       = "gcs://${google_storage_bucket.landing.name}/"
}

output "lakehouse_bucket" {
  value = google_storage_bucket.lakehouse.name
}

output "lakehouse_bucket_url" {
  value = "gcs://${google_storage_bucket.lakehouse.name}/"
}

output "pubsub_topic" {
  value = google_pubsub_topic.landing_events.name
}

output "pubsub_subscription_id" {
  description = "Full name for Snowflake GCP_PUBSUB_SUBSCRIPTION_NAME"
  value       = google_pubsub_subscription.landing_events.id
}

output "pubsub_subscription_name" {
  value = google_pubsub_subscription.landing_events.name
}

output "ingest_service_account" {
  value = google_service_account.ingest.email
}

output "artifact_registry_repo" {
  description = "Docker repo path for image tags"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.retail.repository_id}"
}

output "source_prefixes" {
  value = [for s in var.sources : "gs://${google_storage_bucket.landing.name}/${s}/dt=YYYY-MM-DD/"]
}
