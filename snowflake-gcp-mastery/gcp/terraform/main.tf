# GCP capstone: "Landing zone in code".
#
#   cd gcp/terraform
#   copy terraform.tfvars.example terraform.tfvars   (then edit it)
#   terraform init
#   terraform plan
#   terraform apply
#   terraform destroy      # end of session
#
# The real work lives in modules/landing_zone so the final capstone can reuse it.

locals {
  required_apis = [
    "iam.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false # never switch APIs off on destroy; other things may use them
}

module "landing_zone" {
  source = "./modules/landing_zone"

  project_id            = var.project_id
  region                = var.region
  landing_bucket_name   = "${var.project_id}-landing"
  lakehouse_bucket_name = "${var.project_id}-lakehouse"
  ads_image             = var.ads_image

  depends_on = [google_project_service.apis]
}
