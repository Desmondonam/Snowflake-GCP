# GCP side: reuse the landing-zone module from the GCP track (G5).
locals {
  required_apis = [
    "iam.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "landing_zone" {
  source = "../../gcp/terraform/modules/landing_zone"

  project_id            = var.project_id
  region                = var.region
  landing_bucket_name   = "${var.project_id}-landing"
  lakehouse_bucket_name = "${var.project_id}-lakehouse"
  ads_image             = var.ads_image

  depends_on = [google_project_service.apis]
}
