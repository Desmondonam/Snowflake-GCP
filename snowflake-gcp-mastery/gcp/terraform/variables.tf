variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (match your Snowflake account: us-central1)"
  type        = string
  default     = "us-central1"
}

variable "ads_image" {
  description = "Ads extractor image. Start with the default sample image; after building yours, set it to <region>-docker.pkg.dev/<project>/retail/ads-extract:latest"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/job:latest"
}
