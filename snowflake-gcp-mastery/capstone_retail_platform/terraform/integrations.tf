# The cross-cloud handshake, fully automated:
#   1. Snowflake creates its integrations and reveals the Google service accounts it will use
#   2. Terraform grants those service accounts least-privilege access in GCP
# (This is what you did by hand in stage_02 lesson 02 with gcp/grant_snowflake_access.sh.)

resource "snowflake_storage_integration_gcs" "gcs" {
  provider                  = snowflake.accountadmin
  name                      = "GCS_INT"
  enabled                   = true
  storage_allowed_locations = [module.landing_zone.landing_bucket_url, module.landing_zone.lakehouse_bucket_url]
  comment                   = "RetailOne landing + lakehouse buckets"
}

locals {
  # DESC STORAGE INTEGRATION → STORAGE_GCP_SERVICE_ACCOUNT, exposed by the provider as describe_output
  snowflake_gcs_service_account = snowflake_storage_integration_gcs.gcs.describe_output[0].service_account
}

resource "snowflake_notification_integration" "gcs_events" {
  provider                     = snowflake.accountadmin
  name                         = "GCS_NOTIF"
  enabled                      = true
  notification_provider        = "GCP_PUBSUB"
  gcp_pubsub_subscription_name = module.landing_zone.pubsub_subscription_id
  comment                      = "Object-created events from the landing bucket (Snowpipe auto-ingest)"
}

resource "snowflake_grant_privileges_to_account_role" "engineer_integrations" {
  for_each = {
    storage      = snowflake_storage_integration_gcs.gcs.name
    notification = snowflake_notification_integration.gcs_events.name
  }
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "INTEGRATION"
    object_name = each.value
  }
}

# ---- GCP grants for Snowflake's service accounts ---------------------------
resource "google_project_iam_custom_role" "snowflake_gcs_reader" {
  project     = var.project_id
  role_id     = "snowflakeGcsReaderTf"
  title       = "Snowflake GCS reader (Terraform)"
  permissions = ["storage.buckets.get", "storage.objects.get", "storage.objects.list"]
}

resource "google_storage_bucket_iam_member" "snowflake_reads_landing" {
  bucket = module.landing_zone.landing_bucket
  role   = google_project_iam_custom_role.snowflake_gcs_reader.id
  member = "serviceAccount:${local.snowflake_gcs_service_account}"
}

resource "google_pubsub_subscription_iam_member" "snowflake_subscriber" {
  project      = var.project_id
  subscription = module.landing_zone.pubsub_subscription_name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${snowflake_notification_integration.gcs_events.gcp_pubsub_service_account}"
}

resource "google_project_iam_member" "snowflake_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${snowflake_notification_integration.gcs_events.gcp_pubsub_service_account}"
}
